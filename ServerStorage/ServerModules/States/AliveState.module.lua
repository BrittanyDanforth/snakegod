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
    warn("[FSM] AliveState entered for", self.controller.player.Name)
    self.controller.collisionState.canCollide = true
    self.controller.data.isAlive = true
    self.controller.data.deathTime = nil
    
    -- Clear ALL revive-related attributes to prevent UI issues
    self.controller.player:SetAttribute("IsReviving", false)
    self.controller.player:SetAttribute("RevivePromptActive", false)
    self.controller.player:SetAttribute("AwaitingReviveResponse", false)
    self.controller.player:SetAttribute("JustRevived", false)
    self.controller.player:SetAttribute("RevivingNow", false)
    self.controller.player:SetAttribute("ReviveDeclined", false)
    self.controller.player:SetAttribute("ReviveTimerExpired", false)
    
    -- Spawn protection
    if self.spawnProtectionDuration > 0 then
        warn("[AliveState] Spawn protection active for", self.spawnProtectionDuration, "seconds")
        self.controller.collisionState.hasSpawnProtection = true
        
        -- Remove spawn protection after duration
        task.spawn(function()
            task.wait(self.spawnProtectionDuration)
            if self.controller and not self.controller.isDestroyed then
                self.controller.collisionState.hasSpawnProtection = false
                warn("[AliveState] Spawn protection ended for", self.controller.player.Name)
            end
        end)
    end
    
    -- Notify state change
    self.controller:notifyStateChange("Alive")
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