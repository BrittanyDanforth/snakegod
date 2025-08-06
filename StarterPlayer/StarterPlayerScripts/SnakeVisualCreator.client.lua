-- SNAKE VISUAL CREATOR
-- This script creates the visual snake using OptimizedSnakeSystemV9
-- Works alongside SnakeMovement.client.lua for complete snake functionality

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Get the visual module
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the visual system
if OptimizedSnakeSystemV9.init then
    OptimizedSnakeSystemV9.init()
end

local player = Players.LocalPlayer
local snakeVisuals = nil

local function createSnakeVisuals(character)
    print("[SnakeVisualCreator] Creating visual snake for character:", character.Name)
    
    -- Clean up old visuals
    if snakeVisuals and typeof(snakeVisuals.destroy) == "function" then
        print("[SnakeVisualCreator] Destroying old snake visuals")
        snakeVisuals:destroy()
        snakeVisuals = nil
    end
    
    -- Wait for server config
    print("[SnakeVisualCreator] Waiting for SnakeConfig attribute from server...")
    local configJson = character:GetAttribute("SnakeConfig")
    if not configJson then
        local connection
        connection = character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            configJson = character:GetAttribute("SnakeConfig")
            if configJson then
                connection:Disconnect()
            end
        end)
        
        local startTime = tick()
        while not configJson and tick() - startTime < 5 do
            wait(0.1)
            configJson = character:GetAttribute("SnakeConfig")
        end
        
        if connection then
            connection:Disconnect()
        end
    end
    
    if not configJson then
        warn("[SnakeVisualCreator] Timeout waiting for SnakeConfig from server!")
        return
    end
    
    -- Decode config
    local decodedConfig = HttpService:JSONDecode(configJson)
    if not decodedConfig then
        warn("[SnakeVisualCreator] Failed to decode snake config!")
        return
    end
    
    -- Fix Color3 and Vector3 values
    local snakeConfig = {
        InitialLength = decodedConfig.InitialLength,
        MaxSegments = decodedConfig.MaxSegments,
        SegmentSpacing = decodedConfig.SegmentSpacing,
        SegmentSize = decodedConfig.SegmentSize and Vector3.new(decodedConfig.SegmentSize.X, decodedConfig.SegmentSize.Y, decodedConfig.SegmentSize.Z),
        HeadSize = decodedConfig.HeadSize and Vector3.new(decodedConfig.HeadSize.X, decodedConfig.HeadSize.Y, decodedConfig.HeadSize.Z),
        HeadMaterial = decodedConfig.HeadMaterial,
        BodyMaterial = decodedConfig.BodyMaterial,
        GlowIntensity = decodedConfig.GlowIntensity,
        GlowRange = decodedConfig.GlowRange,
        HeadColor = decodedConfig.HeadColor and Color3.new(decodedConfig.HeadColor.R, decodedConfig.HeadColor.G, decodedConfig.HeadColor.B),
        BodyColors = {}
    }
    
    -- Convert body colors
    if decodedConfig.BodyColors then
        for i, colorData in ipairs(decodedConfig.BodyColors) do
            snakeConfig.BodyColors[i] = Color3.new(colorData.R, colorData.G, colorData.B)
        end
    end
    
    -- Create visual snake
    snakeVisuals = OptimizedSnakeSystemV9.createSnake(character, snakeConfig)
    
    if not snakeVisuals then
        warn("[SnakeVisualCreator] Failed to create snake visuals!")
        return
    end
    
    print("[SnakeVisualCreator] Snake visuals created successfully with length:", snakeConfig.InitialLength)
    
    -- Store reference globally for other systems
    _G.SnakeVisuals = snakeVisuals
    
    -- Listen for config updates
    character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
        local newConfigJson = character:GetAttribute("SnakeConfig")
        if newConfigJson and snakeVisuals then
            local newDecodedConfig = HttpService:JSONDecode(newConfigJson)
            local newConfig = {
                HeadColor = newDecodedConfig.HeadColor and Color3.new(newDecodedConfig.HeadColor.R, newDecodedConfig.HeadColor.G, newDecodedConfig.HeadColor.B),
                BodyColors = {}
            }
            if newDecodedConfig.BodyColors then
                for i, colorData in ipairs(newDecodedConfig.BodyColors) do
                    newConfig.BodyColors[i] = Color3.new(colorData.R, colorData.G, colorData.B)
                end
            end
            if snakeVisuals.updateConfig then
                snakeVisuals:updateConfig(newConfig)
            end
        end
    end)
    
    -- Listen for length updates
    character:GetAttributeChangedSignal("SnakeLength"):Connect(function()
        local newLength = character:GetAttribute("SnakeLength")
        if newLength and snakeVisuals and snakeVisuals.updateLength then
            snakeVisuals:updateLength(newLength)
        end
    end)
    
    -- Listen for boost state
    character:GetAttributeChangedSignal("IsBoosting"):Connect(function()
        local isBoosting = character:GetAttribute("IsBoosting")
        if snakeVisuals and snakeVisuals.setBoosting then
            snakeVisuals:setBoosting(isBoosting)
        end
    end)
end

-- Connect to character spawning
player.CharacterAdded:Connect(createSnakeVisuals)

-- Handle existing character
if player.Character then
    createSnakeVisuals(player.Character)
end

print("[SnakeVisualCreator] Loaded - handles visual snake creation")