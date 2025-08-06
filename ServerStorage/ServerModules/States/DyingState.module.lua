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
        
        -- IMMEDIATE death effect for visual feedback
        local deathEffectRemote = remotes:FindFirstChild("PlayerDeathEffect")
        if deathEffectRemote and self.deathPosition then
            deathEffectRemote:FireAllClients(self.controller.player, self.deathPosition)
        end
        
        -- Disable movement IMMEDIATELY (no wait)
        if humanoid then
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            humanoid.PlatformStand = true
        end
        
        -- Stop snake movement by disconnecting its update loop
        local snakeSystem = _G.PlayerSnakes and _G.PlayerSnakes[self.controller.player]
        if snakeSystem and snakeSystem.updateConnection then
            snakeSystem.updateConnection:Disconnect()
            snakeSystem.updateConnection = nil
        end
        
        -- Tell client to stop snake movement IMMEDIATELY
        local stopMovementRemote = remotes:FindFirstChild("StopSnakeMovement")
        if stopMovementRemote then
            stopMovementRemote:FireClient(self.controller.player)
        end
        
        -- Make snake fade out quickly for polished effect
        if self.controller.snakeObject then
            if self.controller.snakeObject:IsA("Model") then
                -- Create a quick fade effect
                task.spawn(function()
                    local parts = {}
                    for _, part in ipairs(self.controller.snakeObject:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                            table.insert(parts, part)
                        end
                    end
                    
                    -- Quick fade out (0.3 seconds)
                    local fadeSteps = 6
                    for i = 1, fadeSteps do
                        for _, part in ipairs(parts) do
                            if part and part.Parent then
                                part.Transparency = i / fadeSteps
                            end
                        end
                        task.wait(0.05)
                    end
                end)
            end
        end
        
        -- Very short pause before showing prompt (reduced from 0.2)
        task.wait(0.1)
        
        -- Check for revives
        if self.controller:hasReviveToken() then
            
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
                            
                            -- Do NOT kill the humanoid - they're reviving!
                            resolve("Reviving")
                        else
                            self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                            
                            -- Player declined - kill humanoid and show death UI
                            if humanoid and humanoid.Health > 0 then
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
                        self.controller.player:SetAttribute("RevivePromptActive", false)
                        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
                        
                        -- Kill humanoid on timeout
                        if humanoid and humanoid.Health > 0 then
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
                    humanoid.Health = 0
                end
                task.wait(0.5)
                resolve("Spectating")
            end
        else
            -- No revives available, go straight to spectating
            
            -- Much shorter wait before showing death UI (reduced from 1.0)
            task.wait(0.3)
            
            -- Show death UI after delay
            if deathUIRemote then
                deathUIRemote:FireClient(self.controller.player, {
                    action = "show"
                })
            end
            
            -- Kill the player after showing UI
            if humanoid and humanoid.Health > 0 then
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