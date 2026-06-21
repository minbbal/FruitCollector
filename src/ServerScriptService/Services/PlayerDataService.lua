-- Handles player state.
-- This script creates leaderstats and keeps values server-side.

local Players = game:GetService("Players")

local PlayerDataService = {}

function PlayerDataService.setupPlayer(player)
    -- Leaderstats are shown in the Roblox leaderboard.
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local coins = Instance.new("IntValue")
    coins.Name = "Coins"
    coins.Value = 0
    coins.Parent = leaderstats

    local fruits = Instance.new("IntValue")
    fruits.Name = "Fruits"
    fruits.Value = 0
    fruits.Parent = leaderstats

    -- Keep player references if needed later.
    -- For now, nothing else is required.
end

function PlayerDataService.getLeaderstats(player)
    return player:FindFirstChild("leaderstats")
end

function PlayerDataService.getCoins(player)
    local leaderstats = PlayerDataService.getLeaderstats(player)
    if not leaderstats then
        return 0
    end

    local coins = leaderstats:FindFirstChild("Coins")
    if coins and coins:IsA("IntValue") then
        return coins.Value
    end

    return 0
end

function PlayerDataService.getFruits(player)
    local leaderstats = PlayerDataService.getLeaderstats(player)
    if not leaderstats then
        return 0
    end

    local fruits = leaderstats:FindFirstChild("Fruits")
    if fruits and fruits:IsA("IntValue") then
        return fruits.Value
    end

    return 0
end

function PlayerDataService.setCoins(player, amount)
    local leaderstats = PlayerDataService.getLeaderstats(player)
    if not leaderstats then
        return
    end

    local coins = leaderstats:FindFirstChild("Coins")
    if coins and coins:IsA("IntValue") then
        coins.Value = amount
    end
end

function PlayerDataService.setFruits(player, amount)
    local leaderstats = PlayerDataService.getLeaderstats(player)
    if not leaderstats then
        return
    end

    local fruits = leaderstats:FindFirstChild("Fruits")
    if fruits and fruits:IsA("IntValue") then
        fruits.Value = amount
    end
end

return PlayerDataService
