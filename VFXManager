-- VFXManager: Handles visual effects for orbs with multiplayer-compatible graphics modes
-- POLISHED VERSION - Fixed collision interference and optimized for performance
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local VFXManager = {}

-- Create SetGraphicsMode RemoteEvent if it doesn't exist
local SetGraphicsModeEvent = ReplicatedStorage:FindFirstChild("SetGraphicsMode")
if not SetGraphicsModeEvent and RunService:IsServer() then
	SetGraphicsModeEvent = Instance.new("RemoteEvent")
	SetGraphicsModeEvent.Name = "SetGraphicsMode"
	SetGraphicsModeEvent.Parent = ReplicatedStorage
elseif not SetGraphicsModeEvent then
	-- Client: wait for it to be created
	SetGraphicsModeEvent = ReplicatedStorage:WaitForChild("SetGraphicsMode", 5)
end

-- Cache for effect templates to avoid recreating them
local effectTemplates = {}

-- Graphics mode configurations
local GRAPHICS_SETTINGS = {
	High = {
		orbGlow = true,
		orbParticles = true,
		particleCount = 20,
		lightingEnabled = true,
		glowBrightness = 2,
		glowRange = 8,
		enabled = true -- Master switch
	},
	Medium = {
		orbGlow = true,
		orbParticles = true,
		particleCount = 10,
		lightingEnabled = true,
		glowBrightness = 1.5,
		glowRange = 6,
		enabled = true
	},
	Low = {
		orbGlow = false,
		orbParticles = false,
		particleCount = 0,
		lightingEnabled = false,
		glowBrightness = 0,
		glowRange = 0,
		enabled = false -- Disable all effects in low mode
	}
}

-- Helper to get graphics mode for a player (defaults to "High")
local function getGraphicsModeForPlayer(player)
	if not player then 
		-- On server or no player specified, return High
		if RunService:IsServer() then
			return "High"
		end
		-- On client, use local player's mode
		player = Players.LocalPlayer
	end

	if player then
		-- Check if effects are disabled for death
		if player:GetAttribute("NoDeathEffects") or player:GetAttribute("DisableClientOrbs") then
			return "Low" -- Force low mode to disable effects
		end
		
		local mode = player:GetAttribute("GraphicsMode")
		if mode == "Low" or mode == "Medium" then
			return mode
		end
	end
	return "High"
end

-- Get graphics settings
function VFXManager.getGraphicsSettings(mode)
	return GRAPHICS_SETTINGS[mode] or GRAPHICS_SETTINGS.High
end

-- Creates a template for the orb collection particle effect
local function createOrbEffectTemplate(graphicsMode)
	local settings = GRAPHICS_SETTINGS[graphicsMode] or GRAPHICS_SETTINGS.High

	-- Check if effects are enabled
	if not settings.enabled or not settings.orbParticles then
		return nil
	end

	local key = "OrbCollect_" .. graphicsMode
	if effectTemplates[key] then
		return effectTemplates[key]:Clone()
	end

	local attachment = Instance.new("Attachment")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Parent = attachment

	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 170, 0))
	emitter.LightEmission = settings.lightingEnabled and 1 or 0.5

	if graphicsMode == "High" then
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 1.5),
			NumberSequenceKeypoint.new(1, 1)
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.5),
			NumberSequenceKeypoint.new(1, 1)
		})
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	else -- Medium
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0.8)
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1)
		})
		-- Simpler texture for medium
		emitter.Texture = ""
	end

	emitter.Speed = NumberRange.new(5, 10)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.ZOffset = 1

	effectTemplates[key] = attachment
	return attachment:Clone()
end

-- Plays the orb collection VFX at a given world position
function VFXManager.playOrbCollectVFX(position, player)
	-- Skip if position is invalid
	if not position or position.Magnitude > 10000 then
		return
	end
	
	-- SERVER: Create VFX marker with collision-safe properties
	if RunService:IsServer() then
		-- Check if player has death effects disabled
		if player and (player:GetAttribute("NoDeathEffects") or player:GetAttribute("DisableClientOrbs")) then
			return -- Don't create any VFX markers during death
		end
		
		-- Create a simple effect marker that clients can detect
		local part = Instance.new("Part")
		part.Name = "OrbVFXMarker"
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Position = position
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false -- IMPORTANT: Prevent touch detection
		part.CanQuery = false -- IMPORTANT: Prevent spatial queries
		part.Transparency = 1
		part.Parent = workspace.CurrentCamera or workspace -- Use CurrentCamera if available to reduce collision checks

		-- Add a value to indicate this is an orb collection
		local marker = Instance.new("StringValue")
		marker.Name = "VFXType"
		marker.Value = "OrbCollect"
		marker.Parent = part

		-- Clean up after a short time
		Debris:AddItem(part, 0.3) -- Reduced from 0.5
		return
	end

	-- CLIENT: Check if effects are enabled
	local localPlayer = Players.LocalPlayer
	if localPlayer and (localPlayer:GetAttribute("NoDeathEffects") or localPlayer:GetAttribute("DisableClientOrbs")) then
		return -- Skip all client effects during death
	end
	
	-- Check local graphics mode
	local graphicsMode = getGraphicsModeForPlayer(player or localPlayer)
	local settings = GRAPHICS_SETTINGS[graphicsMode]
	
	if not settings.enabled then
		return -- Effects disabled for this graphics mode
	end
	
	local effect = createOrbEffectTemplate(graphicsMode)
	if not effect then
		return -- No effect template available
	end

	-- Parent to a non-collision container if possible
	effect.Parent = workspace.CurrentCamera or workspace
	effect.WorldPosition = position

	local emitter = effect:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter:Emit(settings.particleCount)
	end

	-- Clean up the effect faster
	task.delay(0.5, function()
		if effect and effect.Parent then
			effect:Destroy()
		end
	end)
end

-- CLIENT ONLY: Watch for VFX markers from server (with optimization)
if RunService:IsClient() then
	-- Throttle VFX processing
	local lastVFXTime = 0
	local VFX_COOLDOWN = 0.05 -- Minimum time between VFX
	
	workspace.ChildAdded:Connect(function(child)
		-- Quick checks first
		if child.Name ~= "OrbVFXMarker" then return end
		
		local currentTime = tick()
		if currentTime - lastVFXTime < VFX_COOLDOWN then
			return -- Skip if too frequent
		end
		
		-- Check for death effects disabled
		local localPlayer = Players.LocalPlayer
		if localPlayer and (localPlayer:GetAttribute("NoDeathEffects") or localPlayer:GetAttribute("DisableClientOrbs")) then
			return
		end
		
		local vfxType = child:FindFirstChild("VFXType")
		if vfxType and vfxType.Value == "OrbCollect" then
			lastVFXTime = currentTime
			-- Play the VFX based on local graphics settings
			VFXManager.playOrbCollectVFX(child.Position, localPlayer)
		end
	end)
	
	-- Listen for DisableDeathEffects remote
	local disableEffectsRemote = ReplicatedStorage:WaitForChild("DisableDeathEffects", 5)
	if disableEffectsRemote then
		disableEffectsRemote.OnClientEvent:Connect(function()
			-- Clear any existing VFX markers
			for _, child in pairs(workspace:GetChildren()) do
				if child.Name == "OrbVFXMarker" then
					child:Destroy()
				end
			end
		end)
	end
end

-- Handle graphics mode changes
if SetGraphicsModeEvent then
	if RunService:IsServer() then
		-- SERVER: Update player's attribute when they change graphics mode
		SetGraphicsModeEvent.OnServerEvent:Connect(function(player, mode)
			if GRAPHICS_SETTINGS[mode] then
				player:SetAttribute("GraphicsMode", mode)
				print("[VFXManager] Set graphics mode for", player.Name, "to", mode)

				-- Force update the player's snake graphics if applicable
				if _G.PlayerSnakes and _G.PlayerSnakes[player] then
					local snake = _G.PlayerSnakes[player]
					if snake and snake.updateGraphicsMode then
						snake:updateGraphicsMode()
					end
				end
			end
		end)
	else
		-- CLIENT: Send graphics mode changes to server
		function VFXManager.setGraphicsMode(mode)
			if GRAPHICS_SETTINGS[mode] then
				SetGraphicsModeEvent:FireServer(mode)
			end
		end
	end
end

-- Cleanup function
function VFXManager.cleanup()
	-- Clear template cache
	for _, template in pairs(effectTemplates) do
		if template and template.Parent then
			template:Destroy()
		end
	end
	effectTemplates = {}
end

return VFXManager
