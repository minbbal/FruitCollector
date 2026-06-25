-- Client-side script for receiving fruit messages.
-- This script only shows information and does not change game data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local FruitDebugEvent = remotesFolder:WaitForChild("FruitDebugEvent")

local function createMessageLabel()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FruitDebugMessageGui"
    screenGui.Parent = playerGui

    local label = Instance.new("TextLabel")
    label.Name = "MessageLabel"
    label.Size = UDim2.new(0, 300, 0, 60)
    label.Position = UDim2.new(0.5, -150, 0, 20)
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.GothamBold
    label.Parent = screenGui

    return label
end

local messageLabel = createMessageLabel()

local function showMessage(text)
    messageLabel.Text = text

    -- Fade out after a short time.
    task.spawn(function()
        task.wait(1.5)
        messageLabel.Text = ""
    end)
end

FruitDebugEvent.OnClientEvent:Connect(function(fruitName, newTotalScore)
    if fruitName == "__log" then
        showMessage(tostring(newTotalScore))
    elseif fruitName ~= "__spawn" and fruitName ~= "__score" and fruitName ~= "__count" then
        showMessage("+1 " .. tostring(fruitName))
    end
end)
