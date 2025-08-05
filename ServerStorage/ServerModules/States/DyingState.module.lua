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
    -- Disable collisions immediately
    self.controller.collisionState.canCollide = false
    
    -- Log the death
    warn("[DyingState] Player", self.controller.player.Name, "entered dying state")
    
    -- Return a promise that determines the next state
    return Promise.new(function(resolve, reject, onCancel)
        -- Check if player has revives
        if self.controller:hasReviveToken() then
            -- Request revive from client
            self.controller:requestReviveFromClient():andThen(function(result)
                if result == "Reviving" then
                    -- Player chose to revive, transition to RevivingState
                    resolve("Reviving")
                else
                    -- Player declined revive
                    resolve("Spectating")
                end
            end):catch(function(err)
                warn("[DyingState] Error requesting revive:", err)
                resolve("Spectating")
            end)
        else
            -- No revives available, go straight to spectating
            warn("[DyingState] No revives available for", self.controller.player.Name)
            resolve("Spectating")
        end
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
    -- Death orbs are now handled by MainServer's DeathOrbHandler
    -- This function is kept for compatibility but does nothing
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