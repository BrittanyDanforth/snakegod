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
    HEAD_RADIUS = 2.5,  -- Tighter radius for head collisions
    BODY_DISTANCE = 3.5,  -- Distance for body collision
    ORB_COLLECTION_RADIUS = 5,
    SELF_COLLISION_IGNORE_SEGMENTS = 10,  -- Ignore first 10 segments for self
    MAX_CHECKS_PER_FRAME = 50,
    LOG_VERBOSE = false,  -- Set to true for debugging
    DEBUG_COLLISIONS = true  -- Enable collision debugging
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
        
        if COLLISION_CONFIG.DEBUG_COLLISIONS and self.frameCount % 60 == 0 then
            local playerSnakeCount = 0
            for _ in pairs(self.snakeCache.playerSnakes or {}) do
                playerSnakeCount = playerSnakeCount + 1
            end
            print("[CollisionModule] Cache updated - Player snakes:", 
                  playerSnakeCount, 
                  "AI snakes:", #self.snakeCache.aiSnakes)
        end
    end
    
    -- Perform collision checks for each player controller
    local checksThisFrame = 0
    local controllersChecked = 0
    
    for _, controller in pairs(self.playerControllers) do
        controllersChecked = controllersChecked + 1
        
        if controller and not controller.isDestroyed and controller.fsm then
            local state = controller.fsm:getCurrentState()
            
            -- Only check collisions for alive players
            if state == "Alive" and checksThisFrame < self.MAX_CHECKS_PER_FRAME then
                local head = controller:getSnakeHead()
                if head then
                    checksThisFrame = checksThisFrame + self:_checkPlayerCollisions(controller.player, controller, head)
                elseif COLLISION_CONFIG.DEBUG_COLLISIONS and self.frameCount % 60 == 0 then
                    warn("[CollisionModule] No head found for", controller.player.Name)
                end
            end
        end
    end
    
    if COLLISION_CONFIG.DEBUG_COLLISIONS and self.frameCount % 180 == 0 then
        print("[CollisionModule] Controllers checked:", controllersChecked, "Collision checks:", checksThisFrame)
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
                if COLLISION_CONFIG.DEBUG_COLLISIONS then
                    warn("[CollisionModule] HEAD-TO-HEAD COLLISION:", player.Name, "vs", otherPlayer.Name)
                end
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
        if otherSnake.segments then
            -- Skip first few segments for self
            local startIndex = (otherPlayer == player) and COLLISION_CONFIG.SELF_COLLISION_IGNORE_SEGMENTS or 1
            
            for i = startIndex, #otherSnake.segments do
                local segment = otherSnake.segments[i]
                if segment then
                    local distance = (head.Position - segment.Position).Magnitude
                    if distance < COLLISION_CONFIG.BODY_DISTANCE then
                        if COLLISION_CONFIG.DEBUG_COLLISIONS then
                            warn("[CollisionModule] BODY COLLISION:", player.Name, "hit", 
                                 otherPlayer == player and "SELF" or otherPlayer.Name, "segment", i)
                        end
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
                        if COLLISION_CONFIG.DEBUG_COLLISIONS then
                            warn("[CollisionModule] AI BODY COLLISION:", player.Name, "hit AI snake")
                        end
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
            if COLLISION_CONFIG.DEBUG_COLLISIONS then
                print("[CollisionModule] Collision ignored - too soon after last collision")
            end
            return -- Ignore collision if too soon after last one
        end
        
        controller.player:SetAttribute("LastCollisionTime", currentTime)
    end
    
    -- Fire appropriate event based on collision type
    if collisionData.type == "Orb" then
        controller.events.onOrbCollision:Fire(collisionData)
    elseif collisionData.isFatal then
        if COLLISION_CONFIG.DEBUG_COLLISIONS then
            warn("[CollisionModule] FIRING FATAL HIT EVENT for", controller.player.Name, "- Type:", collisionData.type)
        end
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
    
    -- Update obstacle cache (walls)
    self.obstacleCache = {}
    local mapBorders = workspace:FindFirstChild("MapBorders")
    if mapBorders then
        for _, border in pairs(mapBorders:GetChildren()) do
            if border:IsA("BasePart") then
                table.insert(self.obstacleCache, border)
            end
        end
    end
    
    -- Update snake cache
    self.snakeCache = {
        playerSnakes = {},
        aiSnakes = {}
    }
    
    -- Cache player snakes - look for actual snake models
    local snakeFolder = workspace:FindFirstChild("Snakes")
    if snakeFolder then
        for _, snakeModel in pairs(snakeFolder:GetChildren()) do
            if snakeModel:IsA("Model") then
                -- Check if it's a player snake
                local playerName = snakeModel.Name:match("Snake_(.+)")
                if playerName then
                    local player = game.Players:FindFirstChild(playerName)
                    if player then
                        local head = snakeModel:FindFirstChild("Segment0_Head") or snakeModel:FindFirstChild("Head")
                        if head then
                            local segments = {}
                            -- Collect all segments
                            for _, part in pairs(snakeModel:GetChildren()) do
                                if part:IsA("BasePart") and part.Name:match("Segment%d+") and part ~= head then
                                    local segmentNum = tonumber(part.Name:match("Segment(%d+)"))
                                    if segmentNum then
                                        segments[segmentNum] = part
                                    end
                                end
                            end
                            
                            self.snakeCache.playerSnakes[player] = {
                                head = head,
                                segments = segments,
                                player = player,
                                model = snakeModel
                            }
                            
                            if COLLISION_CONFIG.DEBUG_COLLISIONS then
                                print("[CollisionModule] Found player snake:", player.Name, "with", #segments, "segments")
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Also check character models for snakes
    for player, controller in pairs(self.playerControllers) do
        if not self.snakeCache.playerSnakes[player] and controller and not controller.isDestroyed then
            local character = player.Character
            if character then
                local snakeModel = character:FindFirstChild("Snake_" .. player.Name)
                if snakeModel then
                    local head = snakeModel:FindFirstChild("Segment0_Head") or snakeModel:FindFirstChild("Head")
                    if head then
                        local segments = {}
                        for _, part in pairs(snakeModel:GetChildren()) do
                            if part:IsA("BasePart") and part.Name:match("Segment%d+") and part ~= head then
                                local segmentNum = tonumber(part.Name:match("Segment(%d+)"))
                                if segmentNum then
                                    segments[segmentNum] = part
                                end
                            end
                        end
                        
                        self.snakeCache.playerSnakes[player] = {
                            head = head,
                            segments = segments,
                            player = player,
                            model = snakeModel
                        }
                    end
                end
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