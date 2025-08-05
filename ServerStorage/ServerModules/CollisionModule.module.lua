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
    HEAD_RADIUS = 3.5,
    BODY_DISTANCE = 2.8,
    ORB_COLLECTION_RADIUS = 5,
    SELF_COLLISION_IGNORE_SEGMENTS = 10,
    FRAME_SKIP = 3, -- Check collisions every N frames for performance
    MAX_CHECKS_PER_FRAME = 50
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
    
    -- Update caches periodically
    local now = os.clock()
    if now - self.lastCacheUpdate > self.CACHE_UPDATE_INTERVAL then
        self:_updateCaches()
        self.lastCacheUpdate = now
    end
    
    -- Check collisions for alive players
    local checksThisFrame = 0
    
    for player, controller in pairs(self.controllers) do
        if checksThisFrame >= COLLISION_CONFIG.MAX_CHECKS_PER_FRAME then
            break
        end
        
        -- Only check alive players who can collide
        local currentState = "Unknown"
        local canCollide = false
        
        -- Safely get current state
        pcall(function()
            if controller.fsm and controller.fsm.getCurrentState then
                currentState = controller.fsm:getCurrentState()
            end
            canCollide = controller:canCollide()
        end)
        
        -- Fallback: if we can't get state but player has a snake, assume they're alive
        if currentState == "Unknown" and controller.snakeObject then
            warn("[CollisionModule] FSM state unknown for", player.Name, "- assuming Alive for collision check")
            currentState = "Alive"
            canCollide = true
        end
        
        if currentState == "Alive" and canCollide then
            self:_checkPlayerCollisions(controller)
            checksThisFrame = checksThisFrame + 1
        end
    end
end

function CollisionModule:_checkPlayerCollisions(controller)
    local head = controller:getSnakeHead()
    if not head then 
        warn("[CollisionModule] No head found for", controller.player.Name)
        return 
    end
    
    warn("[CollisionModule] Checking collisions for", controller.player.Name, "at position", head.Position)
    warn("[CollisionModule] Snake cache has", #self.snakeCache, "snakes")
    
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
    -- Check collision with other snakes
    for _, snakeData in ipairs(self.snakeCache) do
        -- Skip self
        if snakeData.Player == controller.player then
            continue
        end
        
        -- Check head-to-head collision
        if snakeData.Head and (snakeData.Head.Position - head.Position).Magnitude <= COLLISION_CONFIG.HEAD_RADIUS then
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
    
    -- Update obstacle cache (walls, boundaries)
    self.obstacleCache = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name == "Obstacle" or obj.Name == "Boundary" or obj.Name == "Wall") then
            table.insert(self.obstacleCache, obj)
        end
    end
    
    -- Update snake cache - find all snakes
    self.snakeCache = {}
    
    -- Find player snakes - they can be in workspace or in SnakeFolder
    for _, player in pairs(Players:GetPlayers()) do
        local snakeModel = nil
        
        -- First check workspace directly (older system)
        snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
        
        -- If not found, check SnakeFolder (newer system)
        if not snakeModel then
            local snakeFolder = workspace:FindFirstChild("SnakeFolder")
            if snakeFolder then
                snakeModel = snakeFolder:FindFirstChild(player.Name) or snakeFolder:FindFirstChild("Snake_" .. player.Name)
            end
        end
        
        if snakeModel and snakeModel:IsA("Model") then
            -- Player snakes from OptimizedSnakeSystemV9 have head as Segment0_Head
            local head = snakeModel:FindFirstChild("Segment0_Head")
            
            if head and head:IsA("BasePart") then
                local segments = {}
                
                -- First add the head (Segment0_Head)
                table.insert(segments, head)
                
                -- Then collect all body segments (Segment1, Segment2, etc.)
                local i = 1
                while true do
                    local segment = snakeModel:FindFirstChild("Segment" .. i)
                    if segment and segment:IsA("BasePart") then
                        table.insert(segments, segment)
                        i = i + 1
                    else
                        break
                    end
                end
                
                warn("[CollisionModule] Found player snake:", snakeModel.Name, "with", #segments, "segments for", player.Name)
                
                table.insert(self.snakeCache, {
                    Head = head,
                    Model = snakeModel,
                    Segments = segments,
                    IsAI = false,
                    Player = player
                })
            end
        end
    end
    
    -- Find AI snakes (they're directly in workspace with names like "AISnakeModel_")
    for _, child in pairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name:match("^AISnakeModel_") then
            -- This is an AI snake
            local head = child:FindFirstChild("Segment0_Head")
            if head and head:IsA("BasePart") then
                -- AI snakes have segments named "AISegment1", "AISegment2", etc.
                local segments = {}
                
                -- First add the head as segment 0
                table.insert(segments, head)
                
                -- Then find all body segments
                for _, part in pairs(child:GetChildren()) do
                    if part:IsA("BasePart") and part.Name:match("^AISegment%d+") then
                        local segmentNumber = tonumber(part.Name:match("AISegment(%d+)"))
                        if segmentNumber then
                            segments[segmentNumber + 1] = part -- +1 because head is at index 1
                        end
                    end
                end
                
                -- Also check if it's tagged as AISnake
                local isAI = CollectionService:HasTag(child, "AISnake")
                
                table.insert(self.snakeCache, {
                    Head = head,
                    Model = child,
                    Segments = segments,
                    IsAI = true,
                    Player = nil
                })
            end
        end
    end
    
    warn("[CollisionModule] Cache updated - Orbs:", #self.orbCache, "Obstacles:", #self.obstacleCache, "Snakes:", #self.snakeCache)
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