-- ClientAISnakeLOD v3.0: Slither.io-inspired ultra-smooth LOD system
-- Revolutionary distance-based fading with segment compression

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ==================================
-- SLITHER.IO STYLE CONFIGURATION
-- ==================================
local UPDATE_RATE = 30 -- Hz (slither.io style smooth updates)
local UPDATE_INTERVAL = 1 / UPDATE_RATE

-- Distance-based fading (slither.io style)
local FADE_START_DISTANCE = 150      -- Full opacity until this distance
local FADE_END_DISTANCE = 1200       -- Completely invisible at this distance
local OUTLINE_FADE_DISTANCE = 1500   -- Even the glow disappears here

-- Segment compression for distant snakes
local COMPRESSION_START = 400        -- Start showing fewer segments
local MAX_COMPRESSION_RATIO = 0.3    -- Show at least 30% of segments

-- Performance settings
local MAX_VISIBLE_SNAKES = 200       -- Limit for performance
local VISIBILITY_CHECK_RADIUS = 1800 -- Don't even process snakes beyond this

-- Visual settings
local FADE_SMOOTHNESS = 0.15         -- How quickly fades happen (lower = smoother)
local GLOW_DISTANCE_MULTIPLIER = 1.2 -- Glow visible 20% further than body
local MIN_HEAD_VISIBILITY = 0.15     -- Head always slightly visible

-- ==================================
-- Utility Functions
-- ==================================
local function smoothStep(edge0, edge1, x)
	x = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return x * x * (3 - 2 * x)
end

local function calculateSegmentVisibility(segmentDistance, isHead)
	if segmentDistance < FADE_START_DISTANCE then
		return 1
	elseif segmentDistance > FADE_END_DISTANCE then
		return isHead and MIN_HEAD_VISIBILITY or 0
	else
		local fade = smoothStep(FADE_START_DISTANCE, FADE_END_DISTANCE, segmentDistance)
		if isHead then
			return math.max(MIN_HEAD_VISIBILITY, 1 - fade)
		else
			return 1 - fade
		end
	end
end

local function calculateCompressionRatio(distance)
	if distance < COMPRESSION_START then
		return 1
	else
		local compressionFactor = smoothStep(COMPRESSION_START, FADE_END_DISTANCE, distance)
		return math.max(MAX_COMPRESSION_RATIO, 1 - compressionFactor * (1 - MAX_COMPRESSION_RATIO))
	end
end

-- ==================================
-- ClientSnake Class (Slither.io Style)
-- ==================================
local ClientSnake = {}
ClientSnake.__index = ClientSnake

function ClientSnake.new(model)
	local self = setmetatable({}, ClientSnake)

	self.model = model
	self.head = model:WaitForChild("Segment0_Head", 5)

	if not self.head then
		warn("ClientSnake.new: Could not find head for model", model)
		return nil
	end

	-- Initialize arrays
	self.segments = {}
	self.segmentData = {} -- Store additional data per segment
	self.beams = {}
	self.glows = {}
	self.basePositions = {} -- Store original positions for compression

	-- Collect and sort segments
	local partsToSort = {}
	for _, child in ipairs(model:GetChildren()) do
		if child.Name:match("^Segment") then
			local index = tonumber(child.Name:match("%d+"))
			if index then
				table.insert(partsToSort, {index = index, part = child})
			end
		end
	end
	table.sort(partsToSort, function(a, b) return a.index < b.index end)

	-- Process segments
	for i, data in ipairs(partsToSort) do
		local part = data.part
		local index = data.index

		self.segments[index] = part
		self.basePositions[index] = part.Position
		self.segmentData[index] = {
			lastTransparency = 1,
			targetTransparency = 1,
			currentTransparency = 1,
			visible = false
		}

		local glow = part:FindFirstChild("Glow")
		if glow then
			self.glows[index] = glow
			glow.Brightness = 2 -- Slither.io style bright glow
		end
	end

	-- Collect beams
	local beamHolder = model:FindFirstChild("BeamHolder")
	if beamHolder then
		for _, beam in ipairs(beamHolder:GetChildren()) do
			if beam:IsA("Beam") then
				local index = tonumber(beam.Name:match("%d+"))
				if index then
					self.beams[index] = beam
					beam.Width0 = beam.Width0 * 1.2 -- Slightly thicker for visibility
					beam.Width1 = beam.Width1 * 1.2
				end
			end
		end
	end

	-- Eyes setup
	self.eyes = {}
	for _, name in ipairs({"LeftEye", "RightEye", "LeftEyePupil", "RightEyePupil"}) do
		local eye = model:FindFirstChild(name)
		if eye then
			table.insert(self.eyes, eye)
		end
	end

	-- State tracking
	self.lastHeadDistance = math.huge
	self.updateAccumulator = 0
	self.compressionRatio = 1
	self.totalLength = #self.segments

	-- Start invisible
	self:SetInitialVisibility()

	return self
end

function ClientSnake:SetInitialVisibility()
	for i, segment in pairs(self.segments) do
		segment.Transparency = 1
		local data = self.segmentData[i]
		data.currentTransparency = 1
		data.lastTransparency = 1
		data.targetTransparency = 1
	end

	for _, beam in pairs(self.beams) do
		beam.Transparency = NumberSequence.new(1)
	end

	for _, glow in pairs(self.glows) do
		glow.Enabled = false
	end

	for _, eye in ipairs(self.eyes) do
		eye.Transparency = 1
	end
end

function ClientSnake:UpdateSegmentVisibility(dt, cameraPos)
	local headPos = self.model:GetAttribute("HeadPosition") or self.head.Position
	local headDistance = (cameraPos - headPos).Magnitude

	-- Check if snake is in range at all
	if headDistance > VISIBILITY_CHECK_RADIUS then
		if self.lastHeadDistance <= VISIBILITY_CHECK_RADIUS then
			self:SetInitialVisibility()
		end
		self.lastHeadDistance = headDistance
		return
	end

	self.lastHeadDistance = headDistance

	-- Calculate compression ratio
	self.compressionRatio = calculateCompressionRatio(headDistance)
	local visibleSegmentCount = math.ceil(self.totalLength * self.compressionRatio)

	-- Calculate segment step for compression
	local segmentStep = self.totalLength / visibleSegmentCount

	-- Update each segment
	local visibleIndex = 0
	for i = 0, self.totalLength - 1 do
		local segment = self.segments[i]
		local data = self.segmentData[i]

		if segment then
			-- Determine if this segment should be shown based on compression
			local shouldShow = false
			local compressionAlpha = 1

			if self.compressionRatio < 1 then
				-- Calculate which segments to show
				local targetIndex = math.floor(visibleIndex * segmentStep)
				shouldShow = (i <= targetIndex + 1) and (visibleIndex < visibleSegmentCount)

				if shouldShow then
					-- Smooth transition for compressed segments
					local nextTargetIndex = math.floor((visibleIndex + 1) * segmentStep)
					if i > targetIndex then
						compressionAlpha = 1 - (i - targetIndex) / (nextTargetIndex - targetIndex + 1)
					end
					visibleIndex = visibleIndex + 1
				end
			else
				shouldShow = true
			end

			-- Calculate distance-based visibility
			local segmentPos = segment.Position
			local segmentDistance = (cameraPos - segmentPos).Magnitude
			local distanceAlpha = calculateSegmentVisibility(segmentDistance, i == 0)

			-- Combine compression and distance alpha
			local targetAlpha = shouldShow and (distanceAlpha * compressionAlpha) or 0
			data.targetTransparency = 1 - targetAlpha

			-- Smooth interpolation
			local diff = data.targetTransparency - data.currentTransparency
			if math.abs(diff) > 0.001 then
				data.currentTransparency = data.currentTransparency + diff * FADE_SMOOTHNESS
				segment.Transparency = data.currentTransparency

				-- Update associated visuals
				self:UpdateSegmentVisuals(i, data.currentTransparency, segmentDistance)
			end
		end
	end
end

function ClientSnake:UpdateSegmentVisuals(index, transparency, distance)
	-- Update beam
	local beam = self.beams[index]
	if beam then
		local nextData = self.segmentData[index + 1]
		local beamTransparency = transparency
		if nextData then
			beamTransparency = (transparency + nextData.currentTransparency) / 2
		end
		beam.Transparency = NumberSequence.new(beamTransparency)

		-- Slither.io style: beams get thinner at distance
		local widthMultiplier = math.max(0.5, 1 - (distance / FADE_END_DISTANCE) * 0.5)
		beam.Width0 = beam.Width0 * widthMultiplier
		beam.Width1 = beam.Width1 * widthMultiplier
	end

	-- Update glow
	local glow = self.glows[index]
	if glow then
		local glowDistance = distance * GLOW_DISTANCE_MULTIPLIER
		local glowAlpha = calculateSegmentVisibility(glowDistance, index == 0)
		glow.Enabled = glowAlpha > 0.1
		if glow.Enabled then
			glow.Brightness = 2 * glowAlpha -- Dynamic brightness
			glow.Range = 15 * glowAlpha -- Dynamic range
		end
	end

	-- Update eyes (only for head)
	if index == 0 then
		local eyeAlpha = 1 - transparency
		for _, eye in ipairs(self.eyes) do
			eye.Transparency = math.max(0.8, 1 - eyeAlpha) -- Eyes fade but stay slightly visible
		end
	end
end

function ClientSnake:Update(dt, cameraPos)
	self.updateAccumulator = self.updateAccumulator + dt

	-- Only update at specified rate
	if self.updateAccumulator >= UPDATE_INTERVAL then
		self:UpdateSegmentVisibility(self.updateAccumulator, cameraPos)
		self.updateAccumulator = 0
	end
end

function ClientSnake:Destroy()
	self:SetInitialVisibility()
	for k in pairs(self) do self[k] = nil end
end

-- ==================================
-- SnakeManager (Performance Optimized)
-- ==================================
local SnakeManager = {}
local trackedSnakes = {}
local snakeArray = {} -- For faster iteration
local lastUpdateTime = 0

function SnakeManager.Track(model)
	if not trackedSnakes[model] then
		task.wait() -- Ensure replication
		local newSnake = ClientSnake.new(model)
		if newSnake then
			trackedSnakes[model] = newSnake
			table.insert(snakeArray, {model = model, snake = newSnake})

			-- Sort by distance for rendering priority
			SnakeManager.SortSnakes()
		end
	end
end

function SnakeManager.Untrack(model)
	if trackedSnakes[model] then
		trackedSnakes[model]:Destroy()
		trackedSnakes[model] = nil

		-- Remove from array
		for i = #snakeArray, 1, -1 do
			if snakeArray[i].model == model then
				table.remove(snakeArray, i)
				break
			end
		end
	end
end

function SnakeManager.SortSnakes()
	local cameraPos = camera.CFrame.Position
	table.sort(snakeArray, function(a, b)
		local distA = (a.model:GetAttribute("HeadPosition") or a.snake.head.Position - cameraPos).Magnitude
		local distB = (b.model:GetAttribute("HeadPosition") or b.snake.head.Position - cameraPos).Magnitude
		return distA < distB
	end)
end

function SnakeManager.Update(dt)
	local currentTime = tick()
	local deltaTime = currentTime - lastUpdateTime
	lastUpdateTime = currentTime

	local cameraPos = camera.CFrame.Position
	local processed = 0

	-- Update snakes (prioritize closer ones)
	for i, data in ipairs(snakeArray) do
		if data.model and data.model.Parent then
			-- Limit processing for performance
			if processed < MAX_VISIBLE_SNAKES then
				data.snake:Update(deltaTime, cameraPos)
				processed = processed + 1
			else
				-- Force distant snakes to be hidden
				data.snake:SetInitialVisibility()
			end
		else
			SnakeManager.Untrack(data.model)
		end
	end

	-- Periodically resort snakes
	if currentTime % 1 < dt then
		SnakeManager.SortSnakes()
	end
end

-- Initialize
lastUpdateTime = tick()

for _, model in ipairs(CollectionService:GetTagged("AISnake")) do
	SnakeManager.Track(model)
end

CollectionService:GetInstanceAddedSignal("AISnake"):Connect(SnakeManager.Track)
CollectionService:GetInstanceRemovedSignal("AISnake"):Connect(SnakeManager.Untrack)
RunService.Heartbeat:Connect(SnakeManager.Update)

print("🐍 ClientAISnakeLOD v3.0: Slither.io-style ultra-smooth LOD initialized!")
print("   ✨ Distance-based fading | 🎯 Segment compression | ⚡ 30Hz updates")
