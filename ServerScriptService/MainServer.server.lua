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
local DeathOrbHandler = require(ServerModules.DeathOrbHandler)

-- Shared configuration  
local Config = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Config"))

-- Player controller storage
local playerControllers = {}

-- Collision system
local collisionSystem = nil

-- Death orb system
local deathOrbHandler = nil

-- Track existing snakes from SnakeSystemIntegration
local snakeSystemIntegration = nil
local existingSnakes = {} -- Track snakes created by the old system
local activeReviveSessions = {} -- Track active revive sessions

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
    
    -- Initialize death orb handler
    deathOrbHandler = DeathOrbHandler.new()
    
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
        -- Snakes are created as Snake_[PlayerName] directly in workspace
        local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
        if snakeModel and snakeModel:IsA("Model") then
            -- Verify it has the head segment
            local head = snakeModel:FindFirstChild("Segment0_Head")
            if head then
                warn("[MainServer] Found snake for", player.Name, "with head:", head.Name)
                controller.snakeObject = snakeModel
                existingSnakes[player] = snakeModel
                
                -- Set initial state to Alive when snake is created
                controller.fsm:changeState("Alive")
                
                -- Apply spawn invincibility
                controller:setInvincible(3)
                warn("[MainServer] State set to Alive with 3 second spawn protection")
                return true
            end
        end
        
        return false
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
                            -- Check if already dying
                            if controller.fsm:getCurrentState() == "Dying" then
                                return
                            end
                            
                            -- Check if revive prompt is active
                            if player:GetAttribute("RevivePromptActive") or player:GetAttribute("AwaitingReviveResponse") then
                                warn("[MainServer] Revive prompt active, ignoring collision for", player.Name)
                                return
                            end
                            
                            -- Check for active revive session
                            if activeReviveSessions[player] then
                                warn("[MainServer] Active revive session found, ignoring collision for", player.Name)
                                return
                            end
                            
                            -- Mark active revive session
                            activeReviveSessions[player] = true
                            
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
                            
                            -- Change to Dying state immediately
                            controller.fsm:changeState("Dying", collisionData)
                            
                            -- Clear revive session after death processing
                            task.spawn(function()
                                task.wait(10) -- Give enough time for revive prompt
                                activeReviveSessions[player] = nil
                            end)
                            
                            -- Then kill the player to trigger existing systems
                            local character = player.Character
                            if character then
                                local humanoid = character:FindFirstChildOfClass("Humanoid")
                                if humanoid and humanoid.Health > 0 then
                                    -- Set killer info for the existing system
                                    if collisionData.killerPlayer then
                                        player:SetAttribute("KilledBy", collisionData.killerPlayer.Name)
                                    elseif collisionData.isAI then
                                        player:SetAttribute("KilledBy", "AI Snake")
                                    else
                                        player:SetAttribute("KilledBy", "Wall")
                                    end
                                    
                                    -- Kill the humanoid - this triggers existing death handling
                                    humanoid.Health = 0
                                end
                            end
                        elseif eventName == "onOrbCollision" then
                            -- Let existing orb system handle collection
                            -- The OrbSpawner system has all the logic
                        end
                    end)
    end
    
    -- Monitor revive state for orb cleanup
    player:GetAttributeChangedSignal("JustRevived"):Connect(function()
        if player:GetAttribute("JustRevived") then
            -- Player is reviving, clean up death orbs
            local character = player.Character
            if character then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart and deathOrbHandler then
                    deathOrbHandler:cleanupOrbsNearPosition(rootPart.Position)
                end
            end
        end
    end)
    
    -- Monitor character spawning
    player.CharacterAdded:Connect(function(character)
        warn("[MainServer] Character added for", player.Name)
        
        -- Reset controller state
        controller.snakeObject = nil
        
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
            while not controller.snakeObject and checkCount < 10 do
                task.wait(0.5)
                checkForSnake()
                checkCount = checkCount + 1
            end
        end)
    end)
    
    -- Handle character removal
    player.CharacterRemoving:Connect(function()
        warn("[MainServer] Character removing for", player.Name)
        
        -- Clear snake references
        if controller.snakeObject then
            controller.snakeObject = nil
        end
        if existingSnakes[player] then
            existingSnakes[player] = nil
        end
        
        -- Reset invincibility when character is removed
        controller.collisionState.invincibleUntil = 0
    end)
end

-- Handle player leaving
local function onPlayerRemoving(player)
    warn("[MainServer] Player removing:", player.Name)
    
    -- Clean up revive sessions
    activeReviveSessions[player] = nil
    
    -- Clean up controller
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
                -- Transition to Spawning state
                warn("[MainServer] Transitioning to Spawning state for", player.Name)
                controller.fsm:changeState("Spawning")
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