-- FruitSpawner.server.lua
-- Uses Workspace fruit assets whose names contain "Fruit" as templates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local FRUIT_TEMPLATE_FOLDER_NAME = "FruitTemplates"
local FRUIT_DEBUG_EVENT_NAME = "FruitDebugEvent"
local FRUIT_SOUND_EVENT_NAME = "FruitSoundEvent"
local FRUIT_RESPAWN_EFFECT_EVENT_NAME = "FruitRespawnEffectEvent"
local FRUIT_NAME_TOKEN = "Fruit"
local FRUIT_SPAWN_AREA_FOLDER_NAME = "FruitSpawnArea"
local AREAS_FOLDER_NAME = "Areas"
local GRASS_SPAWN_AREA_NAME = "Grass"
local TARGET_LONGEST_AXIS = 2.2
local SPAWN_INTERVAL = 2
local SPAWN_HEIGHT_ABOVE_GRASS = 80
local FALL_DETECTION_OFFSET = 30
local FALL_CHECK_INTERVAL = 0.2
local FALL_RESPAWN_DELAY = 4.5
local BGM_SOUND_ID = "rbxassetid://1839825760"
local BGM_VOLUME = 0.25

Players.CharacterAutoLoads = false

local fruitTemplateFolder = ServerStorage:FindFirstChild(FRUIT_TEMPLATE_FOLDER_NAME)
if not fruitTemplateFolder then
    fruitTemplateFolder = Instance.new("Folder")
    fruitTemplateFolder.Name = FRUIT_TEMPLATE_FOLDER_NAME
    fruitTemplateFolder.Parent = ServerStorage
end

local fruitDebugEvent = ReplicatedStorage:FindFirstChild(FRUIT_DEBUG_EVENT_NAME)
if not fruitDebugEvent then
    fruitDebugEvent = Instance.new("RemoteEvent")
    fruitDebugEvent.Name = FRUIT_DEBUG_EVENT_NAME
    fruitDebugEvent.Parent = ReplicatedStorage
end

local fruitSoundEvent = ReplicatedStorage:FindFirstChild(FRUIT_SOUND_EVENT_NAME)
if not fruitSoundEvent then
    fruitSoundEvent = Instance.new("RemoteEvent")
    fruitSoundEvent.Name = FRUIT_SOUND_EVENT_NAME
    fruitSoundEvent.Parent = ReplicatedStorage
end

local fruitRespawnEffectEvent = ReplicatedStorage:FindFirstChild(FRUIT_RESPAWN_EFFECT_EVENT_NAME)
if not fruitRespawnEffectEvent then
    fruitRespawnEffectEvent = Instance.new("RemoteEvent")
    fruitRespawnEffectEvent.Name = FRUIT_RESPAWN_EFFECT_EVENT_NAME
    fruitRespawnEffectEvent.Parent = ReplicatedStorage
end

local warnedMissingGrassArea = false
local warnedMissingGrassParts = false
local loggedGrassAreaFound = false
local lastLoggedGrassPartCount = nil
local processingFall = {}
local playerHasLoadedCharacter = {}
local fallCheckAccumulator = 0

local function debugLog(message)
    print("[FruitSpawner] " .. message)
end

local function debugPlayer(player, message)
    print("[FallDebug] " .. player.Name .. " " .. message)
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

local function isFruitName(name)
    return string.find(name, FRUIT_NAME_TOKEN, 1, true) ~= nil
end

local function isFruitAsset(instance)
    return (instance:IsA("Model") or instance:IsA("BasePart")) and isFruitName(instance.Name)
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
        warn("[FruitSpawner] Cannot resize fruit template without BasePart: " .. instance.Name)
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

local function findGrassSpawnArea()
    local fruitSpawnArea = Workspace:FindFirstChild(FRUIT_SPAWN_AREA_FOLDER_NAME)
    local areas = fruitSpawnArea and fruitSpawnArea:FindFirstChild(AREAS_FOLDER_NAME)
    local grass = areas and areas:FindFirstChild(GRASS_SPAWN_AREA_NAME)

    if not grass then
        if not warnedMissingGrassArea then
            warnedMissingGrassArea = true
            warn("[FruitSpawner] Grass spawn area not found at Workspace/FruitSpawnArea/Areas/Grass. Fruit spawning is paused.")
        end
        return nil
    end

    if not loggedGrassAreaFound then
        loggedGrassAreaFound = true
        debugLog("Grass spawn area found: " .. grass:GetFullName())
    end

    return grass
end

local function getGrassSpawnParts()
    local grass = findGrassSpawnArea()
    if not grass then
        return {}
    end

    local parts = {}
    if grass:IsA("BasePart") then
        table.insert(parts, grass)
    elseif grass:IsA("Folder") or grass:IsA("Model") then
        for _, descendant in ipairs(grass:GetDescendants()) do
            if descendant:IsA("BasePart") then
                table.insert(parts, descendant)
            end
        end
    end

    if #parts <= 0 then
        if not warnedMissingGrassParts then
            warnedMissingGrassParts = true
            warn("[FruitSpawner] Grass spawn area has no BasePart. Fruit spawning is paused.")
        end
    elseif lastLoggedGrassPartCount ~= #parts then
        lastLoggedGrassPartCount = #parts
        debugLog("Grass spawn part count: " .. tostring(#parts))
    end

    return parts
end

local function getGrassMinY()
    local spawnParts = getGrassSpawnParts()
    if #spawnParts <= 0 then
        return nil
    end

    local minY = math.huge
    for _, part in ipairs(spawnParts) do
        minY = math.min(minY, part.Position.Y - (part.Size.Y * 0.5))
    end

    return minY
end

local function getRandomSpawnPosition()
    local spawnParts = getGrassSpawnParts()
    if #spawnParts <= 0 then
        return nil, nil
    end

    local selectedPart = spawnParts[math.random(1, #spawnParts)]
    local halfX = selectedPart.Size.X * 0.5
    local halfZ = selectedPart.Size.Z * 0.5
    local x = selectedPart.Position.X + ((math.random() * 2 - 1) * halfX)
    local z = selectedPart.Position.Z + ((math.random() * 2 - 1) * halfZ)
    local y = selectedPart.Position.Y + SPAWN_HEIGHT_ABOVE_GRASS

    debugLog("Selected spawn part: " .. selectedPart:GetFullName())

    return Vector3.new(x, y, z), selectedPart
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
        end
    end

    return fruitAssets
end

local function cacheWorkspaceFruitTemplates()
    local fruitAssets = findWorkspaceFruitAssets()

    for _, asset in ipairs(fruitAssets) do
        local template = asset:Clone()
        template.Name = asset.Name
        normalizeFruitSize(template)
        setTemplatePhysics(template)
        template.Parent = fruitTemplateFolder

        debugLog("Fruit template found: " .. template.Name)
        asset:Destroy()
    end

    debugLog("Fruit template count: " .. tostring(#fruitTemplateFolder:GetChildren()))
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
    fruitDebugEvent:FireClient(player, "__score", score.Value, 0, "server")
    debugPlayer(player, "score penalty: " .. tostring(oldScore) .. " -> " .. tostring(score.Value))

    local fruitCounts = ensureFruitCounts(player)
    for _, value in ipairs(fruitCounts:GetChildren()) do
        if value:IsA("IntValue") then
            local oldCount = value.Value
            value.Value = math.floor(value.Value / 2)
            fruitDebugEvent:FireClient(player, "__count", value.Name, value.Value, "server")
            debugPlayer(player, value.Name .. " penalty: " .. tostring(oldCount) .. " -> " .. tostring(value.Value))
        end
    end
end

local function respawnPlayerAfterDelay(player)
    debugPlayer(player, "not killing character; waiting " .. tostring(FALL_RESPAWN_DELAY) .. " seconds before respawn")
    debugPlayer(player, "respawn scheduled in " .. tostring(FALL_RESPAWN_DELAY) .. " seconds")
    task.delay(FALL_RESPAWN_DELAY, function()
        if not player.Parent then
            processingFall[player] = nil
            return
        end

        debugPlayer(player, "running SpawnLocation respawn now")
        player:LoadCharacter()
        fruitRespawnEffectEvent:FireClient(player)
    end)
end

local function handlePlayerFall(player, reason)
    if processingFall[player] then
        return
    end

    processingFall[player] = true
    debugPlayer(player, "fall detected: " .. reason)
    applyFallPenalty(player)

    respawnPlayerAfterDelay(player)
end

local function setupCharacter(player, character)
    playerHasLoadedCharacter[player] = true

    task.defer(function()
        if player.Parent and character.Parent then
            if processingFall[player] then
                debugPlayer(player, "SpawnLocation respawn complete")
            end
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

    player.CharacterRemoving:Connect(function()
        if playerHasLoadedCharacter[player] and not processingFall[player] then
            handlePlayerFall(player, "character removed")
        end
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
    local oldScore = score.Value
    score.Value += 1

    local fruitCount = ensureFruitCountValue(player, fruitName)
    fruitCount.Value += 1

    print(string.format(
        "[FruitDebug] %s collected %s / FruitCount: %d / TotalScore: %d",
        player.Name,
        fruitName,
        fruitCount.Value,
        score.Value
    ))
    debugLog(player.Name .. " collected " .. fruitName)
    debugLog(player.Name .. " score changed: " .. tostring(oldScore) .. " -> " .. tostring(score.Value))
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
        warn("[FruitSpawner] No fruit templates found in ServerStorage/FruitTemplates.")
        return
    end

    local spawnPosition = getRandomSpawnPosition()
    if not spawnPosition then
        return
    end

    local template = templates[math.random(1, #templates)]
    local fruit = template:Clone()
    fruit.Name = template.Name
    fruit:SetAttribute("Collected", false)
    setSpawnedFruitPhysics(fruit)
    fruit.Parent = Workspace
    moveToPosition(fruit, spawnPosition)
    bindTouchEvents(fruit)
    fruitSoundEvent:FireAllClients("drop", fruit.Name)
    fruitDebugEvent:FireAllClients("__spawn", fruit.Name, 0, 0, "server")

    debugLog(string.format(
        "Spawned %s at %.2f, %.2f, %.2f",
        fruit.Name,
        spawnPosition.X,
        spawnPosition.Y,
        spawnPosition.Z
    ))
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

        local grassMinY = getGrassMinY()
        if not grassMinY then
            return
        end

        local fallY = grassMinY - FALL_DETECTION_OFFSET
        for _, player in ipairs(Players:GetPlayers()) do
            if not processingFall[player] and playerHasLoadedCharacter[player] then
                local character = player.Character
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")

                if not character or not character.Parent then
                    handlePlayerFall(player, "character missing")
                elseif not rootPart then
                    handlePlayerFall(player, "HumanoidRootPart missing")
                elseif humanoid and humanoid.Health <= 0 then
                    handlePlayerFall(player, "humanoid dead")
                elseif rootPart.Position.Y < fallY then
                    handlePlayerFall(player, string.format(
                        "HumanoidRootPart Y %.2f below fall Y %.2f",
                        rootPart.Position.Y,
                        fallY
                    ))
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
cacheWorkspaceFruitTemplates()
startSpawner()
startFallMonitor()
