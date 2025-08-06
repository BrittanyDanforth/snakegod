-- Death Orb Collection Feedback
-- Shows special UI feedback when collecting death orbs

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
screenGui.Parent = playerGui

-- Wait for the remote event
local OrbCollectedEvent = ReplicatedStorage:WaitForChild("OrbCollected", 5)
if not OrbCollectedEvent then
    warn("OrbCollected event not found")
    return
end

-- Create a function to show collection feedback
local function showCollectionFeedback(position, orbName, isDeathOrb, orbValue)
    if not isDeathOrb then return end -- Only show special feedback for death orbs
    
    -- Create a text label that shows the value collected
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 200, 0, 50)
    label.Position = UDim2.new(0.5, -100, 0.5, -25)
    label.BackgroundTransparency = 1
    label.Text = "+" .. tostring(orbValue or 1)
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 200, 0)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.SourceSansBold
    label.Parent = screenGui
    
    -- Add a sub-label for death orb indication
    local subLabel = Instance.new("TextLabel")
    subLabel.Size = UDim2.new(1, 0, 0.4, 0)
    subLabel.Position = UDim2.new(0, 0, 1, -5)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "REVENGE ORB!"
    subLabel.TextScaled = true
    subLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    subLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    subLabel.TextStrokeTransparency = 0
    subLabel.Font = Enum.Font.SourceSansItalic
    subLabel.Parent = label
    
    -- Convert 3D position to screen position
    local camera = workspace.CurrentCamera
    local screenPos, onScreen = camera:WorldToViewportPoint(position)
    
    if onScreen then
        label.Position = UDim2.new(0, screenPos.X - 100, 0, screenPos.Y - 25)
    end
    
    -- Animate the label
    local startSize = label.Size
    local endSize = UDim2.new(0, 300, 0, 75)
    
    -- Scale up animation
    local scaleTween = TweenService:Create(label,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {
            Size = endSize,
            Position = UDim2.new(0, screenPos.X - 150, 0, screenPos.Y - 37.5)
        }
    )
    scaleTween:Play()
    
    -- Float up and fade animation
    task.wait(0.3)
    local floatTween = TweenService:Create(label,
        TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(0, screenPos.X - 150, 0, screenPos.Y - 100),
            TextTransparency = 1,
            TextStrokeTransparency = 1
        }
    )
    
    local subFloatTween = TweenService:Create(subLabel,
        TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            TextTransparency = 1,
            TextStrokeTransparency = 1
        }
    )
    
    floatTween:Play()
    subFloatTween:Play()
    
    -- Rainbow effect during animation
    local connection
    local hue = 0
    connection = RunService.Heartbeat:Connect(function(dt)
        hue = (hue + dt * 2) % 1
        label.TextColor3 = Color3.fromHSV(hue, 1, 1)
    end)
    
    floatTween.Completed:Connect(function()
        if connection then
            connection:Disconnect()
        end
        label:Destroy()
    end)
    
    -- Screen flash effect
    local flash = Instance.new("Frame")
    flash.Size = UDim2.new(1, 0, 1, 0)
    flash.Position = UDim2.new(0, 0, 0, 0)
    flash.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    flash.BackgroundTransparency = 0.8
    flash.Parent = screenGui
    
    local flashTween = TweenService:Create(flash,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 1}
    )
    flashTween:Play()
    flashTween.Completed:Connect(function()
        flash:Destroy()
    end)
end

-- Connect to the event
OrbCollectedEvent.OnClientEvent:Connect(function(orbPos, orbName, isDeathOrb, orbValue)
    showCollectionFeedback(orbPos, orbName, isDeathOrb, orbValue)
end)

print("Death Orb Collection Feedback loaded!")