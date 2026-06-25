-- Optional second UI script.
-- This script does the same job as the client script above.
-- You can keep one of them and delete the other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local FruitDebugEvent = remotesFolder:WaitForChild("FruitDebugEvent")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitGui"
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 320, 0, 50)
label.Position = UDim2.new(0.5, -160, 0, 80)
label.BackgroundTransparency = 1
label.Text = ""
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.Parent = screenGui

local function showMessage(text)
    label.Text = text
    task.spawn(function()
        task.wait(1.5)
        label.Text = ""
    end)
end

FruitDebugEvent.OnClientEvent:Connect(function(fruitName, newTotalScore)
    if fruitName == "__log" then
        showMessage(tostring(newTotalScore))
    elseif fruitName ~= "__spawn" and fruitName ~= "__score" and fruitName ~= "__count" then
        showMessage("+1 " .. tostring(fruitName))
    end
end)
