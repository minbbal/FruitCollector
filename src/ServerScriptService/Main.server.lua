-- Main server script.
-- This file creates services and starts the game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.Services.PlayerDataService)
local FruitSpawnerService = require(script.Parent.Services.FruitSpawnerService)
local SellService = require(script.Parent.Services.SellService)

local FruitMessage = ReplicatedStorage.Remotes:WaitForChild("FruitMessage")

local function initializePlayer(player)
    -- Create leaderstats and setup player data.
    PlayerDataService.setupPlayer(player)

    -- Optional future DataStore loading can go here.
    -- Example:
    -- PlayerDataService.loadPlayerData(player)
end

-- Initialize players already in game.
for _, player in Players:GetPlayers() do
    initializePlayer(player)
end

-- Initialize new players.
Players.PlayerAdded:Connect(function(player)
    initializePlayer(player)
end)

-- Clean up when player leaves.
Players.PlayerRemoving:Connect(function(player)
    -- Optional future DataStore saving can go here.
    -- PlayerDataService.savePlayerData(player)
end)

-- Start services.
FruitSpawnerService.start()
SellService.start()

print("FruitCollector server started.")
