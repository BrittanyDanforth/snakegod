--[[
    MainServer.server.lua - Main entry point for the modular snake game
    Manages PlayerController lifecycles and coordinates all server systems
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

-- AI Snake management (if needed)
local aiSnakeManager = nil

-- Initialize systems
local function initializeSystems()
    print("[MainServer] Initializing game systems...")
    
    -- Initialize collision system
    collisionSystem = CollisionModule.new(playerControllers)
    collisionSystem:start()
    
    -- Setup orb collection handlers
    setupOrbHandlers()
    
    -- Setup score handlers
    setupScoreHandlers()
    
    print("[MainServer] Systems initialized successfully")
end

-- Handle player joining
local function onPlayerAdded(player)
    print("[MainServer] Player joined:", player.Name)
    
    -- Create player controller
    local controller = PlayerController.new(player, Config)
    playerControllers[player] = controller
    
    -- Connect to spawn request
    player.CharacterAdded:Connect(function(character)
        -- Small delay to ensure character is loaded
        task.wait(0.5)
        
        -- Start player in spawning state
        if controller and not controller.isDestroyed then
            controller.fsm:changeState("Spawning")
        end
    end)
    
    -- Check if player already has a character (joined with character)
    if player.Character then
        task.wait(0.5)
        controller.fsm:changeState("Spawning")
    end
end

-- Handle player leaving
local function onPlayerRemoving(player)
    print("[MainServer] Player leaving:", player.Name)
    
    local controller = playerControllers[player]
    if controller then
        -- Destroy controller (handles all cleanup)
        controller:destroy()
        playerControllers[player] = nil
    end
end

-- Setup orb collection handlers
function setupOrbHandlers()
    -- Listen to all player controllers for orb collection
    RunService.Heartbeat:Connect(function()
        for player, controller in pairs(playerControllers) do
            -- This is handled per-controller, but we could add global logic here
        end
    end)
end

-- Setup score tracking and leaderboard
function setupScoreHandlers()
    -- Create leaderstats for each player
    local function createLeaderstats(player)
        local leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
        
        local score = Instance.new("IntValue")
        score.Name = "Score"
        score.Value = 0
        score.Parent = leaderstats
        
        local length = Instance.new("IntValue")
        length.Name = "Length"
        length.Value = 3
        length.Parent = leaderstats
        
        return leaderstats
    end
    
    -- Connect score changes to leaderstats
    Players.PlayerAdded:Connect(function(player)
        local leaderstats = createLeaderstats(player)
        
        -- Wait for controller
        repeat task.wait() until playerControllers[player]
        local controller = playerControllers[player]
        
        -- Update leaderstats when score changes
        controller.events.onScoreChanged:Connect(function(newScore)
            leaderstats.Score.Value = newScore
        end)
        
        -- Connect orb collection to score
        controller.events.onOrbCollision:Connect(function(orb)
            local orbValue = orb:GetAttribute("Value") or 1
            controller:addScore(orbValue)
            controller:addLength(1)
            leaderstats.Length.Value = controller:getLength()
        end)
    end)
end

-- Handle game rounds (placeholder for round system)
local function handleGameRounds()
    -- This would manage round starts, ends, etc.
    -- For now, players can spawn immediately
end

-- Remote event handlers
local function setupRemoteHandlers()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    
    -- Handle respawn requests
    local respawnRemote = ReplicatedStorage:FindFirstChild("RespawnSnake")
    if respawnRemote then
        respawnRemote.OnServerEvent:Connect(function(player)
            local controller = playerControllers[player]
            if controller and controller.fsm:getCurrentState() == "Spectating" then
                -- Allow respawn from spectating
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
    print("[MainServer] Starting Snake Game Server...")
    
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
    
    -- Start game rounds
    handleGameRounds()
    
    print("[MainServer] Server started successfully!")
end

-- Run main
main()