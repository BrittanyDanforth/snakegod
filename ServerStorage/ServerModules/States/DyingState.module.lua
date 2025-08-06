--[[
    DyingState.module - Handles death sequence with cancellable Promises
    Eliminates race conditions and ensures proper cleanup
]]

-- Services and dependencies
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")

-- Modules
local SnakeUpgrades = require(ReplicatedStorage:WaitForChild("SnakeUpgrades"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local playerDeathEvent = remotes:WaitForChild("PlayerDeathEffect")
local promptReviveRemote = remotes:WaitForChild("PromptRevive")
local reviveResponseRemote = remotes:WaitForChild("ReviveResponse")
local stopSnakeMovementRemote = remotes:WaitForChild("StopSnakeMovement")
local showDeathScreenRemote = remotes:WaitForChild("ShowDeathScreen")
local setSpectatorCameraRemote = remotes:WaitForChild("SetSpectatorCamera")

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
    
    -- Save snake body configuration before fading
    self:_saveSnakeBodyConfiguration()
    
    -- Clean up any visual effects (ghost mode particles, etc)
    self:_cleanupVisualEffects()
    
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

function DyingState:_saveSnakeBodyConfiguration()
    -- Get the snake system
    local snakeSystem = _G.PlayerSnakes and _G.PlayerSnakes[self.controller.player]
    if not snakeSystem then 
        warn("[DyingState] No snake system found for saving configuration")
        return 
    end
    
    -- Save the entire snake state efficiently
    local savedState = {
        -- Current length
        length = snakeSystem.actualLength or snakeSystem.length or self.currentLength,
        targetLength = snakeSystem.targetLength or self.currentLength,
        -- Visual properties
        config = snakeSystem.config,
        -- Head position
        headPosition = snakeSystem.head and snakeSystem.head.Position or self.deathPosition,
        -- Save segment data (optimized)
        segments = {},
        -- Save visible segment count
        visibleSegmentCount = snakeSystem.visibleSegmentCount or 0
    }
    
    -- Save position history efficiently (only recent positions)
    if snakeSystem.positionHistory and #snakeSystem.positionHistory > 0 then
        savedState.positionHistory = {}
        -- Only save last 200 positions for performance
        local startIdx = math.max(1, #snakeSystem.positionHistory - 200)
        for i = startIdx, #snakeSystem.positionHistory do
            local entry = snakeSystem.positionHistory[i]
            if entry then
                table.insert(savedState.positionHistory, {
                    position = entry.position,
                    lookVector = entry.lookVector,
                    time = entry.time
                })
            end
        end
    end
    
    -- Save segment positions and properties efficiently
    if snakeSystem.segments then
        -- Sample segments if there are too many (for performance)
        local maxSegmentsToSave = 100
        local skipInterval = 1
        
        if #snakeSystem.segments > maxSegmentsToSave then
            skipInterval = math.ceil(#snakeSystem.segments / maxSegmentsToSave)
        end
        
        for i = 1, #snakeSystem.segments, skipInterval do
            local segment = snakeSystem.segments[i]
            if segment and segment.Parent then
                table.insert(savedState.segments, {
                    position = segment.Position,
                    size = segment.Size,
                    color = segment.Color,
                    transparency = segment.Transparency,
                    index = i -- Store original index for reconstruction
                })
            end
        end
    end
    
    -- Store in controller for immediate access
    self.controller.savedSnakeState = savedState
    
    -- Also store minimal data as attributes for backup
    self.controller.player:SetAttribute("SavedSnakeLength", savedState.length)
    self.controller.player:SetAttribute("SavedSnakeSegmentCount", savedState.visibleSegmentCount)
    
    warn("[DyingState] Saved snake configuration with", #savedState.segments, "sampled segments (from", savedState.visibleSegmentCount, "total)")
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
    
    -- Create fade effect with proper handling
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
        
        -- FIXED: Properly fade out beams without tweening NumberSequence
        if snakeSystem.beams then
            for _, beam in pairs(snakeSystem.beams) do
                if beam and beam:IsA("Beam") then
                    -- Can't tween NumberSequence, so just set it
                    beam.Enabled = false
                    beam.Transparency = NumberSequence.new(1)
                    beam.Width0 = 0
                    beam.Width1 = 0
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
        
        -- Disable particles if any
        if snakeSystem.boostParticles then
            snakeSystem.boostParticles.Enabled = false
        end
        
        -- Create quick fade for all parts
        for _, part in ipairs(parts) do
            if part and part.Parent then
                local tween = TweenService:Create(part,
                    TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    {
                        Transparency = 1,
                        Size = part.Size * 0.7 -- More aggressive shrink
                    }
                )
                tween:Play()
                table.insert(tweens, tween)
            end
        end
        
        -- Wait for fade
        task.wait(0.25)
        
        -- Completely hide everything
        if snakeSystem.model then
            -- Hide all descendants
            for _, obj in ipairs(snakeSystem.model:GetDescendants()) do
                if obj:IsA("BasePart") then
                    obj.Transparency = 1
                    obj.CanCollide = false
                elseif obj:IsA("Beam") then
                    obj.Enabled = false
                elseif obj:IsA("PointLight") or obj:IsA("SpotLight") then
                    obj.Enabled = false
                elseif obj:IsA("ParticleEmitter") then
                    obj.Enabled = false
                end
            end
            
            -- Parent to nil to completely hide
            snakeSystem.model.Parent = nil
        end
    end)
    
    -- Spawn death orbs immediately (don't wait for fade)
    task.spawn(function()
        task.wait(0.1) -- Very short delay
        self:_spawnDeathOrbs(segmentPositions)
    end)
end

function DyingState:_spawnDeathOrbs(segmentPositions)
    -- Spawn death orbs along the snake body
    warn("[DyingState] Spawning death orbs")
    
    -- Dynamic orb count based on snake length
    local baseOrbCount = 20
    local lengthBonus = math.floor(self.currentLength / 100) * 5
    local maxOrbs = math.min(baseOrbCount + lengthBonus, 50) -- Scale with length but cap at 50
    local orbCount = math.min(math.floor(self.currentLength * 0.3), maxOrbs)
    local orbValue = math.max(1, math.floor(self.currentLength * 0.4 / orbCount))
    
    -- If we have segment positions, spawn orbs along the body
    if segmentPositions and #segmentPositions > 0 then
        local spawnedOrbs = 0
        local skipInterval = math.max(1, math.floor(#segmentPositions / orbCount))
        
        -- Batch spawn for better performance
        local orbsToSpawn = {}
        
        for i = 1, #segmentPositions do
            if spawnedOrbs >= orbCount then break end
            
            if (i - 1) % skipInterval == 0 or i == #segmentPositions then
                local pos = segmentPositions[i]
                if pos then
                    -- Create a more organic spread pattern
                    local spread = 2.5 -- Increased spread for more visual appeal
                    local heightVariation = 1.5 -- Add vertical variation
                    local offset = Vector3.new(
                        (math.random() - 0.5) * spread * (1 + math.random() * 0.5),
                        math.random() * heightVariation, -- More vertical spread
                        (math.random() - 0.5) * spread * (1 + math.random() * 0.5)
                    )
                    
                    -- Vary orb values slightly for visual interest
                    local valueVariation = math.random(0.8, 1.2)
                    local finalValue = math.max(1, math.floor(orbValue * valueVariation))
                    
                    table.insert(orbsToSpawn, {position = pos + offset, value = finalValue})
                    spawnedOrbs = spawnedOrbs + 1
                end
            end
        end
        
        -- Spawn orbs in small batches to avoid lag spike
        for i, orbData in ipairs(orbsToSpawn) do
            self:_createDeathOrb(orbData.position, orbData.value)
            
            -- Small delay every few orbs to prevent lag
            if i % 5 == 0 then
                task.wait()
            end
        end
        
        print(string.format("✅ Spawned %d death orbs along snake body", spawnedOrbs))
    else
        -- Fallback: spawn in a spread pattern
        warn("[DyingState] No segment positions, using fallback pattern")
        for i = 1, orbCount do
            local angle = (i / orbCount) * math.pi * 2 * 3
            local distance = (i / orbCount) * math.min(self.currentLength * 0.5, 30)
            
            local offset = Vector3.new(
                math.cos(angle) * distance,
                0,
                math.sin(angle) * distance
            )
            
            self:_createDeathOrb(self.deathPosition + offset, orbValue)
            
            if i % 8 == 0 then
                task.wait(0.02)
            end
        end
    end
end

function DyingState:_createDeathOrb(position, value)
    -- Ensure Orbs folder exists
    local orbsFolder = workspace:FindFirstChild("Orbs")
    if not orbsFolder then
        orbsFolder = Instance.new("Folder")
        orbsFolder.Name = "Orbs"
        orbsFolder.Parent = workspace
    end
    
    -- Create death orb matching the game's orb style
    local orb = Instance.new("Part")
    orb.Name = "Orb" -- Use "Orb" name so AI snakes recognize it
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Neon
    
    -- Scale size based on value for visual feedback
    local baseSize = 2.5
    local sizeMultiplier = 1 + (math.min(value, 10) - 1) * 0.1 -- Size increases with value up to 3.5
    local finalSize = baseSize * sizeMultiplier
    orb.Size = Vector3.new(finalSize, finalSize, finalSize)
    
    orb.TopSurface = Enum.SurfaceType.Smooth
    orb.BottomSurface = Enum.SurfaceType.Smooth
    orb.CanCollide = false
    orb.Anchored = true
    orb.Position = position
    
    -- Start with a random color for immediate rainbow effect
    local hueStart = math.random()
    orb.Color = Color3.fromHSV(hueStart, 1, 1)
    
    -- Set attributes for the orb system
    orb:SetAttribute("OrbValue", value)
    orb:SetAttribute("IsDeathOrb", true)
    orb:SetAttribute("OrbType", "normal") -- Use "normal" so AI can eat them
    
    -- Add glow that scales with value
    local glow = Instance.new("PointLight")
    glow.Brightness = 2 + value * 0.1
    glow.Range = 10 + value * 0.5
    glow.Color = orb.Color
    glow.Parent = orb
    
    -- Parent to Orbs folder BEFORE adding attachments/particles
    orb.Parent = orbsFolder
    
    -- Rainbow effect - full spectrum like original
    task.spawn(function()
        local hue = hueStart
        while orb and orb.Parent do
            -- Full rainbow cycle
            hue = (hue + 0.01) % 1
            local color = Color3.fromHSV(hue, 1, 1)
            orb.Color = color
            if glow and glow.Parent then
                glow.Color = color
            end
            task.wait(0.05)
        end
    end)
    
    -- Smooth floating animation (like real orbs)
    task.spawn(function()
        local startY = position.Y
        local time = math.random() * math.pi * 2 -- Random start phase
        local rotSpeed = (math.random() * 2 - 1) * 2 -- Faster rotation
        local floatSpeed = math.random() * 0.5 + 1.5 -- Vary float speed
        
        while orb and orb.Parent do
            time = time + 0.03
            -- Gentle floating motion with varied height
            local floatOffset = math.sin(time * floatSpeed) * 0.8
            -- Slow rotation
            local rotation = time * rotSpeed
            
            orb.CFrame = CFrame.new(position.X, startY + floatOffset, position.Z) * CFrame.Angles(0, rotation, 0)
            
            task.wait()
        end
    end)
    
    -- Add particle effect AFTER parenting to avoid attachment warning
    local attachment = Instance.new("Attachment")
    attachment.Parent = orb
    
    local particle = Instance.new("ParticleEmitter")
    particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particle.Rate = 15 + value * 2 -- More particles for higher value orbs
    particle.Lifetime = NumberRange.new(0.5, 1)
    particle.SpreadAngle = Vector2.new(360, 360)
    particle.Speed = NumberRange.new(1, 2)
    particle.VelocityInheritance = 0
    particle.Color = ColorSequence.new(Color3.fromRGB(255, 200, 0))
    particle.Size = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3 * sizeMultiplier),
        NumberSequenceKeypoint.new(0.5, 0.2 * sizeMultiplier),
        NumberSequenceKeypoint.new(1, 0)
    }
    particle.Transparency = NumberSequence.new{
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    }
    particle.Parent = attachment
    
    -- Clean up after 90 seconds
    Debris:AddItem(orb, 90)
    
    -- Attach touch handler for collection (this was missing!)
    if OrbUtils.attachOrbTouched then
        OrbUtils.attachOrbTouched(orb)
    end
    
    return orb
end

function DyingState:_cleanupVisualEffects()
    local player = self.controller.player
    local character = player.Character
    
    -- Reset all effect-related attributes
    player:SetAttribute("MagnetRange", 0)
    player:SetAttribute("MagnetActive", false)
    player:SetAttribute("ActiveMagnet", false)
    player:SetAttribute("TempMagnetRange", 1)
    player:SetAttribute("SpawnGhostMode", false)
    
    -- Clean up any particle effects from GamepassHandler
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            -- Remove ghost effect light
            local ghostEffect = rootPart:FindFirstChild("GhostEffect")
            if ghostEffect then
                ghostEffect:Destroy()
            end
            
            -- Remove any attachments with particles (ghost mode particles)
            for _, child in ipairs(rootPart:GetChildren()) do
                if child:IsA("Attachment") then
                    child:Destroy()
                end
            end
        end
    end
    
    warn("[DyingState] Cleaned up visual effects for", player.Name)
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