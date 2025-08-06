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
        snakeConfig = HttpService:JSONDecode(configJson)
        print("[Client] Using server-provided snake config")
    else
        -- Default config if server hasn't set one yet
        snakeConfig = {
            InitialLength = 10,
            BodyColors = {Color3.fromHex("#00FF00"), Color3.fromHex("#00DD00")},
            HeadColor = Color3.fromHex("#00FF00")
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
local character = player.Character or player.CharacterAdded:Wait()
setupSnake(character)

-- Also run the setup function every time the player RESPAWNS
player.CharacterAdded:Connect(setupSnake)