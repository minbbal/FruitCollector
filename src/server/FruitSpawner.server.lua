-- FruitSpawner.server.lua
-- Current map rules:
--   fruit templates: Workspace children/descendants whose names start with "Fruit"
--   fruit spawn areas: Workspace/FruitSpawnArea/Areas descendants named "Grass" that are BaseParts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local REMOTES_FOLDER_NAME = "Remotes"
local FRUIT_TEMPLATE_FOLDER_NAME = "FruitTemplates"
local FRUIT_DEBUG_EVENT_NAME = "FruitDebugEvent"
local FRUIT_SOUND_EVENT_NAME = "FruitSoundEvent"
local FRUIT_RESPAWN_EFFECT_EVENT_NAME = "FruitRespawnEffectEvent"
local FRUIT_NAME_PREFIX = "Fruit"
local FRUIT_SPAWN_AREA_FOLDER_NAME = "FruitSpawnArea"
local AREAS_FOLDER_NAME = "Areas"
local GRASS_SPAWN_AREA_NAME = "Grass"
local TARGET_LONGEST_AXIS = 2.2
local SPAWN_INTERVAL = 2
local SPAWN_HEIGHT_ABOVE_GRASS = 80
local FALL_DETECTION_OFFSET = 30
local FALL_CHECK_INTERVAL = 0.2
local FALL_RESPAWN_DELAY = 4.5
local MAP_WAIT_TIMEOUT = 15
local BGM_SOUND_ID = "rbxassetid://1839825760"
local BGM_VOLUME = 0.25

Players.CharacterAutoLoads = false

local rng = Random.new()
local processingFall = {}
local playerHasLoadedCharacter = {}
local fallCheckAccumulator = 0
local warnedNoTemplates = false
local warnedMissingGrassParts = false
local warnedNestedFruitSpawnArea = false
local warnedFallbackAreas = false
local loggedMissingMapSnapshot = false

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = REMOTES_FOLDER_NAME
    remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name)
    local remoteEvent = remotesFolder:FindFirstChild(name)
    if not remoteEvent then
        remoteEvent = Instance.new("RemoteEvent")
        remoteEvent.Name = name
        remoteEvent.Parent = remotesFolder
    end

    return remoteEvent
end

local fruitDebugEvent = ensureRemoteEvent(FRUIT_DEBUG_EVENT_NAME)
local fruitSoundEvent = ensureRemoteEvent(FRUIT_SOUND_EVENT_NAME)
local fruitRespawnEffectEvent = ensureRemoteEvent(FRUIT_RESPAWN_EFFECT_EVENT_NAME)

local fruitTemplateFolder = ServerStorage:FindFirstChild(FRUIT_TEMPLATE_FOLDER_NAME)
if not fruitTemplateFolder then
    fruitTemplateFolder = Instance.new("Folder")
    fruitTemplateFolder.Name = FRUIT_TEMPLATE_FOLDER_NAME
    fruitTemplateFolder.Parent = ServerStorage
end

local function mapLog(message)
    print("[MapDebug] " .. message)
end

local function fruitLog(message)
    print("[FruitDebug] " .. message)
end

local function remoteLog(message)
    print("[RemoteDebug] " .. message)
end

local function respawnLog(message)
    print("[RespawnDebug] " .. message)
end

local function sendDebugLog(player, message)
    fruitDebugEvent:FireClient(player, "__log", message, 0, 0, "server")
end

local function setupBackgroundMusic()
    local bgm = SoundService:FindFirstChild("FruitCollectorBGM")
    if not bgm then
        bgm = Instance.new("Sound")
        bgm.Name = "FruitCollectorBGM"
        bgm.Parent = SoundService
    end

    bgm.SoundId = BGM_SOUND_ID
    bgm.Looped = true
    bgm.Volume = BGM_VOLUME

    if not bgm.IsPlaying then
        bgm:Play()
    end
end

local function getWorkspaceChildNames()
    local names = {}
    for _, child in ipairs(Workspace:GetChildren()) do
        table.insert(names, child.Name .. ":" .. child.ClassName)
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local function isFruitName(name)
    return string.sub(name, 1, 5) == FRUIT_NAME_PREFIX
end

local function isProtectedMapInstance(instance)
    return instance.Name == FRUIT_SPAWN_AREA_FOLDER_NAME or instance:FindFirstAncestor(FRUIT_SPAWN_AREA_FOLDER_NAME) ~= nil
end

local function isFruitAsset(instance)
    return (instance:IsA("Model") or instance:IsA("BasePart"))
        and isFruitName(instance.Name)
        and not isProtectedMapInstance(instance)
end

local function hasFruitAssetAncestor(instance)
    local ancestor = instance.Parent
    while ancestor and ancestor ~= Workspace do
        if isFruitAsset(ancestor) then
            return true
        end
        ancestor = ancestor.Parent
    end

    return false
end

local function getLargestAxisSize(instance)
    if instance:IsA("Model") then
        local largest = 0
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                largest = math.max(largest, descendant.Size.X, descendant.Size.Y, descendant.Size.Z)
            end
        end
        return largest
    end

    if instance:IsA("BasePart") then
        return math.max(instance.Size.X, instance.Size.Y, instance.Size.Z)
    end

    return 0
end

local function normalizeFruitSize(instance)
    local largest = getLargestAxisSize(instance)
    if largest <= 0 then
        warn("[FruitDebug] Cannot resize fruit template without BasePart: " .. instance.Name)
        return
    end

    local scale = TARGET_LONGEST_AXIS / largest
    if instance:IsA("Model") then
        instance:ScaleTo(scale)
    elseif instance:IsA("BasePart") then
        instance.Size = instance.Size * scale
    end
end

local function setTemplatePhysics(instance)
    if instance:IsA("BasePart") then
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        instance.Transparency = 0
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.Transparency = 0
        end
    end
end

local function setSpawnedFruitPhysics(instance)
    if instance:IsA("BasePart") then
        instance.Anchored = false
        instance.CanCollide = true
        instance.CanTouch = true
        instance.CanQuery = true
        instance.Transparency = 0
        instance.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = false
            descendant.CanCollide = true
            descendant.CanTouch = true
            descendant.CanQuery = true
            descendant.Transparency = 0
            descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
        end
    end
end

local function getAreasFolder()
    local fruitSpawnArea = Workspace:FindFirstChild(FRUIT_SPAWN_AREA_FOLDER_NAME)
    local areas = fruitSpawnArea and fruitSpawnArea:FindFirstChild(AREAS_FOLDER_NAME)

    if fruitSpawnArea and areas then
        return fruitSpawnArea, areas
    end

    local nestedFruitSpawnArea = Workspace:FindFirstChild(FRUIT_SPAWN_AREA_FOLDER_NAME, true)
    if nestedFruitSpawnArea then
        local nestedAreas = nestedFruitSpawnArea:FindFirstChild(AREAS_FOLDER_NAME)
        if nestedAreas then
            if not warnedNestedFruitSpawnArea then
                warnedNestedFruitSpawnArea = true
                warn("[MapDebug] Workspace/FruitSpawnArea was not a direct child. Using nested spawn area: " .. nestedFruitSpawnArea:GetFullName())
            end
            return nestedFruitSpawnArea, nestedAreas
        end
    end

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant.Name == AREAS_FOLDER_NAME then
            for _, areasDescendant in ipairs(descendant:GetDescendants()) do
                if areasDescendant.Name == GRASS_SPAWN_AREA_NAME and areasDescendant:IsA("BasePart") then
                    if not warnedFallbackAreas then
                        warnedFallbackAreas = true
                        warn("[MapDebug] FruitSpawnArea not found. Using Areas folder containing Grass as fallback: " .. descendant:GetFullName())
                    end
                    return nil, descendant
                end
            end
        end
    end

    return fruitSpawnArea, areas
end

local function getGrassSpawnParts()
    local fruitSpawnArea, areas = getAreasFolder()
    if not areas then
        if not loggedMissingMapSnapshot then
            loggedMissingMapSnapshot = true
            mapLog("FruitSpawnArea found: " .. tostring(fruitSpawnArea ~= nil))
            mapLog("Areas found: false")
            mapLog("Workspace children: " .. getWorkspaceChildNames())
        end
        return {}
    end

    local parts = {}
    for _, descendant in ipairs(areas:GetDescendants()) do
        if descendant.Name == GRASS_SPAWN_AREA_NAME and descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end

    if #parts <= 0 and not warnedMissingGrassParts then
        warnedMissingGrassParts = true
        warn("[MapDebug] No Grass BasePart found under Workspace/FruitSpawnArea/Areas. Fruit spawning is paused.")
    elseif #parts > 0 then
        warnedMissingGrassParts = false
    end

    return parts
end

local function waitForGrassSpawnParts(timeoutSeconds)
    local deadline = os.clock() + timeoutSeconds
    local spawnParts = getGrassSpawnParts()

    while #spawnParts <= 0 and os.clock() < deadline do
        task.wait(0.5)
        spawnParts = getGrassSpawnParts()
    end

    return spawnParts
end

local function getGrassMinY(spawnParts)
    if #spawnParts <= 0 then
        return nil
    end

    local minY = math.huge
    for _, part in ipairs(spawnParts) do
        minY = math.min(minY, part.Position.Y - (part.Size.Y * 0.5))
    end

    return minY
end

local function getFallY(spawnParts)
    local grassMinY = getGrassMinY(spawnParts)
    if not grassMinY then
        return nil, nil
    end

    return grassMinY, grassMinY - FALL_DETECTION_OFFSET
end

local function getRandomFruitSpawnPosition()
    local spawnParts = getGrassSpawnParts()
    if #spawnParts <= 0 then
        return nil, nil
    end

    local grass = spawnParts[rng:NextInteger(1, #spawnParts)]
    local halfX = grass.Size.X * 0.5
    local halfZ = grass.Size.Z * 0.5
    local x = grass.Position.X + rng:NextNumber(-halfX, halfX)
    local z = grass.Position.Z + rng:NextNumber(-halfZ, halfZ)
    local y = grass.Position.Y + SPAWN_HEIGHT_ABOVE_GRASS
    local position = Vector3.new(x, y, z)

    if x < grass.Position.X - halfX or x > grass.Position.X + halfX
        or z < grass.Position.Z - halfZ or z > grass.Position.Z + halfZ then
        warn(string.format(
            "[FruitDebug] Calculated spawn position outside Grass bounds. Grass=%s Position=(%.2f, %.2f, %.2f)",
            grass:GetFullName(),
            position.X,
            position.Y,
            position.Z
        ))
        return nil, grass
    end

    fruitLog("Selected Grass: " .. grass:GetFullName())
    fruitLog(string.format("Calculated spawn position=(%.2f, %.2f, %.2f)", position.X, position.Y, position.Z))
    return position, grass
end

local function moveToPosition(instance, position)
    if instance:IsA("Model") then
        instance:PivotTo(CFrame.new(position))
    elseif instance:IsA("BasePart") then
        instance.CFrame = CFrame.new(position)
    end
end

local function findWorkspaceFruitAssets()
    local fruitAssets = {}
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if isFruitAsset(descendant) and not hasFruitAssetAncestor(descendant) then
            table.insert(fruitAssets, descendant)
        elseif isFruitName(descendant.Name) and isProtectedMapInstance(descendant) then
            fruitLog("Skipped protected map object while scanning fruit templates: " .. descendant:GetFullName())
        end
    end
    return fruitAssets
end

local function cacheWorkspaceFruitTemplates()
    for _, existingTemplate in ipairs(fruitTemplateFolder:GetChildren()) do
        existingTemplate:Destroy()
    end

    local fruitAssets = findWorkspaceFruitAssets()
    local names = {}

    for _, asset in ipairs(fruitAssets) do
        local template = asset:Clone()
        template.Name = asset.Name
        normalizeFruitSize(template)
        setTemplatePhysics(template)
        template.Parent = fruitTemplateFolder
        table.insert(names, template.Name)
        asset:Destroy()
    end

    table.sort(names)
    fruitLog("Workspace fruit template names: " .. (#names > 0 and table.concat(names, ", ") or "(none)"))
    fruitLog("ServerStorage/FruitTemplates count: " .. tostring(#fruitTemplateFolder:GetChildren()))
end

local function findSpawnLocation()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("SpawnLocation") then
            return descendant
        end
    end
    return nil
end

local function logStartupDebug()
    local fruitSpawnArea, areas = getAreasFolder()
    mapLog("FruitSpawnArea found: " .. tostring(fruitSpawnArea ~= nil))
    mapLog("Areas found: " .. tostring(areas ~= nil))

    local grassParts = waitForGrassSpawnParts(MAP_WAIT_TIMEOUT)
    fruitSpawnArea, areas = getAreasFolder()
    mapLog("FruitSpawnArea found after wait: " .. tostring(fruitSpawnArea ~= nil))
    mapLog("Areas found after wait: " .. tostring(areas ~= nil))
    mapLog("Grass BasePart count: " .. tostring(#grassParts))
    for _, part in ipairs(grassParts) do
        mapLog(string.format(
            "%s Position=(%.2f, %.2f, %.2f) Size=(%.2f, %.2f, %.2f)",
            part:GetFullName(),
            part.Position.X,
            part.Position.Y,
            part.Position.Z,
            part.Size.X,
            part.Size.Y,
            part.Size.Z
        ))
    end

    local grassMinY, fallY = getFallY(grassParts)
    mapLog("grassMinY: " .. tostring(grassMinY))
    mapLog("FALL_Y: " .. tostring(fallY))

    local remoteNames = {}
    for _, child in ipairs(remotesFolder:GetChildren()) do
        if child:IsA("RemoteEvent") then
            table.insert(remoteNames, child.Name)
        end
    end
    table.sort(remoteNames)
    remoteLog("RemoteEvents: " .. table.concat(remoteNames, ", "))

    local spawnLocation = findSpawnLocation()
    if spawnLocation then
        respawnLog(string.format(
            "SpawnLocation found: true %s Position=(%.2f, %.2f, %.2f)",
            spawnLocation:GetFullName(),
            spawnLocation.Position.X,
            spawnLocation.Position.Y,
            spawnLocation.Position.Z
        ))
    else
        warn("[RespawnDebug] SpawnLocation found: false")
    end
end

local function ensureScore(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    end

    local score = leaderstats:FindFirstChild("Score")
    if not score then
        score = Instance.new("IntValue")
        score.Name = "Score"
        score.Value = 0
        score.Parent = leaderstats
    end

    return score
end

local function ensureFruitCounts(player)
    local fruitCounts = player:FindFirstChild("FruitCounts")
    if not fruitCounts then
        fruitCounts = Instance.new("Folder")
        fruitCounts.Name = "FruitCounts"
        fruitCounts.Parent = player
    end
    return fruitCounts
end

local function ensureFruitCountValue(player, fruitName)
    local fruitCounts = ensureFruitCounts(player)
    local fruitCount = fruitCounts:FindFirstChild(fruitName)
    if not fruitCount then
        fruitCount = Instance.new("IntValue")
        fruitCount.Name = fruitName
        fruitCount.Value = 0
        fruitCount.Parent = fruitCounts
    end
    return fruitCount
end

local function applyFallPenalty(player)
    local score = ensureScore(player)
    local oldScore = score.Value
    score.Value = math.floor(score.Value / 2)
    respawnLog(player.Name .. " score penalty: " .. tostring(oldScore) .. " -> " .. tostring(score.Value))
    fruitDebugEvent:FireClient(player, "__score", score.Value, 0, "server")

    for _, value in ipairs(ensureFruitCounts(player):GetChildren()) do
        if value:IsA("IntValue") then
            local oldCount = value.Value
            value.Value = math.floor(value.Value / 2)
            respawnLog(player.Name .. " " .. value.Name .. " count penalty: " .. tostring(oldCount) .. " -> " .. tostring(value.Value))
            fruitDebugEvent:FireClient(player, "__count", value.Name, value.Value, "server")
        end
    end
end

local function respawnPlayerAfterDelay(player)
    respawnLog(player.Name .. " respawn scheduled in " .. tostring(FALL_RESPAWN_DELAY) .. " seconds")
    fruitDebugEvent:FireClient(player, "__log", "respawn scheduled in " .. tostring(FALL_RESPAWN_DELAY) .. " seconds", 0, 0, "server")

    task.delay(FALL_RESPAWN_DELAY, function()
        if not player.Parent then
            processingFall[player] = nil
            return
        end

        respawnLog(player.Name .. " LoadCharacter called")
        player:LoadCharacter()
        fruitRespawnEffectEvent:FireClient(player)
    end)
end

local function handlePlayerFall(player, hrpY, fallY)
    if processingFall[player] then
        return
    end

    processingFall[player] = true
    respawnLog(string.format("%s fall detected HRP.Y=%.2f FALL_Y=%.2f", player.Name, hrpY, fallY))
    fruitDebugEvent:FireClient(player, "__log", string.format("fall detected HRP.Y %.2f below FALL_Y %.2f", hrpY, fallY), 0, 0, "server")
    applyFallPenalty(player)
    respawnPlayerAfterDelay(player)
end

local function setupCharacter(player, character)
    playerHasLoadedCharacter[player] = true
    task.defer(function()
        if player.Parent and character.Parent and processingFall[player] then
            respawnLog(player.Name .. " respawn complete; fall debounce cleared")
            processingFall[player] = nil
        end
    end)
end

local function setupPlayer(player)
    ensureScore(player)
    ensureFruitCounts(player)

    player.CharacterAdded:Connect(function(character)
        setupCharacter(player, character)
    end)

    if not player.Character then
        player:LoadCharacter()
    else
        setupCharacter(player, player.Character)
    end
end

local function collectFruit(player, fruit)
    if fruit:GetAttribute("Collected") then
        return
    end

    fruit:SetAttribute("Collected", true)

    local fruitName = fruit.Name
    local score = ensureScore(player)
    score.Value += 1

    local fruitCount = ensureFruitCountValue(player, fruitName)
    fruitCount.Value += 1

    fruitLog(string.format("%s collected %s / FruitCount=%d / Score=%d", player.Name, fruitName, fruitCount.Value, score.Value))
    fruitDebugEvent:FireClient(player, fruitName, score.Value, fruitCount.Value, player.Name)
    fruitSoundEvent:FireClient(player, "pickup", fruitName)
    fruit:Destroy()
end

local function bindTouchEvents(fruit)
    local function onTouched(hit)
        local character = hit.Parent
        if not character then
            return
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return
        end

        local player = Players:GetPlayerFromCharacter(character)
        if player then
            collectFruit(player, fruit)
        end
    end

    if fruit:IsA("BasePart") then
        fruit.Touched:Connect(onTouched)
    end

    for _, descendant in ipairs(fruit:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Touched:Connect(onTouched)
        end
    end
end

local function spawnFruit()
    local templates = fruitTemplateFolder:GetChildren()
    if #templates <= 0 then
        if not warnedNoTemplates then
            warnedNoTemplates = true
            warn("[FruitDebug] No fruit templates found in ServerStorage/FruitTemplates. Fruit spawning is paused.")
        end
        return
    end

    local spawnPosition = getRandomFruitSpawnPosition()
    if not spawnPosition then
        return
    end

    local template = templates[rng:NextInteger(1, #templates)]
    local fruit = template:Clone()
    fruit.Name = template.Name
    fruit:SetAttribute("Collected", false)
    setSpawnedFruitPhysics(fruit)
    fruit.Parent = Workspace
    moveToPosition(fruit, spawnPosition)
    bindTouchEvents(fruit)

    fruitSoundEvent:FireAllClients("drop", fruit.Name)
    fruitDebugEvent:FireAllClients("__spawn", fruit.Name, 0, 0, "server")
    fruitLog(string.format("Spawned fruit=%s position=(%.2f, %.2f, %.2f)", fruit.Name, spawnPosition.X, spawnPosition.Y, spawnPosition.Z))
end

local function startSpawner()
    task.spawn(function()
        while true do
            spawnFruit()
            task.wait(SPAWN_INTERVAL)
        end
    end)
end

local function startFallMonitor()
    RunService.Heartbeat:Connect(function(deltaTime)
        fallCheckAccumulator += deltaTime
        if fallCheckAccumulator < FALL_CHECK_INTERVAL then
            return
        end
        fallCheckAccumulator = 0

        local grassParts = getGrassSpawnParts()
        local _, fallY = getFallY(grassParts)
        if not fallY then
            return
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if not processingFall[player] and playerHasLoadedCharacter[player] then
                local character = player.Character
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                if rootPart and rootPart.Position.Y < fallY then
                    handlePlayerFall(player, rootPart.Position.Y, fallY)
                end
            end
        end
    end)
end

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
    processingFall[player] = nil
    playerHasLoadedCharacter[player] = nil
end)

setupBackgroundMusic()
logStartupDebug()
cacheWorkspaceFruitTemplates()
startSpawner()
startFallMonitor()
