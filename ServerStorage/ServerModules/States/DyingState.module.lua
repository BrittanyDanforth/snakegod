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
    
    -- Store death info
    local character = self.controller.player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        self.deathPosition = character.HumanoidRootPart.Position
    end
    
    -- Store current length from leaderstats
    local leaderstats = self.controller.player:FindFirstChild("leaderstats")
    if leaderstats and leaderstats:FindFirstChild("Length") then
        self.currentLength = leaderstats.Length.Value
    else
        self.currentLength = 55 -- default
    end
    
    -- Log the death
    warn("[DyingState] Player", self.controller.player.Name, "entered dying state")
    warn("[DyingState] Death position:", self.deathPosition, "Current length:", self.currentLength)
    
    -- Return promise for next state
    return Promise.new(function(resolve, reject, onCancel)
        -- Check for revives
        if self.controller:hasReviveToken() then
            warn("[DyingState] Player has revive tokens available")
            
            -- Get remotes
            local remotes = ReplicatedStorage:WaitForChild("Remotes")
            local promptRevive = remotes:FindFirstChild("PromptRevive")
            
            if promptRevive then
                -- Set attributes for revive system
                self.controller.player:SetAttribute("RevivePromptActive", true)
                self.controller.player:SetAttribute("AwaitingReviveResponse", true)
                
                -- Fire revive prompt to client
                promptRevive:FireClient(self.controller.player, {
                    revivesLeft = self.controller.player:GetAttribute("RevivesAvailable"),
                    deathCause = collisionData and (
                        collisionData.killerPlayer and ("Player: " .. collisionData.killerPlayer.Name) or
                        collisionData.isWallCollision and "Wall" or
                        collisionData.isBodyCollision and "Body Collision" or
                        "Unknown"
                    ) or "Unknown"
                })
                
                -- Set up response listener with timeout
                local responseConnection
                local timeoutTask
                local responded = false
                
                responseConnection = promptRevive.OnServerEvent:Connect(function(respondingPlayer, response)
                    if respondingPlayer == self.controller.player and not responded then
                        responded = true
                        responseConnection:Disconnect()
                        
                        if timeoutTask then
                            task.cancel(timeoutTask)
                        end
                        
                        -- Clear prompt attributes
                        self.controller.player:SetAttribute("RevivePromptActive", false)
                        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                        
                        if response == "revive" then
                            -- Store revival info
                            self.controller.player:SetAttribute("ReviveSnakeLength", self.currentLength)
                            if self.deathPosition then
                                self.controller.player:SetAttribute("RevivePosition", 
                                    string.format("%.2f, %.2f, %.2f", 
                                        self.deathPosition.X, 
                                        self.deathPosition.Y, 
                                        self.deathPosition.Z
                                    )
                                )
                            end
                            
                            warn("[DyingState] Player chose to revive")
                            resolve("Reviving")
                        else
                            warn("[DyingState] Player declined revive")
                            resolve("Spectating")
                        end
                    end
                end)
                
                -- Set up timeout (10 seconds)
                timeoutTask = task.delay(10, function()
                    if not responded then
                        responded = true
                        responseConnection:Disconnect()
                        
                        -- Clear prompt attributes
                        self.controller.player:SetAttribute("RevivePromptActive", false)
                        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                        
                        warn("[DyingState] Revive prompt timed out")
                        resolve("Spectating")
                    end
                end)
                
                -- Handle cancellation
                onCancel(function()
                    if responseConnection then
                        responseConnection:Disconnect()
                    end
                    if timeoutTask then
                        task.cancel(timeoutTask)
                    end
                    -- Clear prompt attributes
                    self.controller.player:SetAttribute("RevivePromptActive", false)
                    self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                end)
            else
                warn("[DyingState] PromptRevive remote not found!")
                resolve("Spectating")
            end
        else
            -- No revives available, go straight to spectating
            warn("[DyingState] No revive tokens available")
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