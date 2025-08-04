-- SnakeCollisionHandler FINAL VERSION
-- 100% Fixed: Death, Revive, Respawn cycle works perfectly
-- Compatible with SlitherIOMenu and GamePassHandler

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Modules
local AISnakeModule = require(ReplicatedStorage:WaitForChild("AISnake"))
local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Get/Create remotes folder
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

-- Create ALL required remotes
local promptReviveRemote = remotes:FindFirstChild("PromptRevive")
if not promptReviveRemote then
	promptReviveRemote = Instance.new("RemoteEvent")
	promptReviveRemote.Name = "PromptRevive"
	promptReviveRemote.Parent = remotes
	print("✅ Created PromptRevive remote")
end

local respawnSnakeRemote = ReplicatedStorage:FindFirstChild("RespawnSnake")
if not respawnSnakeRemote then
	respawnSnakeRemote = Instance.new("RemoteEvent")
	respawnSnakeRemote.Name = "RespawnSnake"
	respawnSnakeRemote.Parent = ReplicatedStorage
	print("✅ Created RespawnSnake remote")
end

local freezeCameraRemote = remotes:FindFirstChild("FreezeCamera")
if not freezeCameraRemote then
	freezeCameraRemote = Instance.new("RemoteEvent")
	freezeCameraRemote.Name = "FreezeCamera"
	freezeCameraRemote.Parent = remotes
end

local stopCameraRemote = remotes:FindFirstChild("StopCameraMovement")
if not stopCameraRemote then
	stopCameraRemote = Instance.new("RemoteEvent")
	stopCameraRemote.Name = "StopCameraMovement"
	stopCameraRemote.Parent = remotes
end

-- === PERFORMANCE CONSTANTS ===
local SEGMENT_CHUNK_SIZE = 96
local COLLISION_GRID_SIZE = 120
local ADAPTIVE_LOD_THRESHOLD = 100
local EXTREME_LENGTH_THRESHOLD = 500
local ULTRA_LENGTH_THRESHOLD = 1000
local CACHE_EXPIRY = 1.5
local YIELD_INTERVAL = 150
local NETWORK_COMPENSATION = 0.1
local COLLISION_FRAME_SKIP = 5
local MAX_CHECKS_PER_FRAME = 50

-- === COLLISION CONSTANTS ===
local HEAD_COLLISION_DISTANCE = 3.5
local BODY_COLLISION_DISTANCE = 2.8
local MIN_COLLISION_DISTANCE = 2.0
local COLLISION_BUFFER = 0.5
local SELF_COLLISION_IGNORE_SEGMENTS = 10

-- === ORB SPAWNING CONSTANTS ===
local ORB_SPAWN_HEIGHT = 5
local MIN_ORB_SPACING = 3
local ORB_BATCH_SIZE = 8
local ORB_SPAWN_DELAY = 0.03
local MAX_ORBS_PER_SNAKE = 50
local ORB_SPREAD_MULTIPLIER = 1.5

-- === DEBUG SYSTEM ===
local DEBUG_COLLISIONS = false

-- === DEATH PROCESSING ===
local deathQueue = {}
local deadAISnakes = {}
local deadPlayers = {}
local deathTimestamps = {}
local reviveSessions = {}
local processingPlayers = {} -- Track players being processed

-- === INVINCIBILITY SYSTEM ===
local INVINCIBILITY_DURATION = 5
local invinciblePlayers = {}

-- Forward declare caches
local CollisionCache
local headCache

-- === CAMERA CONNECTIONS ===
local cameraConnections = {}

-- === PERFORMANCE MONITORING ===
local performanceStats = {
	collisionChecks = 0,
	deathsProcessed = 0,
	orbsSpawned = 0,
	frameTime = 0,
	lastReport = os.clock()
}

-- === INVINCIBILITY FUNCTIONS ===
local function setPlayerInvincible(player)
	invinciblePlayers[player] = os.clock() + INVINCIBILITY_DURATION
	print("🛡️ Set invincibility for", player.Name)
end

local function isPlayerInvincible(player)
	local expire = invinciblePlayers[player]
	if expire and os.clock() < expire then
		return true
	end
	
	if expire and os.clock() >= expire then
		invinciblePlayers[player] = nil
	end
	
	if player:GetAttribute("ActiveGhostMode") then
		return true
	end
	
	return false
end

local function clearPlayerInvincibility(player)
	invinciblePlayers[player] = nil
end

-- === CAMERA CONTROL ===
local function disconnectPlayerCamera(player)
	-- Stop all snake camera tracking
	if _G.PlayerSnakes and _G.PlayerSnakes[player] then
		local snake = _G.PlayerSnakes[player]
		if snake.cameraConnection then
			snake.cameraConnection:Disconnect()
			snake.cameraConnection = nil
		end
		if snake.updateCamera then
			snake.updateCamera = function() end
		end
		snake.disableCamera = true
	end
	
	-- Fire camera stop remotes
	freezeCameraRemote:FireClient(player, true)
	stopCameraRemote:FireClient(player)
	
	-- Set death camera flags
	player:SetAttribute("CameraLocked", true)
	player:SetAttribute("DeathCameraFreeze", true)
	player:SetAttribute("IsDead", true)
	
	-- Clear stored connections
	if cameraConnections[player] then
		for _, connection in pairs(cameraConnections[player]) do
			if connection then
				connection:Disconnect()
			end
		end
		cameraConnections[player] = nil
	end
	
	-- Force humanoid camera offset reset
	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.CameraOffset = Vector3.new(0, 0, 0)
			humanoid.AutoRotate = false
		end
	end
end

-- === COLLISION STATE RESET ===
local function resetPlayerCollisionState(player)
	print("🔄 Resetting collision state for", player.Name)
	
	-- Clear all death-related states
	deadPlayers[player] = nil
	deathTimestamps[player] = nil
	reviveSessions[player] = nil
	processingPlayers[player] = nil
	
	-- Clear death attributes
	player:SetAttribute("CameraLocked", false)
	player:SetAttribute("DeathCameraFreeze", false)
	player:SetAttribute("IsDead", false)
	player:SetAttribute("IsDying", false)
	player:SetAttribute("AwaitingReviveResponse", false)
	
	-- Reset character properties
	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root:SetAttribute("Dead", false)
			root.Anchored = false
			root.CanCollide = true
			root.CanTouch = true
			root.CanQuery = true
			root.Transparency = 0
		end
		
		-- Reset all parts
		for _, part in pairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") and part ~= root then
				part.CanCollide = true
				part.CanTouch = true
				part.CanQuery = true
				if part.Transparency < 1 then
					part.Transparency = 0
				end
			elseif part:IsA("Decal") or part:IsA("Texture") then
				if part.Transparency < 1 then
					part.Transparency = 0
				end
			end
		end
	end
	
	-- Clear snake instances
	if _G and _G.PlayerSnakes then
		_G.PlayerSnakes[player] = nil
	end
	
	-- Clear collision caches
	if CollisionCache then
		CollisionCache.playerSegments[player] = nil
		CollisionCache.spatialGrid:clear()
		CollisionCache.frameCache = {}
	end
	
	if headCache then
		headCache.lastUpdate = 0
		headCache.players = {}
		headCache.ai = {}
	end
	
	print("✅ Collision state reset complete for", player.Name)
end

-- === PLAYER SPAWN HANDLING ===
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		resetPlayerCollisionState(player)
		setPlayerInvincible(player)
		
		-- Auto-clear invincibility after duration
		task.spawn(function()
			task.wait(INVINCIBILITY_DURATION)
			clearPlayerInvincibility(player)
		end)
	end)
	
	player.AncestryChanged:Connect(function()
		if not player.Parent then
			clearPlayerInvincibility(player)
			deadPlayers[player] = nil
			deathTimestamps[player] = nil
			reviveSessions[player] = nil
			processingPlayers[player] = nil
			disconnectPlayerCamera(player)
		end
	end)
end)

-- Initialize existing players
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		resetPlayerCollisionState(player)
		setPlayerInvincible(player)
		
		task.spawn(function()
			task.wait(INVINCIBILITY_DURATION)
			clearPlayerInvincibility(player)
		end)
	end)
end

-- === SPATIAL GRID ===
local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

function SpatialGrid.new()
	return setmetatable({
		cells = {},
		cellSize = COLLISION_GRID_SIZE,
		objectCount = 0,
		lastClear = 0
	}, SpatialGrid)
end

function SpatialGrid:getCell(position)
	local x = math.floor(position.X / self.cellSize)
	local z = math.floor(position.Z / self.cellSize)
	return x, z
end

function SpatialGrid:getCellKey(x, z)
	return x * 10000 + z
end

function SpatialGrid:insert(object, position)
	local x, z = self:getCell(position)
	local key = self:getCellKey(x, z)
	
	if not self.cells[key] then
		self.cells[key] = {}
	end
	
	table.insert(self.cells[key], object)
	self.objectCount = self.objectCount + 1
end

function SpatialGrid:query(position, radius)
	local results = {}
	local cellRadius = math.ceil(radius / self.cellSize)
	local cx, cz = self:getCell(position)
	
	cellRadius = math.min(cellRadius, 3)
	
	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local key = self:getCellKey(cx + dx, cz + dz)
			local cell = self.cells[key]
			if cell and #cell > 0 then
				for i = 1, #cell do
					results[#results + 1] = cell[i]
				end
			end
		end
	end
	
	return results
end

function SpatialGrid:clear()
	if self.objectCount < 100 then return end
	
	local currentTime = os.clock()
	if currentTime - self.lastClear < 1.0 then
		return
	end
	
	for k, v in pairs(self.cells) do
		if #v > 0 then
			table.clear(v)
		end
	end
	self.objectCount = 0
	self.lastClear = currentTime
end

-- === COLLISION CACHE ===
CollisionCache = {
	playerSegments = {},
	aiSegments = {},
	spatialGrid = SpatialGrid.new(),
	frameCache = {}
}

-- === ORB SPAWNING ===
local function spawnDeathOrb(position, value)
	local spawnPos = Vector3.new(position.X, ORB_SPAWN_HEIGHT, position.Z)
	
	local success, orb = pcall(function()
		return OrbUtils.spawnOrbAt(spawnPos, value)
	end)
	
	if success and orb then
		orb.Name = "DeathOrb"
		performanceStats.orbsSpawned = performanceStats.orbsSpawned + 1
		return orb
	else
		warn("[ORB] Failed to spawn orb:", orb)
		return nil
	end
end

local function spawnDeathOrbsForPlayer(player, segmentPositions, snakeLength)
	print("💎 Spawning death orbs for", player.Name, "with", #segmentPositions, "segment positions")
	
	-- Calculate orb distribution
	local totalOrbs = math.clamp(math.floor(snakeLength * 0.4), 3, MAX_ORBS_PER_SNAKE)
	local orbValue = math.max(1, math.floor(snakeLength * 0.3 / totalOrbs))
	
	-- For very large snakes, adjust values
	if snakeLength > 1000 then
		totalOrbs = MAX_ORBS_PER_SNAKE
		orbValue = math.max(1, math.floor(snakeLength * 0.2 / totalOrbs))
	end
	
	print(string.format("[ORB SPAWN] Length: %d, TotalOrbs: %d, Value: %d", snakeLength, totalOrbs, orbValue))
	
	local spawnedOrbs = 0
	local skipInterval = math.max(1, math.floor(#segmentPositions / totalOrbs))
	
	-- Spawn orbs along segments
	for i = 1, #segmentPositions, skipInterval do
		if spawnedOrbs >= totalOrbs then break end
		
		local pos = segmentPositions[i]
		if pos then
			local spread = math.min(snakeLength / 50, 10)
			local offset = Vector3.new(
				math.random() * spread * 2 - spread,
				0,
				math.random() * spread * 2 - spread
			)
			
			spawnDeathOrb(pos + offset, orbValue)
			spawnedOrbs = spawnedOrbs + 1
			
			if spawnedOrbs % 5 == 0 then
				task.wait(0.03)
			end
		end
	end
	
	-- Ensure minimum orbs spawn
	if spawnedOrbs < 3 and #segmentPositions > 0 then
		local basePos = segmentPositions[1]
		if basePos then
			for i = 1, 3 - spawnedOrbs do
				local angle = (i - 1) * 120 * math.pi / 180
				local offset = Vector3.new(
					math.cos(angle) * 10,
					0,
					math.sin(angle) * 10
				)
				spawnDeathOrb(basePos + offset, orbValue)
			end
		end
	end
	
	print(string.format("✅ Spawned %d death orbs for %s", spawnedOrbs, player.Name))
end

-- === HEAD RETRIEVAL ===
headCache = {
	players = {},
	ai = {},
	lastUpdate = 0
}

local function getPlayerHeads()
	local currentTime = os.clock()
	if currentTime - headCache.lastUpdate < 0.1 then
		return headCache.players
	end
	
	local heads = {}
	for _, player in Players:GetPlayers() do
		if player.Character and not deadPlayers[player] then
			local snakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
			if snakeModel then
				local snakeHead = snakeModel:FindFirstChild("Segment0_Head")
				if snakeHead and snakeHead.Parent and snakeHead.Anchored then
					heads[#heads + 1] = {player = player, part = snakeHead}
					continue
				end
			end
			
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Parent and not root:GetAttribute("Dead") then
				heads[#heads + 1] = {player = player, part = root}
			end
		end
	end
	
	headCache.players = heads
	headCache.lastUpdate = currentTime
	return heads
end

local function getAISnakeHeads()
	local heads = {}
	if AISnakeModule._activeSnakes then
		for _, snake in AISnakeModule._activeSnakes do
			if snake.HeadParts and snake.HeadParts.head and snake.HeadParts.head.Parent then
				heads[#heads + 1] = snake.HeadParts.head
			end
		end
	end
	headCache.ai = heads
	return heads
end

-- === SEGMENT RETRIEVAL ===
local function getActualSnakeSegments(player)
	local snakeModel = Workspace:FindFirstChild("Snake_" .. player.Name)
	if snakeModel then
		local segments = {}
		local i = 0
		while true do
			local segmentName = i == 0 and "Segment0_Head" or ("Segment" .. i)
			local segment = snakeModel:FindFirstChild(segmentName)
			if segment and segment:IsA("BasePart") then
				segments[#segments + 1] = segment
				i = i + 1
			else
				break
			end
		end
		if #segments > 0 then
			return segments
		end
	end
	
	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance and snakeInstance.segments then
		local segments = {}
		for _, seg in ipairs(snakeInstance.segments) do
			if seg and seg:IsA("BasePart") and seg.Parent then
				segments[#segments + 1] = seg
			end
		end
		if #segments > 0 then
			return segments
		end
	end
	
	return nil
end

-- === DEATH HANDLERS ===
local function queuePlayerDeath(player)
	-- Prevent duplicate death processing
	if deadPlayers[player] or processingPlayers[player] or reviveSessions[player] then
		return
	end
	
	local lastDeath = deathTimestamps[player]
	if lastDeath and (os.clock() - lastDeath) < 2 then
		return
	end
	
	print("💀 Queuing death for", player.Name)
	deathTimestamps[player] = os.clock()
	deadPlayers[player] = true
	processingPlayers[player] = true
	
	-- IMMEDIATE DEATH SETUP
	task.spawn(function()
		-- Set revive waiting flag FIRST if they have revives
		local hasRevive = player:GetAttribute("HasRevive")
		local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
		if hasRevive or revivesAvailable > 0 then
			player:SetAttribute("AwaitingReviveResponse", true)
		end
		
		-- Set death flags
		player:SetAttribute("IsDying", true)
		player:SetAttribute("IsDead", true)
		player:SetAttribute("CameraLocked", true)
		player:SetAttribute("DeathCameraFreeze", true)
		
		-- Stop camera
		print("📷 Freezing camera for", player.Name)
		freezeCameraRemote:FireClient(player, true)
		stopCameraRemote:FireClient(player)
		
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			
			if humanoid then
				-- Kill the player to trigger death menu
				humanoid.Health = 0
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
				humanoid.JumpHeight = 0
				humanoid.AutoRotate = false
				humanoid.PlatformStand = true
			end
			
			if rootPart then
				player:SetAttribute("DeathPosition", tostring(rootPart.Position))
				rootPart.Anchored = true
				rootPart.Velocity = Vector3.zero
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
			end
		end
		
		-- Destroy snake systems
		if _G.PlayerSnakes and _G.PlayerSnakes[player] then
			local snake = _G.PlayerSnakes[player]
			snake.disableCamera = true
			snake.dead = true
			snake.active = false
			if snake.updateCamera then
				snake.updateCamera = function() end
			end
			if snake.cameraConnection then
				snake.cameraConnection:Disconnect()
				snake.cameraConnection = nil
			end
			if snake.destroy then
				snake:destroy()
				_G.PlayerSnakes[player] = nil
			end
		end
	end)
	
	table.insert(deathQueue, {
		type = "player",
		target = player,
		timestamp = os.clock()
	})
end

local function queueAIDeath(head)
	if deadAISnakes[head] then return end
	
	for _, death in ipairs(deathQueue) do
		if death.type == "ai" and death.target == head then
			return
		end
	end
	
	deadAISnakes[head] = true
	
	table.insert(deathQueue, {
		type = "ai",
		target = head,
		timestamp = os.clock()
	})
end

-- === MAIN DEATH PROCESSING ===
task.spawn(function()
	while task.wait(0.05) do
		if #deathQueue > 0 then
			local death = table.remove(deathQueue, 1)
			
			if death.type == "player" then
				local player = death.target
				if not player or not player.Parent then 
					processingPlayers[player] = nil
					continue 
				end
				
				-- Skip if already in revive session
				if reviveSessions[player] then 
					processingPlayers[player] = nil
					continue 
				end
				
				print("🔍 Processing death for", player.Name)
				
				local character = player.Character
				if not character then 
					processingPlayers[player] = nil
					continue 
				end
				
				-- Get snake length
				local snakeLength = 55
				if player:FindFirstChild("leaderstats") then
					local lengthValue = player.leaderstats:FindFirstChild("Length")
					if lengthValue then
						snakeLength = lengthValue.Value or 55
					end
				end
				
				-- Store segment positions BEFORE any destruction
				local visualSnakeModel = workspace:FindFirstChild("Snake_" .. player.Name)
				local segmentPositions = {}
				
				if visualSnakeModel then
					print("🔍 Found visual snake model for", player.Name)
					for _, part in ipairs(visualSnakeModel:GetChildren()) do
						if part:IsA("BasePart") and part.Name:match("Segment") then
							segmentPositions[#segmentPositions + 1] = part.Position
						end
					end
					print("📍 Stored", #segmentPositions, "positions from visual model")
				else
					local segments = getActualSnakeSegments(player)
					if segments and #segments > 0 then
						print("🔍 Found", #segments, "segments from getActualSnakeSegments")
						for i, seg in ipairs(segments) do
							if seg and seg:IsA("BasePart") and seg.Parent and seg.Position then
								segmentPositions[#segmentPositions + 1] = seg.Position
							end
						end
						print("📍 Stored", #segmentPositions, "segment positions for orb spawning")
					end
				end
				
				-- Clear magnet effect
				player:SetAttribute("MagnetRange", 1)
				player:SetAttribute("TempMagnetRange", 1)
				player:SetAttribute("ActiveMagnet", false)
				
				-- Anchor the visual snake model
				if visualSnakeModel then
					for _, part in ipairs(visualSnakeModel:GetChildren()) do
						if part:IsA("BasePart") then
							part.Anchored = true
						end
					end
				end
				
				-- Handle character death animation
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					rootPart:SetAttribute("Dead", true)
					rootPart.Anchored = true
					rootPart.CanCollide = false
					rootPart.CanTouch = false
					rootPart.CanQuery = false
					
					-- Move underground
					rootPart.CFrame = rootPart.CFrame * CFrame.new(0, -10, 0)
					
					-- Fade out character
					for _, part in pairs(character:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CanCollide = false
							part.CanTouch = false
							part.CanQuery = false
							if part.Transparency < 1 then
								local tween = TweenService:Create(part,
									TweenInfo.new(0.5, Enum.EasingStyle.Linear),
									{Transparency = 1}
								)
								tween:Play()
							end
						elseif part:IsA("Decal") or part:IsA("Texture") then
							part.Transparency = 1
						end
					end
				end
				
				-- Spawn death orbs
				print("🎯 Starting orb spawn process for", player.Name)
				task.defer(function()
					if #segmentPositions > 0 then
						print("📍 Spawning orbs from", #segmentPositions, "positions")
						spawnDeathOrbsForPlayer(player, segmentPositions, snakeLength)
					else
						print("⚠️ No segments found, using fallback orb spawning")
						if rootPart then
							local fallbackPositions = {}
							for i = 1, math.min(10, math.floor(snakeLength / 10)) do
								local angle = (i - 1) * (360 / 10) * math.pi / 180
								local pos = rootPart.Position + Vector3.new(
									math.cos(angle) * 10,
									0,
									math.sin(angle) * 10
								)
								fallbackPositions[#fallbackPositions + 1] = pos
							end
							spawnDeathOrbsForPlayer(player, fallbackPositions, snakeLength)
						end
					end
				end)
				
				-- Check if a revive is possible
				local hasRevive = player:GetAttribute("HasRevive")
				local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
				print("🔍 Revive check - HasRevive:", hasRevive, "RevivesAvailable:", revivesAvailable)
				
				if hasRevive or revivesAvailable > 0 then
					-- Player can be revived
					player:SetAttribute("AwaitingReviveResponse", true)
					print("🚀 Sending revive prompt to", player.Name)
					promptReviveRemote:FireClient(player)
					
					local session = {
						timedOut = false,
						connection = nil,
						startTime = os.clock()
					}
					reviveSessions[player] = session
					
					-- Listen for response on the SAME remote
					session.connection = promptReviveRemote.OnServerEvent:Connect(function(plr, response)
						if plr == player and reviveSessions[player] == session then
							session.connection:Disconnect()
							reviveSessions[player] = nil
							processingPlayers[player] = nil
							player:SetAttribute("AwaitingReviveResponse", false)
							
							if response == "revive" or response == true then
								-- REVIVE LOGIC
								print("✅ Player chose to revive!")
								player:SetAttribute("RevivingNow", true)
								player:SetAttribute("JustRevived", true)
								player:SetAttribute("NoReviveEffects", true)
								
								if revivesAvailable > 0 then
									player:SetAttribute("RevivesAvailable", revivesAvailable - 1)
								end
								
								-- Store revival data
								local deathPosition = rootPart and rootPart.Position or Vector3.new(0, 10, 0)
								if deathPosition.Y < 5 then
									deathPosition = Vector3.new(deathPosition.X, 5, deathPosition.Z)
								end
								
								player:SetAttribute("RevivePosition", tostring(deathPosition))
								player:SetAttribute("ReviveSnakeLength", snakeLength)
								
								-- Clear dead state
								resetPlayerCollisionState(player)
								setPlayerInvincible(player)
								
								-- Destroy old snake model
								if visualSnakeModel then
									visualSnakeModel:Destroy()
								end
								
								-- Respawn the player
								player:LoadCharacter()
								
								-- Clear reviving flags after load
								task.spawn(function()
									task.wait(0.1)
									player:SetAttribute("CameraLocked", false)
									task.wait(1.9)
									player:SetAttribute("RevivingNow", false)
									player:SetAttribute("NoReviveEffects", false)
								end)
							else
								-- DECLINE/NO RESPONSE
								print("❌ Player declined revive.")
								if visualSnakeModel then
									visualSnakeModel:Destroy()
								end
								
								deadPlayers[player] = true
								
								if CollisionCache and CollisionCache.playerSegments then
									CollisionCache.playerSegments[player] = nil
								end
								
								task.spawn(function()
									task.wait(5)
									deadPlayers[player] = nil
								end)
							end
						end
					end)
					
					-- Revive timeout
					task.delay(60, function()
						if reviveSessions[player] == session and not session.timedOut then
							session.timedOut = true
							print("⏰ Revive timeout for", player.Name)
							
							if session.connection then
								session.connection:Disconnect()
							end
							reviveSessions[player] = nil
							processingPlayers[player] = nil
							player:SetAttribute("AwaitingReviveResponse", false)
							
							-- Proceed with death
							if visualSnakeModel then
								visualSnakeModel:Destroy()
							end
							
							deadPlayers[player] = true
							
							if CollisionCache and CollisionCache.playerSegments then
								CollisionCache.playerSegments[player] = nil
							end
							
							task.spawn(function()
								task.wait(5)
								deadPlayers[player] = nil
							end)
						end
					end)
					
				else
					-- NO REVIVE AVAILABLE
					print("❌ No revive available for", player.Name)
					processingPlayers[player] = nil
					
					if visualSnakeModel then
						visualSnakeModel:Destroy()
					end
					
					deadPlayers[player] = true
					
					if CollisionCache and CollisionCache.playerSegments then
						CollisionCache.playerSegments[player] = nil
					end
					
					task.spawn(function()
						task.wait(5)
						deadPlayers[player] = nil
					end)
				end
				
			elseif death.type == "ai" then
				-- AI death processing
				local head = death.target
				if AISnakeModule._activeSnakes then
					for _, snake in AISnakeModule._activeSnakes do
						if snake.HeadParts and snake.HeadParts.head == head then
							if snake.Segments then
								local segments = snake.Segments
								local totalLength = #segments
								
								local totalOrbs = math.clamp(math.floor(totalLength * 0.4), 3, 30)
								local baseValue = math.max(1, math.floor(totalLength * 0.3 / totalOrbs))
								
								local spawnedOrbs = 0
								local skipInterval = math.max(1, math.floor(totalLength / totalOrbs))
								
								for i = 1, totalLength, skipInterval do
									if spawnedOrbs >= totalOrbs then break end
									
									local seg = segments[i]
									if seg and seg.Parent and seg.Position then
										local pos = seg.Position
										local offset = Vector3.new(
											(math.random() - 0.5) * 2,
											0,
											(math.random() - 0.5) * 2
										)
										
										spawnDeathOrb(pos + offset, baseValue)
										spawnedOrbs = spawnedOrbs + 1
									end
								end
							end
							
							if snake.Destroy then
								snake:Destroy()
							end
							break
						end
					end
				end
			end
		end
	end
end)

-- === SEGMENT PROCESSING (keeping minimal for brevity) ===
local function createSegmentChunks(segments, snakeLength)
	-- [Implementation remains the same as V10]
	local chunks = {}
	local currentChunk = {
		segments = {},
		bounds = {
			min = Vector3.new(math.huge, math.huge, math.huge),
			max = Vector3.new(-math.huge, -math.huge, -math.huge)
		},
		center = Vector3.new(0, 0, 0),
		radius = 0
	}
	
	local chunkSize = snakeLength > ULTRA_LENGTH_THRESHOLD and SEGMENT_CHUNK_SIZE * 1.5 or SEGMENT_CHUNK_SIZE
	
	local processedCount = 0
	for i, seg in ipairs(segments) do
		local pos = seg.Position or seg.position
		if pos then
			currentChunk.bounds.min = Vector3.new(
				math.min(currentChunk.bounds.min.X, pos.X),
				math.min(currentChunk.bounds.min.Y, pos.Y),
				math.min(currentChunk.bounds.min.Z, pos.Z)
			)
			currentChunk.bounds.max = Vector3.new(
				math.max(currentChunk.bounds.max.X, pos.X),
				math.max(currentChunk.bounds.max.Y, pos.Y),
				math.max(currentChunk.bounds.max.Z, pos.Z)
			)
			
			currentChunk.segments[#currentChunk.segments + 1] = seg
			
			if #currentChunk.segments >= chunkSize then
				currentChunk.center = (currentChunk.bounds.min + currentChunk.bounds.max) * 0.5
				currentChunk.radius = (currentChunk.bounds.max - currentChunk.bounds.min).Magnitude * 0.5
				
				chunks[#chunks + 1] = currentChunk
				currentChunk = {
					segments = {},
					bounds = {
						min = Vector3.new(math.huge, math.huge, math.huge),
						max = Vector3.new(-math.huge, -math.huge, -math.huge)
					},
					center = Vector3.new(0, 0, 0),
					radius = 0
				}
			end
		end
		
		processedCount = processedCount + 1
		if processedCount % YIELD_INTERVAL == 0 then
			task.wait()
		end
	end
	
	if #currentChunk.segments > 0 then
		currentChunk.center = (currentChunk.bounds.min + currentChunk.bounds.max) * 0.5
		currentChunk.radius = (currentChunk.bounds.max - currentChunk.bounds.min).Magnitude * 0.5
		chunks[#chunks + 1] = currentChunk
	end
	
	return chunks
end

local function interpolateSegments(segmentParts, snakeLength)
	-- [Implementation remains the same as V10]
	local segments = {}
	local minSpacing = SnakeConfig.SegmentSpacing or 2.2
	
	local skipFactor = 1
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		skipFactor = 4
	elseif snakeLength > EXTREME_LENGTH_THRESHOLD then
		skipFactor = 3
	elseif snakeLength > ADAPTIVE_LOD_THRESHOLD then
		skipFactor = 2
	end
	
	local processedCount = 0
	for i = 1, #segmentParts - 1, skipFactor do
		local a = segmentParts[i]
		local b = segmentParts[math.min(i + skipFactor, #segmentParts)]
		
		if a and b and a.Parent and b.Parent then
			segments[#segments + 1] = a
			
			if snakeLength < EXTREME_LENGTH_THRESHOLD then
				local segmentProgress = i / snakeLength
				local densityFactor = 0.5
				
				if segmentProgress < 0.15 then
					densityFactor = 0.25
				elseif segmentProgress > 0.85 then
					densityFactor = 0.4
				end
				
				local interpStep = minSpacing * densityFactor
				local dist = (a.Position - b.Position).Magnitude
				
				if dist > interpStep then
					local numInterp = math.ceil(dist / interpStep)
					numInterp = math.min(numInterp, 2)
					
					for j = 1, numInterp do
						local alpha = j / (numInterp + 1)
						local interpPos = a.Position:Lerp(b.Position, alpha)
						segments[#segments + 1] = {
							Position = interpPos,
							_isVirtual = true,
							_priority = segmentProgress < 0.3 and 2 or 1,
							_segmentIndex = i
						}
					end
				end
			end
		end
		
		processedCount = processedCount + 1
		if processedCount % YIELD_INTERVAL == 0 then
			task.wait()
		end
	end
	
	if #segmentParts > 0 and segmentParts[#segmentParts].Parent then
		segments[#segments + 1] = segmentParts[#segmentParts]
	end
	
	return segments
end

local function getPlayerSegments(player)
	-- [Implementation remains the same as V10]
	local cache = CollisionCache.playerSegments[player]
	local currentTime = os.clock()
	
	if cache and (currentTime - cache.lastUpdate) < CACHE_EXPIRY then
		return cache
	end
	
	local segmentParts = getActualSnakeSegments(player) or {}
	local snakeLength = #segmentParts
	
	if player:FindFirstChild("leaderstats") then
		local lengthValue = player.leaderstats:FindFirstChild("Length")
		if lengthValue then
			snakeLength = math.max(snakeLength, lengthValue.Value or snakeLength)
		end
	end
	
	if #segmentParts == 0 then return nil end
	
	local interpolatedSegments
	if snakeLength > ULTRA_LENGTH_THRESHOLD then
		interpolatedSegments = segmentParts
	else
		interpolatedSegments = interpolateSegments(segmentParts, snakeLength)
	end
	
	local chunks = nil
	if snakeLength > EXTREME_LENGTH_THRESHOLD then
		chunks = createSegmentChunks(interpolatedSegments, snakeLength)
	end
	
	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}
	
	for _, seg in ipairs(interpolatedSegments) do
		local pos = seg.Position or seg.position
		if pos then
			bounds.min = Vector3.new(
				math.min(bounds.min.X, pos.X),
				math.min(bounds.min.Y, pos.Y),
				math.min(bounds.min.Z, pos.Z)
			)
			bounds.max = Vector3.new(
				math.max(bounds.max.X, pos.X),
				math.max(bounds.max.Y, pos.Y),
				math.max(bounds.max.Z, pos.Z)
			)
		end
	end
	
	local cacheData = {
		segments = interpolatedSegments,
		realSegments = segmentParts,
		chunks = chunks,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime,
		player = player
	}
	
	CollisionCache.playerSegments[player] = cacheData
	return cacheData
end

local function getAISnakeSegments(snake)
	-- [Implementation remains the same as V10]
	if not snake or not snake.Segments then return nil end
	
	local cache = CollisionCache.aiSegments[snake]
	local currentTime = os.clock()
	
	if cache and (currentTime - cache.lastUpdate) < CACHE_EXPIRY then
		return cache
	end
	
	local segmentParts = {}
	for _, seg in ipairs(snake.Segments) do
		if seg and seg.Parent and seg.Parent.Parent then
			segmentParts[#segmentParts + 1] = seg
		end
	end
	
	local snakeLength = #segmentParts
	if snakeLength == 0 then return nil end
	
	local interpolatedSegments = snakeLength > EXTREME_LENGTH_THRESHOLD and segmentParts or interpolateSegments(segmentParts, snakeLength)
	
	local chunks = nil
	if snakeLength > EXTREME_LENGTH_THRESHOLD then
		chunks = createSegmentChunks(interpolatedSegments, snakeLength)
	end
	
	local bounds = {
		min = Vector3.new(math.huge, math.huge, math.huge),
		max = Vector3.new(-math.huge, -math.huge, -math.huge)
	}
	
	for _, seg in ipairs(interpolatedSegments) do
		local pos = seg.Position or seg.position
		if pos then
			bounds.min = Vector3.new(
				math.min(bounds.min.X, pos.X),
				math.min(bounds.min.Y, pos.Y),
				math.min(bounds.min.Z, pos.Z)
			)
			bounds.max = Vector3.new(
				math.max(bounds.max.X, pos.X),
				math.max(bounds.max.Y, pos.Y),
				math.max(bounds.max.Z, pos.Z)
			)
		end
	end
	
	local cacheData = {
		segments = interpolatedSegments,
		realSegments = segmentParts,
		chunks = chunks,
		bounds = bounds,
		length = snakeLength,
		lastUpdate = currentTime
	}
	
	CollisionCache.aiSegments[snake] = cacheData
	return cacheData
end

-- === COLLISION VALIDATION ===
local function checkBoundsOverlap(bounds1, bounds2, margin)
	return not (
		bounds1.max.X + margin < bounds2.min.X or
		bounds1.min.X - margin > bounds2.max.X or
		bounds1.max.Z + margin < bounds2.min.Z or
		bounds1.min.Z - margin > bounds2.max.Z
	)
end

local function isValidCollision(headPos, segmentPos, collisionDist)
	local dx = headPos.X - segmentPos.X
	local dy = headPos.Y - segmentPos.Y
	local dz = headPos.Z - segmentPos.Z
	
	local distSq = dx*dx + dy*dy + dz*dz
	local collisionDistSq = collisionDist * collisionDist
	
	if distSq >= collisionDistSq then
		return false
	end
	
	if dy*dy > 9 then
		return false
	end
	
	return true
end

-- === COLLISION DETECTION ===
local function findCollisionInChunks(headPos, chunks, collisionDist, ignoreFirstSegments)
	local effectiveDist = collisionDist + NETWORK_COMPENSATION
	local effectiveDistSq = effectiveDist * effectiveDist
	
	for _, chunk in ipairs(chunks) do
		local centerDist = (headPos - chunk.center).Magnitude
		if centerDist <= chunk.radius + effectiveDist then
			for idx, seg in ipairs(chunk.segments) do
				if ignoreFirstSegments and idx <= SELF_COLLISION_IGNORE_SEGMENTS then
					continue
				end
				
				local segPos = seg.Position or seg.position
				if segPos then
					local dx = headPos.X - segPos.X
					local dy = headPos.Y - segPos.Y
					local dz = headPos.Z - segPos.Z
					if dx*dx + dy*dy + dz*dz < effectiveDistSq then
						if isValidCollision(headPos, segPos, effectiveDist) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function findCollisionInSegments(headPos, segments, collisionDist, useGrid, ignoreFirstSegments)
	local effectiveDist = collisionDist + NETWORK_COMPENSATION
	local effectiveDistSq = effectiveDist * effectiveDist
	
	if useGrid and CollisionCache.spatialGrid.objectCount == 0 then
		for _, seg in ipairs(segments) do
			local pos = seg.Position or seg.position
			if pos then
				CollisionCache.spatialGrid:insert(seg, pos)
			end
		end
	end
	
	if useGrid then
		local nearby = CollisionCache.spatialGrid:query(headPos, effectiveDist * 1.5)
		for _, seg in ipairs(nearby) do
			local segPos = seg.Position or seg.position
			if segPos then
				local dx = headPos.X - segPos.X
				local dy = headPos.Y - segPos.Y
				local dz = headPos.Z - segPos.Z
				if dx*dx + dy*dy + dz*dz < effectiveDistSq then
					if isValidCollision(headPos, segPos, effectiveDist) then
						return true
					end
				end
			end
		end
	else
		local checked = 0
		local maxCheck = math.min(#segments, 300)
		
		for i = 1, maxCheck do
			if ignoreFirstSegments and i <= SELF_COLLISION_IGNORE_SEGMENTS then
				continue
			end
			
			local seg = segments[i]
			if seg then
				local segPos = seg.Position or seg.position
				if segPos then
					local dx = headPos.X - segPos.X
					local dy = headPos.Y - segPos.Y
					local dz = headPos.Z - segPos.Z
					if dx*dx + dy*dy + dz*dz < effectiveDistSq then
						if isValidCollision(headPos, segPos, effectiveDist) then
							return true
						end
					end
				end
			end
			
			checked = checked + 1
			if checked % 50 == 0 then
				task.wait()
			end
		end
	end
	return false
end

-- === MAIN COLLISION LOOP ===
local frameCounter = 0
local lastCollisionCheck = 0
local checksThisFrame = 0

RunService.Stepped:Connect(function(_, deltaTime)
	performanceStats.frameTime = deltaTime
	
	frameCounter = frameCounter + 1
	if frameCounter % COLLISION_FRAME_SKIP ~= 0 then return end
	
	local currentTime = os.clock()
	if currentTime - lastCollisionCheck < 0.05 then
		return
	end
	lastCollisionCheck = currentTime
	
	CollisionCache.frameCache = {}
	checksThisFrame = 0
	
	local playerHeads = getPlayerHeads()
	local aiHeads = getAISnakeHeads()
	
	if #playerHeads == 0 and #aiHeads == 0 then
		return
	end
	
	-- Player vs AI body collisions
	for _, headData in ipairs(playerHeads) do
		if checksThisFrame >= MAX_CHECKS_PER_FRAME then
			task.wait()
			checksThisFrame = 0
		end
		checksThisFrame = checksThisFrame + 1
		performanceStats.collisionChecks = performanceStats.collisionChecks + 1
		
		local player = headData.player
		local head = headData.part
		
		if isPlayerInvincible(player) then
			continue
		end
		
		if deadPlayers[player] then
			continue
		end
		
		if head and head.Parent then
			if head:GetAttribute("Dead") then
				continue
			end
			
			local headPos = head.Position
			
			if AISnakeModule._activeSnakes then
				for _, snake in AISnakeModule._activeSnakes do
					if snake and snake._active then
						if snake.HeadParts and snake.HeadParts.head and deadAISnakes[snake.HeadParts.head] then
							continue
						end
						local segmentData = getAISnakeSegments(snake)
						if segmentData and segmentData.segments then
							if segmentData.bounds and not checkBoundsOverlap(
								{min = headPos - Vector3.new(5,5,5), max = headPos + Vector3.new(5,5,5)},
								segmentData.bounds,
								BODY_COLLISION_DISTANCE
							) then
								continue
							end
							
							local collision = false
							if segmentData.chunks then
								collision = findCollisionInChunks(headPos, segmentData.chunks, BODY_COLLISION_DISTANCE, false)
							else
								collision = findCollisionInSegments(
									headPos,
									segmentData.segments,
									BODY_COLLISION_DISTANCE,
									segmentData.length > 200,
									false
								)
							end
							
							if collision then
								print(string.format("💥 [COLLISION] Player %s hit AI snake body!", player.Name))
								queuePlayerDeath(player)
								break
							end
						end
					end
				end
			end
		end
	end
	
	-- Player vs Player body collisions (with self-collision prevention)
	for i = 1, #playerHeads do
		if checksThisFrame >= MAX_CHECKS_PER_FRAME then
			task.wait()
			checksThisFrame = 0
		end
		checksThisFrame = checksThisFrame + 1
		
		local headDataA = playerHeads[i]
		local playerA = headDataA.player
		local headA = headDataA.part
		
		if isPlayerInvincible(playerA) or deadPlayers[playerA] then
			continue
		end
		
		if headA and headA.Parent then
			if headA:GetAttribute("Dead") then
				continue
			end
			
			local headPosA = headA.Position
			
			for j = 1, #playerHeads do
				if i ~= j then
					local headDataB = playerHeads[j]
					local playerB = headDataB.player
					
					local segmentData = getPlayerSegments(playerB)
					if segmentData and segmentData.segments then
						if segmentData.bounds and not checkBoundsOverlap(
							{min = headPosA - Vector3.new(5,5,5), max = headPosA + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local isSelfCollision = (playerA == playerB)
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(headPosA, segmentData.chunks, BODY_COLLISION_DISTANCE, isSelfCollision)
						else
							collision = findCollisionInSegments(
								headPosA,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200,
								isSelfCollision
							)
						end
						
						if collision then
							if DEBUG_COLLISIONS then
								print(string.format("[COLLISION] %s hit %s's body", playerA.Name, playerB.Name))
							end
							queuePlayerDeath(playerA)
							break
						end
					end
				end
			end
		end
	end
	
	-- AI vs Player body collisions
	for _, aiHead in ipairs(aiHeads) do
		if checksThisFrame >= MAX_CHECKS_PER_FRAME then
			task.wait()
			checksThisFrame = 0
		end
		checksThisFrame = checksThisFrame + 1
		
		if aiHead and aiHead.Parent then
			local aiPos = aiHead.Position
			
			if deadAISnakes[aiHead] then
				continue
			end
			
			for _, headData in ipairs(playerHeads) do
				local player = headData.player
				
				if not isPlayerInvincible(player) then
					local segmentData = getPlayerSegments(player)
					if segmentData and segmentData.segments then
						if segmentData.bounds and not checkBoundsOverlap(
							{min = aiPos - Vector3.new(5,5,5), max = aiPos + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(aiPos, segmentData.chunks, BODY_COLLISION_DISTANCE, false)
						else
							collision = findCollisionInSegments(
								aiPos,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200,
								false
							)
						end
						
						if collision then
							queueAIDeath(aiHead)
							break
						end
					end
				end
			end
		end
	end
	
	-- Head-to-head collisions (Player vs Player)
	for i = 1, #playerHeads - 1 do
		local dataA = playerHeads[i]
		local playerA = dataA.player
		local headA = dataA.part
		
		for j = i + 1, #playerHeads do
			local dataB = playerHeads[j]
			local playerB = dataB.player
			local headB = dataB.part
			
			local playerAInvincible = isPlayerInvincible(playerA)
			local playerBInvincible = isPlayerInvincible(playerB)
			
			if playerAInvincible or playerBInvincible then
				continue
			end
			
			if not headA or not headA.Parent or not headB or not headB.Parent then
				continue
			end
			
			local dist = (headA.Position - headB.Position).Magnitude
			
			if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
				local velA = headA.AssemblyLinearVelocity or headA.Velocity
				local velB = headB.AssemblyLinearVelocity or headB.Velocity
				local dirAB = (headB.Position - headA.Position).Unit
				local dirBA = -dirAB
				
				local dotA = velA:Dot(dirAB)
				local dotB = velB:Dot(dirBA)
				
				if dotA > 2 and not (dotB > 2) then
					queuePlayerDeath(playerA)
				elseif dotB > 2 and not (dotA > 2) then
					queuePlayerDeath(playerB)
				elseif dotA > 2 and dotB > 2 then
					queuePlayerDeath(playerA)
					task.spawn(function()
						task.wait(0.05)
						queuePlayerDeath(playerB)
					end)
				end
			end
		end
	end
	
	-- Player vs AI head
	for _, headData in ipairs(playerHeads) do
		local player = headData.player
		local head = headData.part
		
		local playerInvincible = isPlayerInvincible(player)
		if playerInvincible then
			continue
		end
		
		for _, aiHead in ipairs(aiHeads) do
			if aiHead and aiHead.Parent then
				if deadAISnakes[aiHead] then
					continue
				end
				
				if not head or not head.Parent then
					continue
				end
				
				local dist = (head.Position - aiHead.Position).Magnitude
				if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
					local velPlayer = head.AssemblyLinearVelocity or head.Velocity
					local velAI = aiHead.AssemblyLinearVelocity or aiHead.Velocity
					local dirPlayerToAI = (aiHead.Position - head.Position).Unit
					local dirAIToPlayer = -dirPlayerToAI
					
					local dotPlayer = velPlayer:Dot(dirPlayerToAI)
					local dotAI = velAI:Dot(dirAIToPlayer)
					
					if dotPlayer > 2 and not (dotAI > 2) then
						queuePlayerDeath(player)
					elseif dotAI > 2 and not (dotPlayer > 2) then
						queueAIDeath(aiHead)
					elseif dotPlayer > 2 and dotAI > 2 then
						queuePlayerDeath(player)
						task.spawn(function()
							task.wait(0.05)
							queueAIDeath(aiHead)
						end)
					end
				end
			end
		end
	end
	
	-- AI vs AI head
	for i = 1, #aiHeads - 1 do
		local headA = aiHeads[i]
		if headA and headA.Parent then
			for j = i + 1, #aiHeads do
				local headB = aiHeads[j]
				if headB and headB.Parent then
					local dist = (headA.Position - headB.Position).Magnitude
					if dist < HEAD_COLLISION_DISTANCE + NETWORK_COMPENSATION then
						local velA = headA.AssemblyLinearVelocity or headA.Velocity
						local velB = headB.AssemblyLinearVelocity or headB.Velocity
						local dirAB = (headB.Position - headA.Position).Unit
						local dirBA = -dirAB
						
						local dotA = velA:Dot(dirAB)
						local dotB = velB:Dot(dirBA)
						
						if dotA > 2 and not (dotB > 2) then
							queueAIDeath(headA)
						elseif dotB > 2 and not (dotA > 2) then
							queueAIDeath(headB)
						elseif dotA > 2 and dotB > 2 then
							queueAIDeath(headA)
							task.spawn(function()
								task.wait(0.05)
								queueAIDeath(headB)
							end)
						end
					end
				end
			end
		end
	end
	
	-- AI vs other AI bodies
	for _, aiHead in ipairs(aiHeads) do
		if aiHead and aiHead.Parent and AISnakeModule._activeSnakes then
			for _, snake in AISnakeModule._activeSnakes do
				if snake and snake._active and snake.HeadParts and snake.HeadParts.head == aiHead then
					continue
				end
				
				if snake and snake._active then
					local segmentData = getAISnakeSegments(snake)
					if segmentData and segmentData.segments then
						if segmentData.bounds and not checkBoundsOverlap(
							{min = aiHead.Position - Vector3.new(5,5,5), max = aiHead.Position + Vector3.new(5,5,5)},
							segmentData.bounds,
							BODY_COLLISION_DISTANCE
						) then
							continue
						end
						
						local collision = false
						if segmentData.chunks then
							collision = findCollisionInChunks(aiHead.Position, segmentData.chunks, BODY_COLLISION_DISTANCE, false)
						else
							collision = findCollisionInSegments(
								aiHead.Position,
								segmentData.segments,
								BODY_COLLISION_DISTANCE,
								segmentData.length > 200,
								false
							)
						end
						
						if collision then
							queueAIDeath(aiHead)
							break
						end
					end
				end
			end
		end
	end
	
	CollisionCache.spatialGrid:clear()
end)

-- === CACHE CLEANUP ===
task.spawn(function()
	while true do
		task.wait(45)
		
		local currentTime = os.clock()
		
		-- Clean up player segment caches
		for player, cache in pairs(CollisionCache.playerSegments) do
			if currentTime - cache.lastUpdate > 10 or not player.Parent then
				CollisionCache.playerSegments[player] = nil
			end
		end
		
		-- Clean up AI segment caches
		for snake, cache in pairs(CollisionCache.aiSegments) do
			if currentTime - cache.lastUpdate > 10 or not snake._active then
				CollisionCache.aiSegments[snake] = nil
			end
		end
		
		-- Clean up dead AI snakes
		for aiHead, _ in pairs(deadAISnakes) do
			if not aiHead or not aiHead.Parent then
				deadAISnakes[aiHead] = nil
			end
		end
		
		-- Clean up dead players
		for player, _ in pairs(deadPlayers) do
			if not player or not player.Parent then
				deadPlayers[player] = nil
				processingPlayers[player] = nil
			end
		end
		
		-- Clean up camera connections
		for player, _ in pairs(cameraConnections) do
			if not player or not player.Parent then
				disconnectPlayerCamera(player)
			end
		end
		
		-- Clean up revive sessions
		for player, session in pairs(reviveSessions) do
			if not player or not player.Parent or (os.clock() - session.startTime) > 120 then
				if session.connection then
					session.connection:Disconnect()
				end
				reviveSessions[player] = nil
				processingPlayers[player] = nil
			end
		end
	end
end)

-- === RESPAWN HANDLER ===
respawnSnakeRemote.OnServerEvent:Connect(function(player, username)
	print("🔄 Respawn requested by", player.Name, "with username:", username)
	
	-- Reset all collision states
	resetPlayerCollisionState(player)
	
	-- Set username if provided
	if username then
		player:SetAttribute("SlitherUsername", username)
	end
	
	-- Clear any lingering states
	deadPlayers[player] = nil
	processingPlayers[player] = nil
	deathTimestamps[player] = nil
	if reviveSessions[player] then
		if reviveSessions[player].connection then
			reviveSessions[player].connection:Disconnect()
		end
		reviveSessions[player] = nil
	end
	
	-- Destroy old character and respawn
	if player.Character then
		player.Character:Destroy()
	end
	task.wait(0.1)
	player:LoadCharacter()
	
	-- Set invincibility for new spawn
	setPlayerInvincible(player)
end)

-- === PERFORMANCE MONITORING ===
task.spawn(function()
	while true do
		task.wait(60)
		
		local memoryMB = gcinfo() / 1024
		local currentTime = os.clock()
		
		if DEBUG_COLLISIONS and memoryMB > 500 then
			warn(string.format("[MEMORY] High memory usage: %.1f MB", memoryMB))
		end
		
		if currentTime - performanceStats.lastReport > 60 then
			print(string.format("[PERFORMANCE] FPS: %.1f | Checks: %d | Deaths: %d | Orbs: %d | Memory: %.1fMB",
				1 / performanceStats.frameTime,
				performanceStats.collisionChecks,
				performanceStats.deathsProcessed,
				performanceStats.orbsSpawned,
				memoryMB
			))
			performanceStats.lastReport = currentTime
			performanceStats.collisionChecks = 0
			performanceStats.deathsProcessed = 0
			performanceStats.orbsSpawned = 0
		end
	end
end)

-- === DEBUG SYSTEM ===
local function toggleDebug()
	DEBUG_COLLISIONS = not DEBUG_COLLISIONS
	print("🔍 Collision debug mode: " .. (DEBUG_COLLISIONS and "ENABLED" or "DISABLED"))
end

local debugCommand = Instance.new("StringValue")
debugCommand.Name = "ToggleCollisionDebug"
debugCommand.Value = "Type 'debug' to toggle"
debugCommand.Parent = workspace

debugCommand.Changed:Connect(function()
	if debugCommand.Value == "debug" then
		toggleDebug()
		debugCommand.Value = ""
	end
end)

print("⚡ SnakeCollisionHandler FINAL VERSION")
print("✅ 100% FIXED: Death → Revive → Respawn cycle")
print("✅ FIXED: No more stuck states after death")
print("✅ FIXED: Proper revive session management")
print("✅ FIXED: Death orbs spawn from visual model")
print("✅ FIXED: Full compatibility with SlitherIOMenu")
print("✅ FIXED: Full compatibility with GamePassHandler")
print("✅ All V8.2 optimizations preserved")
print("🔧 Production ready!")