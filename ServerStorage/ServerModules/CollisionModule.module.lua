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

function CollisionModule.new(playerControllers)
    local self = setmetatable({}, CollisionModule)
    
    self.controllers = playerControllers -- Reference to table of all PlayerControllers
    self.frameCount = 0
    self.collisionConnection = nil
    
    -- Cache for performance
    self.orbCache = {}
    self.obstacleCache = {}
    self.snakeCache = {} -- All snake data
    self.lastCacheUpdate = 0
    self.CACHE_UPDATE_INTERVAL = 1 -- Update cache every second
    
    warn("[CollisionModule] Created new collision module")
    return self
end

function CollisionModule:start()
    warn("[CollisionModule] Starting collision detection system")
    -- Connect to heartbeat for collision checks
    self.collisionConnection = RunService.Heartbeat:Connect(function(dt)
        self:update(dt)
    end)
end

function CollisionModule:stop()
    if self.collisionConnection then
        self.collisionConnection:Disconnect()
        self.collisionConnection = nil
    end
end

function CollisionModule:update(dt)
    self.frameCount = self.frameCount + 1
    
    -- Skip frames for performance
    if self.frameCount % COLLISION_CONFIG.FRAME_SKIP ~= 0 then
        return
    end
    
    -- Update cache periodically
    local now = os.clock()
    if now - self.lastCacheUpdate > self.CACHE_UPDATE_INTERVAL then
        self:_updateCaches()
        self.lastCacheUpdate = now
    end
    
    -- Perform collision checks for each player controller
    local checksThisFrame = 0
    for player, controller in pairs(self.controllers) do
        if controller and not controller.isDestroyed and controller.fsm then
            local state = controller.fsm:getCurrentState()
            
            -- Only check collisions for alive players
            if state ~= "Alive" or checksThisFrame >= COLLISION_CONFIG.MAX_CHECKS_PER_FRAME then
                continue
            end
            
            self:_checkPlayerCollisions(controller)
            checksThisFrame = checksThisFrame + 1
        end
    end
end

function CollisionModule:_checkPlayerCollisions(controller)
    local head = controller:getSnakeHead()
    if not head then 
        if COLLISION_CONFIG.LOG_VERBOSE then
            warn("[CollisionModule] No head found for", controller.player.Name)
        end
        return 
    end
    
    -- Only log position checks in verbose mode
    if COLLISION_CONFIG.LOG_VERBOSE then
        warn("[CollisionModule] Checking collisions for", controller.player.Name, "at position", tostring(head.Position))
        warn("[CollisionModule] Snake cache has", #self.snakeCache, "snakes")
    end
    
    -- Check for orb collection
    self:_checkOrbCollection(controller, head)
    
    -- Check for fatal collisions
    self:_checkFatalCollisions(controller, head)
end

function CollisionModule:_checkOrbCollection(controller, head)
    -- Check all orbs manually since they might not be tagged
    local orbFolder = workspace:FindFirstChild("Orbs")
    if not orbFolder then return end
    
    for _, orb in pairs(orbFolder:GetChildren()) do
        if orb:IsA("BasePart") and (orb.Position - head.Position).Magnitude <= COLLISION_CONFIG.ORB_COLLECTION_RADIUS then
            -- Fire orb collection event
            controller.events.onOrbCollision:Fire(orb)
            
            -- Let the existing system handle the orb collection
            -- since it has special logic for different orb types
        end
    end
end

function CollisionModule:_checkFatalCollisions(controller, head)
    -- Add debouncing to prevent multiple collision detections
    local player = controller.player
    local lastCollisionTime = player:GetAttribute("LastCollisionTime") or 0
    local currentTime = tick()
    
    -- Ignore collisions within 1 second of last collision
    if currentTime - lastCollisionTime < 1 then
        return
    end
    
    -- Check collision with other snakes
    for _, snakeData in ipairs(self.snakeCache) do
        -- Skip self
        if snakeData.Player == controller.player then
            continue
        end
        
        -- Check head-to-head collision
        if snakeData.Head and (snakeData.Head.Position - head.Position).Magnitude <= COLLISION_CONFIG.HEAD_RADIUS then
            -- Set collision timestamp
            player:SetAttribute("LastCollisionTime", currentTime)
            
            local collisionData = {
                isFatal = true,
                hitPart = snakeData.Head,
                hitPosition = head.Position,
                preventOrbs = false,
                isHeadCollision = true,
                killerPlayer = snakeData.Player,
                isAI = snakeData.IsAI
            }
            
            warn("[CollisionModule] HEAD COLLISION DETECTED between", controller.player.Name, "and", snakeData.IsAI and "AI Snake" or snakeData.Player.Name)
            controller.events.onFatalHit:Fire(collisionData)
            return
        end
        
        -- Check collision with snake body segments
        if snakeData.Segments then
            for i, segment in ipairs(snakeData.Segments) do
                if segment and segment:IsA("BasePart") then
                    -- For self collision, skip first N segments
                    if snakeData.Player == controller.player and i <= COLLISION_CONFIG.SELF_COLLISION_IGNORE_SEGMENTS then
                        continue
                    end
                    
                    if (segment.Position - head.Position).Magnitude <= COLLISION_CONFIG.BODY_DISTANCE then
                        -- Set collision timestamp
                        player:SetAttribute("LastCollisionTime", currentTime)
                        
                        local collisionData = {
                            isFatal = true,
                            hitPart = segment,
                            hitPosition = head.Position,
                            preventOrbs = false,
                            isBodyCollision = true,
                            killerPlayer = snakeData.Player,
                            isAI = snakeData.IsAI
                        }
                        
                        warn("[CollisionModule] BODY COLLISION DETECTED between", controller.player.Name, "and", snakeData.IsAI and "AI Snake" or (snakeData.Player and snakeData.Player.Name or "Unknown"))
                        controller.events.onFatalHit:Fire(collisionData)
                        return
                    end
                end
            end
        end
    end
    
    -- Check collision with obstacles/walls
    for _, obstacle in ipairs(self.obstacleCache) do
        if obstacle and obstacle:IsA("BasePart") and (obstacle.Position - head.Position).Magnitude <= COLLISION_CONFIG.HEAD_RADIUS * 2 then
            -- Set collision timestamp
            player:SetAttribute("LastCollisionTime", currentTime)
            
            local collisionData = {
                isFatal = true,
                hitPart = obstacle,
                hitPosition = head.Position,
                preventOrbs = false,
                isWallCollision = true
            }
            
            warn("[CollisionModule] WALL COLLISION DETECTED for", controller.player.Name)
            controller.events.onFatalHit:Fire(collisionData)
            return
        end
    end
end

function CollisionModule:_updateCaches()
    -- Update snake cache
    local snakes = {}
    
    -- Add player snakes
    for _, controller in pairs(self.controllers) do
        if controller and not controller.isDestroyed and controller.player.Character then
            local snakeModel = controller.player.Character:FindFirstChild("Snake_" .. controller.player.Name)
            if snakeModel then
                local head = snakeModel:FindFirstChild("Segment0_Head")
                if head then
                    local segments = {}
                    for i = 1, 100 do -- Limit to first 100 segments for performance
                        local segment = snakeModel:FindFirstChild("Segment" .. i)
                        if segment then
                            table.insert(segments, segment)
                        else
                            break
                        end
                    end
                    
                    table.insert(snakes, {
                        Player = controller.player,
                        Head = head,
                        Segments = segments,
                        IsAI = false
                    })
                    
                    if COLLISION_CONFIG.LOG_VERBOSE then
                        warn("[CollisionModule] Found player snake:", snakeModel.Name, "with", #segments, "segments for", controller.player.Name)
                    end
                end
            end
        end
    end
    
    -- Add AI snakes
    local aiSnakeFolder = workspace:FindFirstChild("AISnakes")
    if aiSnakeFolder then
        for _, aiSnake in ipairs(aiSnakeFolder:GetChildren()) do
            if aiSnake:IsA("Model") then
                local head = aiSnake:FindFirstChild("Head")
                if head then
                    local segments = {}
                    -- AI snakes might have different segment naming
                    for _, child in ipairs(aiSnake:GetChildren()) do
                        if child:IsA("BasePart") and child.Name:match("Segment") then
                            table.insert(segments, child)
                        end
                    end
                    
                    table.insert(snakes, {
                        Player = nil,
                        Head = head,
                        Segments = segments,
                        IsAI = true
                    })
                end
            end
        end
    end
    
    self.snakeCache = snakes
    
    -- Update obstacle cache
    local obstacles = {}
    for _, obj in ipairs(CollectionService:GetTagged("Obstacle")) do
        if obj:IsA("BasePart") then
            table.insert(obstacles, obj)
        end
    end
    self.obstacleCache = obstacles
    
    -- Update orb cache
    local orbs = {}
    for _, obj in ipairs(CollectionService:GetTagged("Orb")) do
        if obj:IsA("BasePart") then
            table.insert(orbs, obj)
        end
    end
    self.orbCache = orbs
    
    self.lastCacheUpdate = tick()
    
    -- Only log cache updates in verbose mode
    if COLLISION_CONFIG.LOG_VERBOSE then
        warn("[CollisionModule] Cache updated - Orbs:", #self.orbCache, "Obstacles:", #self.obstacleCache, "Snakes:", #self.snakeCache)
    end
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

return CollisionModule