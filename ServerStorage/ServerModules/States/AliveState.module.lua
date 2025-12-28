--[[
    AliveState.module - Primary gameplay state
    Handles player input processing, movement, and collision response
]]

local AliveState = {}
AliveState.__index = AliveState

function AliveState.new(controller)
    local self = setmetatable({}, AliveState)
    self.controller = controller
    self.name = "Alive"
    return self
end

function AliveState:OnEnter()
    -- Enable player controls
    self.controller.collisionState.canCollide = true
    
    -- Notify systems that player is alive
    self.controller:notifyStateChange("Alive")
    
    -- Reset any death-related attributes
    if self.controller.player then
        self.controller.player:SetAttribute("IsDead", false)
        self.controller.player:SetAttribute("IsReviving", false)
    end
end

function AliveState:OnExecute(dt)
    -- This state primarily relies on external systems:
    -- - OptimizedSnakeSystem handles movement based on player input
    -- - CollisionModule handles collision detection
    -- The state just ensures we're ready to respond to events
    
    -- Check if we should still be alive
    if not self.controller.snakeObject or self.controller.isDestroyed then
        self.controller.fsm:changeState("Spectating")
    end
end

function AliveState:OnExit()
    -- Disable controls when leaving alive state
    self.controller.collisionState.canCollide = false
    
    -- Notify that we're no longer alive
    self.controller:notifyStateChange("NotAlive")
end

-- Handle collision events while alive
function AliveState:handleCollision(collisionData)
    -- This would be called by the collision system
    -- The state determines what happens based on collision type
    
    if collisionData.isFatal and self.controller:canCollide() then
        -- Transition to dying state with collision data
        self.controller.fsm:changeState("Dying", collisionData)
    end
end

return AliveState