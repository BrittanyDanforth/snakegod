--[[
    RevivingState.module - Manages the revive countdown with cancellable Promise
    Handles the transition back to spawning or to spectating on cancellation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(script.Parent.Parent.Lib.Promise)

local RevivingState = {}
RevivingState.__index = RevivingState

function RevivingState.new(controller)
    local self = setmetatable({}, RevivingState)
    self.controller = controller
    self.name = "Reviving"
    return self
end

function RevivingState:OnEnter()
    warn("[RevivingState] Entered reviving state for", self.controller.player.Name)
    
    -- This returns a Promise that resolves to the next state
    return Promise.new(function(resolve, reject, onCancel)
        -- Validate we can revive
        if not self.controller:hasReviveToken() then
            warn("[RevivingState] No revive tokens, going to spectating")
            return resolve("Spectating")
        end
        
        -- Use revive token
        self.controller:useReviveToken()
        
        -- Set reviving attribute
        self.controller.player:SetAttribute("IsReviving", true)
        
        -- Start countdown - reduced from 5 to 3 seconds
        local countdownDuration = 3  -- Faster revive time
        local startTime = os.clock()
        
        -- Update UI with countdown
        local updateConnection
        updateConnection = game:GetService("RunService").Heartbeat:Connect(function()
            local elapsed = os.clock() - startTime
            local remaining = math.max(0, countdownDuration - elapsed)
            
            -- Update client UI
            self:_updateReviveUI(remaining)
            
            if remaining <= 0 then
                updateConnection:Disconnect()
            end
        end)
        
        -- Setup cancellation
        local cancelled = false
        onCancel(function()
            cancelled = true
            if updateConnection then
                updateConnection:Disconnect()
            end
            self.controller:hideReviveUI()
        end)
        
        -- Wait for countdown or cancellation
        Promise.delay(countdownDuration):andThen(function()
            if updateConnection then
                updateConnection:Disconnect()
            end
            
            if not cancelled and not self.controller.isDestroyed then
                -- Successfully revived
                warn("[RevivingState] Countdown complete, transitioning to Spawning")
                -- Pass the current state name so SpawningState knows we're reviving
                self.controller.fsm.previousStateForSpawning = "Reviving"
                resolve("Spawning")
            else
                -- Cancelled or destroyed
                resolve("Spectating")
            end
        end)
        
        -- Also listen for player input to cancel
        local remotes = ReplicatedStorage:WaitForChild("Remotes")
        local cancelRemote = remotes:FindFirstChild("CancelRevive")
        
        if cancelRemote then
            local cancelConnection
            cancelConnection = cancelRemote.OnServerEvent:Connect(function(player)
                if player == self.controller.player then
                    cancelConnection:Disconnect()
                    cancelled = true
                    resolve("Spectating")
                end
            end)
            
            onCancel(function()
                if cancelConnection then
                    cancelConnection:Disconnect()
                end
            end)
        end
    end)
end

function RevivingState:OnExecute(dt)
    -- State logic is handled in the Promise
end

function RevivingState:OnExit()
    -- Clear reviving attribute
    self.controller.player:SetAttribute("IsReviving", false)
    
    -- Hide UI
    self.controller:hideReviveUI()
    
    -- Notify state change
    self.controller:notifyStateChange("ReviveComplete")
end

function RevivingState:_updateReviveUI(timeRemaining)
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local updateRemote = remotes:FindFirstChild("UpdateReviveCountdown")
    
    if updateRemote then
        updateRemote:FireClient(self.controller.player, {
            timeRemaining = timeRemaining,
            isReviving = true
        })
    end
end

return RevivingState