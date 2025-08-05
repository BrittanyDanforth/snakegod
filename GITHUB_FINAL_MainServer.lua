--[[
    MainServer.server.lua - FINAL FIXED VERSION
    Works alongside SnakeSystemIntegration
    
    GITHUB READY VERSION - All Fixes Applied
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Import modules
local ServerModules = ServerStorage:WaitForChild("ServerModules")
local PlayerController = require(ServerModules.PlayerController)
local CollisionModule = require(ServerModules.CollisionModule)

-- Shared configuration  
local Config = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Config"))

-- Player controller storage
local playerControllers = {}

-- Collision system
local collisionSystem = nil

-- Track existing snakes from SnakeSystemIntegration
local snakeSystemIntegration = nil
local existingSnakes = {} -- Track snakes created by the old system

-- Wait for SnakeSystemIntegration to load
local function waitForSnakeSystem()
    -- Find the SnakeSystemIntegration script
    for _, script in pairs(game:GetDescendants()) do
        if script.Name == "SnakeSystemIntegration" and script:IsA("Script") then
            snakeSystemIntegration = script
            break
        end
    end
end

-- Initialize systems
local function initializeSystems()
    warn("[MainServer] Initializing game systems...")
    
    -- Wait for existing systems
    waitForSnakeSystem()
    
    -- Initialize collision system
    collisionSystem = CollisionModule.new(playerControllers)
    collisionSystem:start()
    
    -- Disable the old InitializeCollisionHandler if it exists
    local collisionHandler = workspace:FindFirstChild("SnakeCollisionHandlerV1")
    if not collisionHandler then
        collisionHandler = workspace:FindFirstChild("SnakeCollisionHandler_FINAL")
    end
    if not collisionHandler then
        -- Try to find it in ServerScriptService
        collisionHandler = game.ServerScriptService:FindFirstChild("SnakeCollisionHandler_FINAL")
    end
    
    if collisionHandler and collisionHandler:IsA("Script") then
        collisionHandler.Disabled = true
        warn("[MainServer] Disabled InitializeCollisionHandler")
    end
    
    warn("[MainServer] Systems initialized successfully")
end

-- Handle player joining
local function onPlayerAdded(player)
    warn("[MainServer] Player joined:", player.Name)
    
    -- Create player controller
    local controller = PlayerController.new(player, Config)
    playerControllers[player] = controller
    
    -- Listen for snake creation from SnakeSystemIntegration
    local function checkForSnake()
        local snakeFolder = workspace:FindFirstChild("SnakeFolder")
        if snakeFolder then
            local playerSnake = snakeFolder:FindFirstChild(player.Name)
            if playerSnake then
                warn("[MainServer] Found snake from SnakeSystemIntegration for", player.Name)
                controller.snakeObject = playerSnake
                existingSnakes[player] = playerSnake
                
                -- Set initial state to Alive when snake is created
                if controller.fsm:getCurrentState() ~= "Alive" then
                    controller.fsm:changeState("Alive")
                end
            end
        end
    end
    
    -- Check periodically for snake creation
    local checkConnection
    checkConnection = RunService.Heartbeat:Connect(function()
        if controller.snakeObject or controller.isDestroyed then
            checkConnection:Disconnect()
            return
        end
        checkForSnake()
    end)
    
    -- Connect controller events to handle collision results
    for eventName, event in pairs(controller.events) do
        -- Death handling via new collision system
        event:Connect(function(collisionData)
            if eventName == "onFatalHit" then
                warn("[MainServer] FATAL COLLISION for", player.Name, "Type:", 
                    collisionData.isHeadCollision and "Head" or 
                    collisionData.isWallCollision and "Wall" or 
                    collisionData.isBodyCollision and "Body" or "Unknown")
                
                -- Get killer info
                if collisionData.killerPlayer then
                    warn("[MainServer] Killed by player:", collisionData.killerPlayer.Name)
                elseif collisionData.isAI then
                    warn("[MainServer] Killed by AI Snake")
                end
                
                -- Kill the player's character to trigger the existing death system
                local character = player.Character
                if character then
                    -- Set death attributes first
                    player:SetAttribute("IsDead", true)
                    player:SetAttribute("LastDeathTime", os.clock())
                    
                    -- Clear magnet immediately to stop orb attraction
                    player:SetAttribute("MagnetRange", 0)
                    player:SetAttribute("TempMagnetRange", 0)
                    player:SetAttribute("ActiveMagnet", false)
                    player:SetAttribute("HasMagnet", false)
                    player:SetAttribute("DisableOrbCollection", true)
                    
                    -- Store killer info
                    if collisionData.killerPlayer then
                        player:SetAttribute("KilledBy", collisionData.killerPlayer.Name)
                    elseif collisionData.isAI then
                        player:SetAttribute("KilledBy", "AI Snake")
                    else
                        player:SetAttribute("KilledBy", "Wall")
                    end
                    
                    -- Kill the humanoid to trigger existing death handling
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        humanoid.Health = 0
                    end
                    
                    -- The existing SnakeSystemIntegration will handle:
                    -- - Spawning orbs
                    -- - Removing the snake
                    -- - Showing death UI
                    -- - Etc.
                end
                
                -- Update FSM state
                controller.fsm:changeState("Dying", collisionData)
            elseif eventName == "onOrbCollision" then
                -- Let existing orb system handle collection
                -- The OrbSpawner system has all the logic
            end
        end)
    end
    
    -- Monitor character spawning
    player.CharacterAdded:Connect(function(character)
        warn("[MainServer] Character added for", player.Name)
        
        -- Reset controller state
        controller.snakeObject = nil
        
        -- Wait a bit for SnakeSystemIntegration to create the snake
        task.wait(1)
        checkForSnake()
        
        -- Also set up monitoring for snake creation
        local checkCount = 0
        task.spawn(function()
            while not controller.snakeObject and checkCount < 10 do
                task.wait(0.5)
                checkForSnake()
                checkCount = checkCount + 1
            end
        end)
    end)
    
    -- Handle character removal
    player.CharacterRemoving:Connect(function()
        if controller.snakeObject then
            controller.snakeObject = nil
        end
        if existingSnakes[player] then
            existingSnakes[player] = nil
        end
    end)
end

-- Handle player leaving
local function onPlayerRemoving(player)
    warn("[MainServer] Player leaving:", player.Name)
    
    local controller = playerControllers[player]
    if controller then
        -- Destroy controller (handles all cleanup)
        controller:destroy()
        playerControllers[player] = nil
    end
    
    if existingSnakes[player] then
        existingSnakes[player] = nil
    end
end

-- Remote event handlers
local function setupRemoteHandlers()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    
    -- Listen for respawn events from existing system
    local respawnRemote = remotes:FindFirstChild("RespawnSnake")
    if respawnRemote then
        respawnRemote.OnServerEvent:Connect(function(player)
            warn("[MainServer] Respawn requested for", player.Name)
            
            local controller = playerControllers[player]
            if controller then
                -- The existing system will handle snake creation
                -- We just update our state
                controller.fsm:changeState("Spawning")
                
                -- Wait for snake to be created
                task.spawn(function()
                    task.wait(1)
                    local snakeFolder = workspace:FindFirstChild("SnakeFolder")
                    if snakeFolder then
                        local playerSnake = snakeFolder:FindFirstChild(player.Name)
                        if playerSnake then
                            controller.snakeObject = playerSnake
                            existingSnakes[player] = playerSnake
                            controller.fsm:changeState("Alive")
                            warn("[MainServer] Player respawned and set to Alive state")
                        end
                    end
                end)
            end
        end)
    end
    
    -- Handle spectator camera cycling  
    local cycleSpectateRemote = remotes:FindFirstChild("CycleSpectateTarget")
    if not cycleSpectateRemote then
        cycleSpectateRemote = Instance.new("RemoteEvent")
        cycleSpectateRemote.Name = "CycleSpectateTarget"
        cycleSpectateRemote.Parent = remotes
    end
    
    cycleSpectateRemote.OnServerEvent:Connect(function(player, direction)
        local controller = playerControllers[player]
        if controller and controller.fsm:getCurrentState() == "Spectating" then
            local state = controller.fsm.currentState
            if state.cycleSpectateTarget then
                state:cycleSpectateTarget(direction or 1)
            end
        end
    end)
end

-- Main initialization
local function main()
    warn("[MainServer] Starting Modular Snake Controller...")
    warn("[MainServer] This works WITH SnakeSystemIntegration")
    
    -- Initialize core systems
    initializeSystems()
    
    -- Setup remote handlers
    setupRemoteHandlers()
    
    -- Connect player events
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Handle existing players (studio testing)
    for _, player in ipairs(Players:GetPlayers()) do
        onPlayerAdded(player)
    end
    
    warn("[MainServer] Modular controller ready!")
    warn("[MainServer] Collision system active")
end

-- Run main
main()