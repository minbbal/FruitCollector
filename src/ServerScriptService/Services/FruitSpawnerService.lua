-- Spawns fruits on the map.
-- This version uses actual fruit templates from Workspace/ServerStorage if they exist.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FruitTypes = require(ReplicatedStorage.Shared.FruitTypes)

local FruitSpawnerService = {}

local fruitFolder = Workspace:FindFirstChild("FruitFolder")
if not fruitFolder then
    fruitFolder = Instance.new("Folder")
    fruitFolder.Name = "FruitFolder"
    fruitFolder.Parent = Workspace
end

local FruitMessage = ReplicatedStorage.Remotes:WaitForChild("FruitMessage")

local function randomPosition()
    return Vector3.new(
        math.random(Config.MAP_MIN_X, Config.MAP_MAX_X),
        Config.SPAWN_Y,
        math.random(Config.MAP_MIN_Z, Config.MAP_MAX_Z)
    )
end

local function findFruitTemplate(fruitName)
    local candidateParents = {
        Workspace,
        ServerStorage,
        ReplicatedStorage,
    }

    for _, parent in candidateParents do
        if parent then
            local found = parent:FindFirstChild(fruitName)
            if found then
                return found
            end
        end
    end

    return nil
end

local function setFruitPhysics(instance)
    if instance:IsA("BasePart") then
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = true
        instance.CanQuery = true
        instance.Transparency = 0
        instance.CastShadow = true
    end

    for _, descendant in instance:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = true
            descendant.CanQuery = true
            descendant.Transparency = 0
            descendant.CastShadow = true
        end
    end
end

local function createFruitInstance(fruitName)
    local fruitInfo = FruitTypes[fruitName]
    if not fruitInfo then
        return nil
    end

    local template = findFruitTemplate(fruitName)
    local fruitInstance = if template then template:Clone() else nil

    if fruitInstance and fruitInstance:IsA("Model") then
        fruitInstance.Name = fruitName
        fruitInstance:SetAttribute("FruitType", fruitName)
        fruitInstance:SetAttribute("Collected", false)
        fruitInstance:SetPrimaryPartCFrame(CFrame.new(randomPosition()))
        setFruitPhysics(fruitInstance)
        fruitInstance.Parent = fruitFolder
        return fruitInstance
    elseif fruitInstance and fruitInstance:IsA("BasePart") then
        fruitInstance.Name = fruitName
        fruitInstance:SetAttribute("FruitType", fruitName)
        fruitInstance:SetAttribute("Collected", false)
        fruitInstance.Position = randomPosition()
        setFruitPhysics(fruitInstance)
        fruitInstance.Parent = fruitFolder
        return fruitInstance
    end

    -- Fallback: create a simple visible part if the asset was not found.
    local fallback = Instance.new("Part")
    fallback.Name = fruitName
    fallback.Shape = Enum.PartType.Ball
    fallback.Size = Vector3.new(3, 3, 3)
    fallback.Material = Enum.Material.Neon
    fallback.Color = Color3.fromRGB(255, 255, 255)
    fallback.Anchored = true
    fallback.CanCollide = false
    fallback.CanTouch = true
    fallback.CanQuery = true
    fallback.Transparency = 0
    fallback.Position = randomPosition()
    fallback.Parent = fruitFolder

    fallback:SetAttribute("FruitType", fruitName)
    fallback:SetAttribute("Collected", false)
    return fallback
end

function FruitSpawnerService.start()
    task.spawn(function()
        while true do
            local currentFruitCount = 0
            for _, child in fruitFolder:GetChildren() do
                if child:GetAttribute("FruitType") ~= nil then
                    currentFruitCount += 1
                end
            end

            if currentFruitCount < Config.MAX_FRUITS then
                local fruitNames = {}
                for name in pairs(FruitTypes) do
                    table.insert(fruitNames, name)
                end

                local fruitName = fruitNames[math.random(1, #fruitNames)]
                local fruitInstance = createFruitInstance(fruitName)
                if fruitInstance then
                    fruitInstance.Touched:Connect(function(hit)
                        local character = hit.Parent
                        local player = Players:GetPlayerFromCharacter(character)
                        if not player then
                            return
                        end

                        if fruitInstance:GetAttribute("Collected") then
                            return
                        end

                        fruitInstance:SetAttribute("Collected", true)
                        fruitInstance:Destroy()

                        local leaderstats = player:FindFirstChild("leaderstats")
                        if leaderstats then
                            local fruitsValue = leaderstats:FindFirstChild("Fruits")
                            if fruitsValue and fruitsValue:IsA("IntValue") then
                                fruitsValue.Value += 1
                            end
                        end

                        FruitMessage:FireClient(player, "+1 " .. fruitName)
                    end)
                end
            end

            task.wait(Config.SPAWN_INTERVAL)
        end
    end)
end

return FruitSpawnerService
