--[[
    CollisionModule.module - Centralized, high-performance collision detection
    Uses modern spatial queries and CollectionService for optimization
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")

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
    self.lastCacheUpdate = 0
    self.CACHE_UPDATE_INTERVAL = 1 -- Update cache every second
    
    return self
end

function CollisionModule:start()
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
        if controller.fsm:getCurrentState() == "Alive" and controller:canCollide() then
            self:_checkPlayerCollisions(controller)
            checksThisFrame = checksThisFrame + 1
        end
    end
end

function CollisionModule:_checkPlayerCollisions(controller)
    local head = controller:getSnakeHead()
    if not head then return end
    
    -- Check for orb collection (using faster bounding radius)
    self:_checkOrbCollection(controller, head)
    
    -- Check for fatal collisions (using precise GetPartsInPart)
    self:_checkFatalCollisions(controller, head)
end

function CollisionModule:_checkOrbCollection(controller, head)
    -- Use GetPartBoundsInRadius for fast orb detection
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Whitelist
    params.FilterDescendantsInstances = self.orbCache
    
    local nearbyParts = workspace:GetPartBoundsInRadius(
        head.Position,
        COLLISION_CONFIG.ORB_COLLECTION_RADIUS,
        params
    )
    
    for _, orb in ipairs(nearbyParts) do
        if orb.Parent and CollectionService:HasTag(orb, "Orb") then
            -- Fire orb collection event
            controller.events.onOrbCollision:Fire(orb)
            
            -- Remove from cache
            local index = table.find(self.orbCache, orb)
            if index then
                table.remove(self.orbCache, index)
            end
            
            -- Destroy the orb
            orb:Destroy()
        end
    end
end

function CollisionModule:_checkFatalCollisions(controller, head)
    -- Create collision hitbox slightly larger than head
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Whitelist
    
    -- Build whitelist: other snake bodies + obstacles
    local whitelist = {}
    
    -- Add all snake bodies except our own
    for _, part in ipairs(CollectionService:GetTagged("SnakeBody")) do
        -- Skip our own snake parts
        if not CollectionService:HasTag(part, controller.playerTag) then
            table.insert(whitelist, part)
        elseif controller.snakeObject then
            -- For self-collision, check segment distance
            local segmentIndex = tonumber(part:GetAttribute("SegmentIndex"))
            if segmentIndex and segmentIndex > COLLISION_CONFIG.SELF_COLLISION_IGNORE_SEGMENTS then
                table.insert(whitelist, part)
            end
        end
    end
    
    -- Add obstacles
    for _, obstacle in ipairs(self.obstacleCache) do
        table.insert(whitelist, obstacle)
    end
    
    params.FilterDescendantsInstances = whitelist
    
    -- Check for collisions
    local touchingParts = workspace:GetPartsInPart(head, params)
    
    if #touchingParts > 0 then
        -- Determine collision type
        local hitPart = touchingParts[1]
        local collisionData = {
            isFatal = true,
            hitPart = hitPart,
            hitPosition = head.Position,
            preventOrbs = false
        }
        
        -- Check if we hit another player's head (grants kill credit)
        if CollectionService:HasTag(hitPart, "SnakeHead") then
            collisionData.killerPlayer = self:_getPlayerFromPart(hitPart)
            collisionData.isHeadCollision = true
        elseif CollectionService:HasTag(hitPart, "Obstacle") then
            collisionData.isWallCollision = true
        else
            collisionData.isBodyCollision = true
        end
        
        -- Fire fatal collision event
        controller.events.onFatalHit:Fire(collisionData)
    end
end

function CollisionModule:_updateCaches()
    -- Update orb cache
    self.orbCache = CollectionService:GetTagged("Orb")
    
    -- Update obstacle cache
    self.obstacleCache = CollectionService:GetTagged("Obstacle")
end

function CollisionModule:_getPlayerFromPart(part)
    -- Find which player owns this part
    for player, controller in pairs(self.controllers) do
        if CollectionService:HasTag(part, controller.playerTag) then
            return player
        end
    end
    return nil
end

-- Add a new orb to the cache immediately
function CollisionModule:registerOrb(orb)
    table.insert(self.orbCache, orb)
end

-- Remove an orb from cache
function CollisionModule:unregisterOrb(orb)
    local index = table.find(self.orbCache, orb)
    if index then
        table.remove(self.orbCache, index)
    end
end

return CollisionModule