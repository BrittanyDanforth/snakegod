-- AISnake Module: SMOOTH AI MOVEMENT V4.0 - FIXED ERRATIC BEHAVIOR
-- Completely redesigned AI brain for smooth, intelligent movement
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SnakeConfig = require(ReplicatedStorage:WaitForChild("SnakeConfig"))
local OrbUtils = require(ReplicatedStorage:WaitForChild("OrbUtils"))

-- Load the orb pickup module
local AISnakeOrbPickup
pcall(function()
	local module = ReplicatedStorage:FindFirstChild("AISnakeOrbPickup") or game.ServerScriptService:FindFirstChild("AISnakeOrbPickup")
	if module then
		AISnakeOrbPickup = require(module)
	end
end)

-- Load SnakeUpgrades module for upgrade orbs
local SnakeUpgrades
pcall(function()
	local module = ReplicatedStorage:FindFirstChild("SnakeUpgrades")
	if module then
		SnakeUpgrades = require(module)
		-- AI Snakes can now pick up upgrade orbs
	end
end)

local Vector3new = Vector3.new
local CFramenew = CFrame.new
local CFramelookAt = CFrame.lookAt
local mathRad = math.rad
local mathRandom = math.random
local mathAtan2 = math.atan2
local mathPi = math.pi
local mathMin = math.min
local mathMax = math.max
local mathAbs = math.abs
local mathCeil = math.ceil
local mathExp = math.exp
local mathSin = math.sin
local mathCos = math.cos
local mathClamp = math.clamp
local mathFloor = math.floor
local mathSqrt = math.sqrt

local AISnake = {}
AISnake.__index = AISnake

-- === OPTIMIZED SETTINGS ===
local MAX_AI_SNAKES = 15 -- Reduced from 14 for better performance
local SPATIAL_GRID_UPDATE_RATE = 1.0 -- Increased from 0.5 (update less often)
local BRAIN_UPDATES_PER_FRAME = 3 -- Update 3 snakes per frame to prevent freezing
local DEBUG_UPDATE_RATE = 5.0 -- Increased from 2.0 (debug less often)
local AI_HEIGHT = 5
local SEGMENT_UPDATE_SKIP = 2 -- Update every other segment for performance
local LONG_SNAKE_THRESHOLD = 100 -- Snakes longer than this use more aggressive optimization
local VERY_LONG_SNAKE_THRESHOLD = 300 -- Even more optimization for very long snakes
local AI_UPDATE_DISTANCE = 200 -- Only update AI within this distance of players
local SEGMENT_POOL_MAX = 500 -- Increased pool size for better reuse

-- LOD Constants (ENHANCED for progressive visibility like slither.io)
local VISIBILITY_CHECK_INTERVAL = 5 -- Check visibility every N frames
local RENDER_DISTANCE = 1000 -- Maximum render distance
local LOD_DISTANCE_NEAR = 200 -- Full snake visible
local LOD_DISTANCE_MID = 400 -- 70% of snake visible
local LOD_DISTANCE_FAR = 600 -- 40% of snake visible
local LOD_DISTANCE_MINIMAL = 800 -- 20% of snake visible (head + some body)
local BEAM_SYNC_INTERVAL = 3 -- Sync beams with parts every N frames
local FORCE_RENDER_SEGMENTS = 150 -- Always force render first N segments for nearby snakes
local MIN_VISIBLE_SEGMENTS = 10 -- Minimum segments to show even from far away
local MAX_VISIBLE_SEGMENTS = 2000 -- Maximum visible segments at once
local DYNAMIC_SEGMENT_LIMIT = 800 -- Initial physical segment creation limit

-- Progressive visibility percentages based on distance
local VISIBILITY_PERCENTAGES = {
	near = 1.0, -- 100% of snake visible
	mid = 0.7, -- 70% of snake visible
	far = 0.4, -- 40% of snake visible
	minimal = 0.2, -- 20% of snake visible
	veryFar = 0.1 -- 10% of snake visible (at least head + few segments)
}

-- Visual Constants from OptimizedSnakeSystem
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 2 -- Professional glow intensity
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 10 -- Optimal segments
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments
local VISUAL_SMOOTHING_FACTOR = 0.6 -- Higher = smoother transitions

-- Growth Animation Constants
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions
local GROWTH_PULSE_STRENGTH = 0.1 -- How much segments pulse when growing
local GROWTH_WAVE_SPEED = 10 -- Speed of growth wave effect

-- Professional Visual Enhancement Constants
local BEAM_TEXTURE_SPEED = 2 -- Flow animation speed for beams
local PARTICLE_VELOCITY_INHERITANCE = 0.7 -- Natural trailing behavior
local PARTICLE_DRAG = 3 -- Exponential velocity decay for boost effects
local BOOST_PARTICLE_SIZE = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0)
}
local MOBILE_PARTICLE_RATE = 100
local DESKTOP_PARTICLE_RATE = 200

-- Professional Texture Library
local BEAM_TEXTURES = {
	gradient = "rbxasset://textures/ui/LuaChat/9-slice/kit-modal-highlight.png",
	flow = "rbxasset://textures/ui/GuiImagePlaceholder.png",
	energy = "rbxasset://textures/particles/sparkles_main.dds",
	smooth = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
}

AISnake._activeSnakes = {}
AISnake._orbTargets = {}

-- === SPATIAL GRID (unchanged) ===
local SpatialGrid = {}
local gridGeneration = 0
local entityPositionCache = {}
local partSizeCache = {}
do
	local CELL_SIZE = 75
	local grid = {}
	local ground = Workspace:FindFirstChild("SlitherIOGround")
	local mapSize = ground and ground.Size or Vector3new(1000, 10, 1000)
	local minX, minZ = -mapSize.X / 2, -mapSize.Z / 2

	local function getCellCoords(position)
		local x = mathFloor((position.X - minX) / CELL_SIZE)
		local z = mathFloor((position.Z - minZ) / CELL_SIZE)
		return x, z
	end

	function SpatialGrid.Clear()
		grid = {}
	end

	function SpatialGrid.Insert(part, owner, type)
		if not part or not part.Parent then return end
		local x, z = getCellCoords(part.Position)
		if not grid[x] then
			grid[x] = {}
		end
		if not grid[x][z] then
			grid[x][z] = {}
		end
		table.insert(grid[x][z], {part = part, owner = owner, type = type})
	end

	function SpatialGrid.QueryRadius(position, radius)
		local results = {}
		local minX, minZ = getCellCoords(position - Vector3new(radius, 0, radius))
		local maxX, maxZ = getCellCoords(position + Vector3new(radius, 0, radius))

		for x = minX, maxX do
			if grid[x] then
				for z = minZ, maxZ do
					if grid[x][z] then
						for _, entity in ipairs(grid[x][z]) do
							if (entity.part.Position - position).Magnitude <= radius then
								table.insert(results, entity)
							end
						end
					end
				end
			end
		end
		return results
	end
end

-- === SEGMENT POOLING (shared with players) ===
local SegmentPool = {}
local PoolSize = 0
local MAX_POOL_SIZE = 1000 -- Increased pool size
local SEGMENT_PARENT = Workspace:FindFirstChild("AISegmentContainer") or Instance.new("Folder", Workspace)
SEGMENT_PARENT.Name = "AISegmentContainer"

local function resetSegment(segment, config)
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false -- Only head needs touch
	segment.CanQuery = false -- Segments don't need query
	segment.Transparency = 0
	segment.Size = config.SegmentSize
	segment.Material = config.BodyMaterial or Enum.Material.Neon
	segment.Shape = Enum.PartType.Ball
	segment.TopSurface = Enum.SurfaceType.Smooth
	segment.BottomSurface = Enum.SurfaceType.Smooth
	-- Don't set color here - let createSegment handle it
	segment.Name = "AISegment"
	-- Clean up children efficiently
	for _, child in ipairs(segment:GetChildren()) do
		if child:IsA("PointLight") or child:IsA("Attachment") then
			child:Destroy()
		end
	end
end

local function getSegment(config)
	if PoolSize > 0 then
		local segment = SegmentPool[PoolSize]
		SegmentPool[PoolSize] = nil
		PoolSize = PoolSize - 1
		resetSegment(segment, config)
		return segment
	else
		local segment = Instance.new("Part")
		resetSegment(segment, config)
		return segment
	end
end

local function returnSegment(segment)
	if not segment then return end

	-- Clean up all children first
	for _, child in ipairs(segment:GetChildren()) do
		child:Destroy()
	end

	-- If pool is full or segment is problematic, just destroy it
	if PoolSize >= MAX_POOL_SIZE then
		segment:Destroy()
		return
	end

	-- Reset segment properties
	segment.Transparency = 1
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.Anchored = true
	segment.Color = Color3.new()
	segment.Material = Enum.Material.Neon
	segment.Size = Vector3.new(3.5, 3.5, 4)

	-- Return to pool
	segment.Parent = SEGMENT_PARENT
	PoolSize = PoolSize + 1
	SegmentPool[PoolSize] = segment
end

-- === HELPER FUNCTIONS (unchanged) ===
local function getOrCreateSnakeModel(aiId)
	local modelName = "AISnakeModel_" .. tostring(aiId)
	local existing = Workspace:FindFirstChild(modelName)
	if existing and existing:IsA("Model") then
		return existing
	end
	local model = Instance.new("Model")
	model.Name = modelName
	model.Parent = Workspace
	return model
end

-- AI Snake color combinations - using patterns similar to SnakeData
local AISnakeColors = {
	{
		-- Yellow (Classic smooth)
		HeadColor = Color3.fromRGB(255, 255, 102),
		BodyColors = {
			Color3.fromRGB(255, 255, 51),
			Color3.fromRGB(255, 255, 102),
			Color3.fromRGB(255, 255, 153),
			Color3.fromRGB(255, 255, 102),
			Color3.fromRGB(255, 255, 51),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Green (Nature)
		HeadColor = Color3.fromRGB(102, 255, 102),
		BodyColors = {
			Color3.fromRGB(60, 180, 80),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(100, 220, 120),
			Color3.fromRGB(80, 200, 100),
			Color3.fromRGB(60, 180, 80),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Blue (Ocean)
		HeadColor = Color3.fromRGB(102, 178, 255),
		BodyColors = {
			Color3.fromRGB(51, 153, 255),
			Color3.fromRGB(102, 178, 255),
			Color3.fromRGB(153, 204, 255),
			Color3.fromRGB(102, 178, 255),
			Color3.fromRGB(51, 153, 255),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	},
	{
		-- Orange (Sunset)
		HeadColor = Color3.fromRGB(255, 178, 102),
		BodyColors = {
			Color3.fromRGB(255, 153, 51),
			Color3.fromRGB(255, 178, 102),
			Color3.fromRGB(255, 204, 153),
			Color3.fromRGB(255, 178, 102),
			Color3.fromRGB(255, 153, 51),
		},
		HeadMaterial = Enum.Material.Neon,
		BodyMaterial = Enum.Material.Neon
	}
}

local function getRandomAIColor()
	-- 50% yellow, 50% others
	if math.random() < 0.5 then
		return AISnakeColors[1] -- Yellow
	else
		return AISnakeColors[math.random(2, #AISnakeColors)]
	end
end

local function deepCopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs(orig) do
			copy[orig_key] = deepCopy(orig_value)
		end
	else
		copy = orig
	end
	return copy
end

-- === VISUAL CREATION (Enhanced to match OptimizedSnakeSystem) ===
local function createVisualHead(config, parentModel)
	-- HEAD IS NOW SEGMENT 0 - Part of the unified body
	local headPart = Instance.new("Part")
	headPart.Name = "Segment0_Head" -- Match OptimizedSnakeSystem naming
	headPart.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	headPart.Material = Enum.Material.Neon -- Consistent with OptimizedSnakeSystem
	headPart.Color = config.HeadColor
	headPart.Shape = Enum.PartType.Ball
	headPart.CanCollide = false
	headPart.CanTouch = true -- CRITICAL: Enable touch detection for orb collection
	headPart.CanQuery = true -- Enable for raycasts
	headPart.Anchored = true
	headPart.TopSurface = Enum.SurfaceType.Smooth
	headPart.BottomSurface = Enum.SurfaceType.Smooth
	headPart.Transparency = 0 -- Head is visible as first segment
	headPart.Parent = parentModel

	-- Professional head glow matching OptimizedSnakeSystem
	local headLight = Instance.new("PointLight")
	headLight.Name = "Glow"
	headLight.Color = config.HeadColor
	headLight.Brightness = GLOW_INTENSITY
	headLight.Range = GLOW_RANGE_BASE * 1.1 -- Slightly larger than body segments
	headLight.Shadows = false -- Performance optimization
	headLight.Parent = headPart

	-- Professional boost particles (match OptimizedSnakeSystem)
	local boostParticles = Instance.new("ParticleEmitter")
	boostParticles.Name = "BoostParticles"
	boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	boostParticles.Color = ColorSequence.new(config.HeadColor)
	boostParticles.Lifetime = NumberRange.new(0.5, 1)
	boostParticles.Rate = 0 -- Start disabled
	boostParticles.Speed = NumberRange.new(5, 10)
	boostParticles.SpreadAngle = Vector2.new(180, 180)
	boostParticles.VelocityInheritance = PARTICLE_VELOCITY_INHERITANCE
	boostParticles.Drag = PARTICLE_DRAG
	boostParticles.Size = BOOST_PARTICLE_SIZE
	boostParticles.Rotation = NumberRange.new(0, 360)
	boostParticles.RotSpeed = NumberRange.new(-180, 180)
	boostParticles.Enabled = false
	boostParticles.LightEmission = 1
	boostParticles.LightInfluence = 0
	boostParticles.ZOffset = 1
	boostParticles.Parent = headPart

	-- Eyes (smaller, integrated style like OptimizedSnakeSystem - ANCHORED, NOT WELDED)
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.5, 0.5, 0.5)
		eye.Transparency = 0
		eye.CanCollide = false
		eye.Anchored = true -- ANCHORED like OptimizedSnakeSystem
		eye:SetAttribute("AlwaysRender", true)
		eye.Parent = parentModel -- Parent to model, not head

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true -- ANCHORED like OptimizedSnakeSystem
		pupil:SetAttribute("AlwaysRender", true)
		pupil.Parent = parentModel -- Parent to model, not eye

		return eye, pupil
	end

	local leftEye, leftPupil = createEye(-1)
	local rightEye, rightPupil = createEye(1)

	-- Remove selection outline and debug UI - not in OptimizedSnakeSystem

	return {
		head = headPart,
		headLight = headLight,
		boostParticles = boostParticles,
		leftEye = leftEye,
		rightEye = rightEye,
		leftPupil = leftPupil,
		rightPupil = rightPupil,
	}
end

local function createSegment(index, position, color, config, parentModel, currentLength)
	local segment = getSegment(config)
	segment.Name = "AISegment" .. index
	segment.Shape = Enum.PartType.Ball -- Match OptimizedSnakeSystem
	segment.Material = Enum.Material.Neon -- Consistent material like OptimizedSnakeSystem

	-- This is temporary - will be set properly by the snake instance
	segment.Size = Vector3.new(BASE_SIZE, BASE_SIZE, BASE_SIZE)
	segment.Color = color
	segment.CFrame = CFramenew(position)
	segment.Parent = parentModel
	segment.Transparency = 0
	segment.CanCollide = false
	segment.CanTouch = index <= 50 -- Only first 50 segments have collision
	segment.CanQuery = false
	segment.Anchored = true

	segment:SetAttribute("IsSnakeSegment", true)
	segment:SetAttribute("SegmentIndex", index)
	segment:SetAttribute("IsAISnake", true)

	-- Strategic glow placement matching OptimizedSnakeSystem
	local shouldHaveGlow = false
	if index <= GLOW_FALLOFF_START then
		shouldHaveGlow = true -- All segments up to falloff
	elseif index <= 100 then
		shouldHaveGlow = index % 2 == 0 -- Every other segment
	elseif index <= 200 then
		shouldHaveGlow = index % 3 == 0 -- Every third
	else
		shouldHaveGlow = index % 5 == 0 -- Every fifth
	end

	if shouldHaveGlow then
		local light = segment:FindFirstChild("Glow") or Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = color
		light.Brightness = GLOW_INTENSITY * 0.9 -- Slightly dimmer than head
		light.Range = GLOW_RANGE_BASE * (0.9 - (index / (currentLength or 100)) * 0.1)
		light.Shadows = false
		light.Enabled = true
		light.Parent = segment
	else
		-- Remove light if it exists on other segments
		local existingLight = segment:FindFirstChild("Glow")
		if existingLight then
			existingLight:Destroy()
		end
	end

	return segment
end

-- === HELPER FUNCTIONS ===
local function getPlayerLength(player)
	if not player or not player.Character then return 0 end
	local count = 0

	local snakeInstance = _G.PlayerSnakes and _G.PlayerSnakes[player]
	if snakeInstance and snakeInstance.segments then
		return #snakeInstance.segments
	end

	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^Segment") then
			count = count + 1
		end
	end
	return count
end

local function getPlayerVelocity(player)
	if not player or not player.Character then return Vector3new(0, 0, 0) end
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:FindFirstChild("AssemblyLinearVelocity") then
		return rootPart.AssemblyLinearVelocity
	end
	return Vector3new(0, 0, 0)
end

-- Wall avoidance
local WALL_NAMES = {"SlitherIOWall_Left", "SlitherIOWall_Right", "SlitherIOWall_Top", "SlitherIOWall_Bottom"}
local wallParts = {}

task.spawn(function()
	task.wait(0.1)
	for _, wallName in ipairs(WALL_NAMES) do
		local wall = Workspace:FindFirstChild(wallName)
		if wall and wall:IsA("BasePart") then
			table.insert(wallParts, wall)
		end
	end
end)

-- Ground-based boundary detection with safe defaults
local MAP_BOUNDS = {
	minX = -350, -- More conservative defaults
	maxX = 350,
	minZ = -350,
	maxZ = 350
}

-- Function to update bounds based on ground
local function updateMapBounds()
	local ground = Workspace:FindFirstChild("SlitherIOGround")
	if ground and ground:IsA("BasePart") then
		local halfSizeX = ground.Size.X / 2
		local halfSizeZ = ground.Size.Z / 2
		MAP_BOUNDS.minX = ground.Position.X - halfSizeX + 30 -- 30 stud buffer
		MAP_BOUNDS.maxX = ground.Position.X + halfSizeX - 30
		MAP_BOUNDS.minZ = ground.Position.Z - halfSizeZ + 30
		MAP_BOUNDS.maxZ = ground.Position.Z + halfSizeZ - 30
		-- Map bounds updated silently
		return true
	end
	return false
end

-- Initial bounds check
updateMapBounds()

-- Periodic bounds check every 30 seconds
task.spawn(function()
	while true do
		task.wait(30)
		local oldBounds = {minX = MAP_BOUNDS.minX, maxX = MAP_BOUNDS.maxX, minZ = MAP_BOUNDS.minZ, maxZ = MAP_BOUNDS.maxZ}
		if updateMapBounds() then
			-- Check if bounds changed
			if oldBounds.minX ~= MAP_BOUNDS.minX or oldBounds.maxX ~= MAP_BOUNDS.maxX or
				oldBounds.minZ ~= MAP_BOUNDS.minZ or oldBounds.maxZ ~= MAP_BOUNDS.maxZ then
				warn("MAP BOUNDS CHANGED! Old:", oldBounds, "New:", MAP_BOUNDS)
			end
		end
	end
end)

local function getWallAvoidanceVector(headPos)
	local avoidVec = Vector3new(0, 0, 0)
	local avoidStrength = 0

	-- Check ground boundaries first (more reliable than walls)
	local boundaryThreshold = 50
	local strongThreshold = 25

	-- Check X boundaries
	if headPos.X < MAP_BOUNDS.minX + boundaryThreshold then
		local dist = MAP_BOUNDS.minX - headPos.X + boundaryThreshold
		avoidVec = avoidVec + Vector3new(1, 0, 0) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	elseif headPos.X > MAP_BOUNDS.maxX - boundaryThreshold then
		local dist = headPos.X - MAP_BOUNDS.maxX + boundaryThreshold
		avoidVec = avoidVec + Vector3new(-1, 0, 0) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	end

	-- Check Z boundaries
	if headPos.Z < MAP_BOUNDS.minZ + boundaryThreshold then
		local dist = MAP_BOUNDS.minZ - headPos.Z + boundaryThreshold
		avoidVec = avoidVec + Vector3new(0, 0, 1) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	elseif headPos.Z > MAP_BOUNDS.maxZ - boundaryThreshold then
		local dist = headPos.Z - MAP_BOUNDS.maxZ + boundaryThreshold
		avoidVec = avoidVec + Vector3new(0, 0, -1) * (dist / boundaryThreshold)
		avoidStrength = math.max(avoidStrength, dist < strongThreshold and 1 or 0.5)
	end

	-- If we have boundary avoidance, use it
	if avoidStrength > 0 then
		return avoidVec.Unit * avoidStrength * 2, avoidStrength
	end

	-- Fall back to wall detection if no boundary issues
	for i = 1, #wallParts do
		local wall = wallParts[i]
		if wall and wall.Parent then
			local wallPos = wall.Position
			local closestPointOnWall = Vector3new(
				mathClamp(headPos.X, wallPos.X - wall.Size.X/2, wallPos.X + wall.Size.X/2),
				headPos.Y,
				mathClamp(headPos.Z, wallPos.Z - wall.Size.Z/2, wallPos.Z + wall.Size.Z/2)
			)
			local dir = headPos - closestPointOnWall
			local dist = dir.Magnitude
			local threshold = 25
			if dist < threshold then
				local strength = (threshold - dist) / threshold
				strength = strength * strength
				avoidVec = avoidVec + dir.Unit * strength
				avoidStrength = avoidStrength + strength
			end
		end
	end
	if avoidStrength > 0 then
		return avoidVec.Unit, avoidStrength
	end
	return nil, 0
end

-- === ENHANCED AI PERSONALITIES - STABLE & DISTINCT ===
AISnake.PersonalityTypes = {
	"Collector", "Explorer", "Predator", "Opportunist", "Farmer", "Raider", "Guardian", "Nomad"
}

AISnake.PersonalityDefinitions = {
	-- COMPLETELY REVAMPED PERSONALITIES WITH NATURAL MOVEMENT
	Collector = {
		Type = "Collector",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = true,
		SpeedMultiplier = 1.05,
		TurnBias = 0.015, -- Very smooth turns
		BoostChance = 0.04,
		CombatRadius = 20,
		RandomTurnInterval = 8.0, -- Long straight paths
		OrbSeekRadius = 300, -- Excellent orb vision
		Description = "Efficient orb collector - avoids all fights",
		FleeThreshold = 10,
		AggressionLevel = 0.0,
		PatrolRadius = 500, -- Uses entire map
		MovementPattern = "spiral", -- New: Spiral outward pattern
		PreferEdgeOrbs = true, -- Collects orbs near edges
		MinStraightDistance = 100, -- Move at least 100 studs before turning
	},
	Explorer = {
		Type = "Explorer",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.15,
		TurnBias = 0.02,
		BoostChance = 0.05,
		CombatRadius = 30,
		RandomTurnInterval = 12.0, -- Very long paths
		OrbSeekRadius = 200,
		Description = "Map explorer - covers maximum ground",
		FleeThreshold = 15,
		AggressionLevel = 0.1,
		PatrolRadius = 600, -- Full map coverage
		MovementPattern = "zigzag", -- Zigzag across map
		ExplorationSectors = 8, -- Divides map into sectors
		CurrentSector = 1,
		MinStraightDistance = 150,
	},
	Predator = {
		Type = "Predator",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.2,
		TurnBias = 0.025,
		BoostChance = 0.08,
		CombatRadius = 60,
		RandomTurnInterval = 6.0,
		OrbSeekRadius = 150,
		Description = "Smart hunter - ambushes smaller snakes",
		FleeThreshold = 20,
		AggressionLevel = 0.8,
		PatrolRadius = 300,
		MovementPattern = "patrol", -- Patrols hunting grounds
		AmbushPoints = {}, -- Will be populated with good ambush spots
		PreferCenterHunting = true,
		MinStraightDistance = 80,
	},
	Opportunist = {
		Type = "Opportunist",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.18,
		TurnBias = 0.03,
		BoostChance = 0.07,
		CombatRadius = 50,
		RandomTurnInterval = 7.0,
		OrbSeekRadius = 180,
		Description = "Adaptive - switches between hunting and collecting",
		FleeThreshold = 15,
		AggressionLevel = 0.6,
		PatrolRadius = 350,
		MovementPattern = "adaptive", -- Changes based on situation
		OpportunityRadius = 100, -- Looks for opportunities
		MinStraightDistance = 90,
	},
	Farmer = {
		Type = "Farmer",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = true,
		SpeedMultiplier = 1.0, -- Slow and steady
		TurnBias = 0.01, -- Very smooth
		BoostChance = 0.02, -- Rarely boosts
		CombatRadius = 15,
		RandomTurnInterval = 10.0,
		OrbSeekRadius = 400, -- Sees orbs from far
		Description = "Peaceful farmer - systematic orb collection",
		FleeThreshold = 5,
		AggressionLevel = 0.0,
		PatrolRadius = 250,
		MovementPattern = "grid", -- Moves in grid pattern
		GridSize = 100, -- Grid square size
		CurrentGridX = 0,
		CurrentGridZ = 0,
		MinStraightDistance = 120,
	},
	Raider = {
		Type = "Raider",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.25,
		TurnBias = 0.04,
		BoostChance = 0.1,
		CombatRadius = 45,
		RandomTurnInterval = 5.0,
		OrbSeekRadius = 120,
		Description = "Aggressive raider - hits and runs",
		FleeThreshold = 25,
		AggressionLevel = 0.9,
		PatrolRadius = 400,
		MovementPattern = "hitandrun", -- Attack then retreat
		RaidCooldown = 10, -- Seconds between raids
		LastRaidTime = 0,
		MinStraightDistance = 70,
	},
	Guardian = {
		Type = "Guardian",
		TargetPlayers = true,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.1,
		TurnBias = 0.02,
		BoostChance = 0.05,
		CombatRadius = 70,
		RandomTurnInterval = 8.0,
		OrbSeekRadius = 160,
		Description = "Area guardian - protects territory",
		FleeThreshold = 30,
		AggressionLevel = 0.5,
		PatrolRadius = 200,
		MovementPattern = "circular", -- Circles territory
		TerritoryCenter = Vector3.new(0, 0, 0),
		TerritoryRadius = 150,
		PatrolAngle = 0,
		MinStraightDistance = 60,
	},
	Nomad = {
		Type = "Nomad",
		TargetPlayers = false,
		TargetOrbs = true,
		AvoidOthers = false,
		SpeedMultiplier = 1.12,
		TurnBias = 0.025,
		BoostChance = 0.06,
		CombatRadius = 35,
		RandomTurnInterval = 15.0, -- Very long journeys
		OrbSeekRadius = 220,
		Description = "Wandering nomad - never stays in one place",
		FleeThreshold = 20,
		AggressionLevel = 0.3,
		PatrolRadius = 700, -- Entire map
		MovementPattern = "wander", -- True random wandering
		WanderTargets = {}, -- Random points to visit
		CurrentWanderTarget = 1,
		MinStraightDistance = 200, -- Long straight paths
	},
}

-- === AI METHODS ===
function AISnake:findBestOrb()
	-- ENHANCED: Increase orb seek radius based on personality
	local baseRadius = self.Personality.OrbSeekRadius or 50
	local minDist = baseRadius * 1.5 -- 50% more range for better orb finding
	local nearest = nil
	local headPos = self.HeadParts and self.HeadParts.head and self.HeadParts.head.Position or self.Position

	-- First check spatial grid for regular orbs
	local nearbyEntities = SpatialGrid.QueryRadius(headPos, minDist)

	-- Prioritize untargeted orbs
	local targetedOrbs = {}
	for ai, orb in pairs(AISnake._orbTargets) do
		if ai ~= self and orb and orb.Parent then
			targetedOrbs[orb] = true
		end
	end

	-- PRIORITIZE UPGRADE ORBS (check OrbFolder directly)
	local orbFolder = Workspace:FindFirstChild("OrbFolder")
	if orbFolder then
		for _, orb in pairs(orbFolder:GetChildren()) do
			if orb:IsA("BasePart") and orb.Name == "UpgradeOrb" and not targetedOrbs[orb] then
				local dist = (orb.Position - headPos).Magnitude
				if dist < minDist then
					minDist = dist
					nearest = orb
				end
			end
		end
	end

	-- If no upgrade orbs, check regular orbs from spatial grid
	if not nearest and #nearbyEntities > 0 then
		for _, entity in ipairs(nearbyEntities) do
			if entity.type == "ORB" and not targetedOrbs[entity.part] then
				local dist = (entity.part.Position - headPos).Magnitude
				if dist < minDist then
					minDist = dist
					nearest = entity.part
				end
			end
		end

		-- If no untargeted orbs, allow targeting of any orb
		if not nearest then
			for _, entity in ipairs(nearbyEntities) do
				if entity.type == "ORB" then
					local dist = (entity.part.Position - headPos).Magnitude
					if dist < minDist then
						minDist = dist
						nearest = entity.part
					end
				end
			end
		end
	end

	return nearest, minDist
end

function AISnake:findNearestSnakeHead()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return nil, math.huge end
	local myPos = myHead.Position
	local minDist = math.huge
	local nearest = nil

	local nearbyEntities = SpatialGrid.QueryRadius(myPos, self.Personality.CombatRadius or 60)

	for _, entity in ipairs(nearbyEntities) do
		if entity.owner ~= self and (entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD") then
			local dist = (entity.part.Position - myPos).Magnitude
			if dist < minDist then
				minDist = dist
				if entity.type == "AI_HEAD" then
					nearest = {part = entity.part, isPlayer = false, snake = entity.owner}
				else
					nearest = {part = entity.part, isPlayer = true, player = entity.owner}
				end
			end
		end
	end
	return nearest, minDist
end

function AISnake:findNearbyThreats()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return {} end
	local myPos = myHead.Position
	local threats = {}

	local threatRadius = 80 -- INCREASED from 60
	local nearbyEntities = SpatialGrid.QueryRadius(myPos, threatRadius)

	for _, entity in ipairs(nearbyEntities) do
		if entity.owner ~= self and (entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD") then
			local dist = (entity.part.Position - myPos).Magnitude
			local enemyLength = 0

			if entity.type == "AI_HEAD" then
				enemyLength = entity.owner.CurrentLength or 0
			else
				enemyLength = getPlayerLength(entity.owner)
			end

			local lengthDiff = enemyLength - self.CurrentLength
			local isThreat = false

			-- More balanced threat detection
			if lengthDiff > 20 or (dist < 20 and lengthDiff > 5) then
				isThreat = true
			end

			if not isThreat and dist < 30 and lengthDiff > 15 then
				local enemyVel = Vector3new(0, 0, 0)
				if entity.type == "PLAYER_HEAD" then
					enemyVel = getPlayerVelocity(entity.owner)
				end
				local toUs = (myPos - entity.part.Position).Unit
				local facingUs = enemyVel.Magnitude > 0.1 and enemyVel.Unit:Dot(toUs) > 0.8
				if facingUs then
					isThreat = true
				end
			end

			if isThreat then
				local threatLevel = mathMax(lengthDiff + 10, 5) / mathMax(dist, 1)
				table.insert(threats, {
					part = entity.part,
					position = entity.part.Position, -- Add position field for convenience
					isPlayer = entity.type == "PLAYER_HEAD",
					owner = entity.owner,
					distance = dist,
					threatLevel = threatLevel,
					lengthDiff = lengthDiff
				})
			end
		end
	end

	table.sort(threats, function(a, b) return a.threatLevel > b.threatLevel end)
	return threats
end

function AISnake:startBoost(duration)
	local now = tick()
	duration = duration or 1.5

	if self.Boosting and self.BoostEndTime > now + duration then
		return
	end

	self.Boosting = true
	self.IsBoosting = true
	self.BoostEndTime = now + duration
	self.BoostCooldown = self.BoostEndTime + mathRandom(15, 30) / 10 -- INCREASED cooldown

	-- Enable boost particles if they exist
	if self.HeadParts and self.HeadParts.boostParticles then
		self.HeadParts.boostParticles.Enabled = true
		-- Adjust particle rate based on mobile/desktop
		local isMobile = game:GetService("UserInputService").TouchEnabled
		self.HeadParts.boostParticles.Rate = isMobile and 100 or 200

		-- Disable particles when boost ends
		task.delay(duration, function()
			if self.HeadParts and self.HeadParts.boostParticles then
				self.HeadParts.boostParticles.Enabled = false
			end
		end)
	end
end

-- FIXED: Much smoother flee logic
function AISnake:getFleeVector()
	local myHead = self.HeadParts and self.HeadParts.head
	if not myHead then return Vector3new(0, 0, 1) end

	local headPos = myHead.Position
	local threats = self:findNearbyThreats()
	local wallVec, wallStrength = getWallAvoidanceVector(headPos)

	-- REDUCED boost frequency
	if #threats > 0 and not self.Boosting and mathRandom() < 0.3 then
		local closestThreat = threats[1]
		local boostDuration = 1.0

		if closestThreat.distance < 15 and closestThreat.lengthDiff > 30 then
			boostDuration = 1.5
		end

		self:startBoost(boostDuration)
	end

	local fleeDir = nil

	if #threats > 0 then
		-- SIMPLIFIED flee direction calculation
		local totalThreatVector = Vector3new(0, 0, 0)
		local totalWeight = 0

		for _, threat in ipairs(threats) do
			local threatPos = threat.part.Position
			local awayFromThreat = (headPos - threatPos).Unit
			local weight = 1 / mathMax(threat.distance, 1)
			totalThreatVector = totalThreatVector + awayFromThreat * weight
			totalWeight = totalWeight + weight
		end

		if totalWeight > 0 then
			fleeDir = (totalThreatVector / totalWeight).Unit
		end
	end

	-- Wall avoidance
	if wallVec and wallStrength > 0.2 then
		if fleeDir then
			fleeDir = (fleeDir + wallVec.Unit * 2).Unit
		else
			fleeDir = wallVec.Unit
		end
	end

	-- Default behavior - prefer center when fleeing
	if not fleeDir then
		local mapCenter = Vector3new(0, headPos.Y, 0)
		local toCenter = (mapCenter - headPos)
		local distFromCenter = toCenter.Magnitude

		if distFromCenter > 150 then
			-- Too far - flee toward center
			fleeDir = toCenter.Unit
		else
			-- Random direction with MORE center bias
			local randomAngle = mathRandom() * 2 * mathPi
			local randomDir = Vector3new(mathSin(randomAngle), 0, mathCos(randomAngle))
			if distFromCenter > 100 then
				fleeDir = (randomDir + toCenter.Unit * 0.5).Unit
			elseif distFromCenter > 60 then
				fleeDir = (randomDir + toCenter.Unit * 0.3).Unit
			else
				fleeDir = randomDir
			end
		end
	end

	-- Only add MINIMAL center bias when VERY far from center
	local mapCenter = Vector3new(0, headPos.Y, 0)
	local distFromCenter = (mapCenter - headPos).Magnitude
	if distFromCenter > 400 and fleeDir then -- Increased from 180
		local toCenter = (mapCenter - headPos).Unit
		fleeDir = (fleeDir + toCenter * 0.1).Unit -- Reduced from 0.4
	end

	return fleeDir
end

-- === HELPER: Check if path to target is safe ===
function AISnake:isPathSafe(targetPos, checkDistance)
	local myHead = self.HeadParts.head
	if not myHead then return false end

	local myPos = myHead.Position
	local toTarget = targetPos - myPos
	local distance = toTarget.Magnitude

	if distance < 0.1 then return true end

	local direction = toTarget.Unit
	local checkDist = mathMin(distance, checkDistance or 50)
	local stepSize = 5

	-- Check points along the path
	for d = stepSize, checkDist, stepSize do
		local checkPos = myPos + direction * d

		-- Check for other snakes at this position
		local nearbyEntities = SpatialGrid.QueryRadius(checkPos, 8)
		for _, entity in ipairs(nearbyEntities) do
			if entity.type == "AI_SEGMENT" or entity.type == "PLAYER_SEGMENT" then
				-- Check if it's not our own segment
				if entity.owner ~= self then
					-- This path crosses another snake!
					return false
				end
			elseif entity.type == "AI_HEAD" or entity.type == "PLAYER_HEAD" then
				if entity.owner ~= self then
					-- Calculate if we'd collide
					local theirVel = entity.part.AssemblyLinearVelocity or Vector3.zero
					local timeToReach = d / self.Speed
					local theirFuturePos = entity.part.Position + theirVel * timeToReach

					if (checkPos - theirFuturePos).Magnitude < 10 then
						-- Collision likely!
						return false
					end
				end
			end
		end
	end

	return true
end

-- === HELPER: Get smart flee direction ===
function AISnake:getSmartFleeDirection(threats)
	-- Safety check for head
	if not self.HeadParts or not self.HeadParts.head then
		return Vector3new(mathRandom(-1, 1), 0, mathRandom(-1, 1)).Unit
	end

	local myPos = self.HeadParts.head.Position

	-- Calculate danger zones from all threats
	local dangerVectors = {}
	for _, threat in ipairs(threats) do
		-- Safety check
		if threat.part and threat.part.Parent then
			local threatPos = threat.part.Position
			local awayFromThreat = (myPos - threatPos).Unit
			local weight = 1 / mathMax(threat.distance, 5) -- Closer = more weight

			-- Extra weight for bigger snakes
			if threat.lengthDiff > 20 then
				weight = weight * 2
			end

			table.insert(dangerVectors, {
				direction = awayFromThreat,
				weight = weight
			})
		end
	end

	-- Combine all danger vectors
	local fleeDir = Vector3.zero
	local totalWeight = 0

	for _, danger in ipairs(dangerVectors) do
		fleeDir = fleeDir + danger.direction * danger.weight
		totalWeight = totalWeight + danger.weight
	end

	-- Add bias towards center if far from it
	local toCenter = Vector3new(0, myPos.Y, 0) - myPos
	local distFromCenter = toCenter.Magnitude
	if distFromCenter > 200 then
		local centerWeight = (distFromCenter - 200) / 100
		fleeDir = fleeDir + toCenter.Unit * centerWeight
		totalWeight = totalWeight + centerWeight
	end

	if totalWeight > 0 then
		fleeDir = (fleeDir / totalWeight).Unit

		-- Check if flee direction is safe
		if not self:isPathSafe(myPos + fleeDir * 30, 30) then
			-- Try perpendicular directions
			local perpDir1 = Vector3new(-fleeDir.Z, 0, fleeDir.X)
			local perpDir2 = Vector3new(fleeDir.Z, 0, -fleeDir.X)

			if self:isPathSafe(myPos + perpDir1 * 30, 30) then
				fleeDir = perpDir1
			elseif self:isPathSafe(myPos + perpDir2 * 30, 30) then
				fleeDir = perpDir2
			end
		end

		return fleeDir
	end

	-- Default: flee towards center
	return toCenter.Unit
end

-- === MUCH SMARTER AI BRAIN ===
function AISnake:_determineAction()
	local headPos = self.HeadParts.head.Position
	local p = self.Personality
	local now = tick()
	local state = "WANDER"
	local steer = self.Direction

	-- Clean up expired states
	if self.Avoiding and now > self.AvoidExpire then
		self.Avoiding = false
		self.FleeReason = ""
	end
	if self.isConfident and now > self.confidenceEndTime then
		self.isConfident = false
		if self.HeadParts and self.HeadParts.headOutline then
			self.HeadParts.headOutline.Color3 = Color3.fromRGB(255, 255, 255)
			self.HeadParts.headOutline.LineThickness = 0.1
			self.HeadParts.headOutline.Transparency = 1
		end
	end
	if self.TargetOrb and (not self.TargetOrb.Parent or now > self.TargetOrbExpire) then
		self.TargetOrb = nil
		AISnake._orbTargets[self] = nil
	end
	if self.TargetSnake and (not self.TargetSnake.part or not self.TargetSnake.part.Parent) then
		self.TargetSnake = nil
		self.trapPhase = 0
		self.isAmbushing = false
	end

	-- Priority 0: BOUNDARY AVOIDANCE (HIGHEST PRIORITY)
	local boundaryBuffer = 80
	local strongBuffer = 40
	local edgeSteer = nil

	-- Check X boundaries
	if headPos.X > MAP_BOUNDS.maxX - boundaryBuffer then
		local strength = 1 - (MAP_BOUNDS.maxX - headPos.X) / boundaryBuffer
		edgeSteer = Vector3new(-1, 0, 0) * strength
	elseif headPos.X < MAP_BOUNDS.minX + boundaryBuffer then
		local strength = 1 - (headPos.X - MAP_BOUNDS.minX) / boundaryBuffer
		edgeSteer = Vector3new(1, 0, 0) * strength
	end

	-- Check Z boundaries
	if headPos.Z > MAP_BOUNDS.maxZ - boundaryBuffer then
		local strength = 1 - (MAP_BOUNDS.maxZ - headPos.Z) / boundaryBuffer
		local zSteer = Vector3new(0, 0, -1) * strength
		edgeSteer = edgeSteer and (edgeSteer + zSteer).Unit or zSteer
	elseif headPos.Z < MAP_BOUNDS.minZ + boundaryBuffer then
		local strength = 1 - (headPos.Z - MAP_BOUNDS.minZ) / boundaryBuffer
		local zSteer = Vector3new(0, 0, 1) * strength
		edgeSteer = edgeSteer and (edgeSteer + zSteer).Unit or zSteer
	end

	-- Strong boundary avoidance overrides everything
	if edgeSteer and (
		headPos.X > MAP_BOUNDS.maxX - strongBuffer or
			headPos.X < MAP_BOUNDS.minX + strongBuffer or
			headPos.Z > MAP_BOUNDS.maxZ - strongBuffer or
			headPos.Z < MAP_BOUNDS.minZ + strongBuffer
		) then
		-- Add some randomness to prevent getting stuck in corners
		local randomAngle = mathRandom(-30, 30) * mathPi / 180
		local cosA = mathCos(randomAngle)
		local sinA = mathSin(randomAngle)
		local rotatedSteer = Vector3new(
			edgeSteer.X * cosA - edgeSteer.Z * sinA,
			0,
			edgeSteer.X * sinA + edgeSteer.Z * cosA
		)

		self.TargetSnake = nil
		self.TargetOrb = nil
		return "AVOID_BOUNDARY", rotatedSteer.Unit
	end

	-- Priority 1: Wall avoidance
	local wallVec, wallStrength = getWallAvoidanceVector(headPos)
	if wallVec and wallStrength > 0.3 then
		self.TargetSnake = nil
		return "AVOID_WALL", wallVec.Unit
	end

	-- Priority 2: COLLISION AVOIDANCE (NEW!)
	-- Check for imminent collisions in our current path
	local lookAheadDist = self.Speed * 1.5 -- Look 1.5 seconds ahead
	local futurePos = headPos + self.Direction * lookAheadDist

	local nearbyDanger = SpatialGrid.QueryRadius(futurePos, 15)
	local collisionThreat = nil
	local minCollisionTime = math.huge

	for _, entity in ipairs(nearbyDanger) do
		if entity.owner ~= self and (entity.type:match("HEAD") or entity.type:match("SEGMENT")) then
			-- Calculate time to collision
			local theirPos = entity.part.Position
			local relPos = theirPos - headPos
			local relVel = self.Direction * self.Speed

			if entity.part.AssemblyLinearVelocity then
				relVel = relVel - entity.part.AssemblyLinearVelocity
			end

			local timeToCollision = relPos:Dot(relVel) / relVel:Dot(relVel)

			if timeToCollision > 0 and timeToCollision < 2 then
				local collisionPos = headPos + self.Direction * self.Speed * timeToCollision
				local theirFuturePos = theirPos

				if entity.part.AssemblyLinearVelocity then
					theirFuturePos = theirPos + entity.part.AssemblyLinearVelocity * timeToCollision
				end

				local collisionDist = (collisionPos - theirFuturePos).Magnitude

				if collisionDist < 8 and timeToCollision < minCollisionTime then
					minCollisionTime = timeToCollision
					collisionThreat = entity
				end
			end
		end
	end

	if collisionThreat and minCollisionTime < 1 then
		-- EMERGENCY AVOIDANCE!
		local threatPos = collisionThreat.part.Position
		local avoidDir = (headPos - threatPos).Unit

		-- Try to go perpendicular to avoid head-on collision
		local perpDir = Vector3new(-avoidDir.Z, 0, avoidDir.X)

		-- Choose direction based on which side is clearer
		local leftClear = self:isPathSafe(headPos + perpDir * 20, 20)
		local rightClear = self:isPathSafe(headPos - perpDir * 20, 20)

		if leftClear and not rightClear then
			steer = perpDir
		elseif rightClear and not leftClear then
			steer = -perpDir
		else
			-- Both or neither clear, just avoid directly
			steer = avoidDir
		end

		self.TargetOrb = nil -- Cancel orb seeking
		return "COLLISION_AVOID", steer
	end

	-- Priority 3: Threat assessment (SMARTER)
	local threats = self:findNearbyThreats()
	local shouldFlee = false
	local fleeReason = ""

	if #threats > 0 then
		local closestThreat = threats[1]

		-- More nuanced fleeing decisions
		if closestThreat.distance < 15 and closestThreat.lengthDiff > 5 then
			shouldFlee = true
			fleeReason = "immediate_danger"
		elseif closestThreat.distance < 25 and closestThreat.lengthDiff > 15 then
			shouldFlee = true
			fleeReason = "bigger_snake_nearby"
		elseif closestThreat.lengthDiff > 30 and closestThreat.distance < 40 then
			shouldFlee = true
			fleeReason = "giant_enemy"
		elseif #threats >= 2 and closestThreat.distance < 30 then
			shouldFlee = true
			fleeReason = "multiple_threats"
		elseif p.Type == "Coward" and closestThreat.lengthDiff > 0 and closestThreat.distance < 35 then
			shouldFlee = true
			fleeReason = "coward_instinct"
		end

		-- Even aggressive types flee from much bigger snakes
		if shouldFlee and (p.Type == "Aggressor" or p.Type == "Hunter") then
			if closestThreat.lengthDiff < 10 and closestThreat.distance > 20 then
				shouldFlee = false
			end
		end
	end

	if shouldFlee or self.Avoiding then
		self.TargetSnake = nil
		self.TargetOrb = nil -- Cancel orb seeking when fleeing

		local fleeDir = self:getSmartFleeDirection(threats)

		self.Avoiding = true
		self.AvoidDir = fleeDir
		self.AvoidExpire = now + 2.5
		if shouldFlee then self.FleeReason = fleeReason end
		return "FLEE", fleeDir
	end

	-- Priority 3.5: Smart orb seeking (HIGHER PRIORITY)
	if p.TargetOrbs and not shouldFlee then -- Don't seek orbs when fleeing
		-- Always look for better orbs
		local orb, dist = self:findBestOrb()

		-- More aggressive orb targeting
		if orb and dist < p.OrbSeekRadius * 2 then -- Double radius for targeting
			-- Switch to closer orb if significantly better
			if self.TargetOrb and self.TargetOrb.Parent then
				local currentDist = (self.TargetOrb.Position - headPos).Magnitude
				if dist < currentDist * 0.7 then -- Switch if 30% closer
					self.TargetOrb = orb
					self.TargetOrbExpire = now + mathRandom(30, 60) / 10
					AISnake._orbTargets[self] = orb
				end
			else
				-- No current target, take this one
				self.TargetOrb = orb
				self.TargetOrbExpire = now + mathRandom(30, 60) / 10
				AISnake._orbTargets[self] = orb
			end
		end

		if self.TargetOrb and self.TargetOrb.Parent then
			state = "SEEK_ORB"
			local toOrb = self.TargetOrb.Position - headPos
			local orbDist = toOrb.Magnitude

			-- More direct orb approach
			if orbDist < 50 then -- Increased from 30
				steer = toOrb.Unit
				-- Boost when close to orb for faster collection
				if orbDist < 20 and not self.Boosting and mathRandom() < 0.3 then
					self:startBoost(0.5) -- Short boost to grab orb
				end
			else
				steer = toOrb.Unit
			end

			-- Clear any combat targets when seeking orbs
			self.TargetSnake = nil

			-- Return early to prioritize orb collection
			return state, steer
		end
	end

	-- Priority 5: Advanced Movement Patterns
	if state == "WANDER" then
		-- Initialize movement tracking
		if not self._lastStraightDistance then
			self._lastStraightDistance = 0
			self._lastTurnPosition = headPos
		end

		-- Calculate distance traveled since last turn
		local distanceSinceTurn = (headPos - self._lastTurnPosition).Magnitude

		-- Check minimum straight distance requirement
		local minStraight = p.MinStraightDistance or 100

		-- Movement pattern based on personality
		local movementPattern = p.MovementPattern or "wander"

		if movementPattern == "spiral" then
			-- Spiral outward pattern for Collectors
			if not self._spiralAngle then self._spiralAngle = 0 end
			if not self._spiralRadius then self._spiralRadius = 50 end

			if distanceSinceTurn > minStraight then
				self._spiralAngle = self._spiralAngle + mathPi / 4 -- 45 degree turns
				self._spiralRadius = mathMin(self._spiralRadius + 20, 400)
				if self._spiralRadius >= 400 then
					self._spiralRadius = 50 -- Reset spiral
				end
				local targetX = mathCos(self._spiralAngle) * self._spiralRadius
				local targetZ = mathSin(self._spiralAngle) * self._spiralRadius
				steer = (Vector3new(targetX, headPos.Y, targetZ) - headPos).Unit
				self._lastTurnPosition = headPos
			else
				-- Continue straight
				steer = self.Direction
			end

		elseif movementPattern == "zigzag" then
			-- Zigzag pattern for Explorers
			if not self._zigzagDirection then self._zigzagDirection = 1 end

			if distanceSinceTurn > minStraight then
				-- Alternate between left and right turns
				self._zigzagDirection = -self._zigzagDirection
				local turnAngle = self.TargetYaw + (mathPi / 6) * self._zigzagDirection -- 30 degree turns
				steer = Vector3new(mathSin(turnAngle), 0, mathCos(turnAngle))
				self.TargetYaw = turnAngle
				self._lastTurnPosition = headPos
			else
				steer = self.Direction
			end

		elseif movementPattern == "grid" then
			-- Grid pattern for Farmers
			local gridSize = p.GridSize or 100
			if not self._gridDirection then self._gridDirection = 0 end

			if distanceSinceTurn > gridSize then
				-- Turn 90 degrees
				self._gridDirection = (self._gridDirection + 1) % 4
				local angles = {0, mathPi/2, mathPi, -mathPi/2}
				self.TargetYaw = angles[self._gridDirection + 1]
				steer = Vector3new(mathSin(self.TargetYaw), 0, mathCos(self.TargetYaw))
				self._lastTurnPosition = headPos
			else
				steer = self.Direction
			end

		elseif movementPattern == "circular" then
			-- Circular patrol for Guardians
			if not p.PatrolAngle then p.PatrolAngle = 0 end

			-- Circle around territory
			p.PatrolAngle = p.PatrolAngle + 0.02 -- Slow rotation
			local radius = p.TerritoryRadius or 150
			local center = p.TerritoryCenter
			local targetX = center.X + mathCos(p.PatrolAngle) * radius
			local targetZ = center.Z + mathSin(p.PatrolAngle) * radius
			local targetPos = Vector3new(targetX, headPos.Y, targetZ)
			steer = (targetPos - headPos).Unit

		else
			-- Default wandering with minimum straight distance
			if (now - (self.LastTurn or 0) > p.RandomTurnInterval) and distanceSinceTurn > minStraight then
				-- Only turn after traveling minimum distance
				local maxTurn = 30
				local turnAmount = mathRandom(-maxTurn, maxTurn)

				-- Prevent 180 degree turns
				if mathAbs(turnAmount) > 90 then
					turnAmount = turnAmount * 0.3
				end

				self.TargetYaw = self.TargetYaw + mathRad(turnAmount)
				self.LastTurn = now
				self._lastTurnPosition = headPos

				steer = Vector3new(mathSin(self.TargetYaw), 0, mathCos(self.TargetYaw))
			else
				-- Continue straight
				steer = self.Direction
			end
		end

		-- Boundary avoidance (keep from edges)
		local edgeBuffer = 100
		if headPos.X > MAP_BOUNDS.maxX - edgeBuffer then
			steer = steer + Vector3new(-1, 0, 0)
			steer = steer.Unit
		elseif headPos.X < MAP_BOUNDS.minX + edgeBuffer then
			steer = steer + Vector3new(1, 0, 0)
			steer = steer.Unit
		end
		if headPos.Z > MAP_BOUNDS.maxZ - edgeBuffer then
			steer = steer + Vector3new(0, 0, -1)
			steer = steer.Unit
		elseif headPos.Z < MAP_BOUNDS.minZ + edgeBuffer then
			steer = steer + Vector3new(0, 0, 1)
			steer = steer.Unit
		end
	end

	return state, steer
end

function AISnake:updateBrain()
	if not self._active or not self.HeadParts or not self.HeadParts.head or not self.HeadParts.head.Parent then
		return
	end

	-- Update brain tick for debugging
	self._lastBrainUpdate = tick()

	local state, steer = self:_determineAction()
	self.State = state
	self.SteerDirection = steer
end

-- === AI CONSTRUCTOR ===
function AISnake.new(startPosition, preservedPersonalityType)
	if #AISnake._activeSnakes >= MAX_AI_SNAKES then
		print("AI Snake limit reached:", MAX_AI_SNAKES)
		return nil
	end

	local self = setmetatable({}, AISnake)

	-- Get random AI color FIRST (50% yellow, 50% others)
	local colorData = getRandomAIColor()

	-- Deep copy config and immediately apply colors
	self.Config = deepCopy(SnakeConfig)
	self.Config.HeadColor = colorData.HeadColor
	self.Config.BodyColors = colorData.BodyColors
	self.Config.HeadMaterial = colorData.HeadMaterial
	self.Config.BodyMaterial = colorData.BodyMaterial

	-- Update map bounds if needed (in case map was created after script started)
	updateMapBounds()

	self.Position = startPosition or Vector3new(0, 5, 0)
	self.Direction = Vector3new(0, 0, 1)

	-- Use AI-specific settings if available
	local aiConfig = self.Config.AI or {}
	self.Speed = aiConfig.BaseSpeed or self.Config.BaseSpeed or 10
	self.NormalSpeed = aiConfig.BaseSpeed or self.Config.BaseSpeed or 10
	self.BoostSpeed = aiConfig.BoostSpeed or self.Config.BoostSpeed or 24
	self.TurnSpeed = aiConfig.TurnSpeed or self.Config.TurnSpeed or 1.8

	self.RandomTurnInterval = 1.5
	self.LastTurn = tick()
	self.TargetYaw = 0
	self.CurrentYaw = 0
	self.LastDirection = self.Direction -- Track momentum
	self.DirectionChangeTime = 0

	self.FollowSpeed = self.Config.FollowSpeed or 0.95
	self.BoostFollowSpeed = self.Config.BoostFollowSpeed or 0.98
	self.SegmentSpacing = self.Config.SegmentSpacing or 2.2
	self.IsBoosting = false

	self.TargetOrb = nil
	self.TargetOrbExpire = 0

	self.State = "WANDER"
	self.SteerDirection = self.Direction
	self.Boosting = false
	self.BoostEndTime = 0
	self.BoostCooldown = 0
	self.TargetSnake = nil
	self.Avoiding = false
	self.AvoidExpire = 0
	self.AvoidDir = nil
	self.FleeReason = ""

	self.isConfident = false
	self.confidenceEndTime = 0
	self.circleAngle = mathRandom() * 2 * mathPi
	self.killCount = 0
	self.lastKillTime = 0

	-- Use preserved personality or assign random one
	local pType
	if preservedPersonalityType and AISnake.PersonalityDefinitions[preservedPersonalityType] then
		pType = preservedPersonalityType
		print("🧠 Restoring personality:", pType)
	else
		pType = AISnake.PersonalityTypes[mathRandom(1, #AISnake.PersonalityTypes)]
		print("🎲 Assigning new personality:", pType)
	end
	self.Personality = deepCopy(AISnake.PersonalityDefinitions[pType])
	self._personalityType = pType

	-- Set up Guardian territory if needed
	if self.Personality.Type == "Guardian" then
		-- Random territory center within map
		local territoryAngle = mathRandom() * 2 * mathPi
		local territoryRadius = mathRandom(100, 200)
		self.Personality.TerritoryCenter = Vector3new(
			mathCos(territoryAngle) * territoryRadius,
			0,
			mathSin(territoryAngle) * territoryRadius
		)
	end


	self.Model = getOrCreateSnakeModel(tostring(self) .. "_" .. mathRandom(100000,999999))
	for _, obj in ipairs(self.Model:GetChildren()) do
		obj:Destroy()
	end

	game:GetService("CollectionService"):AddTag(self.Model, "AISnake")

	self.RootPart = Instance.new("Part")
	self.RootPart.Name = "AISnakeRoot"
	self.RootPart.Size = Vector3new(2, 2, 2)
	self.RootPart.Anchored = true
	self.RootPart.CanCollide = false
	self.RootPart.Transparency = 1
	self.RootPart.Position = self.Position
	self.RootPart.Parent = self.Model

	self.HeadParts = createVisualHead(self.Config, self.Model)

	self.Segments = {}

	-- Use initial length from config
	self.CurrentLength = self.Config.InitialLength or 10

	-- Calculate initial growth factor
	self.growthFactor = self:calculateGrowthFactor()

	-- FIXED: Proper position history initialization
	self.MaxHistorySize = mathCeil(self.Config.MaxSegments * 1.2) + 20
	self.PositionHistory = table.create(self.MaxHistorySize)
	self.HistoryHead = 1

	-- Initialize history at spawn position to prevent gaps
	for i = 1, self.MaxHistorySize do
		-- All history starts at the same position
		self.PositionHistory[i] = { position = self.Position, lookVector = self.Direction }
	end

	function self:addToHistory(data)
		self.PositionHistory[self.HistoryHead] = data
		self.HistoryHead = (self.HistoryHead % self.MaxHistorySize) + 1
	end

	function self:getFromHistory(stepsBack)
		local index = self.HistoryHead - stepsBack
		if index < 1 then
			index = index + self.MaxHistorySize
		end
		return self.PositionHistory[index]
	end

	-- Create attachment part for beams (invisible)
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.CanTouch = false
	attachmentPart.Anchored = true
	attachmentPart.Position = self.Position
	attachmentPart.Parent = self.Model
	attachmentPart:SetAttribute("AlwaysRender", true)

	-- Store attachments and beams for seamless rendering
	self.Attachments = {}
	self.Beams = {}

	-- Create head attachment
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "Attachment0"
	headAttachment.Parent = attachmentPart
	self.Attachments[0] = headAttachment

	-- Store head as segment 0 for consistency with OptimizedSnakeSystem
	self.Segments[0] = self.HeadParts.head

	-- Calculate base size with growth factor
	local currentBaseSize = BASE_SIZE * self.growthFactor

	-- Set proper head size
	local headSize = self:getSegmentSize(0, currentBaseSize)
	self.HeadParts.head.Size = Vector3.new(headSize, headSize, headSize)

	-- OPTIMIZED: Create segments dynamically based on length
	local initialSegmentCount = math.min(self.CurrentLength, DYNAMIC_SEGMENT_LIMIT)

	-- FIXED: Create segments at proper positions WITHOUT GAPS
	for i = 1, initialSegmentCount do
		-- Start ALL segments at the SAME position to prevent gaps
		local pos = self.Position
		local color = self:getSegmentColor(i) -- Use the new function
		local segment = createSegment(i, pos, color, self.Config, self.Model, i)
		self.Segments[i] = segment

		-- Set proper size using getSegmentSize
		local segmentSize = self:getSegmentSize(i, currentBaseSize)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		-- Start segments invisible
		segment.Transparency = 1

		-- Ensure segment is at exact position
		segment.CFrame = CFramenew(pos)

		-- Create attachment for this segment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.Attachments[i] = attachment
	end

	-- Create seamless beams between visible segments (like OptimizedSnakeSystem)
	for i = 0, initialSegmentCount - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.Attachments[i]
		beam.Attachment1 = self.Attachments[i + 1]

		-- Professional beam properties matching OptimizedSnakeSystem
		local beamWidth = self:getBeamWidth(i, currentBaseSize)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		beam.Texture = BEAM_TEXTURES.gradient -- Professional gradient
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.TextureSpeed = BEAM_TEXTURE_SPEED -- Animated flow effect
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.Transparency = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1) -- Slight fade at edges
		}

		-- Color matching with smooth transitions
		if i == 0 then
			-- Head to first segment - smooth color transition
			local headColor = self:getSegmentColor(0)
			local seg1Color = self:getSegmentColor(1)
			beam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, headColor),
				ColorSequenceKeypoint.new(0.3, headColor:Lerp(seg1Color, 0.3)),
				ColorSequenceKeypoint.new(0.7, headColor:Lerp(seg1Color, 0.7)),
				ColorSequenceKeypoint.new(1, seg1Color)
			})
		else
			beam.Color = ColorSequence.new(self:getSegmentColor(i))
		end

		beam.Parent = attachmentPart
		self.Beams[i] = beam
	end

	-- Store attachment part reference
	self.AttachmentPart = attachmentPart

	-- Track actual created segments
	self.actualSegmentCount = initialSegmentCount

	-- Initialize model attributes for client LOD
	self.Model:SetAttribute("CurrentLength", self.CurrentLength)
	self.Model:SetAttribute("HeadPosition", self.Position)

	-- Spawn sequence to prevent gaps
	task.defer(function()
		-- Wait for model to be ready
		task.wait(0.1)

		-- Gradually move forward to create proper segment spacing
		for step = 1, 20 do
			-- Move forward slightly
			local moveDistance = self.SegmentSpacing * 0.1
			local newPos = self.Position + self.Direction * moveDistance
			self.Position = newPos
			self.RootPart.Position = newPos

			-- Update head position
			if self.HeadParts and self.HeadParts.head then
				local headOffset = self.Direction * 1.5
				self.HeadParts.head.CFrame = CFramelookAt(self.Position + headOffset, self.Position + headOffset + self.Direction)
			end

			-- Add to history
			self:addToHistory({ position = self.Position, lookVector = self.Direction })

			-- Small wait
			task.wait(0.02)
		end

		-- Clear spawn stabilization flag
		self._spawnStabilizing = nil

		-- CRITICAL: Reset AI state after spawn
		self.State = "WANDER"
		self.TargetOrb = nil
		self.TargetSnake = nil
		self.Avoiding = false
		self.AvoidExpire = 0

		-- Force a random initial direction
		local randomTurn = mathRandom() * mathPi * 2
		self.TargetYaw = randomTurn
		self.CurrentYaw = randomTurn
		self.Direction = Vector3new(mathSin(randomTurn), 0, mathCos(randomTurn))

		-- Reset movement timers
		self.LastTurn = tick()
		self.BoostCooldown = tick() + 2 -- Wait before first boost

		-- CRITICAL: Initialize brain update time
		self._lastBrainUpdate = tick()

		-- Force immediate brain update
		self:updateBrain()

		-- Fade in segments
		for i, segment in ipairs(self.Segments) do
			if segment and segment.Parent then
				task.spawn(function()
					local fadeSteps = 10
					for step = 1, fadeSteps do
						if segment and segment.Parent then
							segment.Transparency = 1 - (step / fadeSteps)
						end
						task.wait(0.02)
					end
					if segment and segment.Parent then
						segment.Transparency = 0
					end
				end)
			end
		end
	end)

	table.insert(AISnake._activeSnakes, self)
	self._active = true

	-- Stuck detection
	self._lastPositions = {}
	self._stuckCheckTime = 0
	self._lastStuckCheck = tick()

	-- Spawn protection
	self._spawnProtection = tick() + 3 -- 3 second spawn protection
	self._spawnStabilizing = tick() + 0.5 -- Half second to let segments arrange

	return self
end

-- === OTHER METHODS (simplified) ===
function AISnake:grow(amount)
	amount = amount or 5

	for i = 1, amount do
		if self.CurrentLength < self.Config.MaxSegments then
			self.CurrentLength = self.CurrentLength + 1

			-- Only create physical segment if within dynamic limit
			if self.CurrentLength <= DYNAMIC_SEGMENT_LIMIT then
				-- Update growth factor before creating new segment
				self.growthFactor = self:calculateGrowthFactor()
				local currentBaseSize = BASE_SIZE * self.growthFactor

				local color = self:getSegmentColor(self.CurrentLength)
				local lastSegment = self.Segments[self.CurrentLength - 1]
				local newPos = lastSegment and lastSegment.Position or self.Position
				local segment = createSegment(self.CurrentLength, newPos, color, self.Config, self.Model, self.CurrentLength)
				self.Segments[self.CurrentLength] = segment

				-- Ensure segment uses correct material from our config
				segment.Material = self.Config.BodyMaterial or Enum.Material.Neon
				segment.Color = color -- Re-apply color to be sure

				-- Match CharacterSetup's segment growth exactly
				segment.Transparency = 1
				segment.Size = Vector3new(0.1, 0.1, 0.1)

				-- Create attachment for new segment
				if self.AttachmentPart and self.Attachments then
					local attachment = Instance.new("Attachment")
					attachment.Name = "Attachment" .. self.CurrentLength
					attachment.Parent = self.AttachmentPart
					attachment.WorldPosition = newPos
					self.Attachments[self.CurrentLength] = attachment

					-- Create beam from previous segment to this new one
					if self.CurrentLength > 1 and self.Beams then
						-- Ensure previous attachment exists
						local prevAttachment = self.Attachments[self.CurrentLength - 1]
						if not prevAttachment then
							-- Create missing attachment for previous segment
							prevAttachment = Instance.new("Attachment")
							prevAttachment.Name = "Attachment" .. (self.CurrentLength - 1)
							prevAttachment.Parent = self.AttachmentPart
							local prevSegment = self.Segments[self.CurrentLength - 1]
							if prevSegment and prevSegment.Parent then
								prevAttachment.WorldPosition = prevSegment.Position
							else
								prevAttachment.WorldPosition = newPos
							end
							self.Attachments[self.CurrentLength - 1] = prevAttachment
						end

						local beam = Instance.new("Beam")
						beam.Name = "Beam" .. (self.CurrentLength - 1)
						beam.Attachment0 = prevAttachment
						beam.Attachment1 = attachment

						-- Professional beam properties
						local beamWidth = self:getBeamWidth(self.CurrentLength - 1, currentBaseSize)
						beam.Width0 = beamWidth
						beam.Width1 = beamWidth
						beam.CurveSize0 = 0
						beam.CurveSize1 = 0
						beam.FaceCamera = true
						beam.Segments = BEAM_SEGMENTS
						beam.Texture = BEAM_TEXTURES.gradient
						beam.TextureMode = Enum.TextureMode.Wrap
						beam.TextureLength = 2
						beam.TextureSpeed = BEAM_TEXTURE_SPEED
						beam.LightEmission = 1
						beam.LightInfluence = 0
						beam.Brightness = 2
						beam.Transparency = NumberSequence.new{
							NumberSequenceKeypoint.new(0, 0),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 0.1)
						}

						-- Color matching
						local prevColor = self:getSegmentColor(self.CurrentLength - 1)
						local currColor = self:getSegmentColor(self.CurrentLength)

						-- Safety check for colors
						if not prevColor or not currColor then
							warn("AISnake:grow - Color is nil for segment", self.CurrentLength)
							beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 51)) -- Default yellow
						elseif prevColor == currColor then
							beam.Color = ColorSequence.new(currColor)
						else
							beam.Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0, prevColor),
								ColorSequenceKeypoint.new(1, currColor)
							})
						end

						beam.Parent = self.AttachmentPart
						self.Beams[self.CurrentLength - 1] = beam
					end
				end

				-- Calculate final size using getSegmentSize
				local finalSize = self:getSegmentSize(self.CurrentLength, currentBaseSize)

				task.spawn(function()
					if not segment or not segment.Parent then return end
					local growTime = 0.18
					local t = 0
					local startSize = Vector3new(0.1, 0.1, 0.1)
					while t < growTime do
						t = t + RunService.Heartbeat:Wait()
						if not segment or not segment.Parent then return end
						local alpha = mathMin(t / growTime, 1)
						segment.Size = startSize:Lerp(Vector3new(finalSize, finalSize, finalSize), alpha)
						segment.Transparency = 1 - alpha
					end
					if segment and segment.Parent then
						segment.Size = Vector3new(finalSize, finalSize, finalSize)
						segment.Transparency = 0
					end
				end)

				-- Update actual segment count
				self.actualSegmentCount = self.CurrentLength
			end
		end
	end

	-- Update all segment sizes with new growth factor to prevent glitching
	if amount > 0 then
		self.growthFactor = self:calculateGrowthFactor()
		local currentBaseSize = BASE_SIZE * self.growthFactor

		-- Smoothly update existing segment sizes and beam widths
		task.spawn(function()
			-- Update segments
			for i = 0, math.min(self.CurrentLength, FORCE_RENDER_SEGMENTS) do
				local segment = self.Segments[i]
				if segment and segment.Parent then
					local targetSize = self:getSegmentSize(i, currentBaseSize)
					-- Use TweenService for smooth size transition
					local tween = TweenService:Create(
						segment,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Size = Vector3.new(targetSize, targetSize, targetSize)}
					)
					tween:Play()
				end
			end

			-- Update beam widths to match new segment sizes
			task.wait(0.1) -- Small delay to let segment tweens start
			for i = 0, math.min(self.CurrentLength - 1, FORCE_RENDER_SEGMENTS) do
				local beam = self.Beams[i]
				if beam and beam.Parent then
					local beamWidth = self:getBeamWidth(i, currentBaseSize)
					-- Tween beam width for smooth transition
					local beamTween = TweenService:Create(
						beam,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Width0 = beamWidth, Width1 = beamWidth}
					)
					beamTween:Play()
				end
			end
		end)
	end
end

function AISnake:setConfidenceBuff()
	if not self._active then return end
	self.isConfident = true
	self.confidenceEndTime = tick() + 8 -- REDUCED from 12
	self.killCount = self.killCount + 1
	self.lastKillTime = tick()
end

function AISnake:Destroy()
	if not self._active then return end
	self._active = false

	-- Immediately mark as destroyed to prevent any updates
	self._destroyed = true

	-- Untrack snake from orb pickup system
	if AISnakeOrbPickup then
		pcall(function()
			AISnakeOrbPickup.UntrackSnake(self)
		end)
	end

	-- Remove from active snakes list
	for i = #AISnake._activeSnakes, 1, -1 do
		if AISnake._activeSnakes[i] == self then
			table.remove(AISnake._activeSnakes, i)
			break
		end
	end
	AISnake._orbTargets[self] = nil

	-- Spawn orbs before destroying segments
	local orbSpawnData = {}
	if self.HeadParts and self.HeadParts.head and self.HeadParts.head.Parent then
		local head = self.HeadParts.head
		table.insert(orbSpawnData, {position = head.Position, size = 3.5, color = head.Color})
	end

	local ORB_SPAWN_DENSITY = 5
	for i = 1, #self.Segments do
		if i % ORB_SPAWN_DENSITY == 1 then
			local segment = self.Segments[i]
			if segment and segment.Parent then
				table.insert(orbSpawnData, {position = segment.Position, size = 1.8, color = segment.Color})
			end
		end
	end

	-- Spawn orbs asynchronously
	task.spawn(function()
		if OrbUtils and OrbUtils.spawnOrb then
			for i = 1, #orbSpawnData do
				local data = orbSpawnData[i]
				pcall(function()
					OrbUtils.spawnOrb(data.position, data.size, data.color)
				end)
			end
		end
	end)

	-- IMMEDIATE CLEANUP - Destroy all segments right away
	for i = 1, #self.Segments do
		local segment = self.Segments[i]
		if segment then
			-- Don't use returnSegment for death, just destroy
			pcall(function()
				segment:Destroy()
			end)
		end
	end
	self.Segments = {}

	-- Clean up beams and attachments
	if self.Beams then
		for _, beam in pairs(self.Beams) do
			if beam and beam.Parent then
				pcall(function()
					beam:Destroy()
				end)
			end
		end
		self.Beams = {}
	end

	if self.Attachments then
		for _, attachment in pairs(self.Attachments) do
			if attachment and attachment.Parent then
				pcall(function()
					attachment:Destroy()
				end)
			end
		end
		self.Attachments = {}
	end

	if self.AttachmentPart and self.AttachmentPart.Parent then
		pcall(function()
			self.AttachmentPart:Destroy()
		end)
		self.AttachmentPart = nil
	end

	-- Destroy head parts
	if self.HeadParts then
		for name, part in pairs(self.HeadParts) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function()
					part:Destroy()
				end)
			end
		end
	end

	-- Destroy model and all its descendants
	if self.Model and self.Model.Parent then
		pcall(function()
			-- First destroy all descendants to ensure nothing is left
			for _, descendant in ipairs(self.Model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant:Destroy()
				end
			end
			self.Model:Destroy()
		end)
	end

	-- Clear all references
	self.Model = nil
	self.HeadParts = nil
	self.RootPart = nil
	self.Segments = nil
end

-- === SMOOTHER MOVEMENT (FIXED) ===
function AISnake:updateMovement(dt)
	if self._destroyed then return end

	if not self._active or not self.HeadParts or not self.HeadParts.head or not self.HeadParts.head.Parent then
		if self._active and not self._destroyed then
			self:Destroy()
		end
		return
	end

	local now = tick()

	-- Don't move during spawn stabilization
	if self._spawnStabilizing and now < self._spawnStabilizing then
		return
	end
	local p = self.Personality

	-- Failsafe: Ensure we have a personality
	if not p then
		warn("AI Snake lost personality! Reassigning...")
		local pType = AISnake.PersonalityTypes[mathRandom(1, #AISnake.PersonalityTypes)]
		self.Personality = deepCopy(AISnake.PersonalityDefinitions[pType])
		p = self.Personality
	end

	local state = self.State
	local steer = self.SteerDirection

	-- Failsafe: Ensure we have a valid steer direction
	if not steer or steer.Magnitude < 0.1 then
		steer = self.Direction
	end

	-- Failsafe: Check if brain updates have stopped
	if self._lastBrainUpdate then
		local timeSinceLastBrain = now - self._lastBrainUpdate
		if timeSinceLastBrain > 2.0 then -- Reduced from 5.0 to 2.0 seconds
			warn("AI Snake brain frozen for", timeSinceLastBrain, "seconds! Forcing update...")
			self:updateBrain()
			-- Also ensure it's in the active list
			local found = false
			for _, snake in ipairs(AISnake._activeSnakes) do
				if snake == self then
					found = true
					break
				end
			end
			if not found and self._active then
				table.insert(AISnake._activeSnakes, self)
				print("🔧 Re-added frozen snake to active list")
			end
		end
	else
		-- First brain update
		self:updateBrain()
		self._lastBrainUpdate = now
	end

	-- SPAWN PROTECTION - Don't check boundaries for first few seconds
	local isSpawnProtected = now < (self._spawnProtection or 0)

	-- Validate position (unless spawn protected)
	if not isSpawnProtected then
		if self.Position.X < MAP_BOUNDS.minX - 10 or self.Position.X > MAP_BOUNDS.maxX + 10 or
			self.Position.Z < MAP_BOUNDS.minZ - 10 or self.Position.Z > MAP_BOUNDS.maxZ + 10 then
			-- Gentle repositioning instead of teleporting
			local safeX = mathClamp(self.Position.X, MAP_BOUNDS.minX + 50, MAP_BOUNDS.maxX - 50)
			local safeZ = mathClamp(self.Position.Z, MAP_BOUNDS.minZ + 50, MAP_BOUNDS.maxZ - 50)
			self.Position = Vector3new(safeX, self.Position.Y, safeZ)
			self.Direction = Vector3new(mathRandom() - 0.5, 0, mathRandom() - 0.5).Unit
			self.State = "WANDER"
			return
		end
	end

	-- SMOOTHER turning
	local forward = self.Direction
	local flatForward = Vector3new(forward.X, 0, forward.Z).Unit
	local flatSteer = Vector3new(steer.X, 0, steer.Z)
	local angle = 0
	if flatSteer.Magnitude > 0.01 then
		flatSteer = flatSteer.Unit
		angle = mathAtan2(flatSteer.X, flatSteer.Z) - mathAtan2(flatForward.X, flatForward.Z)
		if angle > mathPi then angle = angle - 2 * mathPi end
		if angle < -mathPi then angle = angle + 2 * mathPi end
	end
	local desiredYaw = self.CurrentYaw + angle
	self.TargetYaw = desiredYaw

	-- BALANCED TURN SPEED - Good for orb collection but still fair
	local turnSpeed = self.TurnSpeed

	-- Special case for orb seeking - need better turning to actually collect them!
	if state == "SEEK_ORB" and self.TargetOrb then
		-- Calculate angle to orb
		local toOrb = (self.TargetOrb.Position - self.Position)
		local dist = toOrb.Magnitude
		if dist < 20 then
			-- Close to orb - allow sharper turns to grab it
			turnSpeed = turnSpeed * 1.5
		end
	elseif state == "AVOID_WALL" then
		-- Still need to avoid walls effectively
		turnSpeed = turnSpeed * 1.3
	elseif state == "AVOID_BOUNDARY" then
		-- Need sharp turns to avoid map edge
		turnSpeed = turnSpeed * 2.5 -- Even sharper for emergencies
	elseif state == "COLLISION_AVOID" then
		-- Emergency collision avoidance needs instant response
		turnSpeed = turnSpeed * 3.0
	end

	-- When boosting, turn slightly slower like players do
	if self.Boosting then
		turnSpeed = turnSpeed * 0.85
	end

	-- MUCH smoother turning
	local yawDiff = self.TargetYaw - self.CurrentYaw
	if yawDiff > mathPi then yawDiff = yawDiff - 2 * mathPi end
	if yawDiff < -mathPi then yawDiff = yawDiff + 2 * mathPi end

	-- Apply turn with proper smoothing
	local maxTurn = turnSpeed * dt
	yawDiff = mathClamp(yawDiff, -maxTurn, maxTurn)
	self.CurrentYaw = self.CurrentYaw + yawDiff

	-- Update direction from yaw
	self.Direction = Vector3new(mathSin(self.CurrentYaw), 0, mathCos(self.CurrentYaw))

	-- Movement variation
	if self.State == "WANDER" or self.State == "FLEE" then
		local wobbleTime = tick() * 2
		local wobbleAmount = 0.1
		local wobble = Vector3new(
			math.sin(wobbleTime) * wobbleAmount,
			0,
			math.cos(wobbleTime * 1.3) * wobbleAmount
		)
		self.Direction = (self.Direction + wobble).Unit
	end

	-- Boundary force (gentler, only when not spawn protected)
	if not isSpawnProtected then
		local lookAheadTime = 1.0
		local futurePos = self.Position + self.Direction * self.Speed * lookAheadTime

		local boundaryForce = Vector3new(0, 0, 0)
		local boundaryStrength = 0

		if futurePos.X > MAP_BOUNDS.maxX - 50 then
			local dist = MAP_BOUNDS.maxX - futurePos.X
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(-1, 0, 0)
		elseif futurePos.X < MAP_BOUNDS.minX + 50 then
			local dist = futurePos.X - MAP_BOUNDS.minX
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(1, 0, 0)
		end

		if futurePos.Z > MAP_BOUNDS.maxZ - 50 then
			local dist = MAP_BOUNDS.maxZ - futurePos.Z
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(0, 0, -1)
		elseif futurePos.Z < MAP_BOUNDS.minZ + 50 then
			local dist = futurePos.Z - MAP_BOUNDS.minZ
			boundaryStrength = mathMax(boundaryStrength, 1 - (dist / 50))
			boundaryForce = boundaryForce + Vector3new(0, 0, 1)
		end

		if boundaryStrength > 0.1 then
			boundaryForce = boundaryForce.Unit
			self.Direction = (self.Direction * (1 - boundaryStrength) + boundaryForce * boundaryStrength).Unit
			if boundaryStrength > 0.5 then
				self.State = "AVOID_BOUNDARY"
				self.TargetOrb = nil
				self.TargetSnake = nil
			end
		end
	end

	-- Boost management
	if self.Boosting and now > self.BoostEndTime then
		self.Boosting = false
		self.IsBoosting = false
	end

	-- SMART boost usage - less boosting when collecting orbs
	if not self.Boosting and now > self.BoostCooldown then
		local shouldBoost = false
		local boostDuration = 1.2

		if state == "AVOID_WALL" then
			shouldBoost = true
			boostDuration = 0.8
		elseif state == "SEEK_ORB" then
			-- RARELY boost when seeking orbs - they need control, not speed
			if mathRandom() < 0.02 then -- Only 2% chance when orb seeking
				shouldBoost = true
				boostDuration = 0.5 -- Very short boost
			end
		elseif state == "FLEE" then
			-- Higher chance to boost when fleeing
			if mathRandom() < 0.3 then
				shouldBoost = true
				boostDuration = 1.5
			end
		else
			-- Normal wandering/hunting boost chance
			if mathRandom() < (p.BoostChance or 0) * 0.3 then -- Reduced general boost chance
				shouldBoost = true
			end
		end

		if shouldBoost then
			self:startBoost(boostDuration)
		end
	end

	-- Speed calculation
	local speedMultiplier = p.SpeedMultiplier or 1

	if self.Boosting then
		self.Speed = self.BoostSpeed * speedMultiplier
	else
		self.Speed = mathMax(self.NormalSpeed, self.NormalSpeed * speedMultiplier)
	end

	-- Position update (with clamping only when not spawn protected)
	local moveDistance = self.Speed * dt
	local newPosition = self.Position + self.Direction * moveDistance

	if not isSpawnProtected then
		local margin = 20
		local clampedX = mathClamp(newPosition.X, MAP_BOUNDS.minX + margin, MAP_BOUNDS.maxX - margin)
		local clampedZ = mathClamp(newPosition.Z, MAP_BOUNDS.minZ + margin, MAP_BOUNDS.maxZ - margin)

		if clampedX ~= newPosition.X or clampedZ ~= newPosition.Z then
			local escapeAngle = mathRandom() * mathPi - mathPi/2
			local currentAngle = mathAtan2(self.Direction.X, self.Direction.Z)
			local newAngle = currentAngle + escapeAngle

			self.Direction = Vector3new(mathSin(newAngle), 0, mathCos(newAngle))
			self.CurrentYaw = newAngle
			self.TargetYaw = newAngle

			self.TargetOrb = nil
			self.TargetSnake = nil
			self.State = "WANDER"
		end

		self.Position = Vector3new(clampedX, newPosition.Y, clampedZ)
	else
		self.Position = newPosition
	end

	self.RootPart.Position = self.Position

	local headOffset = self.Direction * 1.5
	local newHeadPos = self.Position + headOffset
	self.HeadParts.head.CFrame = CFramelookAt(newHeadPos, newHeadPos + self.Direction)

	-- Update eyes position (match OptimizedSnakeSystem)
	if self.HeadParts.leftEye and self.HeadParts.rightEye then
		local headCF = self.HeadParts.head.CFrame
		local headSize = self.HeadParts.head.Size.X
		local eyeScale = headSize / 3.5 * 0.5 -- BASE_SIZE = 3.5
		local eyeOffset = headSize * 0.3
		local eyeForward = -headSize * 0.35

		-- Update eye sizes
		self.HeadParts.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
		self.HeadParts.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
		self.HeadParts.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
		self.HeadParts.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

		-- Position eyes
		self.HeadParts.leftEye.CFrame = headCF * CFramenew(-eyeOffset, eyeOffset * 0.5, eyeForward)
		self.HeadParts.rightEye.CFrame = headCF * CFramenew(eyeOffset, eyeOffset * 0.5, eyeForward)
		self.HeadParts.leftPupil.CFrame = self.HeadParts.leftEye.CFrame * CFramenew(0, 0, -eyeScale * 0.3)
		self.HeadParts.rightPupil.CFrame = self.HeadParts.rightEye.CFrame * CFramenew(0, 0, -eyeScale * 0.3)
	end

	-- Set velocity for collision detection
	self.HeadParts.head.AssemblyLinearVelocity = self.Direction * self.Speed

	-- CHECK FOR ORB PICKUPS (including upgrade orbs)
	local headPos = self.HeadParts.head.Position
	local pickupRadius = 8 -- Increased for better upgrade orb pickup (they're bigger)

	local orbsToCheck = {}

	-- Add orbs from workspace
	for _, obj in pairs(Workspace:GetChildren()) do
		if obj:IsA("BasePart") and (obj.Name == "Orb" or obj.Name == "UpgradeOrb" or obj.Name == "DeathOrb") then
			table.insert(orbsToCheck, obj)
		end
	end

	-- Also check OrbFolder if it exists
	local orbFolder = Workspace:FindFirstChild("OrbFolder") or Workspace:FindFirstChild("Orbs")
	if orbFolder then
		for _, orb in ipairs(orbFolder:GetChildren()) do
			if orb:IsA("BasePart") then
				table.insert(orbsToCheck, orb)
			end
		end
	end

	-- Now check all orbs
	for _, orb in ipairs(orbsToCheck) do
		if orb:IsA("BasePart") and orb.Parent then
			local dist = (orb.Position - headPos).Magnitude

			if dist <= pickupRadius then
				-- Check if orb is already being collected
				local isBeingCollected = orb:GetAttribute("BeingCollected")
				if isBeingCollected then
					continue -- Skip this orb
				end

				-- Mark orb as being collected to prevent double collection
				orb:SetAttribute("BeingCollected", true)

				-- Handle all orbs the same way
				local valueObj = orb:FindFirstChild("Value")
				local orbValue = valueObj and valueObj.Value or 1

				if orb.Name == "UpgradeOrb" then
					-- Apply upgrade
					if SnakeUpgrades then
						print("🎯 AI Snake collecting upgrade orb!")
						SnakeUpgrades.GiveUpgrade(self)
					end
				else
					-- Regular orb - grow the snake
					self:grow(orbValue)
				end

				-- Destroy the orb
				orb:Destroy()
				break -- Only pick up one orb per frame
			end
		end
	end

	-- History management
	local lastHistoryPoint = self:getFromHistory(1)
	local dist = (self.Position - lastHistoryPoint.position).Magnitude

	-- EXACT same interpolation as CharacterSetup
	if dist > 0.02 then
		if dist > self.Config.SegmentSpacing * 0.7 then
			local isBoosting = self.Speed > 16 -- AI boost check
			local maxInterp = isBoosting and 6 or 3
			local numInterpolations = mathMin(mathFloor(dist / (self.Config.SegmentSpacing * 0.35)), maxInterp)
			for i = 1, numInterpolations do
				local fraction = i / (numInterpolations + 1)
				local interpPos = lastHistoryPoint.position:Lerp(self.Position, fraction)
				local interpLook = lastHistoryPoint.lookVector:Lerp(self.Direction, fraction).Unit
				self:addToHistory({ position = interpPos, lookVector = interpLook })
			end
		end
		self:addToHistory({ position = self.Position, lookVector = self.Direction })
	end

	-- Segment following (OPTIMIZED)
	local followSpeed = self.IsBoosting and self.BoostFollowSpeed or self.FollowSpeed

	self._segmentUpdateFrame = (self._segmentUpdateFrame or 0) + 1

	self.Model:SetAttribute("CurrentLength", self.CurrentLength)
	self.Model:SetAttribute("HeadPosition", self.Position)

	local currentBaseSize = BASE_SIZE * self.growthFactor

	local segmentSkip = 1
	if self.CurrentLength > VERY_LONG_SNAKE_THRESHOLD then
		segmentSkip = 4 -- Skip more for very long snakes
	elseif self.CurrentLength > LONG_SNAKE_THRESHOLD then
		segmentSkip = 2 -- Skip every other for long snakes
	end

	local updateOffset = self._segmentUpdateFrame % segmentSkip

	if self.Attachments and self.Attachments[0] then
		self.Attachments[0].WorldPosition = self.HeadParts.head.Position
	end

	if not self.CurrentLength then
		warn("AISnake:updateMovement - CurrentLength is nil for snake", self.Name)
		return
	end
	local maxSegmentToUpdate = math.min(self.CurrentLength, DYNAMIC_SEGMENT_LIMIT)

	for i = 1 + updateOffset, maxSegmentToUpdate, segmentSkip do
		local segment = self:ensureSegmentExists(i)
		if segment and segment.Parent then
			local delay = mathFloor(i * 1.2)
			local targetData = self:getFromHistory(delay)
			if targetData then
				local spacingMultiplier = 0.15 -- Base spacing from CharacterSetup
				if self.CurrentLength > 1500 then
					spacingMultiplier = 0.2 -- More spacing to show pattern
				end
				local segmentPos = targetData.position - targetData.lookVector * (self.Config.SegmentSpacing * spacingMultiplier)
				local currentSegmentPos = segment.Position

				if i > 1 then
					local prevSegment = self.Segments[i - 1]
					if prevSegment and prevSegment.Parent then
						local gap = (currentSegmentPos - prevSegment.Position).Magnitude
						if gap > self.Config.SegmentSpacing * 1.5 then
							local dir = (prevSegment.Position - currentSegmentPos).Unit
							segmentPos = prevSegment.Position - dir * self.Config.SegmentSpacing
						end
					end
				end

				local newPos = currentSegmentPos:Lerp(segmentPos, followSpeed)
				segment.CFrame = CFramenew(newPos)

				if self.Attachments and self.Attachments[i] then
					self.Attachments[i].WorldPosition = newPos
				end
			end
		end
	end

	-- Update attachment positions for skipped segments (to keep beams smooth)
	if segmentSkip > 1 then
		for i = 1, maxSegmentToUpdate do
			if i % segmentSkip ~= updateOffset then
				local segment = self.Segments[i]
				if segment and segment.Parent and self.Attachments and self.Attachments[i] then
					self.Attachments[i].WorldPosition = segment.Position
				end
			end
		end
	end

end

-- === UPDATE LOOPS ===
if AISnake._movementConnection then AISnake._movementConnection:Disconnect() end
if AISnake._brainConnection then AISnake._brainConnection:Disconnect() end

local brainUpdateCounter = 0

AISnake._movementConnection = RunService.Heartbeat:Connect(function(dt)
	local snakesToUpdate = {}
	for i = 1, #AISnake._activeSnakes do
		local snake = AISnake._activeSnakes[i]
		if snake and snake._active then
			table.insert(snakesToUpdate, snake)
		end
	end

	brainUpdateCounter = brainUpdateCounter + 1
	if brainUpdateCounter >= 30 then
		brainUpdateCounter = 0
		for i = 1, #snakesToUpdate do
			local snake = snakesToUpdate[i]
			if snake and snake._active then
				snake:updateBrain()
			end
		end
	end

	for i = 1, #snakesToUpdate do
		local snake = snakesToUpdate[i]
		if snake and snake._active then
			snake:updateMovement(dt)
		end
	end
end)

AISnake._brainUpdateIndex = 1
AISnake._spatialGridTimer = 0

local lastCleanup = 0
local CLEANUP_INTERVAL = 10 -- Clean every 10 seconds

AISnake._brainConnection = RunService.Stepped:Connect(function(time, deltaTime)
	AISnake._spatialGridTimer = AISnake._spatialGridTimer + deltaTime

	if time - lastCleanup > CLEANUP_INTERVAL then
		lastCleanup = time
		local removed = 0
		for i = #AISnake._activeSnakes, 1, -1 do
			local snake = AISnake._activeSnakes[i]
			if not snake or not snake._active or snake._destroyed then
				table.remove(AISnake._activeSnakes, i)
				removed = removed + 1
			end
		end
		if removed > 0 then
			print("🧹 Cleaned up", removed, "invalid AI snakes from active list")
		end
	end

	if AISnake._spatialGridTimer >= SPATIAL_GRID_UPDATE_RATE then
		AISnake._spatialGridTimer = 0

		SpatialGrid.Clear()

		for _, snake in ipairs(AISnake._activeSnakes) do
			if snake._active and snake.HeadParts and snake.HeadParts.head then
				SpatialGrid.Insert(snake.HeadParts.head, snake, "AI_HEAD")

				for i = 1, #snake.Segments, 4 do
					local segment = snake.Segments[i]
					if segment then
						SpatialGrid.Insert(segment, snake, "AI_SEGMENT")
					end
				end
			end
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				local head = player.Character:FindFirstChild("HumanoidRootPart")
				if head then
					SpatialGrid.Insert(head, player, "PLAYER_HEAD")
				end

				local segmentCount = 0
				for _, part in ipairs(player.Character:GetChildren()) do
					if part:IsA("BasePart") and part.Name:match("Segment") then
						segmentCount = segmentCount + 1
						if segmentCount % 4 == 1 then
							SpatialGrid.Insert(part, player, "PLAYER_SEGMENT")
						end
					end
				end
			end
		end

		for _, orb in ipairs(OrbUtils.orbs) do
			SpatialGrid.Insert( orb, orb, "ORB")
		end
	end

	local snakes = AISnake._activeSnakes
	if #snakes == 0 then
		AISnake._brainUpdateIndex = 1 -- Reset index when no snakes
		return
	end

	-- Get nearest player position for LOD
	local nearestPlayerPos = nil
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			nearestPlayerPos = player.Character.HumanoidRootPart.Position
			break -- Found one, that's enough
		end
	end

	for i = 1, BRAIN_UPDATES_PER_FRAME do
		if AISnake._brainUpdateIndex > #snakes then
			AISnake._brainUpdateIndex = 1
		end
		if AISnake._brainUpdateIndex < 1 then
			AISnake._brainUpdateIndex = 1
		end

		local snake = snakes[AISnake._brainUpdateIndex]
		if snake and snake._active then
			local shouldUpdate = true
			if nearestPlayerPos and snake.Position then
				local dist = (snake.Position - nearestPlayerPos).Magnitude
				if dist > AI_UPDATE_DISTANCE then
					shouldUpdate = false
				end
			end

			if shouldUpdate then
				snake:updateBrain()
			end
		end

		AISnake._brainUpdateIndex = AISnake._brainUpdateIndex + 1
	end
end)

-- Get segment color matching OptimizedSnakeSystem
function AISnake:getSegmentColor(index)
	if not self.Config or not self.Config.BodyColors or #self.Config.BodyColors == 0 then
		return Color3.fromRGB(255, 255, 51) -- Default yellow color
	end

	if index == 0 then
		return self.Config.HeadColor or self.Config.BodyColors[1]
	elseif index <= 8 then -- HEAD_BLEND_SEGMENTS = 8
		local blendFactor = (index / 8) ^ 0.7
		local headColor = self.Config.HeadColor or self.Config.BodyColors[1]
		local bodyColor = self.Config.BodyColors[1]
		return headColor:Lerp(bodyColor, blendFactor)
	else
		local colorIndex = ((index - 1) % #self.Config.BodyColors) + 1
		return self.Config.BodyColors[colorIndex]
	end
end

-- Calculate growth factor exactly like OptimizedSnakeSystem
function AISnake:calculateGrowthFactor()
	local length = self.CurrentLength

	if length <= 50 then
		return 1.0
	elseif length <= 200 then
		return 1.0 + (length - 50) / 150 * 0.5 -- Up to 1.5x
	elseif length <= 1000 then
		return 1.5 + (length - 200) / 800 * 1.0 -- Up to 2.5x
	elseif length <= 5000 then
		return 2.5 + (length - 1000) / 4000 * 0.5 -- Up to 3.0x
	else
		return 3.0 + math.min((length - 5000) / 10000 * 0.5, 0.5) -- Max 3.5x
	end
end

-- Smooth size transition function from OptimizedSnakeSystem
function AISnake:getSegmentSize(index, baseSize)
	local sizeMult = 1
	local visibleSegmentCount = self.CurrentLength

	if index == 0 then
		-- Head with subtle size increase
		return baseSize * HEAD_SIZE_MULTIPLIER * sizeMult
	elseif index <= HEAD_BLEND_SEGMENTS then
		-- Smooth transition from head to body
		local blendFactor = index / HEAD_BLEND_SEGMENTS
		local headSize = baseSize * HEAD_SIZE_MULTIPLIER
		local bodySize = baseSize * (1 - 0.05 * blendFactor) -- Subtle initial taper
		return (headSize + (bodySize - headSize) * (blendFactor ^ 0.5)) * sizeMult
	else
		-- Body with gradual taper
		local taperFactor = 1 - (index / self.CurrentLength) * 0.2
		-- Apply exponential smoothing to taper
		taperFactor = 1 - (1 - taperFactor) ^ 1.5
		return baseSize * taperFactor * sizeMult
	end
end

-- Calculate beam width with proper transitions (matching OptimizedSnakeSystem)
function AISnake:getBeamWidth(index, baseSize)
	local segmentSize1 = self:getSegmentSize(index, baseSize)
	local segmentSize2 = self:getSegmentSize(index + 1, baseSize)

	local avgSize = (segmentSize1 + segmentSize2) / 2
	local visibleSegmentCount = self.CurrentLength
	local beamTaper = 1 - (index / visibleSegmentCount) * BEAM_TAPER_STRENGTH
	local aiConfig = self.Config.AI or {}
	local beamWidthBase = aiConfig.BeamWidthMultiplier or BEAM_WIDTH_BASE * 0.9

	return avgSize * beamWidthBase * beamTaper
end

-- Dynamically create segments if they don't exist yet
function AISnake:ensureSegmentExists(index)
	if index > DYNAMIC_SEGMENT_LIMIT or index > self.CurrentLength then
		return nil
	end

	local segment = self.Segments[index]
	if segment and segment.Parent then
		return segment
	end

	-- Create segment on demand
	local delay = mathFloor(index * 1.2)
	local targetData = self:getFromHistory(delay)
	if not targetData then
		return nil
	end

	local color = self:getSegmentColor(index)
	segment = createSegment(index, targetData.position, color, self.Config, self.Model, self.CurrentLength)

	-- Apply proper size
	local currentBaseSize = BASE_SIZE * self.growthFactor
	local segmentSize = self:getSegmentSize(index, currentBaseSize)
	segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

	segment.Transparency = 0
	segment.CanTouch = index <= 50 -- Only first 50 segments have collision
	segment.CanQuery = index <= 10

	self.Segments[index] = segment

	-- Create attachment if needed
	if not self.Attachments[index] then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. index
		attachment.Parent = self.AttachmentPart
		attachment.WorldPosition = segment.Position
		self.Attachments[index] = attachment
	end

	-- Create beam to previous segment if needed
	if index > 0 and not self.Beams[index - 1] then
		local prevAttachment = self.Attachments[index - 1]
		if prevAttachment then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. (index - 1)
			beam.Attachment0 = prevAttachment
			beam.Attachment1 = self.Attachments[index]

			-- Beam properties
			local beamWidth = self:getBeamWidth(index - 1, currentBaseSize)
			beam.Width0 = beamWidth
			beam.Width1 = beamWidth
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.FaceCamera = true
			beam.Segments = BEAM_SEGMENTS
			beam.Texture = BEAM_TEXTURES.gradient
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 2
			beam.TextureSpeed = BEAM_TEXTURE_SPEED
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 2
			beam.Transparency = NumberSequence.new{
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 0.1)
			}
			beam.Color = ColorSequence.new(color)

			beam.Parent = self.AttachmentPart
			self.Beams[index - 1] = beam
			beam.Enabled = true
		end
	end

	return segment
end

return AISnake
