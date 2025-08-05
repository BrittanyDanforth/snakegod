--[[
	AGGRESSIVE GamepassHandler with Direct Communication (FIXED)
	This version removes Neon material check since those are death orbs
	Focuses on grey revive orbs specifically
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Wait for all required remotes
local playerRevivedEffectRemote = remotes:WaitForChild("PlayerRevivedEffect")
local forceCleanupRemote = remotes:WaitForChild("ForceCleanupEffects", 5) -- Optional
local emergencyOrbRemovalRemote = remotes:WaitForChild("EmergencyOrbRemoval", 5) -- Optional

-- Aggressive cleanup configuration
local CLEANUP_RADIUS = 100 -- Expanded from typical 30-50
local CLEANUP_INTERVAL = 0.05 -- Check every 3 frames (assuming 60fps)
local AGGRESSIVE_CLEANUP_DURATION = 5 -- Continue cleanup for 5 seconds after any event

-- Track active cleanup sessions
local activeCleanupEndTime = 0
local isCleaningUp = false

-- Master cleanup function - EXTREMELY AGGRESSIVE
local function aggressiveCleanupEffects(duration)
	duration = duration or AGGRESSIVE_CLEANUP_DURATION
	activeCleanupEndTime = tick() + duration
	
	if not isCleaningUp then
		isCleaningUp = true
		
		task.spawn(function()
			while tick() < activeCleanupEndTime do
				-- Multiple cleanup passes per frame
				for pass = 1, 3 do
					if player.Character then
						-- 1. Clean character attachments
						for _, part in ipairs(player.Character:GetDescendants()) do
							if part:IsA("PointLight") or part:IsA("SpotLight") or part:IsA("SurfaceLight") then
								part:Destroy()
							elseif part:IsA("ParticleEmitter") or part:IsA("Sparkles") or part:IsA("Fire") or part:IsA("Smoke") then
								part:Destroy()
							elseif part:IsA("ForceField") then
								part:Destroy()
							elseif part:IsA("SelectionBox") or part:IsA("SelectionSphere") then
								part:Destroy()
							elseif part:IsA("BillboardGui") or part:IsA("SurfaceGui") then
								if part.Name:lower():match("effect") or part.Name:lower():match("vfx") then
									part:Destroy()
								end
							end
						end
						
						-- 2. Clean workspace around character
						local rootPart = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("Torso")
						if rootPart then
							-- Use GetPartBoundsInRadius for sphere search
							local parts = workspace:GetPartBoundsInRadius(rootPart.Position, CLEANUP_RADIUS)
							
							for _, part in ipairs(parts) do
								-- Skip player's own parts
								if part.Parent == player.Character then continue end
								
								-- Aggressive orb detection (NO NEON CHECK)
								if part:IsA("BasePart") then
									local isOrb = false
									
									-- Size check - small parts
									if part.Size.Magnitude < 3 then
										isOrb = true
									end
									
									-- Color check - grey orbs specifically
									local h, s, v = part.Color:ToHSV()
									if s < 0.3 and v > 0.2 and v < 0.9 then
										isOrb = true
									end
									
									-- Specific grey color checks
									if part.BrickColor == BrickColor.new("Medium stone grey") or
									   part.BrickColor == BrickColor.new("Dark stone grey") or
									   part.BrickColor == BrickColor.new("Light stone grey") then
										isOrb = true
									end
									
									-- Name check
									local lowName = part.Name:lower()
									if lowName:match("orb") or lowName:match("effect") or lowName:match("vfx") or 
									   lowName:match("particle") or lowName:match("revive") then
										isOrb = true
									end
									
									-- Material check - ForceField only (NOT Neon - that's for death orbs)
									if part.Material == Enum.Material.ForceField then
										isOrb = true
									end
									
									-- Transparency check - semi-transparent effects
									if part.Transparency > 0.2 and part.Transparency < 0.9 then
										isOrb = true
									end
									
									-- Default Part detection (common for revive orbs)
									if part.Name == "Part" and part.Size.Magnitude < 2 then
										isOrb = true
									end
									
									if isOrb then
										part:Destroy()
									end
								end
								
								-- Clean any effect objects
								if part:IsA("ParticleEmitter") or part:IsA("PointLight") or part:IsA("ForceField") then
									part:Destroy()
								end
							end
						end
					end
					
					-- Small yield between passes
					task.wait()
				end
				
				task.wait(CLEANUP_INTERVAL)
			end
			
			isCleaningUp = false
		end)
	end
end

-- CRITICAL FIX: Use OnClientEvent for client-side listening
playerRevivedEffectRemote.OnClientEvent:Connect(function()
	print("✅ [AGGRESSIVE] GamepassHandler received PlayerRevivedEffect signal")
	
	-- Immediately start aggressive cleanup
	aggressiveCleanupEffects(10) -- Extra long cleanup for revive events
	
	-- Schedule multiple cleanup waves
	for i = 1, 5 do
		task.wait(0.5 * i)
		aggressiveCleanupEffects(3)
	end
	
	-- NO EFFECT CREATION - We're keeping the orb permanently disabled
	-- If you ever want effects back, add them here with careful timing
end)

-- Listen for force cleanup commands (if implemented)
if forceCleanupRemote then
	forceCleanupRemote.OnClientEvent:Connect(function()
		print("🧹 [AGGRESSIVE] Force cleanup requested")
		aggressiveCleanupEffects(5)
	end)
end

-- Listen for emergency orb removal (if implemented)
if emergencyOrbRemovalRemote then
	emergencyOrbRemovalRemote.OnClientEvent:Connect(function()
		print("🚨 [AGGRESSIVE] Emergency orb removal activated")
		aggressiveCleanupEffects(10)
	end)
end

-- Continuous monitoring for any effects that slip through
local lastCleanupCheck = 0
RunService.Heartbeat:Connect(function()
	if tick() - lastCleanupCheck > 1 then -- Check every second
		lastCleanupCheck = tick()
		
		if player.Character then
			-- Quick scan for forbidden effects
			local foundEffect = false
			
			for _, child in ipairs(player.Character:GetDescendants()) do
				if child:IsA("PointLight") or child:IsA("ParticleEmitter") or child:IsA("ForceField") then
					foundEffect = true
					child:Destroy()
				end
			end
			
			if foundEffect then
				print("⚠️ [AGGRESSIVE] Detected unwanted effect - initiating cleanup")
				aggressiveCleanupEffects(3)
			end
		end
	end
end)

-- Character spawn cleanup
player.CharacterAdded:Connect(function(character)
	-- Wait a frame to ensure character is loaded
	task.wait()
	
	-- Immediate preventive cleanup
	aggressiveCleanupEffects(2)
	
	-- Remove the JustRevived attribute check entirely
	-- We now rely solely on direct RemoteEvent communication
	
	print("🎮 [AGGRESSIVE] Character spawned - preventive cleanup active")
end)

-- Aggressive attribute cleanup
local function cleanupAttributes()
	local attributesToClear = {
		"JustRevived",
		"RevivingNow",
		"RevivePosition",
		"DeathPosition",
		"NoReviveEffects",
		"AwaitingReviveResponse",
		"RevivePromptActive"
	}
	
	for _, attr in ipairs(attributesToClear) do
		if player:GetAttribute(attr) ~= nil then
			player:SetAttribute(attr, nil)
		end
	end
end

-- Clean attributes periodically
task.spawn(function()
	while true do
		task.wait(2)
		cleanupAttributes()
	end
end)

print("✅ [AGGRESSIVE] GamepassHandler loaded with maximum cleanup aggression!")