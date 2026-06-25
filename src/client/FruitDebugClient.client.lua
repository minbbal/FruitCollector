-- FruitDebugClient.client.lua
-- Always-on debug UI for fruit collection counts.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MAX_RECENT_LOGS = 8
local FRUIT_DEBUG_EVENT_NAME = "FruitDebugEvent"
local FRUIT_SOUND_EVENT_NAME = "FruitSoundEvent"
local PICKUP_SOUND_ID = "rbxassetid://135483737426662"
local DROP_SOUND_ID = "rbxassetid://9120066881"
local JUMP_SOUND_ID = "rbxassetid://135162567109750"
local PLACEHOLDER_SOUND_ID = "rbxassetid://" .. utf8.char(
    0xC5EC,
    0xAE30,
    0xC5D0,
    0x5F,
    0xC0AC,
    0xC6B4,
    0xB4DC,
    0x5F,
    0x49,
    0x44,
    0x5F,
    0xB123,
    0xAE30
)
local PICKUP_VOLUME = 1
local DROP_VOLUME = 0.6
local JUMP_VOLUME = 0.7
local JUMP_SOUND_COOLDOWN = 0.2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local fruitDebugEvent = ReplicatedStorage:WaitForChild(FRUIT_DEBUG_EVENT_NAME)
local fruitSoundEvent = ReplicatedStorage:WaitForChild(FRUIT_SOUND_EVENT_NAME)

local fruitCounts = {}
local recentLogs = {}
local totalScore = 0
local lastJumpSoundTime = 0

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FruitDebugGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 300, 0, 330)
panel.Position = UDim2.new(0, 12, 0, 12)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
panel.BackgroundTransparency = 0.18
panel.BorderSizePixel = 0
panel.Parent = screenGui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.Parent = panel

local label = Instance.new("TextLabel")
label.Name = "DebugText"
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextColor3 = Color3.fromRGB(245, 248, 255)
label.TextSize = 15
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextWrapped = false
label.Text = "Fruit Debug\nTotal Score: 0\n\nRecent Log:"
label.Parent = panel

local function getSortedFruitNames()
    local names = {}
    for fruitName in pairs(fruitCounts) do
        table.insert(names, fruitName)
    end

    table.sort(names)
    return names
end

local function renderDebugText()
    local lines = {
        "Fruit Debug",
        "Total Score: " .. tostring(totalScore),
        "",
    }

    for _, fruitName in ipairs(getSortedFruitNames()) do
        table.insert(lines, fruitName .. ": " .. tostring(fruitCounts[fruitName]))
    end

    table.insert(lines, "")
    table.insert(lines, "Recent Log:")

    for _, logLine in ipairs(recentLogs) do
        table.insert(lines, logLine)
    end

    label.Text = table.concat(lines, "\n")
end

local function addRecentLog(logLine)
    table.insert(recentLogs, 1, logLine)
    while #recentLogs > MAX_RECENT_LOGS do
        table.remove(recentLogs)
    end

    renderDebugText()
end

local function isMissingSoundId(soundId)
    return soundId == nil or soundId == "" or soundId == PLACEHOLDER_SOUND_ID
end

local function playSound(soundId, volume, labelText)
    if isMissingSoundId(soundId) then
        local message = "[SoundDebug] " .. labelText .. " sound id missing"
        warn(message)
        addRecentLog(message)
        return false
    end

    local sound = Instance.new("Sound")
    sound.Name = "FruitSound_" .. labelText
    sound.SoundId = soundId
    sound.Volume = volume
    sound.Parent = SoundService

    print("[FruitSound] Playing:", labelText, soundId)
    addRecentLog("[SoundDebug] playing " .. labelText)

    sound.Ended:Connect(function()
        sound:Destroy()
    end)

    Debris:AddItem(sound, 5)
    sound:Play()
    return true
end

local function connectJumpSound(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then
        warn("[SoundDebug] jump sound failed: Humanoid missing")
        addRecentLog("[SoundDebug] jump humanoid missing")
        return
    end

    humanoid.Jumping:Connect(function(isActive)
        if not isActive then
            return
        end

        local now = os.clock()
        if now - lastJumpSoundTime < JUMP_SOUND_COOLDOWN then
            return
        end

        lastJumpSoundTime = now
        playSound(JUMP_SOUND_ID, JUMP_VOLUME, "jump")
    end)
end

fruitDebugEvent.OnClientEvent:Connect(function(fruitName, newTotalScore, fruitCount, playerName)
    if fruitName == "__spawn" then
        addRecentLog("Spawned " .. tostring(newTotalScore))
        return
    end

    totalScore = newTotalScore
    fruitCounts[fruitName] = fruitCount

    addRecentLog(string.format("+1 %s / Total %d", fruitName, newTotalScore))

    print(string.format(
        "[FruitDebugClient] %s collected %s / FruitCount: %d / TotalScore: %d",
        playerName,
        fruitName,
        fruitCount,
        newTotalScore
    ))
end)

fruitSoundEvent.OnClientEvent:Connect(function(action, fruitName)
    print("[FruitSound] Request received:", action, fruitName)
    addRecentLog("[SoundDebug] request " .. tostring(action) .. " " .. tostring(fruitName))

    if action == "pickup" then
        playSound(PICKUP_SOUND_ID, PICKUP_VOLUME, "pickup")
    elseif action == "drop" then
        playSound(DROP_SOUND_ID, DROP_VOLUME, "drop")
    else
        local message = "[SoundDebug] unknown sound action " .. tostring(action)
        warn(message)
        addRecentLog(message)
    end
end)

if player.Character then
    connectJumpSound(player.Character)
end

player.CharacterAdded:Connect(connectJumpSound)
