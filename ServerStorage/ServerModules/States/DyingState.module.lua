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
    
    -- Store character reference for later
    local character = self.controller.player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    
    -- IMPORTANT: Do NOT kill the humanoid yet - wait for revive decision
    
    -- Return promise for next state
    return Promise.new(function(resolve, reject, onCancel)
        -- First, tell the client NOT to show death screen yet
        local remotes = ReplicatedStorage:WaitForChild("Remotes")
        local deathUIRemote = remotes:FindFirstChild("ControlDeathUI")
        if not deathUIRemote then
            deathUIRemote = Instance.new("RemoteEvent")
            deathUIRemote.Name = "ControlDeathUI"
            deathUIRemote.Parent = remotes
        end
        
        -- Hide death UI initially
        deathUIRemote:FireClient(self.controller.player, {
            action = "hide"
        })
        
        -- Wait a moment for death to process
        task.wait(0.5)
        
        -- Disable movement but don't kill yet
        if humanoid then
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.PlatformStand = true
        end
        
        -- Make snake invisible/non-collidable
        if self.controller.snakeObject then
            if self.controller.snakeObject:IsA("Model") then
                for _, part in ipairs(self.controller.snakeObject:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                        part.Transparency = 0.5
                    end
                end
            end
        end
        
        -- Short pause before showing prompt
        task.wait(0.2)
        
        -- Check for revives
        if self.controller:hasReviveToken() then
            warn("[DyingState] Player has revive tokens available")
            
            -- Check if we're already prompting to prevent duplicates
            if self.controller.player:GetAttribute("RevivePromptActive") then
                warn("[DyingState] Revive prompt already active, skipping duplicate")
                return resolve("Spectating")
            end
            
            -- Get remotes
            local remotes = ReplicatedStorage:WaitForChild("Remotes")
            local promptRevive = remotes:FindFirstChild("PromptRevive")
            local reviveResponse = remotes:FindFirstChild("ReviveResponse")
            
            -- Create response remote if needed
            if not reviveResponse then
                reviveResponse = Instance.new("RemoteEvent")
                reviveResponse.Name = "ReviveResponse"
                reviveResponse.Parent = remotes
            end
            
            if promptRevive then
                -- Check if we haven't already sent a prompt
                if self.controller.player:GetAttribute("RevivePromptActive") then
                    warn("[DyingState] Revive prompt already active, not sending duplicate")
                    resolve("Spectating")
                    return
                end
                
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
                
                responseConnection = reviveResponse.OnServerEvent:Connect(function(respondingPlayer, response)
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
                            -- Set revive attributes for SnakeSystemIntegration
                            self.controller.player:SetAttribute("ReviveSnakeLength", self.currentLength)
                            if self.deathPosition then
                                self.controller.player:SetAttribute("RevivePosition", 
                                    string.format("%f,%f,%f", self.deathPosition.X, self.deathPosition.Y, self.deathPosition.Z))
                            end
                            
                            warn("[DyingState] Player chose to revive")
                            -- Do NOT kill the humanoid - they're reviving!
                            resolve("Reviving")
                        else
                            warn("[DyingState] Player declined revive")
                            self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                            
                            -- Player declined - kill humanoid and show death UI
                            if humanoid and humanoid.Health > 0 then
                                warn("[DyingState] Killing player humanoid (declined revive)")
                                humanoid.Health = 0
                            end
                            
                            -- Show death UI after killing
                            task.wait(0.5)
                            if deathUIRemote then
                                deathUIRemote:FireClient(self.controller.player, {
                                    action = "show"
                                })
                            end
                            
                            resolve("Spectating")
                        end
                    end
                end)
                
                -- Handle timeout
                timeoutTask = task.delay(10, function()
                    if not responded and responseConnection then
                        responseConnection:Disconnect()
                        warn("[DyingState] Revive prompt timed out")
                        self.controller.player:SetAttribute("RevivePromptActive", false)
                        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                        
                        -- Kill humanoid on timeout
                        if humanoid and humanoid.Health > 0 then
                            warn("[DyingState] Killing player humanoid (timeout)")
                            humanoid.Health = 0
                        end
                        
                        -- Show death UI on timeout
                        task.wait(0.5)
                        if deathUIRemote then
                            deathUIRemote:FireClient(self.controller.player, {
                                action = "show"
                            })
                        end
                        
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
                -- Wait a bit before killing to prevent jarring transition
                task.wait(1.0)
                -- Kill the player since we can't prompt
                if humanoid and humanoid.Health > 0 then
                    warn("[DyingState] Killing player humanoid (no prompt remote)")
                    humanoid.Health = 0
                end
                task.wait(0.5)
                resolve("Spectating")
            end
        else
            -- No revives available, go straight to spectating
            warn("[DyingState] No revive tokens available")
            
            -- Wait a bit before showing death UI to prevent jarring transition
            task.wait(1.0)
            
            -- Show death UI after delay
            if deathUIRemote then
                deathUIRemote:FireClient(self.controller.player, {
                    action = "show"
                })
            end
            
            -- Kill the player after showing UI
            if humanoid and humanoid.Health > 0 then
                warn("[DyingState] Killing player humanoid (no revives)")
                humanoid.Health = 0
            end
            
            -- Wait for death to process
            task.wait(0.5)
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

function DyingState:_killPlayer()
    -- Kill the humanoid to trigger death systems
    local character = self.controller.player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            warn("[DyingState] Killing player humanoid")
            humanoid.Health = 0
        end
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