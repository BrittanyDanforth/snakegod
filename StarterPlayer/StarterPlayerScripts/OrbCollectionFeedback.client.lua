-- Death Orb Collection Feedback
-- Shows minimal UI feedback when collecting death orbs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create UI for feedback
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OrbCollectionFeedback"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10 -- Ensure it's on top
screenGui.Parent = playerGui

-- Wait for the remote event
local OrbCollectedEvent = ReplicatedStorage:WaitForChild("OrbCollected", 5)
if not OrbCollectedEvent then
    warn("OrbCollected event not found")
    return
end

-- Keep track of active labels to prevent overlap
local activeLabels = {}
local lastFeedbackTime = 0
local feedbackCooldown = 0.1 -- Minimum time between feedback displays

-- Create a function to show collection feedback
local function showCollectionFeedback(position, orbName, isDeathOrb, orbValue)
    if not isDeathOrb then return end -- Only show special feedback for death orbs
    
    -- Throttle feedback to prevent spam
    local currentTime = tick()
    if currentTime - lastFeedbackTime < feedbackCooldown then
        return -- Skip this feedback
    end
    lastFeedbackTime = currentTime
    
    -- Limit active labels
    if #activeLabels > 5 then
        return -- Too many active labels, skip
    end
    
    -- Get viewport size
    local viewportSize = workspace.CurrentCamera.ViewportSize
    
    -- Random position on screen (avoid edges)
    local margin = 100
    local randomX = math.random(margin, viewportSize.X - margin)
    local randomY = math.random(margin, viewportSize.Y - margin)
    
    -- Check if position is too close to other active labels
    for _, label in pairs(activeLabels) do
        if label and label.Parent then
            local labelPos = label.Position
            local dx = math.abs(labelPos.X.Offset - randomX)
            local dy = math.abs(labelPos.Y.Offset - randomY)
            if dx < 80 and dy < 40 then
                -- Too close, adjust position
                randomX = math.random(margin, viewportSize.X - margin)
                randomY = math.random(margin, viewportSize.Y - margin)
            end
        end
    end
    
    -- Create a small text label that shows the value collected
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 60, 0, 30)
    label.Position = UDim2.new(0, randomX, 0, randomY)
    label.BackgroundTransparency = 1
    label.Text = "+" .. tostring(orbValue or 1)
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.3
    label.Font = Enum.Font.SourceSansBold
    label.Parent = screenGui
    
    -- Add to active labels
    table.insert(activeLabels, label)
    
    -- Simple fade out animation
    local fadeInfo = TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local fadeTween = TweenService:Create(label, fadeInfo, {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        Position = UDim2.new(0, randomX, 0, randomY - 30) -- Slight upward drift
    })
    
    -- Play animation
    fadeTween:Play()
    
    -- Clean up when done
    fadeTween.Completed:Connect(function()
        -- Remove from active labels
        for i, activeLabel in ipairs(activeLabels) do
            if activeLabel == label then
                table.remove(activeLabels, i)
                break
            end
        end
        label:Destroy()
    end)
end

-- Connect to the event
OrbCollectedEvent.OnClientEvent:Connect(function(orbPos, orbName, isDeathOrb, orbValue)
    showCollectionFeedback(orbPos, orbName, isDeathOrb, orbValue)
end)

print("Death Orb Collection Feedback loaded!")