-- THIS IS THE ENTIRE SCRIPT FOR: StarterPlayer > StarterPlayerScripts > ClientSnakeController

print("[Client] ClientSnakeController started.")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Get the module, but do NOT run it yet.
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the system on the client
if OptimizedSnakeSystemV9.init then
    OptimizedSnakeSystemV9.init()
end

local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local snakeVisuals = nil -- Variable to hold our snake instance

-- Create/get remote for sending input to server
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) -- 10 second timeout
local mouseDirectionRemote = nil
if remoteEvents then
    mouseDirectionRemote = remoteEvents:FindFirstChild("UpdateMouseDirection") or remoteEvents:WaitForChild("UpdateMouseDirection", 5)
else
    warn("[Client] RemoteEvents folder not found!")
end

-- Movement constants for client-side prediction
local BASE_SPEED = 35
local BOOST_SPEED = 55
local TURN_SPEED = 3

-- This function creates the snake. We will call it whenever the player spawns.
local function setupSnake(character)
    print("[Client] Character detected:", character.Name, ". Setting up snake visuals.")

    -- If there's an old snake, destroy it first (for respawning)
    if snakeVisuals and typeof(snakeVisuals.destroy) == "function" then
        print("[Client] Destroying old snake visuals.")
        snakeVisuals:destroy()
        snakeVisuals = nil
    end

    -- 1. Wait for the server to finish preparing the data
    print("[Client] Waiting for SnakeConfig attribute from server...")
    local configJson = character:GetAttribute("SnakeConfig")
    if not configJson then
        -- If the attribute isn't there yet, wait for it. This prevents race conditions.
        local connection
        connection = character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            configJson = character:GetAttribute("SnakeConfig")
            if configJson then
                connection:Disconnect()
            end
        end)
        
        -- Also add a timeout
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
        warn("[Client] Timeout waiting for SnakeConfig from server!")
        return
    end
    
    print("[Client] Received SnakeConfig from server.")

    -- 2. Decode the data from a string back into a Lua table
    local decodedConfig = HttpService:JSONDecode(configJson)
    
    if not decodedConfig then
        warn("[Client] FAILED to decode snake config!")
        return
    end
    
    -- 3. Fix Color3 values (they don't serialize properly through JSON)
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

    -- 4. Create the new snake visuals USING the config from the server
    snakeVisuals = OptimizedSnakeSystemV9.createSnake(character, snakeConfig)

    if snakeVisuals then
        print("[Client] Snake visuals created successfully with length:", snakeConfig.InitialLength)
        
        -- Listen for config updates
        character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            local newConfigJson = character:GetAttribute("SnakeConfig")
            if newConfigJson and snakeVisuals then
                local newDecodedConfig = HttpService:JSONDecode(newConfigJson)
                -- Convert colors again
                local newConfig = {
                    HeadColor = newDecodedConfig.HeadColor and Color3.new(newDecodedConfig.HeadColor.R, newDecodedConfig.HeadColor.G, newDecodedConfig.HeadColor.B),
                    BodyColors = {}
                }
                if newDecodedConfig.BodyColors then
                    for i, colorData in ipairs(newDecodedConfig.BodyColors) do
                        newConfig.BodyColors[i] = Color3.new(colorData.R, colorData.G, colorData.B)
                    end
                end
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

-- Clean spawn logic - connect once and check for existing character
player.CharacterAdded:Connect(setupSnake)

-- If the character already exists when the script runs, set it up
if player.Character then
    setupSnake(player.Character)
end

-- Client-side prediction for instant movement
local lastSentTime = 0

RunService.Heartbeat:Connect(function(deltaTime)
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- 1. Get Mouse Position in the 3D world
    local mouse = player:GetMouse()
    local mousePos = mouse.Hit.Position
    
    -- Project to the snake's plane (Y = 5)
    local targetPosition = Vector3.new(mousePos.X, 5, mousePos.Z)
    
    -- 2. Calculate the direction from the snake to the mouse
    local currentPos = rootPart.Position
    local directionToMouse = (targetPosition - currentPos)
    
    -- Only move if the mouse is far enough away (prevents jittering)
    if directionToMouse.Magnitude > 5 then
        local targetDirection = directionToMouse.Unit
        
        -- 3. Smoothly rotate the character to face the new direction
        local currentDirection = rootPart.CFrame.LookVector
        local newDirection = currentDirection:Lerp(targetDirection, TURN_SPEED * deltaTime)
        
        -- Ensure the direction is normalized
        if newDirection.Magnitude > 0 then
            newDirection = newDirection.Unit
            
            -- 4. Move the character forward (client-side prediction)
            local isBoosting = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or 
                             UserInputService:IsKeyDown(Enum.KeyCode.Space)
            local currentSpeed = isBoosting and BOOST_SPEED or BASE_SPEED
            
            local newPosition = currentPos + (newDirection * currentSpeed * deltaTime)
            -- Keep at ground level
            newPosition = Vector3.new(newPosition.X, 5, newPosition.Z)
            
            -- 5. Apply the new CFrame. This moves the snake INSTANTLY on your screen.
            rootPart.CFrame = CFrame.lookAt(newPosition, newPosition + newDirection)
        end
        
        -- 6. Send the direction to the server periodically
        local currentTime = tick()
        if currentTime - lastSentTime > 0.033 then -- 30Hz update rate
            lastSentTime = currentTime
            
            -- Store locally for other systems
            char:SetAttribute("MouseDirection", targetDirection)
            
            -- Send to server
            if mouseDirectionRemote then
                mouseDirectionRemote:FireServer(targetDirection)
            end
        end
    end
end)