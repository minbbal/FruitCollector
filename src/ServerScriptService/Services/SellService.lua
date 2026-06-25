-- Handles selling fruits for coins.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SellService = {}
local REMOTES_FOLDER_NAME = "Remotes"
local FRUIT_DEBUG_EVENT_NAME = "FruitDebugEvent"

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = REMOTES_FOLDER_NAME
    remotesFolder.Parent = ReplicatedStorage
end

local fruitDebugEvent = remotesFolder:FindFirstChild(FRUIT_DEBUG_EVENT_NAME)
if not fruitDebugEvent then
    fruitDebugEvent = Instance.new("RemoteEvent")
    fruitDebugEvent.Name = FRUIT_DEBUG_EVENT_NAME
    fruitDebugEvent.Parent = remotesFolder
end

local function createSellZone()
    local sellZone = Workspace:FindFirstChild("SellZone")
    if sellZone then
        return sellZone
    end

    sellZone = Instance.new("Part")
    sellZone.Name = "SellZone"
    sellZone.Size = Vector3.new(14, 4, 14)
    sellZone.Position = Vector3.new(0, 1, 30)
    sellZone.Anchored = true
    sellZone.Color = Color3.fromRGB(60, 120, 255)
    sellZone.Material = Enum.Material.SmoothPlastic
    sellZone.CanCollide = false
    sellZone.Transparency = 0.3
    sellZone.Parent = Workspace

    return sellZone
end

function SellService.start()
    local sellZone = createSellZone()

    sellZone.Touched:Connect(function(hit)
        local character = hit.Parent
        local player = Players:GetPlayerFromCharacter(character)
        if not player then
            return
        end

        local fruitsCount = PlayerDataService.getFruits(player)
        if fruitsCount <= 0 then
            return
        end

        local earnedCoins = fruitsCount * Config.DEFAULT_FRUIT_SELL_PRICE

        -- Update coin and fruit values.
        local currentCoins = PlayerDataService.getCoins(player)
        PlayerDataService.setCoins(player, currentCoins + earnedCoins)
        PlayerDataService.setFruits(player, 0)

        -- Tell the player the result.
        fruitDebugEvent:FireClient(player, "__log", string.format(
            "Sold %d fruits for %d coins!",
            fruitsCount,
            earnedCoins
        ), 0, "server")
    end)
end

return SellService
