-- FruitSpawner.server.lua
-- This script searches Workspace for fruit-like assets, copies them into
-- ServerStorage/FruitTemplates, and spawns collectible fruit clones.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local FRUIT_TEMPLATE_FOLDER_NAME = "FruitTemplates"
local FRUIT_TEMPLATE_FOLDER = ServerStorage:FindFirstChild(FRUIT_TEMPLATE_FOLDER_NAME)
if not FRUIT_TEMPLATE_FOLDER then
    FRUIT_TEMPLATE_FOLDER = Instance.new("Folder")
    FRUIT_TEMPLATE_FOLDER.Name = FRUIT_TEMPLATE_FOLDER_NAME
    FRUIT_TEMPLATE_FOLDER.Parent = ServerStorage
end

local FRUIT_KEYWORDS = {
    "apple",
    "banana",
    "orange",
    "strawberry",
    "grape",
    "watermelon",
    "fruit",
}

local TARGET_SCALE = 2.2
local SPAWN_INTERVAL = 2
local SPAWN_HEIGHT = 5
local SPAWN_EDGE_RATIO = 0.2
local DEFAULT_ARENA_RADIUS = 40

local function isFruitName(name)
    local lowerName = string.lower(name)
    for _, keyword in ipairs(FRUIT_KEYWORDS) do
        if string.find(lowerName, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function getLargestAxisSize(instance)
    if instance:IsA("Model") then
        local maxSize = 0
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local size = math.max(descendant.Size.X, descendant.Size.Y, descendant.Size.Z)
                if size > maxSize then
                    maxSize = size
                end
            end
        end
        return maxSize
    elseif instance:IsA("BasePart") or instance:IsA("MeshPart") then
        return math.max(instance.Size.X, instance.Size.Y, instance.Size.Z)
    end
    return 0
end

local function normalizeInstanceSize(instance)
    local longest = getLargestAxisSize(instance)
    if longest <= 0 then
        return
    end

    local scale = TARGET_SCALE / longest

    if instance:IsA("Model") then
        instance:ScaleTo(scale)
    elseif instance:IsA("BasePart") or instance:IsA("MeshPart") then
        instance.Size = instance.Size * scale
    end
end

local function hideOriginal(instance)
    if instance:IsA("Model") then
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Transparency = 1
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
            end
        end
        instance.Parent = nil
    elseif instance:IsA("BasePart") or instance:IsA("MeshPart") then
        instance.Transparency = 1
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        instance.Parent = nil
    end
end

local function prepareTemplate(instance)
    if instance:IsA("Model") then
        if not instance.PrimaryPart then
            local part = instance:FindFirstChildWhichIsA("BasePart")
            if part then
                instance.PrimaryPart = part
            end
        end

        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Transparency = 0
                descendant.Anchored = true
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
            end
        end

        if instance.PrimaryPart then
            instance.PrimaryPart.Anchored = true
        end

        instance.Parent = FRUIT_TEMPLATE_FOLDER
    elseif instance:IsA("BasePart") or instance:IsA("MeshPart") then
        instance.Transparency = 0
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        instance.Parent = FRUIT_TEMPLATE_FOLDER
    end
end

local function findFruitAssets()
    local fruitAssets = {}

    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if (descendant:IsA("Model") or descendant:IsA("BasePart") or descendant:IsA("MeshPart"))
            and isFruitName(descendant.Name)
            and not descendant:IsDescendantOf(FRUIT_TEMPLATE_FOLDER)
        then
            table.insert(fruitAssets, descendant)
        end
    end

    return fruitAssets
end

local function getSpawnCenter()
    local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
    if spawnLocation and spawnLocation:IsA("SpawnLocation") then
        return spawnLocation.Position
    end

    return Vector3.new(0, SPAWN_HEIGHT, 0)
end

local function getSpawnRadius()
    local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
    if spawnLocation and spawnLocation:IsA("SpawnLocation") then
        local size = spawnLocation.Size
        local radiusFromSize = math.max(size.X, size.Z) * 0.5
        return math.max(radiusFromSize * 6, DEFAULT_ARENA_RADIUS)
    end

    return DEFAULT_ARENA_RADIUS
end

local function randomSpawnPosition()
    local center = getSpawnCenter()
    local radius = getSpawnRadius()
    local innerRadius = radius * (1 - SPAWN_EDGE_RATIO)

    local angle = math.random() * math.pi * 2
    local distance = innerRadius + (math.random() * (radius - innerRadius))

    return Vector3.new(
        center.X + math.cos(angle) * distance,
        SPAWN_HEIGHT,
        center.Z + math.sin(angle) * distance
    )
end

local function setupFruitInstance(fruit)
    if fruit:IsA("Model") then
        if not fruit.PrimaryPart then
            local part = fruit:FindFirstChildWhichIsA("BasePart")
            if part then
                fruit.PrimaryPart = part
            end
        end

        fruit:SetAttribute("FruitTag", true)
        for _, descendant in ipairs(fruit:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Transparency = 0
                descendant.Anchored = false
                descendant.CanCollide = true
                descendant.CanTouch = true
                descendant.CanQuery = true
                descendant.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
            end
        end
    elseif fruit:IsA("BasePart") or fruit:IsA("MeshPart") then
        fruit.Transparency = 0
        fruit.Anchored = false
        fruit.CanCollide = true
        fruit.CanTouch = true
        fruit.CanQuery = true
        fruit.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
    end

    fruit.Parent = Workspace

    local spawnPosition = randomSpawnPosition()

    if fruit:IsA("Model") and fruit.PrimaryPart then
        fruit:PivotTo(CFrame.new(spawnPosition))
    elseif fruit:IsA("Model") then
        local firstPart = fruit:FindFirstChildWhichIsA("BasePart")
        if firstPart then
            firstPart.CFrame = CFrame.new(spawnPosition)
        end
    else
        fruit.Position = spawnPosition
    end
end

local function createLeaderboard(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local score = Instance.new("IntValue")
    score.Name = "Score"
    score.Value = 0
    score.Parent = leaderstats
end

Players.PlayerAdded:Connect(function(player)
    createLeaderboard(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    createLeaderboard(player)
end

local function collectFruit(player, fruit)
    if fruit:GetAttribute("Collected") then
        return
    end

    fruit:SetAttribute("Collected", true)
    fruit:Destroy()

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        local scoreValue = leaderstats:FindFirstChild("Score")
        if scoreValue and scoreValue:IsA("IntValue") then
            scoreValue.Value += 1
        end
    end
end

local function bindTouchEvents(fruit)
    if fruit:IsA("Model") then
        for _, descendant in ipairs(fruit:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Touched:Connect(function(hit)
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
                end)
            end
        end
    elseif fruit:IsA("BasePart") or fruit:IsA("MeshPart") then
        fruit.Touched:Connect(function(hit)
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
        end)
    end
end

local function startSpawner()
    task.spawn(function()
        while true do
            local templates = FRUIT_TEMPLATE_FOLDER:GetChildren()
            if #templates > 0 then
                local template = templates[math.random(1, #templates)]
                local fruit = template:Clone()
                setupFruitInstance(fruit)
                bindTouchEvents(fruit)
            end
            task.wait(SPAWN_INTERVAL)
        end
    end)
end

local fruitAssets = findFruitAssets()
for _, asset in ipairs(fruitAssets) do
    normalizeInstanceSize(asset)
    hideOriginal(asset)
    prepareTemplate(asset)
end

startSpawner()
