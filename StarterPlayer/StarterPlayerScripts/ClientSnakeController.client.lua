-- THIS IS THE ENTIRE SCRIPT FOR: StarterPlayer > StarterPlayerScripts > ClientSnakeController

print("[Client] ClientSnakeController started.")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get the module, but do NOT run it yet.
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the system on the client
if OptimizedSnakeSystemV9.init then
    OptimizedSnakeSystemV9.init()
end

local player = Players.LocalPlayer
local snakeVisuals = nil -- Variable to hold our snake instance

-- Create/get remote for sending input to server
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) -- 10 second timeout
local mouseDirectionRemote = nil
if remoteEvents then
    mouseDirectionRemote = remoteEvents:FindFirstChild("UpdateMouseDirection") or remoteEvents:WaitForChild("UpdateMouseDirection", 5)
else
    warn("[Client] RemoteEvents folder not found!")
end

-- This function creates the snake. We will call it whenever the player spawns.
local function setupSnake(character)
    print("[Client] Character detected:", character.Name, ". Setting up snake visuals.")

    -- If there's an old snake, destroy it first (for respawning)
    if snakeVisuals and typeof(snakeVisuals.destroy) == "function" then
        print("[Client] Destroying old snake visuals.")
        snakeVisuals:destroy()
        snakeVisuals = nil
    end

    -- Wait for server to set the config (with timeout)
    local startTime = tick()
    local timeout = 5 -- 5 second timeout
    
    while not character:GetAttribute("SnakeConfig") and (tick() - startTime) < timeout do
        wait(0.1)
    end

    -- Get config from server attributes or use default
    local snakeConfig
    local configJson = character:GetAttribute("SnakeConfig")
    if configJson then
        local HttpService = game:GetService("HttpService")
        local decodedConfig = HttpService:JSONDecode(configJson)
        
        -- Validate and fix color properties
        snakeConfig = {
            InitialLength = decodedConfig.InitialLength or 85,
            HeadColor = decodedConfig.HeadColor and Color3.new(decodedConfig.HeadColor.R or decodedConfig.HeadColor[1], decodedConfig.HeadColor.G or decodedConfig.HeadColor[2], decodedConfig.HeadColor.B or decodedConfig.HeadColor[3]) or Color3.fromRGB(76, 217, 100),
            BodyColors = {},
            HeadMaterial = decodedConfig.HeadMaterial or Enum.Material.Neon,
            BodyMaterial = decodedConfig.BodyMaterial or Enum.Material.Neon,
            SegmentSize = decodedConfig.SegmentSize or Vector3.new(4, 4, 4),
            HeadSize = decodedConfig.HeadSize or Vector3.new(4.5, 4.5, 4.5),
            SegmentSpacing = decodedConfig.SegmentSpacing or 3.2,
            MaxSegments = decodedConfig.MaxSegments or 50000
        }
        
        -- Convert body colors
        if decodedConfig.BodyColors then
            for i, colorData in ipairs(decodedConfig.BodyColors) do
                if type(colorData) == "table" then
                    snakeConfig.BodyColors[i] = Color3.new(colorData.R or colorData[1], colorData.G or colorData[2], colorData.B or colorData[3])
                else
                    snakeConfig.BodyColors[i] = Color3.fromRGB(60, 180, 80) -- Default green
                end
            end
        else
            -- Default body colors
            snakeConfig.BodyColors = {
                Color3.fromRGB(60, 180, 80),
                Color3.fromRGB(80, 200, 100),
                Color3.fromRGB(100, 220, 120),
                Color3.fromRGB(80, 200, 100),
                Color3.fromRGB(60, 180, 80),
            }
        end
        
        print("[Client] Using server-provided snake config with validated colors")
    else
        -- Default config if server hasn't set one yet
        snakeConfig = {
            InitialLength = 85,
            BodyColors = {
                Color3.fromRGB(60, 180, 80),
                Color3.fromRGB(80, 200, 100),
                Color3.fromRGB(100, 220, 120),
                Color3.fromRGB(80, 200, 100),
                Color3.fromRGB(60, 180, 80),
            },
            HeadColor = Color3.fromRGB(76, 217, 100),
            HeadMaterial = Enum.Material.Neon,
            BodyMaterial = Enum.Material.Neon,
            SegmentSize = Vector3.new(4, 4, 4),
            HeadSize = Vector3.new(4.5, 4.5, 4.5),
            SegmentSpacing = 3.2,
            MaxSegments = 50000
        }
        warn("[Client] Timeout waiting for server config, using default")
    end

    -- Create the new snake visuals
    snakeVisuals = OptimizedSnakeSystemV9.createSnake(character, snakeConfig)

    if snakeVisuals then
        print("[Client] Snake visuals created successfully.")
        
        -- Listen for config updates
        character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            local newConfigJson = character:GetAttribute("SnakeConfig")
            if newConfigJson and snakeVisuals then
                local HttpService = game:GetService("HttpService")
                local newConfig = HttpService:JSONDecode(newConfigJson)
                -- Update visual properties if the snake system supports it
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
    else
        warn("[Client] FAILED to create snake visuals!")
    end
end

-- Run the setup function when the player's character first appears
print("[Client] Waiting for character...")
local character = player.Character
if character then
    print("[Client] Character already exists!")
    setupSnake(character)
else
    print("[Client] Waiting for CharacterAdded event...")
    character = player.CharacterAdded:Wait()
    setupSnake(character)
end

-- Also run the setup function every time the player RESPAWNS
player.CharacterAdded:Connect(function(char)
    print("[Client] Character respawned!")
    setupSnake(char)
end)

-- Handle mouse input
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")

local function getMouseWorldPosition()
    local mouse = player:GetMouse()
    local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
    
    -- Cast ray to Y=5 plane (ground level)
    local t = (5 - ray.Origin.Y) / ray.Direction.Y
    local hitPos = ray.Origin + ray.Direction * t
    
    return hitPos
end

-- Send mouse direction to server
local lastSentTime = 0
RunService.Heartbeat:Connect(function()
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local currentTime = tick()
    if currentTime - lastSentTime > 0.033 then -- 30Hz update rate
        lastSentTime = currentTime
        
        local mousePos = getMouseWorldPosition()
        local rootPos = player.Character.HumanoidRootPart.Position
        local direction = (mousePos - rootPos).Unit
        
        -- Store locally for client prediction
        player.Character:SetAttribute("MouseDirection", direction)
        
        -- Send to server if remote exists
        if mouseDirectionRemote then
            mouseDirectionRemote:FireServer(direction)
        end
    end
end)