-- FruitDebugClient.client.lua
-- Always-on debug UI for fruit collection counts.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MAX_RECENT_LOGS = 8
local FRUIT_DEBUG_EVENT_NAME = "FruitDebugEvent"
local FRUIT_SOUND_EVENT_NAME = "FruitSoundEvent"
local FRUIT_RESPAWN_EFFECT_EVENT_NAME = "FruitRespawnEffectEvent"
local PICKUP_SOUND_ID = "rbxassetid://135483737426662"
local DROP_SOUND_ID = "rbxassetid://9120066881"
local JUMP_SOUND_ID = "rbxassetid://135162567109750"
local RESPAWN_SOUND_ID = "rbxassetid://80995537118101"
local RESPAWN_JINGLE_SOUND_ID = "rbxassetid://1841983099"
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
local RESPAWN_VOLUME = 0.8
local RESPAWN_JINGLE_VOLUME = 0.5
local JUMP_SOUND_COOLDOWN = 0.2
local RESPAWN_EFFECT_LIFETIME = 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local fruitDebugEvent = remotesFolder:WaitForChild(FRUIT_DEBUG_EVENT_NAME)
local fruitSoundEvent = remotesFolder:WaitForChild(FRUIT_SOUND_EVENT_NAME)
local fruitRespawnEffectEvent = remotesFolder:WaitForChild(FRUIT_RESPAWN_EFFECT_EVENT_NAME)

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

local function findSpawnLocation()
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("SpawnLocation") then
            return descendant
        end
    end

    return nil
end

local function playRespawnEffect()
    local spawnLocation = findSpawnLocation()
    if not spawnLocation then
        local message = "[RespawnEffect] SpawnLocation missing"
        warn(message)
        addRecentLog(message)
        return
    end

    addRecentLog("[RespawnEffect] start")

    local effectPart = Instance.new("Part")
    effectPart.Name = "FruitRespawnEffect"
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.CanTouch = false
    effectPart.CanQuery = false
    effectPart.Transparency = 1
    effectPart.Size = Vector3.new(1, 1, 1)
    effectPart.CFrame = CFrame.new(spawnLocation.Position + Vector3.new(0, spawnLocation.Size.Y * 0.5 + 3, 0))
    effectPart.Parent = workspace

    local attachment = Instance.new("Attachment")
    attachment.Parent = effectPart

    local light = Instance.new("PointLight")
    light.Brightness = 5
    light.Range = 18
    light.Color = Color3.fromRGB(255, 244, 180)
    light.Parent = attachment

    local particles = Instance.new("ParticleEmitter")
    particles.Rate = 90
    particles.Lifetime = NumberRange.new(0.7, 1.3)
    particles.Speed = NumberRange.new(5, 10)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(120, 220, 255))
    particles.LightEmission = 0.75
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.45, 0.55),
        NumberSequenceKeypoint.new(1, 0),
    })
    particles.Parent = attachment
    particles:Emit(80)

    playSound(RESPAWN_SOUND_ID, RESPAWN_VOLUME, "respawn")
    playSound(RESPAWN_JINGLE_SOUND_ID, RESPAWN_JINGLE_VOLUME, "respawn_jingle")

    task.delay(1.2, function()
        if particles.Parent then
            particles.Enabled = false
        end
        if light.Parent then
            light.Enabled = false
        end
    end)

    Debris:AddItem(effectPart, RESPAWN_EFFECT_LIFETIME)
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

    if fruitName == "__log" then
        addRecentLog(tostring(newTotalScore))
        return
    end

    if fruitName == "__score" then
        totalScore = newTotalScore
        renderDebugText()
        return
    end

    if fruitName == "__count" then
        fruitCounts[tostring(newTotalScore)] = fruitCount
        renderDebugText()
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

fruitRespawnEffectEvent.OnClientEvent:Connect(function()
    print("[RespawnEffect] Request received")
    playRespawnEffect()
end)

if player.Character then
    connectJumpSound(player.Character)
end

player.CharacterAdded:Connect(connectJumpSound)
