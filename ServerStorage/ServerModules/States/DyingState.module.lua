--[[
    DyingState.module - Handles death sequence with cancellable Promises
    Eliminates race conditions and ensures proper cleanup
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(script.Parent.Parent.Lib.Promise)

local DyingState = {}
DyingState.__index = DyingState

function DyingState.new(controller)
    local self = setmetatable({}, DyingState)
    self.controller = controller
    self.name = "Dying"
    return self
end

function DyingState:OnEnter(collisionData)
    -- This returns a Promise that resolves to the next state
    return Promise.new(function(resolve, reject, onCancel)
        -- Check if controller is still valid
        if self.controller.isDestroyed then
            return reject("Controller destroyed")
        end
        
        -- Update death statistics
        self.controller.data.deathCount = self.controller.data.deathCount + 1
        self.controller.data.lastDeathTime = os.clock()
        
        -- Set death attributes
        self.controller.player:SetAttribute("IsDead", true)
        
        -- Disable collisions immediately
        self.controller.collisionState.canCollide = false
        
        -- Step 1: Play death effects (non-yielding)
        self.controller:playDeathEffects(collisionData)
        
        -- Spawn death orbs if needed
        if collisionData and not collisionData.preventOrbs then
            self:_spawnDeathOrbs()
        end
        
        -- Freeze camera
        self:_freezeCamera()
        
        -- Step 2: Wait for death animation
        local deathAnimPromise = Promise.delay(2) -- 2 second death animation
        
        deathAnimPromise:andThen(function()
            -- Check if we should offer revive
            if self.controller:hasReviveToken() and not self.controller.isDestroyed then
                -- Step 3: Request revive from client
                return self.controller:requestReviveFromClient()
            else
                -- No revive available, go straight to spectating
                return Promise.resolve("Spectating")
            end
        end):andThen(function(nextState)
            -- Resolve the main promise with the next state
            resolve(nextState)
        end):catch(function(err)
            warn("Death sequence error:", err)
            resolve("Spectating") -- Default to spectating on error
        end)
        
        -- Critical: Setup cancellation handler
        onCancel(function()
            -- This runs if the player leaves or state is forcibly changed
            self.controller:hideReviveUI()
            self:_cleanupDeath()
        end)
    end)
end

function DyingState:OnExecute(dt)
    -- Nothing to update during death
end

function DyingState:OnExit()
    -- Ensure UI is hidden
    self.controller:hideReviveUI()
    
    -- Notify state change
    self.controller:notifyStateChange("DeathComplete")
end

function DyingState:_spawnDeathOrbs()
    -- Spawn orbs at death location
    local head = self.controller:getSnakeHead()
    if not head then return end
    
    local OrbUtils = ReplicatedStorage:FindFirstChild("OrbUtils")
    if not OrbUtils then return end
    
    local OrbUtilsModule = require(OrbUtils)
    
    -- Calculate orbs to spawn based on length
    local orbCount = math.min(
        math.floor(self.controller:getLength() * 0.7),
        self.controller.config.maxDeathOrbs or 50
    )
    
    -- Spawn orbs asynchronously
    task.spawn(function()
        for i = 1, orbCount do
            if self.controller.isDestroyed then break end
            
            local offset = Vector3.new(
                math.random(-10, 10),
                0,
                math.random(-10, 10)
            )
            
            -- OrbUtilsModule.spawnOrb(head.Position + offset, 1)
            -- Orb spawning is handled by the existing SnakeSystemIntegration
            task.wait(0.03) -- Small delay between orbs
        end
    end)
end

function DyingState:_freezeCamera()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local freezeCamera = remotes:FindFirstChild("FreezeCamera")
    
    if freezeCamera then
        freezeCamera:FireClient(self.controller.player, true)
    end
end

function DyingState:_cleanupDeath()
    -- Destroy snake model
    if self.controller.snakeModel then
        Debris:AddItem(self.controller.snakeModel, 0.5)
        self.controller.snakeModel = nil
    end
    
    -- Clear snake object
    if self.controller.snakeObject then
        if self.controller.snakeObject.destroy then
            self.controller.snakeObject:destroy()
        end
        self.controller.snakeObject = nil
    end
end

return DyingState