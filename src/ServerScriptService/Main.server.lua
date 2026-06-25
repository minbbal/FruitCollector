-- Main server script.
-- This file creates services and starts the game.

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.Services.PlayerDataService)
local SellService = require(script.Parent.Services.SellService)

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
SellService.start()

print("FruitCollector server started.")
