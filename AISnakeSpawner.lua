-- POLISHED AI SNAKE SPAWNER V3.0 - FIXED INITIAL DEATH DETECTION
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local AISnake = require(ReplicatedStorage:WaitForChild("AISnake"))

-- === CONFIGURATION ===
local NUM_SNAKES = 11
local SPAWN_HEIGHT = 5
local MIN_SPAWN_DELAY = 3      -- Minimum time between death and respawn
local CHECK_INTERVAL = 1       -- Check for dead snakes every 1 second
local SPAWN_PROTECTION = 5     -- Seconds before checking if newly spawned snake is alive
local SPAWN_SPACING = 150      -- Increased from 100 to 150 studs minimum distance
local INITIAL_SPAWN_DELAY = 10 -- Delay before starting death checks

-- === STATE TRACKING ===
local snakeSlots = {}  -- Track each snake slot
local spawnerStartTime = tick()
local initialSpawnComplete = false

for i = 1, NUM_SNAKES do
	snakeSlots[i] = {
		snake = nil,
		deathTime = nil,
		spawning = false,
		spawnTime = nil,         -- Track when snake was spawned
		lastPersonality = nil,   -- Track personality for respawn
		lastPosition = nil       -- Track last known position
	}
end

-- === MAP BOUNDS ===
local mapBounds = {
	minX = -600,
	maxX = 600,
	minZ = -600,
	maxZ = 600
}

-- Update map bounds based on ground
local function updateMapBounds()
	local ground = Workspace:FindFirstChild("SlitherIOGround")
	if ground and ground:IsA("BasePart") then
		local halfX = ground.Size.X / 2
		local halfZ = ground.Size.Z / 2
		mapBounds.minX = -halfX + 50
		mapBounds.maxX = halfX - 50
		mapBounds.minZ = -halfZ + 50
		mapBounds.maxZ = halfZ - 50
	end
end

-- === HELPER FUNCTIONS ===
local function isPositionSafe(position)
	-- Check distance from all active snakes
	for _, slot in pairs(snakeSlots) do
		if slot.snake and slot.snake._active and slot.snake.HeadParts and slot.snake.HeadParts.head then
			local headPos = slot.snake.HeadParts.head.Position
			if (position - headPos).Magnitude < SPAWN_SPACING then
				return false
			end
		end
	end
	
	-- Check distance from players
	for _, player in pairs(game.Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local playerPos = player.Character.HumanoidRootPart.Position
			if (position - playerPos).Magnitude < SPAWN_SPACING then
				return false
			end
		end
	end
	
	return true
end

local function getRandomSpawnPosition()
	updateMapBounds()
	
	local maxAttempts = 20
	local attempt = 0
	
	while attempt < maxAttempts do
		attempt = attempt + 1
		
		-- Generate random position within bounds
		local x = math.random() * (mapBounds.maxX - mapBounds.minX) + mapBounds.minX
		local z = math.random() * (mapBounds.maxZ - mapBounds.minZ) + mapBounds.minZ
		local position = Vector3.new(x, SPAWN_HEIGHT, z)
		
		-- Check if position is safe
		if isPositionSafe(position) then
			return position
		end
	end
	
	-- Fallback: use a random position anyway
	local angle = math.random() * 2 * math.pi
	local distance = math.random(150, 400)
	return Vector3.new(
		math.cos(angle) * distance,
		SPAWN_HEIGHT,
		math.sin(angle) * distance
	)
end

local function cleanupSnake(slot)
	if slot.snake then
		-- Save important data before cleanup
		if slot.snake.Personality and slot.snake.Personality.Type then
			slot.lastPersonality = slot.snake.Personality.Type
		end
		
		if slot.snake.HeadParts and slot.snake.HeadParts.head and slot.snake.HeadParts.head.Parent then
			slot.lastPosition = slot.snake.HeadParts.head.Position
		end

		-- Try cleanup
		pcall(function()
			if slot.snake.Destroy then
				slot.snake:Destroy()
			end
		end)

		-- Extra cleanup - find and destroy the model
		pcall(function()
			if slot.snake.Model and slot.snake.Model.Parent then
				slot.snake.Model:Destroy()
			end
		end)

		slot.snake = nil
	end
end

local function spawnSnake(slotIndex)
	local slot = snakeSlots[slotIndex]

	-- Safety check
	if slot.spawning then
		return false
	end

	slot.spawning = true

	-- Clean up any existing snake
	cleanupSnake(slot)

	-- Small delay to ensure cleanup
	task.wait(0.1)

	-- Get spawn position
	local position = getRandomSpawnPosition()
	
	-- Spawn new snake
	local success, result = pcall(function()
		-- Create snake with preserved personality if available
		local snake = AISnake.new(position, slot.lastPersonality)
		if snake then
			-- Wait for snake to initialize
			task.wait(0.5)
			return snake
		end
		return nil
	end)

	if success and result then
		slot.snake = result
		slot.deathTime = nil
		slot.spawnTime = tick() -- Record spawn time
		slot.spawning = false
		
		local personality = result.Personality and result.Personality.Type or "Unknown"
		print(string.format("✅ AI Snake #%d spawned at %.1f, %.1f, %.1f | Personality: %s", 
			slotIndex, position.X, position.Y, position.Z, personality))
		
		return true
	else
		slot.spawning = false
		warn("❌ Failed to spawn AI Snake #" .. slotIndex .. ":", result or "Unknown error")
		return false
	end
end

local function isSnakeAlive(slot)
	-- During initial spawn phase, always assume alive
	if not initialSpawnComplete then
		return true
	end
	
	-- Don't check snakes that are still in spawn protection
	if slot.spawnTime and tick() - slot.spawnTime < SPAWN_PROTECTION then
		return true -- Assume alive during protection period
	end
	
	-- Check various death conditions
	if not slot.snake then
		return false
	end
	
	if slot.snake._destroyed then
		return false
	end
	
	if not slot.snake._active then
		return false
	end
	
	-- Check if model exists
	if not slot.snake.Model or not slot.snake.Model.Parent then
		return false
	end
	
	-- Check if head exists
	if not slot.snake.HeadParts or not slot.snake.HeadParts.head or not slot.snake.HeadParts.head.Parent then
		return false
	end
	
	-- Check if root part exists
	if not slot.snake.RootPart or not slot.snake.RootPart.Parent then
		return false
	end
	
	return true
end

-- === INITIAL SPAWN ===
print("🐍 AI Snake Spawner V3.0 Starting...")
print("📊 Configuration: " .. NUM_SNAKES .. " snakes, " .. MIN_SPAWN_DELAY .. "s respawn delay")

-- Update map bounds
updateMapBounds()

-- Spawn all snakes initially with staggered timing
task.spawn(function()
	print("🚀 Beginning initial spawn sequence...")
	
	for i = 1, NUM_SNAKES do
		local success = spawnSnake(i)
		if not success then
			-- Retry once
			task.wait(1)
			spawnSnake(i)
		end
		task.wait(0.5) -- Half second between each spawn
	end
	
	-- Wait for all snakes to fully initialize
	task.wait(SPAWN_PROTECTION)
	initialSpawnComplete = true
	print("✅ Initial spawn sequence complete! Death monitoring active.")
end)

-- === RESPAWN MONITOR ===
local lastDebugTime = 0

task.spawn(function()
	-- Wait for initial spawn delay
	task.wait(INITIAL_SPAWN_DELAY)
	
	while true do
		task.wait(CHECK_INTERVAL)
		
		-- Skip checks until initial spawn is complete
		if not initialSpawnComplete then
			continue
		end
		
		local currentTime = tick()
		local aliveCount = 0
		local deadCount = 0
		
		for i = 1, NUM_SNAKES do
			local slot = snakeSlots[i]
			
			if isSnakeAlive(slot) then
				aliveCount = aliveCount + 1
			else
				deadCount = deadCount + 1
				
				-- Handle dead snake
				if not slot.spawning then
					if not slot.deathTime then
						-- Just died - mark death time
						slot.deathTime = currentTime
						if slot.lastPersonality then
							print("💀 AI Snake #" .. i .. " died (" .. slot.lastPersonality .. ")")
						else
							print("💀 AI Snake #" .. i .. " died")
						end
						cleanupSnake(slot)
					elseif currentTime - slot.deathTime >= MIN_SPAWN_DELAY then
						-- Ready to respawn
						print("🔄 Respawning AI Snake #" .. i .. "...")
						task.spawn(function()
							spawnSnake(i)
						end)
					end
				end
			end
		end
		
		-- Debug output every 10 seconds
		if currentTime - lastDebugTime > 10 then
			lastDebugTime = currentTime
			print(string.format("📊 AI Snakes: %d alive, %d dead/respawning", aliveCount, deadCount))
		end
	end
end)

-- === CLEANUP ORPHANED MODELS ===
task.spawn(function()
	while true do
		task.wait(30) -- Check every 30 seconds
		
		local cleaned = 0
		local checked = 0
		
		for _, obj in pairs(Workspace:GetChildren()) do
			if obj.Name:match("AISnakeModel_") and obj:IsA("Model") then
				checked = checked + 1
				
				-- Check if this model belongs to any active snake
				local isActive = false
				for _, slot in pairs(snakeSlots) do
					if slot.snake and slot.snake.Model == obj then
						isActive = true
						break
					end
				end
				
				-- Clean up if not active
				if not isActive then
					pcall(function()
						obj:Destroy()
					end)
					cleaned = cleaned + 1
				end
			end
		end
		
		if cleaned > 0 then
			print(string.format("🧹 Cleaned %d/%d orphaned snake models", cleaned, checked))
		end
	end
end)

-- === PERFORMANCE MONITOR ===
task.spawn(function()
	-- Wait for system to stabilize
	task.wait(30)
	
	while true do
		task.wait(60) -- Check every minute
		
		local totalSegments = 0
		local totalLength = 0
		local personalities = {}
		
		for _, slot in pairs(snakeSlots) do
			if slot.snake and slot.snake._active then
				totalSegments = totalSegments + (slot.snake.CurrentLength or 0)
				totalLength = totalLength + 1
				
				local personality = slot.snake.Personality and slot.snake.Personality.Type or "Unknown"
				personalities[personality] = (personalities[personality] or 0) + 1
			end
		end
		
		if totalLength > 0 then
			print(string.format("📈 Performance: %d total segments across %d snakes (avg: %.1f)", 
				totalSegments, totalLength, totalSegments / totalLength))
			
			-- Print personality distribution
			local personalityStr = ""
			for personality, count in pairs(personalities) do
				personalityStr = personalityStr .. personality .. ": " .. count .. " | "
			end
			print("🧠 Personalities: " .. personalityStr)
		end
	end
end)

print("✅ AI Snake Spawner V3.0 initialized successfully!")