-- SnakeCollisionHandler V8.2 SIMPLE FIX
-- Just fixing the death orbs and ReviveUI issues

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get your existing modules
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Get remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local promptReviveRemote = remotes:FindFirstChild("PromptRevive") or Instance.new("RemoteEvent", remotes)
promptReviveRemote.Name = "PromptRevive"

-- FIX 1: Make sure ReviveResponse remote exists
local reviveResponseRemote = remotes:FindFirstChild("ReviveResponse") or Instance.new("RemoteEvent", remotes)
reviveResponseRemote.Name = "ReviveResponse"

-- Your existing death processing function - FIXED
local function processPlayerDeath(player)
	local character = player.Character
	if not character then return end
	
	print("💀 Processing death for", player.Name)
	
	-- FIX 2: Get segments BEFORE destroying anything
	local segmentPositions = {}
	local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
	
	if snakeModel then
		-- Store all segment positions first
		for i = 0, 500 do
			local segmentName = i == 0 and "Segment0_Head" or ("Segment" .. i)
			local segment = snakeModel:FindFirstChild(segmentName)
			if segment and segment:IsA("BasePart") then
				segmentPositions[#segmentPositions + 1] = segment.Position
			else
				break
			end
		end
	end
	
	-- Get snake length
	local snakeLength = 10
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local lengthValue = leaderstats:FindFirstChild("Length")
		if lengthValue then
			snakeLength = lengthValue.Value
		end
	end
	
	print("📊 Snake length:", snakeLength, "Segments found:", #segmentPositions)
	
	-- FIX 3: Spawn orbs with the positions we saved
	task.spawn(function()
		-- Calculate orbs
		local totalOrbs = math.min(math.floor(snakeLength * 0.4), 50)
		local orbValue = math.max(1, math.floor(snakeLength * 0.3 / totalOrbs))
		
		print("💎 Spawning", totalOrbs, "orbs with value", orbValue)
		
		local spawnedOrbs = 0
		
		-- Spawn along segments
		if #segmentPositions > 0 then
			local skipInterval = math.max(1, math.floor(#segmentPositions / totalOrbs))
			
			for i = 1, #segmentPositions, skipInterval do
				if spawnedOrbs >= totalOrbs then break end
				
				local pos = segmentPositions[i]
				local orbPos = Vector3.new(
					pos.X + math.random(-5, 5),
					5, -- Orb height
					pos.Z + math.random(-5, 5)
				)
				
				-- Spawn orb
				local success, orb = pcall(function()
					return OrbUtils.spawnOrbAt(orbPos, orbValue)
				end)
				
				if success and orb then
					spawnedOrbs = spawnedOrbs + 1
				end
			end
		end
		
		-- Ensure minimum orbs
		if spawnedOrbs < 3 then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				for i = 1, 3 - spawnedOrbs do
					local angle = i * 120 * math.pi / 180
					local orbPos = Vector3.new(
						rootPart.Position.X + math.cos(angle) * 10,
						5,
						rootPart.Position.Z + math.sin(angle) * 10
					)
					
					pcall(function()
						OrbUtils.spawnOrbAt(orbPos, orbValue)
					end)
				end
			end
		end
		
		print("✅ Spawned orbs for", player.Name)
	end)
	
	-- FIX 4: Check and show ReviveUI properly
	local hasRevive = player:GetAttribute("HasRevive") or (player:GetAttribute("RevivesAvailable") or 0) > 0
	
	if hasRevive then
		print("🔄 Player has revive, showing UI")
		
		-- Send the prompt
		promptReviveRemote:FireClient(player)
		
		-- Listen for response
		local responseConnection
		local responded = false
		
		responseConnection = reviveResponseRemote.OnServerEvent:Connect(function(respondingPlayer, response)
			if respondingPlayer == player and not responded then
				responded = true
				responseConnection:Disconnect()
				
				print("📨 Revive response:", response)
				
				if response == "revive" or response == true then
					-- Revive the player
					print("✨ Reviving player")
					
					-- Deduct revive
					local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
					if revivesAvailable > 0 then
						player:SetAttribute("RevivesAvailable", revivesAvailable - 1)
					end
					
					-- Respawn
					player:LoadCharacter()
				else
					-- Player declined
					print("❌ Player declined revive")
				end
			end
		end)
		
		-- Timeout after 60 seconds
		task.wait(60)
		if not responded and responseConnection then
			responseConnection:Disconnect()
			print("⏰ Revive timed out")
		end
	else
		print("❌ No revive available")
	end
	
	-- Clean up snake model after everything
	if snakeModel then
		snakeModel:Destroy()
	end
end

-- Example of how to call this when a player dies
-- Replace this with your existing death trigger
local function onPlayerDied(player)
	processPlayerDeath(player)
end

-- Simple test command (remove in production)
game.Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		if msg == "/testdeath" then
			onPlayerDied(player)
		end
	end)
end)

print("✅ SnakeCollisionHandler V8.2 SIMPLE FIX loaded")
print("🔧 Fixed: Death orbs now spawn properly")
print("🔧 Fixed: ReviveUI now shows up")
print("💡 Test with /testdeath command")