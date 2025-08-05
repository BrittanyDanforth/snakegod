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
    
    -- Don't return a promise - let the existing death system handle everything
    -- The existing SnakeSystemIntegration will handle:
    -- - Showing ReviveUI
    -- - Spawning orbs
    -- - Death effects
    -- - Respawning
    
    -- Check if player has revive available
    local player = self.controller.player
    local hasRevive = player:GetAttribute("HasRevive") or false
    local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
    
    if hasRevive or revivesAvailable > 0 then
        -- Return a promise that will prompt for revive
        return Promise.new(function(resolve, reject, onCancel)
            -- Send revive prompt
            local remotes = ReplicatedStorage:WaitForChild("Remotes")
            local promptReviveRemote = remotes:FindFirstChild("PromptRevive")
            
            if not promptReviveRemote then
                warn("[DyingState] PromptRevive remote not found")
                return resolve("Spectating")
            end
            
            -- Set attributes to prevent duplicate prompts
            player:SetAttribute("RevivePromptActive", true)
            player:SetAttribute("AwaitingReviveResponse", true)
            
            -- Send prompt to client
            promptReviveRemote:FireClient(player)
            
            -- Set up response handler
            local responseConnection
            local responseReceived = false
            
            responseConnection = promptReviveRemote.OnServerEvent:Connect(function(plr, response)
                if plr == player and not responseReceived then
                    responseReceived = true
                    responseConnection:Disconnect()
                    
                    player:SetAttribute("RevivePromptActive", false)
                    player:SetAttribute("AwaitingReviveResponse", false)
                    
                    if response == "revive" then
                        -- Transition to Reviving state
                        player:SetAttribute("RevivingNow", true)
                        player:SetAttribute("JustRevived", true)
                        resolve("Reviving")
                    else
                        -- Transition to Spectating state
                        resolve("Spectating")
                    end
                end
            end)
            
            -- Timeout handler (10 seconds)
            task.delay(10, function()
                if responseConnection and responseConnection.Connected then
                    responseConnection:Disconnect()
                    player:SetAttribute("RevivePromptActive", false)
                    player:SetAttribute("AwaitingReviveResponse", false)
                    
                    if not responseReceived then
                        resolve("Spectating")
                    end
                end
            end)
            
            -- Clean up on cancel
            onCancel(function()
                if responseConnection then
                    responseConnection:Disconnect()
                end
                player:SetAttribute("RevivePromptActive", false) 
                player:SetAttribute("AwaitingReviveResponse", false)
            end)
        end)
    else
        -- No revive available, go to spectating
        return Promise.resolve("Spectating")
    end
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