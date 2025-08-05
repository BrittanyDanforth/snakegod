-- VFXHandler_Client LocalScript
-- Place this in: StarterPlayer > StarterPlayerScripts
-- Handles client-side visual effects for revive and other events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Get VFXManager module
local VFXManager = require(ReplicatedStorage:WaitForChild("VFXManager"))

-- Get Death VFX Config
local DeathVFXConfig
pcall(function()
	DeathVFXConfig = require(ReplicatedStorage:WaitForChild("DeathVFXConfig", 5))
end)

-- Default config if not found
if not DeathVFXConfig then
	DeathVFXConfig = {
		DEATH_COLORS = {
			primary = Color3.fromRGB(147, 51, 255),    -- Purple
			secondary = Color3.fromRGB(0, 255, 127),   -- Green
			glow = Color3.fromRGB(255, 255, 255),      -- White
		},
		PARTICLES = {
			count = 30,
			lifetime = 1.5,
			speed = 50,
			spread = 360,
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.5, 1.5),
				NumberSequenceKeypoint.new(1, 0)
			}),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0.3),
				NumberSequenceKeypoint.new(1, 1)
			})
		}
	}
end

-- Wait for the Remotes folder and the specific event to exist
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveEffectRemote = remotes:WaitForChild("PlayerRevivedEffect")
local deathEffectRemote = remotes:WaitForChild("PlayerDeathEffect", 5)

-- Function to create death VFX using configurable colors
local function createDeathVFX(character)
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	
	local player = Players.LocalPlayer
	if player:GetAttribute("NoDeathEffects") then
		return
	end
	
	local position = character.HumanoidRootPart.Position
	local graphicsMode = player:GetAttribute("GraphicsMode") or "High"
	local settings = VFXManager.getGraphicsSettings(graphicsMode)
	
	if not settings.enabled then
		return
	end
	
	-- Create death particle burst
	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Parent = workspace.CurrentCamera or workspace
	
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DeathParticles"
	
	-- Use colors from config
	emitter.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, DeathVFXConfig.DEATH_COLORS.primary),
		ColorSequenceKeypoint.new(0.5, DeathVFXConfig.DEATH_COLORS.secondary),
		ColorSequenceKeypoint.new(1, DeathVFXConfig.DEATH_COLORS.glow)
	}
	
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = DeathVFXConfig.PARTICLES.size
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Transparency = DeathVFXConfig.PARTICLES.transparency
	emitter.Speed = NumberRange.new(DeathVFXConfig.PARTICLES.speed * 0.5, DeathVFXConfig.PARTICLES.speed)
	emitter.Lifetime = NumberRange.new(DeathVFXConfig.PARTICLES.lifetime * 0.8, DeathVFXConfig.PARTICLES.lifetime)
	emitter.Rate = 0
	emitter.SpreadAngle = Vector2.new(DeathVFXConfig.PARTICLES.spread, DeathVFXConfig.PARTICLES.spread)
	emitter.VelocityInheritance = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = attachment
	
	-- Emit burst based on graphics settings
	local particleCount = math.floor(DeathVFXConfig.PARTICLES.count * (settings.particleCount / 20))
	emitter:Emit(particleCount)
	
	-- Create expanding shockwave
	if settings.orbGlow then
		local shockwave = Instance.new("Part")
		shockwave.Name = "DeathShockwave"
		shockwave.Shape = Enum.PartType.Ball
		shockwave.Material = Enum.Material.ForceField
		shockwave.Size = Vector3.new(4, 4, 4)
		shockwave.Color = DeathVFXConfig.DEATH_COLORS.primary
		shockwave.Anchored = true
		shockwave.CanCollide = false
		shockwave.CanTouch = false
		shockwave.CanQuery = false
		shockwave.Position = position
		shockwave.Transparency = 0.3
		shockwave.Parent = workspace.CurrentCamera or workspace
		
		-- Animate shockwave
		local tween = TweenService:Create(shockwave, 
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = Vector3.new(30, 30, 30),
				Transparency = 1
			}
		)
		tween:Play()
		tween.Completed:Connect(function()
			shockwave:Destroy()
		end)
	end
	
	-- Clean up emitter
	task.delay(DeathVFXConfig.PARTICLES.lifetime + 0.5, function()
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end)
end

-- Function to create revival VFX using VFXManager's style
local function createReviveVFX()
    local player = Players.LocalPlayer
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    -- Check if effects are disabled
    if player:GetAttribute("NoDeathEffects") or player:GetAttribute("DisableClientOrbs") then
        return
    end
    
    -- Get graphics settings
    local graphicsMode = player:GetAttribute("GraphicsMode") or "High"
    local settings = VFXManager.getGraphicsSettings(graphicsMode)
    
    if not settings.enabled then
        return -- Effects disabled for this graphics mode
    end
    
    local position = character.HumanoidRootPart.Position
    
    -- Create revival effect based on graphics settings
    if settings.orbGlow or settings.lightingEnabled then
        -- Create a glowing orb effect
        local part = Instance.new("Part")
        part.Name = "ReviveEffect"
        part.Shape = Enum.PartType.Ball
        part.Material = Enum.Material.ForceField
        part.Size = Vector3.new(6, 6, 6)
        		part.Color = DeathVFXConfig.REVIVAL_COLORS.primary -- Use config color
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Position = position
        part.Transparency = 0.3
        part.Parent = workspace.CurrentCamera or workspace
        
        if settings.lightingEnabled then
            local light = Instance.new("PointLight")
            light.Brightness = settings.glowBrightness * 1.5
            light.Range = settings.glowRange * 2
            			light.Color = DeathVFXConfig.REVIVAL_COLORS.glow
            light.Parent = part
        end
        
        -- Animate expansion and fade
        local startTime = tick()
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local elapsed = tick() - startTime
            if elapsed > 1.5 then
                part:Destroy()
                connection:Disconnect()
                return
            end
            
            local scale = 1 + (elapsed * 2)
            part.Size = Vector3.new(6, 6, 6) * scale
            part.Transparency = 0.3 + (elapsed * 0.5)
        end)
    end
    
    -- Add particles if enabled
    if settings.orbParticles and settings.particleCount > 0 then
        local attachment = Instance.new("Attachment")
        attachment.Position = position
        attachment.Parent = workspace.CurrentCamera or workspace
        
        local emitter = Instance.new("ParticleEmitter")
        		emitter.Color = ColorSequence.new(DeathVFXConfig.REVIVAL_COLORS.primary, DeathVFXConfig.REVIVAL_COLORS.secondary)
        emitter.LightEmission = 1
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 2),
            NumberSequenceKeypoint.new(1, 0)
        })
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.8, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        })
        emitter.Speed = NumberRange.new(10, 20)
        emitter.Lifetime = NumberRange.new(0.5, 1)
        emitter.Rate = 0
        emitter.SpreadAngle = Vector2.new(360, 360)
        emitter.Parent = attachment
        
        -- Emit burst of particles
        emitter:Emit(settings.particleCount * 2)
        
        -- Clean up
        task.delay(2, function()
            if attachment and attachment.Parent then
                attachment:Destroy()
            end
        end)
    end
end

-- This LocalScript is on the client, so it can correctly listen for OnClientEvent
reviveEffectRemote.OnClientEvent:Connect(function()
    print("✅ VFXHandler_Client received the 'PlayerRevivedEffect' command from the server.")
    
    -- To keep the revival effect GONE, leave this commented out:
    -- createReviveVFX()
    
    -- Uncomment the line above if you want to enable revival VFX
    -- The VFX will respect the player's graphics settings automatically
end)

-- Listen for death effects
if deathEffectRemote then
	deathEffectRemote.OnClientEvent:Connect(function()
		local character = Players.LocalPlayer.Character
		if character then
			createDeathVFX(character)
		end
	end)
end

-- Also trigger death VFX when humanoid dies
local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		-- Only create VFX if not disabled
		if not Players.LocalPlayer:GetAttribute("NoDeathEffects") then
			createDeathVFX(character)
		end
	end)
end

local player = Players.LocalPlayer
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

print("VFXHandler_Client loaded - Death VFX colors are customizable in DeathVFXConfig")