--[[
	AGGRESSIVE SnakeCollisionHandler with Enhanced Direct Communication
	This version implements more aggressive cleanup and failsafe mechanisms
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ensure remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- Create all communication remotes
local playerRevivedEffectRemote = remotes:FindFirstChild("PlayerRevivedEffect")
if not playerRevivedEffectRemote then
	playerRevivedEffectRemote = Instance.new("RemoteEvent")
	playerRevivedEffectRemote.Name = "PlayerRevivedEffect"
	playerRevivedEffectRemote.Parent = remotes
end

local forceCleanupRemote = remotes:FindFirstChild("ForceCleanupEffects")
if not forceCleanupRemote then
	forceCleanupRemote = Instance.new("RemoteEvent")
	forceCleanupRemote.Name = "ForceCleanupEffects"
	forceCleanupRemote.Parent = remotes
end

local emergencyOrbRemovalRemote = remotes:FindFirstChild("EmergencyOrbRemoval")
if not emergencyOrbRemovalRemote then
	emergencyOrbRemovalRemote = Instance.new("RemoteEvent")
	emergencyOrbRemovalRemote.Name = "EmergencyOrbRemoval"
	emergencyOrbRemovalRemote.Parent = remotes
end

-- Aggressive cleanup configuration
local AGGRESSIVE_CLEANUP_PASSES = 15 -- Increased from 10
local CLEANUP_INTERVAL = 0.05 -- More frequent checks
local WORKSPACE_SCAN_RADIUS = 150 -- Larger scan area
local EFFECT_DESTRUCTION_DELAY = 0 -- Instant destruction

-- Track cleanup operations
local activeCleanups = {}
local globalCleanupActive = false

-- MASTER RESET FUNCTION - Nuclear option for state cleanup
local function resetPlayerCollisionState(player)
	if not player then return end
	
	-- Clear ALL attributes aggressively
	local attributesToClear = {
		"JustRevived", "RevivingNow", "RevivePosition", "DeathPosition",
		"NoReviveEffects", "AwaitingReviveResponse", "RevivePromptActive",
		"ReviveSnakeLength", "DeathTime", "IsProcessingDeath", "IsDead",
		"HasRevives", "ReviveCount", "LastDeathPosition", "LastReviveTime"
	}
	
	for _, attr in ipairs(attributesToClear) do
		pcall(function() player:SetAttribute(attr, nil) end)
	end
	
	-- Force cleanup on client
	forceCleanupRemote:FireClient(player)
	
	print(string.format("🔄 [AGGRESSIVE] Master reset completed for %s", player.Name))
end

-- AGGRESSIVE WORKSPACE CLEANUP
local function aggressiveWorkspaceCleanup(centerPosition, radius)
	radius = radius or WORKSPACE_SCAN_RADIUS
	
	-- Multiple scan methods for thorough coverage
	task.spawn(function()
		-- Method 1: GetPartBoundsInRadius
		local parts1 = workspace:GetPartBoundsInRadius(centerPosition, radius)
		
		-- Method 2: GetPartBoundsInBox
		local parts2 = workspace:GetPartBoundsInBox(
			CFrame.new(centerPosition),
			Vector3.new(radius * 2, radius * 2, radius * 2)
		)
		
		-- Combine results
		local allParts = {}
		local seen = {}
		
		for _, part in ipairs(parts1) do
			if not seen[part] then
				seen[part] = true
				table.insert(allParts, part)
			end
		end
		
		for _, part in ipairs(parts2) do
			if not seen[part] then
				seen[part] = true
				table.insert(allParts, part)
			end
		end
		
		-- Aggressive part destruction
		for _, part in ipairs(allParts) do
			local shouldDestroy = false
			
			-- Skip player models
			local humanoid = part:FindFirstAncestorOfClass("Model") and part:FindFirstAncestorOfClass("Model"):FindFirstChild("Humanoid")
			if humanoid then continue end
			
			-- Effect detection criteria
			if part:IsA("BasePart") then
				-- Size criteria - small objects
				if part.Size.Magnitude < 5 then
					shouldDestroy = true
				end
				
				-- Name criteria - aggressive pattern matching
				local lowName = part.Name:lower()
				local suspiciousNames = {
					"orb", "effect", "vfx", "particle", "revive", "spawn",
					"light", "glow", "aura", "magic", "power", "energy"
				}
				
				for _, pattern in ipairs(suspiciousNames) do
					if lowName:match(pattern) then
						shouldDestroy = true
						break
					end
				end
				
				-- Color criteria - grey/white effects
				local h, s, v = part.Color:ToHSV()
				if (s < 0.3 and v > 0.3) or (v > 0.9) then -- Grey or very bright
					if part.Size.Magnitude < 3 then
						shouldDestroy = true
					end
				end
				
				-- Material criteria
				local effectMaterials = {
					Enum.Material.Neon,
					Enum.Material.ForceField,
					Enum.Material.Glass
				}
				
				for _, mat in ipairs(effectMaterials) do
					if part.Material == mat then
						shouldDestroy = true
						break
					end
				end
				
				-- Transparency criteria
				if part.Transparency > 0.1 and part.Transparency < 0.95 then
					shouldDestroy = true
				end
				
				-- Default part detection
				if part.BrickColor == BrickColor.new("Medium stone grey") and part.Size.Magnitude < 2 then
					shouldDestroy = true
				end
			end
			
			-- Direct effect objects
			if part:IsA("ParticleEmitter") or part:IsA("PointLight") or part:IsA("SpotLight") or
			   part:IsA("ForceField") or part:IsA("Fire") or part:IsA("Smoke") or part:IsA("Sparkles") then
				shouldDestroy = true
			end
			
			-- Billboard/Surface GUIs with effect names
			if (part:IsA("BillboardGui") or part:IsA("SurfaceGui")) then
				local lowName = part.Name:lower()
				if lowName:match("effect") or lowName:match("vfx") then
					shouldDestroy = true
				end
			end
			
			if shouldDestroy then
				pcall(function() part:Destroy() end)
			end
		end
	end)
end

-- ENHANCED DEATH PROCESSING
local function queuePlayerDeath(player, deathPosition)
	-- Immediate aggressive cleanup
	emergencyOrbRemovalRemote:FireClient(player)
	
	-- Multiple cleanup waves
	task.spawn(function()
		for wave = 1, 5 do
			task.wait(0.1 * wave)
			
			-- Workspace cleanup around death position
			aggressiveWorkspaceCleanup(deathPosition, 100 + (wave * 20))
			
			-- Character cleanup
			if player.Character then
				-- Destroy all effects on character
				for _, desc in ipairs(player.Character:GetDescendants()) do
					if desc:IsA("PointLight") or desc:IsA("ParticleEmitter") or 
					   desc:IsA("ForceField") or desc:IsA("Fire") or desc:IsA("Smoke") or
					   desc:IsA("Sparkles") or desc:IsA("SelectionBox") then
						pcall(function() desc:Destroy() end)
					end
				end
			end
		end
	end)
	
	-- Continue with normal death processing...
	-- [Insert your existing death processing logic here]
end

-- ENHANCED REVIVE HANDLING
local function handlePlayerRevive(player, deathPosition, snakeLength)
	-- Pre-revive cleanup
	resetPlayerCollisionState(player)
	aggressiveWorkspaceCleanup(deathPosition, 200)
	
	-- CRITICAL: Fire the direct communication BEFORE LoadCharacter
	-- This ensures the client is ready to suppress any effects
	playerRevivedEffectRemote:FireClient(player)
	
	-- Small delay to ensure client receives the message
	task.wait(0.1)
	
	-- Now safe to load character
	player:LoadCharacter()
	
	-- Post-revive aggressive cleanup
	task.spawn(function()
		-- Multiple cleanup passes after respawn
		for i = 1, AGGRESSIVE_CLEANUP_PASSES do
			task.wait(CLEANUP_INTERVAL)
			
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				local rootPos = player.Character.HumanoidRootPart.Position
				
				-- Cleanup around spawn position
				aggressiveWorkspaceCleanup(rootPos, 50 + (i * 5))
				
				-- Force client cleanup
				if i % 3 == 0 then
					forceCleanupRemote:FireClient(player)
				end
			end
		end
	end)
	
	print(string.format("✅ [AGGRESSIVE] Revive completed for %s with maximum cleanup", player.Name))
end

-- CONTINUOUS MONITORING SYSTEM
local monitoredPlayers = {}

local function startPlayerMonitoring(player)
	if monitoredPlayers[player] then return end
	
	monitoredPlayers[player] = true
	
	task.spawn(function()
		while monitoredPlayers[player] and player.Parent do
			task.wait(1)
			
			if player.Character then
				local foundSuspiciousEffect = false
				
				-- Check for any effects that shouldn't exist
				for _, child in ipairs(player.Character:GetDescendants()) do
					if child:IsA("PointLight") or child:IsA("ParticleEmitter") or child:IsA("ForceField") then
						foundSuspiciousEffect = true
						pcall(function() child:Destroy() end)
					end
				end
				
				-- Check workspace around player
				local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local nearbyParts = workspace:GetPartBoundsInRadius(rootPart.Position, 20)
					
					for _, part in ipairs(nearbyParts) do
						if part.Parent ~= player.Character then
							local lowName = part.Name:lower()
							if lowName:match("orb") or lowName:match("effect") then
								foundSuspiciousEffect = true
								pcall(function() part:Destroy() end)
							end
						end
					end
				end
				
				if foundSuspiciousEffect then
					print(string.format("⚠️ [AGGRESSIVE] Suspicious effects detected on %s - emergency cleanup!", player.Name))
					emergencyOrbRemovalRemote:FireClient(player)
					aggressiveWorkspaceCleanup(rootPart.Position, 100)
				end
			end
		end
		
		monitoredPlayers[player] = nil
	end)
end

-- PLAYER LIFECYCLE HOOKS
Players.PlayerAdded:Connect(function(player)
	-- Start monitoring immediately
	startPlayerMonitoring(player)
	
	-- Clean any pre-existing attributes
	resetPlayerCollisionState(player)
	
	player.CharacterAdded:Connect(function(character)
		-- Preventive cleanup on spawn
		task.wait(0.1)
		forceCleanupRemote:FireClient(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	monitoredPlayers[player] = nil
	
	-- Final cleanup
	if player.Character then
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			aggressiveWorkspaceCleanup(rootPart.Position, 200)
		end
	end
end)

-- GLOBAL CLEANUP COMMAND (for debugging)
local function performGlobalCleanup()
	print("🌍 [AGGRESSIVE] Performing global cleanup...")
	
	-- Clean entire workspace of suspicious objects
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local lowName = obj.Name:lower()
			if lowName:match("orb") or lowName:match("effect") or lowName:match("vfx") then
				local humanoid = obj:FindFirstAncestorOfClass("Model") and obj:FindFirstAncestorOfClass("Model"):FindFirstChild("Humanoid")
				if not humanoid then
					pcall(function() obj:Destroy() end)
				end
			end
		elseif obj:IsA("ParticleEmitter") or obj:IsA("PointLight") or obj:IsA("ForceField") then
			local humanoid = obj:FindFirstAncestorOfClass("Model") and obj:FindFirstAncestorOfClass("Model"):FindFirstChild("Humanoid")
			if not humanoid then
				pcall(function() obj:Destroy() end)
			end
		end
	end
	
	-- Force cleanup on all players
	for _, player in ipairs(Players:GetPlayers()) do
		forceCleanupRemote:FireClient(player)
	end
end

-- Run global cleanup periodically
task.spawn(function()
	while true do
		task.wait(30) -- Every 30 seconds
		performGlobalCleanup()
	end
end)

print("✅ [AGGRESSIVE] SnakeCollisionHandler loaded with maximum aggression and direct communication!")