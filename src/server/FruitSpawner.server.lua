-- FruitSpawner.server.lua
-- Uses Workspace fruit assets whose names contain "Fruit" as templates.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local FRUIT_TEMPLATE_FOLDER_NAME = "FruitTemplates"
local FRUIT_NAME_TOKEN = "Fruit"
local TARGET_LONGEST_AXIS = 2.2
local SPAWN_INTERVAL = 2
local SPAWN_HEIGHT_ABOVE_SPAWN = 15
local SPAWN_AREA_SCALE = 1.2

local fruitTemplateFolder = ServerStorage:FindFirstChild(FRUIT_TEMPLATE_FOLDER_NAME)
if not fruitTemplateFolder then
    fruitTemplateFolder = Instance.new("Folder")
    fruitTemplateFolder.Name = FRUIT_TEMPLATE_FOLDER_NAME
    fruitTemplateFolder.Parent = ServerStorage
end

local warnedMissingSpawnLocation = false

local function debugLog(message)
    print("[FruitSpawner] " .. message)
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

local function findSpawnLocation()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("SpawnLocation") then
            return descendant
        end
    end

    if not warnedMissingSpawnLocation then
        warnedMissingSpawnLocation = true
        warn("[FruitSpawner] SpawnLocation not found. Fruit spawning is paused.")
    end

    return nil
end

local function getRandomSpawnPosition()
    local spawnLocation = findSpawnLocation()
    if not spawnLocation then
        return nil
    end

    local halfX = spawnLocation.Size.X * 0.5 * SPAWN_AREA_SCALE
    local halfZ = spawnLocation.Size.Z * 0.5 * SPAWN_AREA_SCALE
    local x = spawnLocation.Position.X + ((math.random() * 2 - 1) * halfX)
    local z = spawnLocation.Position.Z + ((math.random() * 2 - 1) * halfZ)
    local y = spawnLocation.Position.Y + (spawnLocation.Size.Y * 0.5) + SPAWN_HEIGHT_ABOVE_SPAWN

    return Vector3.new(x, y, z)
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

local function collectFruit(player, fruit)
    if fruit:GetAttribute("Collected") then
        return
    end

    fruit:SetAttribute("Collected", true)

    local score = ensureScore(player)
    local oldScore = score.Value
    score.Value += 1

    debugLog(player.Name .. " collected " .. fruit.Name)
    debugLog(player.Name .. " score changed: " .. tostring(oldScore) .. " -> " .. tostring(score.Value))

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

for _, player in ipairs(Players:GetPlayers()) do
    ensureScore(player)
end

Players.PlayerAdded:Connect(function(player)
    ensureScore(player)
end)

cacheWorkspaceFruitTemplates()
startSpawner()
