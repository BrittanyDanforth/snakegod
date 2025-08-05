--[[
    PlayerController.module - Single Source of Truth for player state
    Manages FSM, snake object, collision state, and all player-related data
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import modules
local FSM = require(script.Parent.FSM)
local Maid = require(script.Parent.Lib.Maid)
local Promise = require(script.Parent.Lib.Promise)

local PlayerController = {}
PlayerController.__index = PlayerController

-- Events for inter-module communication
local function createEvent()
    local event = {}
    local connections = {}
    
    function event:Connect(callback)
        local connection = {callback = callback, connected = true}
        table.insert(connections, connection)
        
        return {
            Disconnect = function()
                connection.connected = false
            end
        }
    end
    
    function event:Fire(...)
        for _, connection in ipairs(connections) do
            if connection.connected then
                task.spawn(connection.callback, ...)
            end
        end
    end
    
    return event
end

function PlayerController.new(player, config)
    local self = setmetatable({}, PlayerController)
    
    -- Core properties
    self.player = player
    self.config = config or {}
    self.isDestroyed = false
    
    -- Single Source of Truth data
    self.data = {
        score = 0,
        orbsCollected = 0,
        length = config.Snake.baseLength,
        speed = config.Snake.baseSpeed,
        killCount = 0,
        deathCount = 0,
        reviveTokens = 1,
        powerUps = {},
        lastRespawnTime = 0,
        lastDeathTime = 0
    }
    
    -- Snake object reference
    self.snakeObject = nil
    self.snakeModel = nil
    
    -- Collision state
    self.collisionState = {
        canCollide = true,
        invincibleUntil = 0,
        lastCollisionTime = 0
    }
    
    -- Initialize FSM
    self.fsm = FSM.new()
    self.fsm:setContext(self)
    
    -- Initialize Maid for cleanup
    self.maid = Maid.new()
    
    -- Events for Observer pattern
    self.events = {
        onOrbCollision = createEvent(),
        onFatalHit = createEvent(),
        onPowerUpCollected = createEvent(),
        onScoreChanged = createEvent(),
        onStateChanged = createEvent(),
        onReviveRequested = createEvent()
    }
    
    -- Tag for CollectionService
    self.playerTag = "PlayerID_" .. player.UserId
    
    -- Setup states (will be done after states are created)
    self:_setupStates()
    
    -- Connect update loop
    self.maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
        if not self.isDestroyed then
            self.fsm:update(dt)
        end
    end))
    
    return self
end

function PlayerController:_setupStates()
    -- Require all state modules
    local States = script.Parent.States
    local SpawningState = require(States.SpawningState)
    local AliveState = require(States.AliveState)
    local DyingState = require(States.DyingState)
    local RevivingState = require(States.RevivingState)
    local SpectatingState = require(States.SpectatingState)
    
    -- Add states to FSM
    self.fsm:addState("Spawning", SpawningState.new(self))
    self.fsm:addState("Alive", AliveState.new(self))
    self.fsm:addState("Dying", DyingState.new(self))
    self.fsm:addState("Reviving", RevivingState.new(self))
    self.fsm:addState("Spectating", SpectatingState.new(self))
    
    -- Connect collision events to alive state
    self.events.onFatalHit:Connect(function(collisionData)
        if self.fsm:getCurrentState() == "Alive" then
            self.fsm:changeState("Dying", collisionData)
        end
    end)
end

-- Data management methods
function PlayerController:getScore()
    return self.data.score
end

function PlayerController:addScore(amount)
    self.data.score = self.data.score + amount
    self.events.onScoreChanged:Fire(self.data.score)
end

function PlayerController:getLength()
    return self.data.length
end

function PlayerController:addLength(amount)
    self.data.length = self.data.length + amount
    -- Snake object will handle visual update
end

function PlayerController:getSpeed()
    return self.data.speed
end

function PlayerController:setSpeed(speed)
    self.data.speed = speed
end

function PlayerController:hasReviveToken()
    return self.data.reviveTokens > 0
end

function PlayerController:useReviveToken()
    if self.data.reviveTokens > 0 then
        self.data.reviveTokens = self.data.reviveTokens - 1
        return true
    end
    return false
end

-- Collision state management
function PlayerController:isInvincible()
    return os.clock() < self.collisionState.invincibleUntil
end

function PlayerController:setInvincible(duration)
    self.collisionState.invincibleUntil = os.clock() + duration
end

function PlayerController:canCollide()
    return self.collisionState.canCollide and not self:isInvincible()
end

-- Snake object management
function PlayerController:setSnakeObject(snakeObject)
    self.snakeObject = snakeObject
    
    if snakeObject and snakeObject.model then
        self.snakeModel = snakeObject.model
        
        -- Tag all snake parts for CollectionService
        for _, part in ipairs(snakeObject.model:GetDescendants()) do
            if part:IsA("BasePart") then
                CollectionService:AddTag(part, "SnakeBody")
                CollectionService:AddTag(part, self.playerTag)
            end
        end
    end
end

function PlayerController:getSnakeHead()
    -- Try multiple methods to find the snake head
    
    -- Method 1: Check if we have a direct snake object reference
    if self.snakeObject then
        -- If it's a model
        if self.snakeObject:IsA("Model") then
            local head = self.snakeObject:FindFirstChild("Segment0_Head") or
                        self.snakeObject:FindFirstChild("1") or
                        self.snakeObject:FindFirstChild("Head")
            if head then return head end
        end
        
        -- If snakeObject has a model property
        if self.snakeObject.model then
            local head = self.snakeObject.model:FindFirstChild("Segment0_Head") or
                        self.snakeObject.model:FindFirstChild("1") or
                        self.snakeObject.model:FindFirstChild("Head")
            if head then return head end
        end
    end
    
    -- Method 2: Look for Snake_[PlayerName] in workspace
    local snakeModel = workspace:FindFirstChild("Snake_" .. self.player.Name)
    if snakeModel then
        local head = snakeModel:FindFirstChild("Segment0_Head") or
                    snakeModel:FindFirstChild("1") or
                    snakeModel:FindFirstChild("Head")
        if head then return head end
    end
    
    -- Method 3: Check SnakeFolder
    local snakeFolder = workspace:FindFirstChild("SnakeFolder")
    if snakeFolder then
        local playerSnake = snakeFolder:FindFirstChild(self.player.Name)
        if playerSnake then
            local head = playerSnake:FindFirstChild("Segment0_Head") or
                        playerSnake:FindFirstChild("1") or
                        playerSnake:FindFirstChild("Head")
            if head then return head end
        end
    end
    
    -- Method 4: Fallback to HumanoidRootPart
    if self.player.Character then
        return self.player.Character:FindFirstChild("HumanoidRootPart")
    end
    
    return nil
end

-- Client communication
function PlayerController:requestReviveFromClient()
    return Promise.new(function(resolve, reject, onCancel)
        local remotes = ReplicatedStorage:WaitForChild("Remotes")
        local promptRevive = remotes:FindFirstChild("PromptRevive")
        
        if not promptRevive then
            return reject("Revive remote not found")
        end
        
        -- Setup response listener
        local connection
        connection = promptRevive.OnServerEvent:Connect(function(respondingPlayer, response)
            if respondingPlayer == self.player then
                connection:Disconnect()
                
                if response == "revive" and self:hasReviveToken() then
                    resolve("Reviving")
                else
                    resolve("Spectating")
                end
            end
        end)
        
        -- Send prompt to client
        promptRevive:FireClient(self.player, {
            show = true,
            hasToken = self:hasReviveToken()
        })
        
        -- Cleanup on cancel
        onCancel(function()
            if connection then
                connection:Disconnect()
            end
            self:hideReviveUI()
        end)
    end)
end

function PlayerController:hideReviveUI()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local promptRevive = remotes:FindFirstChild("PromptRevive")
    
    if promptRevive then
        promptRevive:FireClient(self.player, {
            show = false
        })
    end
end

function PlayerController:playDeathEffects(collisionData)
    -- This will handle death VFX, sounds, etc.
    -- For now, just a placeholder
    if self.snakeModel then
        -- Could spawn particles, play sounds, etc.
    end
end

-- State change notification
function PlayerController:notifyStateChange(newState)
    self.events.onStateChanged:Fire(newState)
end

-- Cleanup
function PlayerController:destroy()
    if self.isDestroyed then
        return
    end
    
    self.isDestroyed = true
    
    -- Cancel any active FSM promises
    self.fsm:destroy()
    
    -- Remove all tagged parts
    for _, part in ipairs(CollectionService:GetTagged(self.playerTag)) do
        part:Destroy()
    end
    
    -- Cleanup snake object
    if self.snakeObject and self.snakeObject.destroy then
        self.snakeObject:destroy()
    end
    
    -- Cleanup all connections and tasks
    self.maid:Destroy()
    
    -- Clear references
    self.player = nil
    self.snakeObject = nil
    self.snakeModel = nil
    self.data = nil
    self.events = nil
end

return PlayerController