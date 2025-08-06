--[[
    CollisionModule.module - FIXED VERSION for actual game structure
    Works with SnakeFolder for players and AISnakes folder for AI
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local CollisionModule = {}
CollisionModule.__index = CollisionModule

-- Constants for collision detection
local COLLISION_CONFIG = {
    HEAD_RADIUS = 4,  -- Radius for head-to-head collision
    BODY_DISTANCE = 3.5,  -- Distance for body collision
    ORB_COLLECTION_RADIUS = 5,  -- Radius for orb collection
    SELF_COLLISION_IGNORE_SEGMENTS = 5,  -- Ignore first N segments for self collision
    MAX_CHECKS_PER_FRAME = 5,  -- Limit collision checks per frame for performance
    LOG_VERBOSE = false  -- Reduce log spam
}

function CollisionModule.new()
    local self = setmetatable({}, CollisionModule)
    
    self.playerControllers = {}
    self.collisionHandlers = {}
    self.frameCount = 0
    self.lastCacheUpdate = 0
    
    -- Performance settings
    self.CACHE_UPDATE_INTERVAL = 0.5
    self.MAX_CHECKS_PER_FRAME = COLLISION_CONFIG.MAX_CHECKS_PER_FRAME or 50
    
    -- Caches
    self.snakeCache = {}
    self.orbCache = {}
    self.obstacleCache = {}
    
    print("[CollisionModule] Created new collision module")
    return self
end

function CollisionModule:start()
    print("[CollisionModule] Starting collision detection system")
    
    -- Initialize caches
    self:_updateCaches()
    
    -- Connect heartbeat for collision checking
    if not self.heartbeatConnection then
        self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
            self:update(dt)
        end)
    end
end

function CollisionModule:stop()
    if self.heartbeatConnection then
        self.heartbeatConnection:Disconnect()
        self.heartbeatConnection = nil
    end
end

function CollisionModule:update(dt)
    self.frameCount = (self.frameCount or 0) + 1
    
    -- Update cache periodically
    if tick() - self.lastCacheUpdate > self.CACHE_UPDATE_INTERVAL then
        self:_updateCaches()
        self.lastCacheUpdate = tick()
    end
    
    -- Perform collision checks for each player controller
    local checksThisFrame = 0
    for _, controller in pairs(self.playerControllers) do
        if controller and not controller.isDestroyed and controller.fsm then
            local state = controller.fsm:getCurrentState()
            
            -- Only check collisions for alive players
            if state ~= "Alive" or checksThisFrame >= self.MAX_CHECKS_PER_FRAME then
                continue
            end
            
            local head = controller:getSnakeHead()
            if head then
                checksThisFrame = checksThisFrame + self:_checkPlayerCollisions(controller.player, controller, head)
            end
        end
    end
end

-- Main collision check function for a player
function CollisionModule:_checkPlayerCollisions(player, controller, head)
    local checksPerformed = 0
    
    -- Check head-to-head collisions with other snakes
    for otherPlayer, otherSnake in pairs(self.snakeCache.playerSnakes) do
        if otherPlayer ~= player and otherSnake.head then
            local distance = (head.Position - otherSnake.head.Position).Magnitude
            if distance < COLLISION_CONFIG.HEAD_RADIUS * 2 then
                self:_handleCollision(controller, {
                    type = "HeadToHead",
                    otherPlayer = otherPlayer,
                    position = head.Position,
                    isFatal = true
                })
                checksPerformed = checksPerformed + 1
            end
        end
    end
    
    -- Check body collisions
    if checksPerformed < 10 then  -- Limit checks per player
        checksPerformed = checksPerformed + self:_checkBodyCollisions(player, controller, head)
    end
    
    -- Check wall collisions
    self:_checkWallCollision(controller, head)
    
    -- Check orb collections
    self:_checkOrbCollections(controller, head)
    
    return checksPerformed
end

-- Check body collisions with other snakes
function CollisionModule:_checkBodyCollisions(player, controller, head)
    local checksPerformed = 0
    
    -- Check against all snake segments
    for otherPlayer, otherSnake in pairs(self.snakeCache.playerSnakes) do
        if otherPlayer ~= player and otherSnake.segments then
            -- Skip first few segments for self
            local startIndex = (otherPlayer == player) and COLLISION_CONFIG.SELF_COLLISION_IGNORE_SEGMENTS or 1
            
            for i = startIndex, #otherSnake.segments do
                local segment = otherSnake.segments[i]
                if segment then
                    local distance = (head.Position - segment.Position).Magnitude
                    if distance < COLLISION_CONFIG.BODY_DISTANCE then
                        self:_handleCollision(controller, {
                            type = "Body",
                            otherPlayer = otherPlayer,
                            position = head.Position,
                            isFatal = true
                        })
                        return checksPerformed + 1
                    end
                end
                checksPerformed = checksPerformed + 1
                if checksPerformed >= 10 then break end
            end
        end
    end
    
    -- Check AI snake collisions
    for _, aiSnake in pairs(self.snakeCache.aiSnakes) do
        if aiSnake.segments then
            for i, segment in ipairs(aiSnake.segments) do
                if segment then
                    local distance = (head.Position - segment.Position).Magnitude
                    if distance < COLLISION_CONFIG.BODY_DISTANCE then
                        self:_handleCollision(controller, {
                            type = "Body",
                            otherPlayer = "AI",
                            position = head.Position,
                            isFatal = true
                        })
                        return checksPerformed + 1
                    end
                end
                checksPerformed = checksPerformed + 1
                if checksPerformed >= 10 then break end
            end
        end
    end
    
    return checksPerformed
end

-- Check wall collisions
function CollisionModule:_checkWallCollision(controller, head)
    local mapSize = 500 -- Should get from config
    local x, z = head.Position.X, head.Position.Z
    
    if math.abs(x) > mapSize or math.abs(z) > mapSize then
        self:_handleCollision(controller, {
            type = "Wall",
            position = head.Position,
            isFatal = true
        })
    end
end

-- Check orb collections (renamed from _checkOrbCollection)
function CollisionModule:_checkOrbCollections(controller, head)
    for _, orb in pairs(self.orbCache) do
        if orb and orb.Parent then
            local distance = (head.Position - orb.Position).Magnitude
            if distance < COLLISION_CONFIG.ORB_COLLECTION_RADIUS then
                self:_handleCollision(controller, {
                    type = "Orb",
                    orb = orb,
                    position = orb.Position,
                    isFatal = false
                })
            end
        end
    end
end

-- Handle collision event
function CollisionModule:_handleCollision(controller, collisionData)
    -- Check debouncing for fatal collisions
    if collisionData.isFatal then
        local lastCollisionTime = controller.player:GetAttribute("LastCollisionTime") or 0
        local currentTime = tick()
        
        if currentTime - lastCollisionTime < 0.5 then
            return -- Ignore collision if too soon after last one
        end
        
        controller.player:SetAttribute("LastCollisionTime", currentTime)
    end
    
    -- Fire appropriate event based on collision type
    if collisionData.type == "Orb" then
        controller.events.onOrbCollision:Fire(collisionData)
    elseif collisionData.isFatal then
        controller.events.onFatalHit:Fire(collisionData)
    end
end

function CollisionModule:_updateCaches()
    -- Update orb cache
    self.orbCache = {}
    local orbFolder = workspace:FindFirstChild("Orbs")
    if orbFolder then
        for _, orb in pairs(orbFolder:GetChildren()) do
            if orb:IsA("BasePart") then
                table.insert(self.orbCache, orb)
            end
        end
    end
    
    -- Update obstacle cache
    self.obstacleCache = {}
    local obstaclesFolder = workspace:FindFirstChild("Obstacles")
    if obstaclesFolder then
        for _, obstacle in pairs(obstaclesFolder:GetChildren()) do
            if obstacle:IsA("BasePart") then
                table.insert(self.obstacleCache, obstacle)
            end
        end
    end
    
    -- Update snake cache
    self.snakeCache = {
        playerSnakes = {},
        aiSnakes = {}
    }
    
    -- Cache player snakes
    for player, controller in pairs(self.playerControllers) do
        if controller and not controller.isDestroyed then
            local head = controller:getSnakeHead()
            if head then
                local segments = {}
                local snakeModel = controller.snakeModel or (controller.snakeObject and controller.snakeObject.model)
                
                if snakeModel then
                    for _, part in pairs(snakeModel:GetChildren()) do
                        if part:IsA("BasePart") and part.Name:match("Segment") and part ~= head then
                            table.insert(segments, part)
                        end
                    end
                end
                
                self.snakeCache.playerSnakes[player] = {
                    head = head,
                    segments = segments,
                    player = player
                }
            end
        end
    end
    
    -- Cache AI snakes
    local aiSnakeFolder = workspace:FindFirstChild("AISnakes")
    if aiSnakeFolder then
        for _, aiModel in pairs(aiSnakeFolder:GetChildren()) do
            if aiModel:IsA("Model") then
                local head = aiModel:FindFirstChild("Head") or aiModel:FindFirstChild("Segment0_Head")
                if head then
                    local segments = {}
                    for _, part in pairs(aiModel:GetChildren()) do
                        if part:IsA("BasePart") and part.Name:match("Segment") and part ~= head then
                            table.insert(segments, part)
                        end
                    end
                    
                    table.insert(self.snakeCache.aiSnakes, {
                        head = head,
                        segments = segments,
                        model = aiModel
                    })
                end
            end
        end
    end
    
    self.lastCacheUpdate = tick()
end

-- Helper to get player from part
function CollisionModule:_getPlayerFromPart(part)
    -- Check if part belongs to a player snake
    if part.Parent and part.Parent.Parent then
        local snakeFolder = workspace:FindFirstChild("SnakeFolder")
        if snakeFolder and part.Parent.Parent == snakeFolder then
            local playerName = part.Parent:GetAttribute("OwnerPlayer") or part.Parent.Name
            return Players:FindFirstChild(playerName)
        end
    end
    return nil
end

function CollisionModule:registerController(player, controller)
    self.playerControllers[player] = controller
end

function CollisionModule:unregisterController(player)
    self.playerControllers[player] = nil
end

return CollisionModule