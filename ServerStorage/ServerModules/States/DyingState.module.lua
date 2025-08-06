--[[
    DyingState.module - Handles death sequence with cancellable Promises
    Eliminates race conditions and ensures proper cleanup
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
    
    -- SAVE SNAKE BODY CONFIGURATION BEFORE FADING
    self:_saveSnakeBodyConfiguration()
    
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
        
        -- Make snake fade out quickly and spawn death orbs
        self:_fadeOutSnakeAndSpawnOrbs()
        
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

function DyingState:_saveSnakeBodyConfiguration()
    -- Get the snake system
    local snakeSystem = _G.PlayerSnakes and _G.PlayerSnakes[self.controller.player]
    if not snakeSystem then 
        warn("[DyingState] No snake system found for saving configuration")
        return 
    end
    
    -- Save the entire snake state
    local savedState = {
        -- Position history for body recreation
        positionHistory = {},
        -- Current length
        length = snakeSystem.actualLength or snakeSystem.length or self.currentLength,
        targetLength = snakeSystem.targetLength or self.currentLength,
        -- Visual properties
        config = snakeSystem.config,
        -- Head position
        headPosition = snakeSystem.head and snakeSystem.head.Position or self.deathPosition,
        -- Save segment data
        segments = {},
        -- Save visible segment count
        visibleSegmentCount = snakeSystem.visibleSegmentCount or 0
    }
    
    -- Copy position history if it exists
    if snakeSystem.positionHistory then
        for i, historyEntry in ipairs(snakeSystem.positionHistory) do
            table.insert(savedState.positionHistory, {
                position = historyEntry.position,
                lookVector = historyEntry.lookVector,
                time = historyEntry.time
            })
        end
    end
    
    -- Save segment positions and properties
    if snakeSystem.segments then
        for i, segment in ipairs(snakeSystem.segments) do
            if segment and segment.Parent then
                table.insert(savedState.segments, {
                    position = segment.Position,
                    size = segment.Size,
                    color = segment.Color,
                    transparency = segment.Transparency
                })
            end
        end
    end
    
    -- Store the saved state as an attribute (using JSON encoding)
    local HttpService = game:GetService("HttpService")
    local success, encoded = pcall(function()
        -- We'll store just the essential data as attributes
        self.controller.player:SetAttribute("SavedSnakeLength", savedState.length)
        self.controller.player:SetAttribute("SavedSnakeSegmentCount", #savedState.segments)
        
        -- Store position history as a simpler format
        if #savedState.positionHistory > 0 then
            local positions = {}
            for i = 1, math.min(100, #savedState.positionHistory) do -- Limit to recent 100 positions
                local entry = savedState.positionHistory[i]
                table.insert(positions, string.format("%f,%f,%f", entry.position.X, entry.position.Y, entry.position.Z))
            end
            self.controller.player:SetAttribute("SavedSnakePositions", table.concat(positions, ";"))
        end
    end)
    
    -- Store in controller for immediate access
    self.controller.savedSnakeState = savedState
    
    warn("[DyingState] Saved snake configuration with", #savedState.segments, "segments")
end

function DyingState:_fadeOutSnakeAndSpawnOrbs()
    local snakeSystem = _G.PlayerSnakes and _G.PlayerSnakes[self.controller.player]
    if not snakeSystem then return end
    
    -- Collect segment positions before fading
    local segmentPositions = {}
    if snakeSystem.segments then
        for i, segment in ipairs(snakeSystem.segments) do
            if segment and segment.Parent then
                table.insert(segmentPositions, segment.Position)
            end
        end
    end
    
    -- Create fade effect with tweens for smoother animation
    task.spawn(function()
        local parts = {}
        local tweens = {}
        
        -- Collect all parts including segments and visual elements
        if snakeSystem.segments then
            for _, segment in ipairs(snakeSystem.segments) do
                if segment and segment:IsA("BasePart") then
                    segment.CanCollide = false
                    table.insert(parts, segment)
                end
            end
        end
        
        -- Also fade the head if it exists
        if snakeSystem.head and snakeSystem.head:IsA("BasePart") then
            snakeSystem.head.CanCollide = false
            table.insert(parts, snakeSystem.head)
        end
        
        -- Fade out beams quickly
        if snakeSystem.beams then
            for _, beam in pairs(snakeSystem.beams) do
                if beam and beam:IsA("Beam") then
                    local tween = TweenService:Create(beam, 
                        TweenInfo.new(0.3, Enum.EasingStyle.Linear),
                        {
                            Transparency = NumberSequence.new(1),
                            Width0 = 0,
                            Width1 = 0
                        }
                    )
                    tween:Play()
                    table.insert(tweens, tween)
                end
            end
        end
        
        -- Fade out glows
        if snakeSystem.glows then
            for _, glow in pairs(snakeSystem.glows) do
                if glow and glow:IsA("PointLight") then
                    local tween = TweenService:Create(glow,
                        TweenInfo.new(0.2, Enum.EasingStyle.Linear),
                        {
                            Brightness = 0,
                            Range = 0
                        }
                    )
                    tween:Play()
                    table.insert(tweens, tween)
                end
            end
        end
        
        -- Create quick fade for all parts
        for _, part in ipairs(parts) do
            if part and part.Parent then
                local tween = TweenService:Create(part,
                    TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    {
                        Transparency = 1,
                        Size = part.Size * 0.8 -- Slight shrink effect
                    }
                )
                tween:Play()
                table.insert(tweens, tween)
            end
        end
        
        -- Wait for tweens to complete
        task.wait(0.3)
        
        -- Hide the model but don't destroy it (we need it for revival)
        if snakeSystem.model then
            snakeSystem.model.Parent = nil
        end
    end)
    
    -- Spawn death orbs along the snake body
    task.wait(0.15) -- Wait for fade to start before spawning orbs
    self:_spawnDeathOrbs(segmentPositions)
end

function DyingState:_spawnDeathOrbs(segmentPositions)
    -- Use the collision handler's death orb spawning
    local success, SnakeCollisionHandler = pcall(function()
        -- Try different possible locations
        local locations = {
            game.ServerScriptService:FindFirstChild("SnakeCollisionHandler"),
            game.ServerScriptService:FindFirstChild("CollisionHandler"),
            game.ServerScriptService:FindFirstChild("SnakeCollisionHandler_FINAL"),
            workspace:FindFirstChild("SnakeCollisionHandler_FINAL")
        }
        
        for _, location in ipairs(locations) do
            if location and location:IsA("ModuleScript") then
                return require(location)
            end
        end
        
        -- If it's a script, not a module, we can't require it
        return nil
    end)
    
    if success and SnakeCollisionHandler and SnakeCollisionHandler.spawnDeathOrbsForPlayer then
        SnakeCollisionHandler.spawnDeathOrbsForPlayer(self.controller.player, segmentPositions or {self.deathPosition}, self.currentLength)
    else
        -- Fallback: spawn orbs manually
        warn("[DyingState] Using fallback orb spawning")
        local orbCount = math.min(math.floor(self.currentLength * 0.4), 50)
        local orbValue = math.max(1, math.floor(self.currentLength * 0.3 / orbCount))
        
        for i = 1, orbCount do
            local pos = self.deathPosition
            if segmentPositions and segmentPositions[i] then
                pos = segmentPositions[i]
            end
            
            local offset = Vector3.new(
                math.random(-2, 2),
                0,
                math.random(-2, 2)
            )
            
            -- Create death orb
            local orb = Instance.new("Part")
            orb.Name = "DeathOrb"
            orb.Shape = Enum.PartType.Ball
            orb.Material = Enum.Material.Neon
            orb.Size = Vector3.new(2, 2, 2)
            orb.TopSurface = Enum.SurfaceType.Smooth
            orb.BottomSurface = Enum.SurfaceType.Smooth
            orb.CanCollide = false
            orb.Position = pos + offset
            orb.Color = Color3.fromRGB(255, 200, 0)
            orb:SetAttribute("OrbValue", orbValue)
            orb:SetAttribute("IsDeathOrb", true)
            
            -- Add glow
            local glow = Instance.new("PointLight")
            glow.Brightness = 2
            glow.Range = 10
            glow.Color = orb.Color
            glow.Parent = orb
            
            orb.Parent = workspace
            
            -- Add floating animation
            local floatTween = TweenService:Create(orb,
                TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                {Position = orb.Position + Vector3.new(0, 2, 0)}
            )
            floatTween:Play()
            
            task.wait(0.03)
        end
    end
end

return DyingState