-- SnakeCollisionHandler V10 MODERN - Complete 2025 Architecture Rewrite
-- Built according to modern Roblox development principles:
-- ✅ Secure client-server architecture with validation
-- ✅ Modern Luau APIs (task, os.clock, etc.)
-- ✅ Trove pattern for memory management
-- ✅ Spatial queries instead of .Touched
-- ✅ Proper state management and cleanup
-- ✅ Fixed death orbs and ReviveUI issues

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Modern Module Dependencies
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove")) -- Assuming you have Trove installed
local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- === MODERN CONSTANTS ===
local COLLISION_CHECK_RATE = 20 -- Hz (20 checks per second)
local COLLISION_CHECK_INTERVAL = 1 / COLLISION_CHECK_RATE
local HEAD_COLLISION_SIZE = Vector3.new(4, 4, 4)
local BODY_COLLISION_SIZE = Vector3.new(3, 3, 3)
local SPATIAL_QUERY_RANGE = 100 -- Only check nearby objects
local MAX_DEATH_ORBS = 50
local ORB_SPAWN_HEIGHT = 5
local INVINCIBILITY_DURATION = 5
local REVIVE_TIMEOUT = 60

-- === MODERN REMOTE EVENTS ===
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	CollisionDetected = remoteFolder:FindFirstChild("CollisionDetected") or Instance.new("RemoteEvent", remoteFolder),
	PlayerDied = remoteFolder:FindFirstChild("PlayerDied") or Instance.new("RemoteEvent", remoteFolder),
	PromptRevive = remoteFolder:FindFirstChild("PromptRevive") or Instance.new("RemoteEvent", remoteFolder),
	ReviveResponse = remoteFolder:FindFirstChild("ReviveResponse") or Instance.new("RemoteEvent", remoteFolder),
	DeathEffects = remoteFolder:FindFirstChild("DeathEffects") or Instance.new("RemoteEvent", remoteFolder),
}

-- Name the remotes
remotes.CollisionDetected.Name = "CollisionDetected"
remotes.PlayerDied.Name = "PlayerDied"
remotes.PromptRevive.Name = "PromptRevive"
remotes.ReviveResponse.Name = "ReviveResponse"
remotes.DeathEffects.Name = "DeathEffects"

-- === MODULE DEFINITION ===
local SnakeCollisionHandler = {}
SnakeCollisionHandler.__index = SnakeCollisionHandler

-- === CONSTRUCTOR ===
function SnakeCollisionHandler.new()
	local self = setmetatable({}, SnakeCollisionHandler)
	
	-- State Management
	self.activeSnakes = {} -- [Player] = SnakeData
	self.snakeTroves = {} -- [Player] = Trove
	self.deadPlayers = {} -- [Player] = true
	self.invinciblePlayers = {} -- [Player] = expiryTime
	self.processingDeaths = {} -- [Player] = true (prevents double death processing)
	self.reviveSessions = {} -- [Player] = {connection, startTime}
	
	-- Performance tracking
	self.lastCollisionCheck = os.clock()
	self.collisionCheckConnection = nil
	
	-- Initialize
	self:setupRemoteListeners()
	self:startCollisionLoop()
	self:setupPlayerHandlers()
	
	print("✅ SnakeCollisionHandler V10 MODERN initialized")
	print("🔧 Using spatial queries, Trove pattern, and modern APIs")
	
	return self
end

-- === PLAYER LIFECYCLE ===
function SnakeCollisionHandler:setupPlayerHandlers()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:onPlayerSpawn(player, character)
		end)
		
		player.CharacterRemoving:Connect(function()
			self:cleanupPlayer(player)
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:cleanupPlayer(player)
	end)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:onPlayerSpawn(player, player.Character)
		end
	end
end

-- === PLAYER SPAWN HANDLING ===
function SnakeCollisionHandler:onPlayerSpawn(player, character)
	-- Clean any previous state
	self:cleanupPlayer(player)
	
	-- Create new snake data with Trove
	local trove = Trove.new()
	self.snakeTroves[player] = trove
	
	-- Initialize snake data
	self.activeSnakes[player] = {
		player = player,
		character = character,
		rootPart = character:WaitForChild("HumanoidRootPart"),
		segments = {},
		length = 10,
		alive = true,
		lastUpdate = os.clock()
	}
	
	-- Reset states
	self.deadPlayers[player] = nil
	self.processingDeaths[player] = nil
	
	-- Grant spawn invincibility
	self:setInvincible(player, INVINCIBILITY_DURATION)
	
	-- Add cleanup to trove
	trove:Add(function()
		self.activeSnakes[player] = nil
		self.deadPlayers[player] = nil
		self.invinciblePlayers[player] = nil
		self.processingDeaths[player] = nil
	end)
	
	print(string.format("🐍 Snake spawned for %s with invincibility", player.Name))
end

-- === MODERN COLLISION DETECTION ===
function SnakeCollisionHandler:startCollisionLoop()
	self.collisionCheckConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - self.lastCollisionCheck < COLLISION_CHECK_INTERVAL then
			return
		end
		self.lastCollisionCheck = now
		
		self:performCollisionChecks()
	end)
end

function SnakeCollisionHandler:performCollisionChecks()
	local allHeads = self:getAllSnakeHeads()
	
	-- Use OverlapParams for efficient filtering
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Whitelist
	overlapParams.MaxParts = 50
	
	for _, headData in ipairs(allHeads) do
		if headData.alive and not self:isInvincible(headData.player) then
			self:checkHeadCollisions(headData, allHeads, overlapParams)
		end
	end
end

function SnakeCollisionHandler:getAllSnakeHeads()
	local heads = {}
	
	-- Get player snake heads
	for player, snakeData in pairs(self.activeSnakes) do
		if snakeData.alive and snakeData.rootPart and snakeData.rootPart.Parent then
			-- Try to find the actual snake head first
			local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
			local headPart = snakeModel and snakeModel:FindFirstChild("Segment0_Head")
			
			table.insert(heads, {
				type = "player",
				player = player,
				part = headPart or snakeData.rootPart,
				position = (headPart or snakeData.rootPart).Position,
				alive = true,
				snakeData = snakeData
			})
		end
	end
	
	-- Get AI snake heads
	if AISnakeModule._activeSnakes then
		for _, aiSnake in pairs(AISnakeModule._activeSnakes) do
			if aiSnake.HeadParts and aiSnake.HeadParts.head and aiSnake.HeadParts.head.Parent then
				table.insert(heads, {
					type = "ai",
					part = aiSnake.HeadParts.head,
					position = aiSnake.HeadParts.head.Position,
					alive = true,
					aiSnake = aiSnake
				})
			end
		end
	end
	
	return heads
end

function SnakeCollisionHandler:checkHeadCollisions(headData, allHeads, overlapParams)
	local headPos = headData.position
	local headPart = headData.part
	
	-- Create spatial query box at head position
	local region = Region3.new(
		headPos - HEAD_COLLISION_SIZE/2,
		headPos + HEAD_COLLISION_SIZE/2
	)
	region = region:ExpandToGrid(4)
	
	-- Modern spatial query
	local partsInRegion = workspace:GetPartBoundsInBox(
		CFrame.new(headPos),
		HEAD_COLLISION_SIZE,
		overlapParams
	)
	
	-- Check collisions with other snake bodies
	for _, part in ipairs(partsInRegion) do
		-- Skip self
		if part == headPart then continue end
		
		-- Check if it's a snake segment
		if CollectionService:HasTag(part, "SnakeSegment") then
			local ownerName = part:GetAttribute("OwnerName")
			local segmentIndex = part:GetAttribute("SegmentIndex") or 999
			
			-- Skip first few segments of own snake (self-collision prevention)
			if headData.type == "player" and ownerName == headData.player.Name and segmentIndex <= 10 then
				continue
			end
			
			-- Valid collision detected
			self:handleCollision(headData, part, ownerName)
			return -- Only process first collision
		end
	end
	
	-- Check head-to-head collisions
	for _, otherHead in ipairs(allHeads) do
		if otherHead ~= headData and otherHead.alive then
			local distance = (headPos - otherHead.position).Magnitude
			
			if distance < HEAD_COLLISION_SIZE.X then
				self:handleHeadToHeadCollision(headData, otherHead)
				return
			end
		end
	end
end

-- === COLLISION HANDLING ===
function SnakeCollisionHandler:handleCollision(attackerData, victimPart, victimOwnerName)
	print(string.format("💥 Collision: %s hit %s's body", 
		attackerData.player and attackerData.player.Name or "AI", 
		victimOwnerName or "Unknown"))
	
	-- Kill the attacker (hit body = death)
	if attackerData.type == "player" then
		self:killPlayer(attackerData.player, "body_collision")
	elseif attackerData.type == "ai" then
		self:killAISnake(attackerData.aiSnake)
	end
end

function SnakeCollisionHandler:handleHeadToHeadCollision(head1, head2)
	-- Calculate velocities to determine winner
	local vel1 = head1.part.AssemblyLinearVelocity or Vector3.zero
	local vel2 = head2.part.AssemblyLinearVelocity or Vector3.zero
	
	local dir1to2 = (head2.position - head1.position).Unit
	local dir2to1 = -dir1to2
	
	local dot1 = vel1:Dot(dir1to2)
	local dot2 = vel2:Dot(dir2to1)
	
	print(string.format("🎯 Head collision: %s vs %s (dots: %.2f vs %.2f)",
		head1.player and head1.player.Name or "AI",
		head2.player and head2.player.Name or "AI",
		dot1, dot2))
	
	-- Determine outcome
	if dot1 > 2 and dot2 <= 2 then
		-- Head1 wins
		if head2.type == "player" then
			self:killPlayer(head2.player, "head_collision")
		else
			self:killAISnake(head2.aiSnake)
		end
	elseif dot2 > 2 and dot1 <= 2 then
		-- Head2 wins
		if head1.type == "player" then
			self:killPlayer(head1.player, "head_collision")
		else
			self:killAISnake(head1.aiSnake)
		end
	elseif dot1 > 2 and dot2 > 2 then
		-- Both die
		if head1.type == "player" then
			self:killPlayer(head1.player, "mutual_collision")
		else
			self:killAISnake(head1.aiSnake)
		end
		
		if head2.type == "player" then
			self:killPlayer(head2.player, "mutual_collision")
		else
			self:killAISnake(head2.aiSnake)
		end
	end
end

-- === MODERN DEATH SYSTEM ===
function SnakeCollisionHandler:killPlayer(player, reason)
	-- Prevent double death processing
	if self.deadPlayers[player] or self.processingDeaths[player] then
		return
	end
	
	local snakeData = self.activeSnakes[player]
	if not snakeData or not snakeData.alive then
		return
	end
	
	print(string.format("💀 Processing death for %s (reason: %s)", player.Name, reason))
	
	-- Mark as processing
	self.processingDeaths[player] = true
	snakeData.alive = false
	
	-- Notify clients for cosmetic effects
	remotes.DeathEffects:FireAllClients(player, snakeData.rootPart.Position, reason)
	
	-- Get snake segments before cleanup
	local segments = self:getPlayerSegments(player)
	local snakeLength = self:getPlayerLength(player)
	
	-- Process death in next frame to ensure segments are captured
	task.defer(function()
		-- Spawn death orbs
		self:spawnDeathOrbs(player, segments, snakeLength)
		
		-- Check for revive
		local hasRevive = player:GetAttribute("HasRevive") or (player:GetAttribute("RevivesAvailable") or 0) > 0
		
		if hasRevive then
			self:promptRevive(player)
		else
			-- No revive - proceed with cleanup
			self:finalizePlayerDeath(player)
		end
	end)
end

-- === GET PLAYER SEGMENTS ===
function SnakeCollisionHandler:getPlayerSegments(player)
	local segments = {}
	
	-- Try to get segments from visual model
	local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if snakeModel then
		for i = 0, 500 do -- Max segments
			local segmentName = i == 0 and "Segment0_Head" or ("Segment" .. i)
			local segment = snakeModel:FindFirstChild(segmentName)
			if segment and segment:IsA("BasePart") then
				table.insert(segments, {
					part = segment,
					position = segment.Position,
					index = i
				})
			else
				break -- No more segments
			end
		end
	end
	
	-- Fallback to stored data
	if #segments == 0 and self.activeSnakes[player] then
		local rootPos = self.activeSnakes[player].rootPart.Position
		-- Create fake segments based on length
		local length = self:getPlayerLength(player)
		for i = 1, math.min(length / 2, 50) do
			table.insert(segments, {
				position = rootPos + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)),
				index = i
			})
		end
	end
	
	return segments
end

-- === GET PLAYER LENGTH ===
function SnakeCollisionHandler:getPlayerLength(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local lengthValue = leaderstats:FindFirstChild("Length")
		if lengthValue then
			return lengthValue.Value
		end
	end
	
	-- Fallback
	return self.activeSnakes[player] and self.activeSnakes[player].length or 10
end

-- === SPAWN DEATH ORBS (FIXED) ===
function SnakeCollisionHandler:spawnDeathOrbs(player, segments, snakeLength)
	print(string.format("💎 Spawning death orbs for %s (length: %d, segments: %d)", 
		player.Name, snakeLength, #segments))
	
	-- Calculate orb distribution
	local totalOrbs = math.clamp(math.floor(snakeLength * 0.4), 3, MAX_DEATH_ORBS)
	local orbValue = math.max(1, math.floor(snakeLength * 0.3 / totalOrbs))
	
	local spawnedOrbs = 0
	local orbPositions = {}
	
	-- Distribute orbs along snake body
	if #segments > 0 then
		local skipInterval = math.max(1, math.floor(#segments / totalOrbs))
		
		for i = 1, #segments, skipInterval do
			if spawnedOrbs >= totalOrbs then break end
			
			local segment = segments[i]
			local basePos = segment.position or (segment.part and segment.part.Position)
			
			if basePos then
				-- Add randomization for spread
				local spread = math.min(snakeLength / 50, 10)
				local offset = Vector3.new(
					math.random() * spread * 2 - spread,
					0,
					math.random() * spread * 2 - spread
				)
				
				local orbPos = Vector3.new(
					basePos.X + offset.X,
					ORB_SPAWN_HEIGHT,
					basePos.Z + offset.Z
				)
				
				-- Spawn orb
				local success, result = pcall(function()
					return OrbUtils.spawnOrbAt(orbPos, orbValue)
				end)
				
				if success and result then
					result.Name = "DeathOrb_" .. player.Name
					spawnedOrbs = spawnedOrbs + 1
					table.insert(orbPositions, orbPos)
				else
					warn("Failed to spawn orb:", result)
				end
			end
		end
	end
	
	-- Ensure minimum orbs spawn
	if spawnedOrbs < 3 and self.activeSnakes[player] then
		local rootPos = self.activeSnakes[player].rootPart.Position
		local remainingOrbs = 3 - spawnedOrbs
		
		for i = 1, remainingOrbs do
			local angle = (i - 1) * (2 * math.pi / remainingOrbs)
			local orbPos = Vector3.new(
				rootPos.X + math.cos(angle) * 10,
				ORB_SPAWN_HEIGHT,
				rootPos.Z + math.sin(angle) * 10
			)
			
			local success, result = pcall(function()
				return OrbUtils.spawnOrbAt(orbPos, orbValue)
			end)
			
			if success and result then
				result.Name = "DeathOrb_" .. player.Name .. "_Extra"
				spawnedOrbs = spawnedOrbs + 1
			end
		end
	end
	
	print(string.format("✅ Spawned %d death orbs for %s", spawnedOrbs, player.Name))
end

-- === REVIVE SYSTEM (FIXED) ===
function SnakeCollisionHandler:promptRevive(player)
	print(string.format("🔄 Prompting revive for %s", player.Name))
	
	-- Clean any existing revive session
	if self.reviveSessions[player] then
		if self.reviveSessions[player].connection then
			self.reviveSessions[player].connection:Disconnect()
		end
		self.reviveSessions[player] = nil
	end
	
	-- Send revive prompt to client
	remotes.PromptRevive:FireClient(player)
	
	-- Set up response listener with timeout
	local startTime = os.clock()
	local responded = false
	
	local connection
	connection = remotes.ReviveResponse.OnServerEvent:Connect(function(respondingPlayer, response)
		if respondingPlayer ~= player or responded then
			return
		end
		
		responded = true
		connection:Disconnect()
		
		print(string.format("📨 Revive response from %s: %s", player.Name, tostring(response)))
		
		if response == "revive" or response == true then
			self:revivePlayer(player)
		else
			self:finalizePlayerDeath(player)
		end
		
		-- Clean session
		self.reviveSessions[player] = nil
	end)
	
	-- Store session
	self.reviveSessions[player] = {
		connection = connection,
		startTime = startTime
	}
	
	-- Set up timeout
	task.delay(REVIVE_TIMEOUT, function()
		if self.reviveSessions[player] and not responded then
			print(string.format("⏰ Revive timeout for %s", player.Name))
			connection:Disconnect()
			self.reviveSessions[player] = nil
			self:finalizePlayerDeath(player)
		end
	end)
end

-- === REVIVE PLAYER ===
function SnakeCollisionHandler:revivePlayer(player)
	print(string.format("✨ Reviving %s", player.Name))
	
	-- Deduct revive
	local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
	if revivesAvailable > 0 then
		player:SetAttribute("RevivesAvailable", revivesAvailable - 1)
	end
	
	-- Clear death states
	self.deadPlayers[player] = nil
	self.processingDeaths[player] = nil
	
	-- Set revive attributes
	player:SetAttribute("JustRevived", true)
	player:SetAttribute("RevivingNow", true)
	
	-- Respawn character
	player:LoadCharacter()
	
	-- Clean revive flags after delay
	task.delay(2, function()
		player:SetAttribute("JustRevived", false)
		player:SetAttribute("RevivingNow", false)
	end)
end

-- === FINALIZE DEATH ===
function SnakeCollisionHandler:finalizePlayerDeath(player)
	print(string.format("⚰️ Finalizing death for %s", player.Name))
	
	-- Mark as dead
	self.deadPlayers[player] = true
	self.processingDeaths[player] = nil
	
	-- Clean up snake
	self:cleanupPlayer(player)
	
	-- Fire death event
	remotes.PlayerDied:FireAllClients(player)
	
	-- Remove from dead players after delay
	task.delay(5, function()
		self.deadPlayers[player] = nil
	end)
end

-- === AI SNAKE DEATH ===
function SnakeCollisionHandler:killAISnake(aiSnake)
	if not aiSnake or not aiSnake.Segments then return end
	
	-- Spawn orbs from AI snake
	local orbCount = math.min(#aiSnake.Segments / 2, 20)
	local orbValue = math.max(1, math.floor(#aiSnake.Segments * 0.2 / orbCount))
	
	for i = 1, #aiSnake.Segments, math.ceil(#aiSnake.Segments / orbCount) do
		local segment = aiSnake.Segments[i]
		if segment and segment.Parent then
			local orbPos = Vector3.new(
				segment.Position.X + math.random(-2, 2),
				ORB_SPAWN_HEIGHT,
				segment.Position.Z + math.random(-2, 2)
			)
			
			pcall(function()
				local orb = OrbUtils.spawnOrbAt(orbPos, orbValue)
				if orb then
					orb.Name = "AIDeathOrb"
				end
			end)
		end
	end
	
	-- Destroy AI snake
	if aiSnake.Destroy then
		aiSnake:Destroy()
	end
end

-- === INVINCIBILITY SYSTEM ===
function SnakeCollisionHandler:setInvincible(player, duration)
	self.invinciblePlayers[player] = os.clock() + duration
	
	-- Auto-clear after duration
	task.delay(duration, function()
		if self.invinciblePlayers[player] and os.clock() >= self.invinciblePlayers[player] then
			self.invinciblePlayers[player] = nil
		end
	end)
end

function SnakeCollisionHandler:isInvincible(player)
	if not player then return false end
	
	-- Check timed invincibility
	local expiry = self.invinciblePlayers[player]
	if expiry and os.clock() < expiry then
		return true
	end
	
	-- Check ghost mode
	if player:GetAttribute("ActiveGhostMode") then
		return true
	end
	
	return false
end

-- === CLEANUP ===
function SnakeCollisionHandler:cleanupPlayer(player)
	-- Use Trove for automatic cleanup
	local trove = self.snakeTroves[player]
	if trove then
		trove:Destroy()
		self.snakeTroves[player] = nil
	end
	
	-- Clean revive sessions
	if self.reviveSessions[player] then
		if self.reviveSessions[player].connection then
			self.reviveSessions[player].connection:Disconnect()
		end
		self.reviveSessions[player] = nil
	end
	
	-- Destroy visual snake model
	local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
	if snakeModel then
		snakeModel:Destroy()
	end
end

-- === REMOTE LISTENERS ===
function SnakeCollisionHandler:setupRemoteListeners()
	-- Client collision reports (validated but used for responsiveness)
	remotes.CollisionDetected.OnServerEvent:Connect(function(player, hitData)
		-- Validate the collision server-side
		if self:validateClientCollision(player, hitData) then
			-- Process if valid
			print(string.format("✅ Valid collision report from %s", player.Name))
		else
			-- Log potential exploit attempt
			warn(string.format("⚠️ Invalid collision report from %s", player.Name))
		end
	end)
end

-- === COLLISION VALIDATION ===
function SnakeCollisionHandler:validateClientCollision(player, hitData)
	-- Ensure player is alive
	if self.deadPlayers[player] or not self.activeSnakes[player] then
		return false
	end
	
	-- Validate hit data structure
	if type(hitData) ~= "table" or not hitData.position or not hitData.targetPlayer then
		return false
	end
	
	-- Check position is reasonable
	local playerPos = self.activeSnakes[player].rootPart.Position
	local reportedPos = hitData.position
	local distance = (playerPos - reportedPos).Magnitude
	
	-- Reject if too far (potential teleport exploit)
	if distance > 50 then
		return false
	end
	
	-- Perform server-side spatial query to verify
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Whitelist
	overlapParams.FilterDescendantsInstances = {workspace}
	
	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(reportedPos),
		HEAD_COLLISION_SIZE,
		overlapParams
	)
	
	-- Verify collision is possible
	return #parts > 0
end

-- === DESTROY ===
function SnakeCollisionHandler:destroy()
	-- Clean all players
	for player, _ in pairs(self.activeSnakes) do
		self:cleanupPlayer(player)
	end
	
	-- Disconnect main loop
	if self.collisionCheckConnection then
		self.collisionCheckConnection:Disconnect()
	end
	
	-- Clear tables
	self.activeSnakes = {}
	self.snakeTroves = {}
	self.deadPlayers = {}
	self.invinciblePlayers = {}
	self.processingDeaths = {}
	self.reviveSessions = {}
end

-- === MODULE EXPORT ===
return SnakeCollisionHandler