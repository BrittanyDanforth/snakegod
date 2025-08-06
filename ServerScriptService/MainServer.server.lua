--[[
    MainServer.server.lua - FIXED VERSION
    Works alongside SnakeSystemIntegration
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

-- Module references
local playerControllers = {}
local collisionSystem = nil
local snakeSystemIntegration = nil
local existingSnakes = {} -- Track snakes created by the old system
local deathOrbHandler = nil -- Will be initialized later

-- Initialize death orb handler
task.spawn(function()
    -- Try to load SnakeCollisionHandler for death orb spawning
    local collisionHandler = workspace:WaitForChild("SnakeCollisionHandler_FINAL", 5)
    if collisionHandler then
        local success, handler = pcall(require, collisionHandler)
        if success and handler then
            deathOrbHandler = handler
        end
    end
end)

-- Wait for snake system to be available
local function waitForSnakeSystem()
    -- SnakeSystemIntegration should already be loaded
    -- Just verify it exists
    local integration = game.ServerScriptService:FindFirstChild("SnakeSystemIntegration") or 
                       workspace:FindFirstChild("SnakeSystemIntegration")
    
    if integration then
        local success, module = pcall(require, integration)
        if success then
            snakeSystemIntegration = module
            return true
        end
    end
    
    return false
end

-- Create/verify remote events
local function createRemoteEvents()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        remotes = Instance.new("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
    end
    
    -- Create necessary remote events if they don't exist
    local requiredRemotes = {
        "PromptRevive",
        "ReviveResponse",
        "UpdateReviveCountdown",
        "CancelRevive",
        "ControlDeathUI",
        "FreezeCamera",
        "UpdateBoostState"
    }
    
    for _, remoteName in ipairs(requiredRemotes) do
        if not remotes:FindFirstChild(remoteName) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = remoteName
            remote.Parent = remotes
        end
    end
    
    -- warn("[MainServer] Created/verified remote events")
end

-- Initialize systems
local function initializeSystems()
    print("[MainServer] Initializing game systems...")
    
    -- Create RemoteEvents
    createRemoteEvents()
    
    -- Initialize collision system
    collisionSystem = CollisionModule.new()
    collisionSystem:start()
    
    -- Other initialization can go here
end

-- Handle player joining
local function setupPlayer(player)
    -- warn("[MainServer] Player joined:", player.Name)
    
    -- Check if controller already exists (for respawn cases)
    if playerControllers[player] then
        -- warn("[MainServer] Controller already exists for", player.Name, "- cleaning up old controller")
        local oldController = playerControllers[player]
        oldController:destroy()
        playerControllers[player] = nil
    end
    
    -- Create controller
    local controller = PlayerController.new(player, Config)
    playerControllers[player] = controller
    
    -- Register with collision system
    if collisionSystem then
        collisionSystem:registerController(player, controller)
    end
    
    -- Expose controller for debugging
    if not _G.PlayerControllers then
        _G.PlayerControllers = {}
    end
    _G.PlayerControllers[player] = controller
    
        -- Listen for snake creation from SnakeSystemIntegration
    local function checkForSnake()
        -- Get current controller
        local currentController = playerControllers[player]
        if not currentController then return end
        
        -- Check for snake in multiple locations
        local snakeModel = nil
        
        -- Check character
        if player.Character then
            snakeModel = player.Character:FindFirstChild("Snake_" .. player.Name)
        end
        
        -- Check workspace Snakes folder
        if not snakeModel then
            local snakesFolder = workspace:FindFirstChild("Snakes")
            if snakesFolder then
                snakeModel = snakesFolder:FindFirstChild("Snake_" .. player.Name)
            end
        end
        
        -- Check global PlayerSnakes table
        if not snakeModel and _G.PlayerSnakes and _G.PlayerSnakes[player] then
            local globalSnake = _G.PlayerSnakes[player]
            if globalSnake.model then
                snakeModel = globalSnake.model
            end
        end
        
        if snakeModel then
            -- Store snake object reference
            currentController.snakeObject = snakeModel
            currentController.snakeModel = snakeModel
            
            -- Find the head
            local head = snakeModel:FindFirstChild("Segment0_Head")
            if head then
                print("[MainServer] Found snake for", player.Name, "with head:", head.Name)
                
                -- Player is ready, set to Alive state
                currentController.fsm:changeState("Alive")
                
                -- Stop tracking this snake
                existingSnakes[player] = true
            else
                warn("[MainServer] Snake found but no head for", player.Name)
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
        -- We only need to handle orb collection here
        -- Fatal hits are already handled by PlayerController
        event:Connect(function(data)
            if eventName == "onOrbCollision" then
                -- Let existing orb system handle collection
                -- The OrbSpawner system has all the logic
            end
        end)
    end
    
    -- Monitor character spawning
    local characterAddedConnection = player.CharacterAdded:Connect(function(character)
        -- warn("[MainServer] Character added for", player.Name)
        
        -- Only handle if this is NOT a revive
        local isReviving = player:GetAttribute("IsReviving")
        if isReviving then
            -- warn("[MainServer] This is a revive spawn, letting SnakeSystemIntegration handle snake creation")
            return
        end
        
        -- Set up death handler for orb spawning
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.Died:Connect(function()
            -- Get snake length for orb calculation
            local snakeLength = 55 -- default
            if player:FindFirstChild("leaderstats") then
                local lengthValue = player.leaderstats:FindFirstChild("Length")
                if lengthValue then
                    snakeLength = lengthValue.Value or 55
                end
            end
            
            -- Get death position
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local deathPosition = rootPart and rootPart.Position or Vector3.new(0, 5, 0)
            
            -- Spawn death orbs
            if deathOrbHandler then
                deathOrbHandler:spawnDeathOrbsForPlayer(player, snakeLength, deathPosition)
            end
        end)
        
        -- Wait a bit for SnakeSystemIntegration to create the snake
        task.wait(1)
        checkForSnake()
        
        -- Also set up monitoring for snake creation
        local checkCount = 0
        task.spawn(function()
            while checkCount < 10 do
                task.wait(0.5)
                -- Make sure player and controller still exist
                local controller = playerControllers[player]
                if not controller or controller.isDestroyed or controller.snakeObject then
                    break
                end
                checkForSnake()
                checkCount = checkCount + 1
            end
        end)
    end)
    
    -- Store cleanup connections
    controller.cleanupConnections = {characterAddedConnection}
    
    player.CharacterRemoving:Connect(function()
        -- warn("[MainServer] Character removing for", player.Name)
    end)
end

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
    print("[MainServer] Player leaving:", player.Name)
    
    -- Clean up controller
    local controller = playerControllers[player]
    if controller then
        controller:destroy()
        playerControllers[player] = nil
        
        -- Unregister from collision system
        if collisionSystem then
            collisionSystem:unregisterController(player)
        end
        
        -- Clean up global reference
        if _G.PlayerControllers then
            _G.PlayerControllers[player] = nil
        end
    end
end)

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
                -- Reset state for respawn
                warn("[MainServer] Handling respawn for", player.Name)
                controller.collisionState.canCollide = false
                
                -- Wait for new snake to be created
                task.spawn(function()
                    task.wait(1.5) -- Give time for snake creation
                    local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
                    if snakeModel and snakeModel:IsA("Model") then
                        local head = snakeModel:FindFirstChild("Segment0_Head")
                        if head then
                            controller.snakeObject = snakeModel
                            existingSnakes[player] = snakeModel
                            
                            -- Safely transition to Alive state
                            local success, err = pcall(function()
                                controller.fsm:changeState("Alive")
                            end)
                            
                            if success then
                                -- Apply spawn invincibility
                                controller:setInvincible(3)
                                warn("[MainServer] Respawn complete - state set to Alive")
                            else
                                warn("[MainServer] Failed to change to Alive state:", err)
                                -- Try to reinitialize controller if needed
                                if controller and not controller.isDestroyed then
                                    controller:_setupStates()
                                    -- Try again
                                    local retry = pcall(function()
                                        controller.fsm:changeState("Alive")
                                        controller:setInvincible(3)
                                    end)
                                    if retry then
                                        warn("[MainServer] Successfully recovered after reinitializing states")
                                    end
                                end
                            end
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
    print("[MainServer] Starting Modular Snake Controller...")
    
    -- Initialize core systems
    initializeSystems()
    
    -- Setup remote handlers
    setupRemoteHandlers()
    
    -- Connect player events
    Players.PlayerAdded:Connect(setupPlayer)
    -- PlayerRemoving is already connected above
    
    -- Handle existing players (studio testing)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end
    
    print("[MainServer] Modular controller ready!")
end

-- Run main
main()