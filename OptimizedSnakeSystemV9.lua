-- Optimized Snake System V9 ULTIMATE - SEAMLESS UNIFIED RENDERING (FIXED GROWTH)
-- Perfect head-body integration with smooth growth transitions
-- ENHANCED: Fixed gap issues, improved LOD handling, stable at extreme lengths
-- 🚀 HYPER-ENHANCED: Professional visual effects from comprehensive research integration

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

-- LOD System Constants (ENHANCED FOR PERFORMANCE)
local LOD_UPDATE_RATE = 5 -- Check LOD every N frames
local LOD_MODES = {
	HIGH = { segments = 500, particles = true, glow = true, beamDetail = "full" },
	MEDIUM = { segments = 150, particles = false, glow = "sparse", beamDetail = "merged" },
	LOW = { segments = 50, particles = false, glow = false, beamDetail = "minimal" }
}

-- LOD Distance Zones with Hysteresis
local LOD_ZONES = {
	HERO = { enter = 0, exit = 270, mode = "HIGH" },      -- 0-250 studs with 20 stud buffer
	MID = { enter = 250, exit = 770, mode = "MEDIUM" },   -- 250-750 studs with buffer
	FAR = { enter = 750, exit = 1000, mode = "LOW" }      -- 750+ studs
}

-- Beam Merging Settings
local BEAM_MERGE_RATIOS = {
	full = 1,     -- 1 beam per segment
	merged = 5,   -- 1 beam per 5 segments
	minimal = 10  -- 1 beam per 10 segments
}

-- Performance Settings
local ENABLE_OVERLAP_BEAMS = true -- Can be toggled for performance
local COLLISION_SEGMENT_COUNT = 50 -- First N segments have collision
local GLOW_UPDATE_RATE = 3 -- Update glows every N frames
local PARTICLE_UPDATE_RATE = 5 -- Update particles every N frames

-- Performance Constants
local SEGMENT_UPDATE_RATE = 75
local NETWORK_UPDATE_RATE = 25
local MAX_SEGMENTS = 500
local SEGMENT_SPACING = 0.5 -- Tighter for seamless look
local HISTORY_SIZE = 2000
local GROWTH_CHECK_INTERVAL = 10

-- Visual Constants - UNIFIED RENDERING
local BASE_SIZE = 3.5 -- Unified base size for head and segments
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 2 -- Professional glow intensity (research: 0.7-2.0 optimal)
local GLOW_RANGE_BASE = 15
local BEAM_SEGMENTS = 10 -- Optimal segments (research: >10 has diminishing returns)
local BEAM_WIDTH_BASE = 0.95 -- Base beam width relative to segments
local BEAM_TAPER_STRENGTH = 0.15 -- How much beams taper (reduced from part taper)
local HEAD_SIZE_MULTIPLIER = 1.05 -- Reduced head size multiplier for consistency
local HEAD_BLEND_SEGMENTS = 8 -- More segments for smoother blend
local GLOW_FALLOFF_START = 50 -- Start reducing glow density after this many segments
local VISUAL_SMOOTHING_FACTOR = 0.6 -- Higher = smoother transitions

-- Growth Animation Constants (NEW)
local GROWTH_SPEED = 0.15 -- How fast we interpolate to target length (increased for smoother growth)
local SEGMENT_GROWTH_DELAY = 0.05 -- Delay between segment additions for smooth appearance
local GROWTH_PULSE_STRENGTH = 0.1 -- How much segments pulse when growing
local GROWTH_WAVE_SPEED = 10 -- Speed of growth wave effect

-- 🎨 PROFESSIONAL VISUAL ENHANCEMENT CONSTANTS
local BEAM_TEXTURE_SPEED = 2 -- Flow animation speed for beams
local PARTICLE_VELOCITY_INHERITANCE = 0.7 -- Natural trailing behavior
local PARTICLE_DRAG = 3 -- Exponential velocity decay for boost effects
local BOOST_PARTICLE_SIZE = NumberSequence.new{
	NumberSequenceKeypoint.new(0, 0.5),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0)
} -- Professional particle size curve
local MOBILE_PARTICLE_RATE = 100 -- Mobile optimized (50-150 range)
local DESKTOP_PARTICLE_RATE = 200 -- Desktop can handle more

-- 🌈 RAINBOW MODE CONSTANTS
local RAINBOW_SPEED = 2 -- HSV rotation speed
local RAINBOW_SEGMENT_OFFSET = 0.1 -- Offset between segments for wave effect

-- 📊 PROFESSIONAL TEXTURE LIBRARY FROM RESEARCH
local BEAM_TEXTURES = {
	gradient = "rbxasset://textures/ui/LuaChat/9-slice/kit-modal-highlight.png",
	flow = "rbxasset://textures/ui/GuiImagePlaceholder.png", 
	energy = "rbxasset://textures/particles/sparkles_main.dds",
	smooth = "rbxasset://textures/ui/LuaChat/icons/ic-gift.png"
}

-- ENHANCED VISIBILITY CONSTANTS
local VISIBILITY_CHECK_INTERVAL = 5 -- Check visibility every N frames
local RENDER_DISTANCE = 500 -- Force render within this distance
local LOD_DISTANCE_NEAR = 100 -- Full quality
local LOD_DISTANCE_MID = 250 -- Medium quality
local LOD_DISTANCE_FAR = 500 -- Low quality
local BEAM_SYNC_INTERVAL = 3 -- Sync beams with parts every N frames
local FORCE_RENDER_SEGMENTS = 150 -- Always force render first N segments
local VISIBILITY_BUFFER_ZONE = 50 -- Extra distance before culling

-- Create network events
local remoteEvents = {}
local function createNetworkEvents()
	local folder = ReplicatedStorage:FindFirstChild("SnakeNetworking")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SnakeNetworking"
		folder.Parent = ReplicatedStorage
	end

	local events = {"PositionUpdate", "LengthUpdate", "SkinUpdate", "BoostUpdate"}
	for _, eventName in ipairs(events) do
		local event = folder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = folder
		end
		remoteEvents[eventName:lower()] = event
	end
end

-- 🎨 PROFESSIONAL COLOR UTILITIES
local function HSVToRGB(h, s, v)
	h = h % 1  -- Ensure h is in [0, 1]
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)

	i = i % 6

	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	elseif i == 5 then return v, p, q
	end
end

-- Optimized Snake Class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	-- Initialize frameCount immediately to prevent any nil errors
	self.frameCount = 0

	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config or {}

	if not self.player then
		warn("⚠️ Failed to get player from character")
		return nil
	end

	-- Hide character model
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		elseif part:IsA("Accessory") then
			part:Destroy()
		end
	end

	self.rootPart.Transparency = 1
	self.rootPart.CanCollide = true
	self.rootPart.CanQuery = false
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Core snake data
	self.length = config.InitialLength or 10
	self.actualLength = self.length
	self.targetLength = self.length
	self.isBoosting = false
	self.growthFactor = 1
	self.lastGrowthCheck = 0

	-- 🎨 ENHANCED: Visual mode states
	self.rainbowMode = false
	self.currentHue = 0
	self.glowPulsePhase = 0
	self.beamAnimationOffset = 0

	-- 📊 ENHANCED: Performance detection
	self.isMobile = UserInputService.TouchEnabled
	self.qualityTier = self.isMobile and "mobile" or "desktop"
	self.particleRateMultiplier = self.isMobile and 0.5 or 1

	-- Growth animation state (NEW)
	self.isGrowing = false
	self.growthStartTime = 0
	self.lastSegmentAddTime = 0
	self.pendingGrowth = 0
	self.growthWaveOffset = 0
	
	-- Frame counter for update throttling (already initialized at constructor start)
	-- Double-check frameCount initialization
	if not self.frameCount or type(self.frameCount) ~= "number" then
		warn("⚠️ OptimizedSnakeSystemV9: frameCount was corrupted, resetting to 0")
		self.frameCount = 0
	end

	-- Movement history
	self.positionHistory = {}
	self.historyIndex = 0

	-- Visual components
	self.model = Instance.new("Model")
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace

	self.segments = {}
	self.beams = {}
	self.attachments = {}
	self.glows = {}
	self.visibleSegmentCount = 0

	-- ENHANCED: Visibility tracking
	self.segmentVisibility = {} -- Track visibility state of each segment
	self.lastVisibilityCheck = 0
	self.lastBeamSync = 0
	self.camera = workspace.CurrentCamera
	self.isLocalPlayer = (self.player == Players.LocalPlayer)

	-- ENHANCED: LOD state tracking
	self.lodStates = {} -- Track LOD level for each segment
	self.forcedRenderSegments = {} -- Segments that should always render

	-- Pre-fill history
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i = 1, HISTORY_SIZE do
		self.positionHistory[i] = {
			position = startPos,
			lookVector = startLook,
			time = tick()
		}
	end

	-- Initialize snake
	self:createUnifiedBody()
	self:startUpdateLoop()

	print("✅ Snake created for", self.player.Name)
	return self
end

function Snake:calculateGrowthFactor()
	local length = self.actualLength

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

-- Smooth size transition function
function Snake:getSegmentSize(index, baseSize)
	local sizeMult = 1

	-- Add growth pulse effect when growing
	if self.isGrowing then
		local timeSinceGrowth = tick() - self.growthStartTime
		local growthWave = math.sin((timeSinceGrowth * GROWTH_WAVE_SPEED) - (index * 0.2)) * GROWTH_PULSE_STRENGTH
		sizeMult = 1 + math.max(0, growthWave * (1 - timeSinceGrowth))
	end

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
		local taperFactor = 1 - (index / self.visibleSegmentCount) * 0.2
		-- Apply exponential smoothing to taper
		taperFactor = 1 - (1 - taperFactor) ^ 1.5
		return baseSize * taperFactor * sizeMult
	end
end

-- Calculate beam width with proper transitions
function Snake:getBeamWidth(index, baseSize)
	local segmentSize1 = self:getSegmentSize(index, baseSize)
	local segmentSize2 = self:getSegmentSize(index + 1, baseSize)

	-- Average the two segment sizes for smooth transition
	local avgSize = (segmentSize1 + segmentSize2) / 2

	-- Apply beam-specific taper (less than segment taper for fuller appearance)
	local beamTaper = 1 - (index / self.visibleSegmentCount) * BEAM_TAPER_STRENGTH

	return avgSize * BEAM_WIDTH_BASE * beamTaper
end

-- ENHANCED: Calculate LOD level based on distance
function Snake:calculateLODLevel(segmentIndex, cameraPosition)
	if not cameraPosition then return "near" end

	local segment = self.segments[segmentIndex]
	if not segment or not segment.Parent then return "culled" end

	-- Always full quality for first segments
	if segmentIndex <= FORCE_RENDER_SEGMENTS then
		return "near"
	end

	local distance = (segment.Position - cameraPosition).Magnitude

	if distance <= LOD_DISTANCE_NEAR then
		return "near"
	elseif distance <= LOD_DISTANCE_MID then
		return "mid"
	elseif distance <= LOD_DISTANCE_FAR then
		return "far"
	else
		return "culled"
	end
end

-- ENHANCED: Apply LOD settings to segment
function Snake:applyLODToSegment(segment, lodLevel, index)
	if not segment or not segment.Parent then return end

	-- Store LOD state
	self.lodStates[index] = lodLevel

	if lodLevel == "culled" then
		-- Don't actually hide the part, just reduce quality
		segment.Transparency = 0.3
		if self.glows[index] then
			self.glows[index].Enabled = false
		end
	elseif lodLevel == "far" then
		segment.Transparency = 0.1
		if self.glows[index] then
			self.glows[index].Enabled = false
		end
	elseif lodLevel == "mid" then
		segment.Transparency = 0
		if self.glows[index] then
			self.glows[index].Enabled = (index % 3 == 0)
		end
	else -- near
		segment.Transparency = 0
		if self.glows[index] then
			self.glows[index].Enabled = true
		end
	end

	-- Mark as visible
	self.segmentVisibility[index] = true
end

-- ENHANCED: Force render important segments
function Snake:forceRenderSegment(segment, index)
	if not segment or not segment.Parent then return end

	-- Set render fidelity hints
	segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Precise)
	segment:SetAttribute("AlwaysRender", true)

	-- Ensure part stays visible
	segment.Transparency = 0

	-- Mark for forced rendering
	self.forcedRenderSegments[index] = true
end

-- 🎨 ENHANCED: Get segment color with rainbow mode support
function Snake:getSegmentColor(index)
	if self.rainbowMode then
		-- Professional HSV rainbow implementation
		local hue = (self.currentHue + (index * RAINBOW_SEGMENT_OFFSET)) % 1
		local r, g, b = HSVToRGB(hue, 1, 1)
		return Color3.new(r, g, b)
	else
		-- Original color logic
		if index == 0 then
			return self.config.HeadColor or self.config.BodyColors[1]
		elseif index <= HEAD_BLEND_SEGMENTS then
			local blendFactor = (index / HEAD_BLEND_SEGMENTS) ^ 0.7
			local headColor = self.config.HeadColor or self.config.BodyColors[1]
			local bodyColor = self.config.BodyColors[1]
			return headColor:Lerp(bodyColor, blendFactor)
		else
			local colorIndex = ((index - 1) % #self.config.BodyColors) + 1
			return self.config.BodyColors[colorIndex]
		end
	end
end

function Snake:createUnifiedBody()
	-- Calculate initial segment count
	local segmentCount = math.min(math.ceil(self.length / 2), MAX_SEGMENTS)

	-- Create attachment holder part
	local attachmentPart = Instance.new("Part")
	attachmentPart.Name = "BeamHolder"
	attachmentPart.Transparency = 1
	attachmentPart.CanCollide = false
	attachmentPart.CanQuery = false
	attachmentPart.Anchored = true
	attachmentPart.Size = Vector3.new(1, 1, 1)
	attachmentPart.Parent = self.model

	-- ENHANCED: Keep attachment part always rendered
	attachmentPart:SetAttribute("AlwaysRender", true)

	-- HEAD IS NOW SEGMENT 0 - Part of the unified body
	local head = Instance.new("Part")
	head.Name = "Segment0_Head"
	head.Shape = Enum.PartType.Ball
	head.Material = Enum.Material.Neon -- Neon for consistent look
	head.Color = self:getSegmentColor(0)
	head.Size = Vector3.new(BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER, BASE_SIZE * HEAD_SIZE_MULTIPLIER)
	head.Transparency = 0
	head.CanCollide = false
	head.CanTouch = true
	head.CanQuery = true
	head.Anchored = true
	head.Parent = self.model

	-- ENHANCED: Force head to always render
	self:forceRenderSegment(head, 0)

	-- 💡 ENHANCED: Professional head glow with research-based values
	local headGlow = Instance.new("PointLight")
	headGlow.Name = "Glow"
	headGlow.Brightness = GLOW_INTENSITY
	headGlow.Range = GLOW_RANGE_BASE * 1.1
	headGlow.Color = head.Color
	headGlow.Shadows = false -- Research: shadows add 2-4ms render time
	headGlow.Parent = head

	-- 🚀 ENHANCED: Professional boost particles with research-based optimization
	local particle = Instance.new("ParticleEmitter")
	particle.Name = "BoostParticles"
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(head.Color)
	particle.Lifetime = NumberRange.new(0.5, 1)
	particle.Rate = 0
	particle.Speed = NumberRange.new(5, 10)
	particle.SpreadAngle = Vector2.new(180, 180)
	particle.VelocityInheritance = PARTICLE_VELOCITY_INHERITANCE -- Research: 0.7 optimal
	particle.Drag = PARTICLE_DRAG -- Research: 2-5 for boost effects
	particle.Size = BOOST_PARTICLE_SIZE -- Professional size curve
	particle.Rotation = NumberRange.new(0, 360)
	particle.RotSpeed = NumberRange.new(-180, 180)
	particle.Enabled = false
	particle.LightEmission = 1
	particle.LightInfluence = 0
	particle.ZOffset = 1 -- Render above snake
	particle.Parent = head

	-- Eyes for character (smaller, integrated)
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = Vector3.new(0.5, 0.5, 0.5)
		eye.Transparency = 0
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model

		-- ENHANCED: Eyes always render
		eye:SetAttribute("AlwaysRender", true)

		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = Vector3.new(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model

		-- ENHANCED: Pupils always render
		pupil:SetAttribute("AlwaysRender", true)

		return eye, pupil
	end

	self.leftEye, self.leftPupil = createEye(-0.6)
	self.rightEye, self.rightPupil = createEye(0.6)

	-- Collision tagging for head
	CollectionService:AddTag(head, "SnakeHead")
	head:SetAttribute("PlayerId", self.player.UserId)

	-- Store head as segment 0
	self.segments[0] = head
	self.head = head
	self.headGlow = headGlow
	self.boostParticles = particle
	self.glows[0] = headGlow
	self.segmentVisibility[0] = true

	-- Create head attachment
	local headAttachment = Instance.new("Attachment")
	headAttachment.Name = "Attachment0"
	headAttachment.Parent = attachmentPart
	self.attachments[0] = headAttachment

	-- Create body segments starting from 1
	for i = 1, segmentCount do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon -- Consistent material

		-- Use new size calculation
		local segmentSize = self:getSegmentSize(i, BASE_SIZE)
		segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

		segment.Transparency = 0
		segment.CanCollide = false
		segment.CanTouch = i <= 50 -- Collision for first 50
		segment.CanQuery = false
		segment.Anchored = true

		-- ENHANCED: Set render fidelity for important segments
		if i <= FORCE_RENDER_SEGMENTS then
			self:forceRenderSegment(segment, i)
		else
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Automatic)
		end

		-- 🎨 ENHANCED: Use new color system
		segment.Color = self:getSegmentColor(i)

		-- Strategic glow placement for performance
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = true -- All segments up to falloff
		elseif i <= 100 then
			shouldHaveGlow = i % 2 == 0 -- Every other segment
		elseif i <= 200 then
			shouldHaveGlow = i % 3 == 0 -- Every third
		else
			shouldHaveGlow = i % 5 == 0 -- Every fifth
		end

		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9 -- Slightly dimmer than head
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / segmentCount) * 0.1) -- Gradual range decrease
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end

		segment.Parent = self.model
		self.segments[i] = segment
		self.segmentVisibility[i] = true

		-- Collision tagging
		if i <= 50 then
			CollectionService:AddTag(segment, "SnakeSegment")
			segment:SetAttribute("SegmentIndex", i)
			segment:SetAttribute("OwnerName", self.player.Name)
		end

		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = attachmentPart
		self.attachments[i] = attachment
	end

	-- Create seamless beams between all segments
	for i = 0, segmentCount - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "Beam" .. i
		beam.Attachment0 = self.attachments[i]
		beam.Attachment1 = self.attachments[i + 1]

		-- 🎨 ENHANCED: Professional beam properties with advanced textures
		local beamWidth = self:getBeamWidth(i, BASE_SIZE)
		beam.Width0 = beamWidth
		beam.Width1 = beamWidth
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.FaceCamera = true
		beam.Segments = BEAM_SEGMENTS
		-- ENHANCED: Professional gradient texture choices
		beam.Texture = BEAM_TEXTURES.gradient -- Superior gradient
		beam.TextureMode = Enum.TextureMode.Wrap -- Research: Wrap + TextureSpeed = flowing motion
		beam.TextureLength = 2
		beam.TextureSpeed = BEAM_TEXTURE_SPEED -- Animated flow effect
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 2 -- Enhanced brightness for glow
		beam.Transparency = NumberSequence.new{
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.1) -- Slight fade at edges
		}

		-- Color matching with smooth transitions
		if i == 0 then
			-- Head to first segment - smooth color transition
			local headColor = self.segments[0].Color
			local seg1Color = self.segments[1].Color
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
		self.beams[i] = beam
	end

	-- Create selective overlap beams for critical areas only
	-- Focus on head blend area and early segments
	for i = 0, math.min(segmentCount - 2, HEAD_BLEND_SEGMENTS * 2) do
		if i % 2 == 0 then -- Every other segment
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. i
			overlapBeam.Attachment0 = self.attachments[i]
			overlapBeam.Attachment1 = self.attachments[i + 2]

			-- Calculate overlap beam width
			local overlapWidth = self:getBeamWidth(i, BASE_SIZE) * 1.15 -- Only 15% wider
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = BEAM_TEXTURES.gradient
			overlapBeam.TextureMode = Enum.TextureMode.Wrap
			overlapBeam.TextureLength = 3
			overlapBeam.TextureSpeed = BEAM_TEXTURE_SPEED * 0.7 -- Slower for variety
			overlapBeam.LightEmission = 0.7
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.5) -- More transparent
			overlapBeam.ZOffset = -0.1 -- Behind main beams

			-- Color
			overlapBeam.Color = ColorSequence.new(self:getSegmentColor(i))

			overlapBeam.Parent = attachmentPart
			self.beams["overlap" .. i] = overlapBeam
		end
	end

	-- Add some strategic overlap beams for the mid-section
	for i = HEAD_BLEND_SEGMENTS * 2, math.min(segmentCount - 3, 50), 3 do
		local overlapBeam = Instance.new("Beam")
		overlapBeam.Name = "OverlapBeamMid" .. i
		overlapBeam.Attachment0 = self.attachments[i]
		overlapBeam.Attachment1 = self.attachments[i + 3]

		local overlapWidth = self:getBeamWidth(i, BASE_SIZE) * 1.1
		overlapBeam.Width0 = overlapWidth
		overlapBeam.Width1 = overlapWidth
		overlapBeam.CurveSize0 = 0
		overlapBeam.CurveSize1 = 0
		overlapBeam.FaceCamera = true
		overlapBeam.Segments = BEAM_SEGMENTS
		overlapBeam.Texture = BEAM_TEXTURES.gradient
		overlapBeam.TextureMode = Enum.TextureMode.Wrap
		overlapBeam.TextureLength = 4
		overlapBeam.TextureSpeed = BEAM_TEXTURE_SPEED * 0.5
		overlapBeam.LightEmission = 0.6
		overlapBeam.LightInfluence = 0
		overlapBeam.Transparency = NumberSequence.new(0.6)
		overlapBeam.ZOffset = -0.1

		overlapBeam.Color = ColorSequence.new(self:getSegmentColor(i))

		overlapBeam.Parent = attachmentPart
		self.beams["overlapMid" .. i] = overlapBeam
	end

	self.attachmentPart = attachmentPart
	self.visibleSegmentCount = segmentCount
end

function Snake:updatePositionHistory()
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector,
		time = tick()
	}
end

function Snake:getHistoricalPosition(stepsBack)
	local index = self.historyIndex - stepsBack
	if index < 1 then
		index = index + HISTORY_SIZE
	end
	return self.positionHistory[index]
end

-- ENHANCED: Update visibility for all segments
function Snake:updateSegmentVisibility(cameraPosition)
	for i = 0, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			local lodLevel = self:calculateLODLevel(i, cameraPosition)
			self:applyLODToSegment(segment, lodLevel, i)
		end
	end
end

-- ENHANCED: Synchronize beam visibility with segments
function Snake:syncBeamVisibility()
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				-- Regular beams
				local seg1Visible = self.segmentVisibility[i] ~= false
				local seg2Visible = self.segmentVisibility[i + 1] ~= false

				-- Beam is visible if both segments are visible
				beam.Enabled = seg1Visible and seg2Visible and i <= self.visibleSegmentCount

				-- Adjust transparency based on segment LOD
				local lod1 = self.lodStates[i] or "near"
				local lod2 = self.lodStates[i + 1] or "near"

				if lod1 == "culled" or lod2 == "culled" then
					beam.Transparency = NumberSequence.new(0.5)
				elseif lod1 == "far" or lod2 == "far" then
					beam.Transparency = NumberSequence.new(0.2)
				else
					beam.Transparency = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 0.1)
					}
				end
			end
		end
	end
end

-- 🎨 ENHANCED: Toggle rainbow mode
function Snake:toggleRainbowMode(enabled)
	self.rainbowMode = enabled
	if enabled then
		print("🌈 Rainbow mode activated!")
	end
end

function Snake:startUpdateLoop()
	local lastNetworkUpdate = 0

	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Robust nil checks
		if not self or not self.character or not self.character.Parent or not self.rootPart or not self.rootPart.Parent then
			if self and self.destroy then
				self:destroy()
			end
			return
		end

		-- Ensure frameCount is always a valid number (extra safety)
		if not self.frameCount or type(self.frameCount) ~= "number" then
			self.frameCount = 0
		end
		self.frameCount = (self.frameCount or 0) + 1

		-- 🎯 SMART UPDATE THROTTLING
		-- Every frame: Critical movement
		self:updatePositionHistory()
		self:updateUnifiedBody()
		
		-- Every 3rd frame: Visual effects
		if self.frameCount and self.frameCount % GLOW_UPDATE_RATE == 0 then
			self:updateVisualEffects()
		end
		
		-- Every 5th frame: LOD and visibility
		if self.frameCount and self.frameCount % LOD_UPDATE_RATE == 0 then
			-- checkVisibility method doesn't exist, visibility is handled in the main update loop
		end
		
		-- Every 5th frame: Particle updates
		if self.frameCount and self.frameCount % PARTICLE_UPDATE_RATE == 0 then
			self:updateParticles()
		end

		-- Smooth length interpolation with growth animation tracking
		if self.actualLength ~= self.targetLength then
			local diff = self.targetLength - self.actualLength
			local growthRate = GROWTH_SPEED

			-- Start growth animation if we're growing
			if diff > 0.1 and not self.isGrowing then
				self.isGrowing = true
				self.growthStartTime = tick()
			end

			-- Use smoother interpolation for growth
			self.actualLength = self.actualLength + diff * growthRate

			-- Stop growth animation when we reach target
			if math.abs(diff) < 0.1 then
				self.actualLength = self.targetLength
				self.isGrowing = false
			end
		else
			self.isGrowing = false
		end

		-- Update growth factor
		if self.frameCount and self.frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self.growthFactor = self:calculateGrowthFactor()
		end

		-- ENHANCED: Update visibility checks
		local cameraPos = self.camera and self.camera.CFrame.Position or self.rootPart.Position
		if self.frameCount and self.frameCount % VISIBILITY_CHECK_INTERVAL == 0 then
			self:updateSegmentVisibility(cameraPos)
		end

		-- ENHANCED: Sync beams with segment visibility
		if self.frameCount and self.frameCount % BEAM_SYNC_INTERVAL == 0 then
			self:syncBeamVisibility()
		end

		-- Update visuals
		self:updateUnifiedBody()

		-- Handle boost effects
		if self.isBoosting then
			-- 🚀 ENHANCED: Professional boost effects
			local rate = self.isMobile and MOBILE_PARTICLE_RATE or DESKTOP_PARTICLE_RATE
			self.boostParticles.Rate = rate * self.particleRateMultiplier

			-- Enhance all glows during boost with pulse
			local pulseMult = 1 + math.sin(self.glowPulsePhase) * 0.2
			for _, glow in pairs(self.glows) do
				if glow and glow.Parent then
					glow.Brightness = GLOW_INTENSITY * 1.5 * pulseMult
				end
			end
		else
			self.boostParticles.Rate = 0
			-- Normal glow with subtle pulse
			local pulseMult = 1 + math.sin(self.glowPulsePhase) * 0.05
			for _, glow in pairs(self.glows) do
				if glow and glow.Parent then
					glow.Brightness = GLOW_INTENSITY * pulseMult
				end
			end
		end

		-- Network updates (optimized rate)
		if self.frameCount and self.frameCount % NETWORK_UPDATE_RATE == 0 then
			self:sendNetworkUpdate()
		end
	end)
end

function Snake:updateUnifiedBody()
	-- DYNAMIC SEGMENT BUDGET (Performance Optimization)
	local cameraDist = 0
	if workspace.CurrentCamera then
		cameraDist = (self.head.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
	end
	
	-- Determine segment budget based on distance
	local segmentBudget = MAX_SEGMENTS
	local currentLODMode = "HIGH"
	
	if cameraDist > LOD_ZONES.FAR.enter then
		segmentBudget = LOD_MODES.LOW.segments
		currentLODMode = "LOW"
	elseif cameraDist > LOD_ZONES.MID.enter then
		segmentBudget = LOD_MODES.MEDIUM.segments
		currentLODMode = "MEDIUM"
	end
	
	-- Store LOD mode for other systems
	self.currentLODMode = currentLODMode
	
	-- Calculate required segments
	local requiredSegments = math.min(math.ceil(self.actualLength / 2), MAX_SEGMENTS)
	
	-- Apply segment budget
	local segmentsToUpdate = math.min(requiredSegments, segmentBudget, self.visibleSegmentCount)

	-- Add new segments if grown with smooth animation
	if requiredSegments > self.visibleSegmentCount then
		local now = tick()
		if now - self.lastSegmentAddTime > SEGMENT_GROWTH_DELAY then
			self:addSegments(1) -- Add one at a time for smooth growth
			self.lastSegmentAddTime = now
		end
	end

	-- Calculate sizes based on growth
	local currentBaseSize = BASE_SIZE * self.growthFactor
	local spacing = currentBaseSize * SEGMENT_SPACING

	-- Update all segments including head (segment 0) - LIMITED BY BUDGET
	for i = 0, segmentsToUpdate do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- ENHANCED: Only update visible segments for performance
			local isVisible = self.segmentVisibility[i] ~= false

			-- 🎨 ENHANCED: Update colors for rainbow mode
			if self.rainbowMode and i % 3 == 0 then -- Update every 3rd segment for performance
				segment.Color = self:getSegmentColor(i)
				if self.glows[i] then
					self.glows[i].Color = segment.Color
				end
			end

			if i == 0 then
				-- Head positioning
				local cf = CFrame.lookAt(
					self.rootPart.Position,
					self.rootPart.Position + self.rootPart.CFrame.LookVector
				)
				segment.CFrame = cf

				-- Use calculated head size
				local headSize = self:getSegmentSize(0, currentBaseSize)
				segment.Size = Vector3.new(headSize, headSize, headSize)

				-- Update eyes with proper scaling
				local eyeScale = headSize / BASE_SIZE * 0.5
				local eyeOffset = headSize * 0.3
				local eyeForward = -headSize * 0.35

				self.leftEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				self.rightEye.Size = Vector3.new(eyeScale, eyeScale, eyeScale)
				self.leftPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
				self.rightPupil.Size = Vector3.new(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)

				self.leftEye.CFrame = cf * CFrame.new(-eyeOffset, eyeOffset * 0.5, eyeForward)
				self.rightEye.CFrame = cf * CFrame.new(eyeOffset, eyeOffset * 0.5, eyeForward)
				self.leftPupil.CFrame = self.leftEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
				self.rightPupil.CFrame = self.rightEye.CFrame * CFrame.new(0, 0, -eyeScale * 0.3)
			elseif isVisible or i <= FORCE_RENDER_SEGMENTS then
				-- Body segment positioning
				local stepsBack = math.floor(i * spacing / 2)
				local histData = self:getHistoricalPosition(stepsBack)
				local nextHistData = self:getHistoricalPosition(stepsBack + 1)

				if histData and nextHistData then
					-- Smooth interpolation
					local alpha = (i * spacing / 2) % 1
					local targetPos = histData.position:Lerp(nextHistData.position, alpha)
					local currentPos = segment.Position

					-- Use higher smoothing during growth for smoother transitions
					local smoothingFactor = self.isGrowing and VISUAL_SMOOTHING_FACTOR * 1.2 or VISUAL_SMOOTHING_FACTOR
					segment.Position = currentPos:Lerp(targetPos, smoothingFactor)

					-- Use calculated segment size
					local segmentSize = self:getSegmentSize(i, currentBaseSize)
					segment.Size = Vector3.new(segmentSize, segmentSize, segmentSize)

					-- Pulse effect during boost
					if self.isBoosting then
						local pulse = math.sin(tick() * 10 + i * 0.1) * 0.03 + 1 -- Reduced pulse
						segment.Size = segment.Size * pulse
					end
				end
			end

			-- Update attachment position
			if self.attachments[i] then
				self.attachments[i].WorldPosition = segment.Position
			end
		end
	end

	-- Update all beams with calculated widths
	for i, beam in pairs(self.beams) do
		if beam and beam.Parent then
			if type(i) == "number" then
				-- Regular beams
				if i <= self.visibleSegmentCount then
					local beamWidth = self:getBeamWidth(i, currentBaseSize)
					beam.Width0 = beamWidth
					beam.Width1 = beamWidth

					-- 🎨 ENHANCED: Update beam colors for rainbow mode
					if self.rainbowMode and i % 5 == 0 then
						beam.Color = ColorSequence.new(self:getSegmentColor(i))
					end

					-- Dynamic color during boost
					if self.isBoosting and i > HEAD_BLEND_SEGMENTS and not self.rainbowMode then
						local colorShift = math.floor(tick() * 3) % #self.config.BodyColors
						local colorIndex = ((i - 1 + colorShift) % #self.config.BodyColors) + 1
						beam.Color = ColorSequence.new(self.config.BodyColors[colorIndex])
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlap") then
				-- Overlap beams
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 2 then
					local overlapWidth = self:getBeamWidth(index, currentBaseSize) * 1.15
					beam.Width0 = overlapWidth
					beam.Width1 = overlapWidth

					-- Update colors for rainbow mode
					if self.rainbowMode and index % 5 == 0 then
						beam.Color = ColorSequence.new(self:getSegmentColor(index))
					end
				else
					beam.Enabled = false
				end
			elseif string.find(i, "overlapMid") then
				-- Mid overlap beams
				local index = tonumber(string.match(i, "%d+"))
				if index and index <= self.visibleSegmentCount - 3 then
					local overlapWidth = self:getBeamWidth(index, currentBaseSize) * 1.1
					beam.Width0 = overlapWidth
					beam.Width1 = overlapWidth

					-- Update colors for rainbow mode
					if self.rainbowMode and index % 5 == 0 then
						beam.Color = ColorSequence.new(self:getSegmentColor(index))
					end
				else
					beam.Enabled = false
				end
			end
		end
	end

	-- Update glow ranges based on size
	for i, glow in pairs(self.glows) do
		if glow and glow.Parent then
			local glowScale = 1 - (i / self.visibleSegmentCount) * 0.3 -- Gradual glow reduction
			glow.Range = (GLOW_RANGE_BASE + (currentBaseSize - BASE_SIZE) * 2) * glowScale
		end
	end
	
	-- HIDE SEGMENTS OVER BUDGET (with smooth fade)
	for i = segmentsToUpdate + 1, self.visibleSegmentCount do
		local segment = self.segments[i]
		if segment and segment.Parent then
			-- Fade out smoothly if transitioning
			if segment.Transparency < 1 then
				segment.Transparency = math.min(segment.Transparency + 0.1, 1)
			end
			
			-- Disable collision for hidden segments
			segment.CanCollide = false
			segment.CanTouch = false
			segment.CanQuery = false
		end
		
		-- Disable beams for hidden segments
		if self.beams[i] then
			self.beams[i].Enabled = false
		end
		if self.overlapBeams and self.overlapBeams[i] then
			self.overlapBeams[i].Enabled = false
		end
		
		-- Disable glows for hidden segments
		if self.glows[i] then
			self.glows[i].Enabled = false
		end
	end
	
	-- Force visibility check with new system
end

function Snake:addSegments(count)
	for i = self.visibleSegmentCount + 1, self.visibleSegmentCount + count do
		if i > MAX_SEGMENTS then break end

		-- Create new segment with fade-in effect
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. i
		segment.Shape = Enum.PartType.Ball
		segment.Material = Enum.Material.Neon

		-- Start small for growth animation
		local targetSize = self:getSegmentSize(i, BASE_SIZE * self.growthFactor)
		segment.Size = Vector3.new(targetSize * 0.1, targetSize * 0.1, targetSize * 0.1)

		segment.Transparency = 0.8 -- Start more transparent
		segment.CanCollide = false
		segment.CanTouch = i <= 50
		segment.CanQuery = false
		segment.Anchored = true

		-- ENHANCED: Apply render settings to new segments
		if i <= FORCE_RENDER_SEGMENTS then
			self:forceRenderSegment(segment, i)
		else
			segment:SetAttribute("RenderFidelity", Enum.RenderFidelity.Automatic)
		end

		segment.Color = self:getSegmentColor(i)

		-- Position at last segment initially
		if self.segments[i - 1] then
			segment.Position = self.segments[i - 1].Position
		end

		-- Add glow based on falloff rules
		local shouldHaveGlow = false
		if i <= GLOW_FALLOFF_START then
			shouldHaveGlow = true
		elseif i <= 100 then
			shouldHaveGlow = i % 2 == 0
		elseif i <= 200 then
			shouldHaveGlow = i % 3 == 0
		else
			shouldHaveGlow = i % 5 == 0
		end

		if shouldHaveGlow then
			local segmentGlow = Instance.new("PointLight")
			segmentGlow.Name = "Glow"
			segmentGlow.Brightness = GLOW_INTENSITY * 0.9
			segmentGlow.Range = GLOW_RANGE_BASE * (0.9 - (i / MAX_SEGMENTS) * 0.2)
			segmentGlow.Color = segment.Color
			segmentGlow.Shadows = false
			segmentGlow.Parent = segment
			self.glows[i] = segmentGlow
		end

		segment.Parent = self.model
		self.segments[i] = segment
		self.segmentVisibility[i] = true
		self.lodStates[i] = "near"

		-- Animate growth
		TweenService:Create(segment, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(targetSize, targetSize, targetSize),
			Transparency = 0
		}):Play()

		-- Add attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "Attachment" .. i
		attachment.Parent = self.attachmentPart
		self.attachments[i] = attachment

		-- Create beam from previous segment
		if self.attachments[i - 1] then
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. (i - 1)
			beam.Attachment0 = self.attachments[i - 1]
			beam.Attachment1 = self.attachments[i]

			-- Calculate beam width for new segment
			local beamWidth = self:getBeamWidth(i - 1, BASE_SIZE * self.growthFactor)
			beam.Width0 = beamWidth * 0.1 -- Start thin
			beam.Width1 = beamWidth * 0.1
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
			beam.Transparency = NumberSequence.new(0.8) -- Start more transparent

			beam.Color = ColorSequence.new(self:getSegmentColor(i))

			beam.Parent = self.attachmentPart
			self.beams[i - 1] = beam

			-- Animate beam growth (width only - transparency needs custom animation)
			TweenService:Create(beam, TweenInfo.new(0.3), {
				Width0 = beamWidth,
				Width1 = beamWidth
			}):Play()

			-- Custom transparency animation for NumberSequence
			local startTime = tick()
			local transparencyConnection
			transparencyConnection = RunService.Heartbeat:Connect(function()
				local elapsed = tick() - startTime
				local progress = math.min(elapsed / 0.3, 1) -- 0.3 second duration

				-- Interpolate from 0.8 to final transparency
				local transparency = 0.8 * (1 - progress)
				beam.Transparency = NumberSequence.new{
					NumberSequenceKeypoint.new(0, transparency),
					NumberSequenceKeypoint.new(0.5, transparency),
					NumberSequenceKeypoint.new(1, transparency + 0.1)
				}

				if progress >= 1 then
					transparencyConnection:Disconnect()
				end
			end)
		end

		-- Add strategic overlap beams for new segments in critical areas
		if i <= HEAD_BLEND_SEGMENTS * 2 and i > 2 and i % 2 == 0 then
			local overlapBeam = Instance.new("Beam")
			overlapBeam.Name = "OverlapBeam" .. (i - 2)
			overlapBeam.Attachment0 = self.attachments[i - 2]
			overlapBeam.Attachment1 = self.attachments[i]

			local overlapWidth = self:getBeamWidth(i - 2, BASE_SIZE * self.growthFactor) * 1.15
			overlapBeam.Width0 = overlapWidth
			overlapBeam.Width1 = overlapWidth
			overlapBeam.CurveSize0 = 0
			overlapBeam.CurveSize1 = 0
			overlapBeam.FaceCamera = true
			overlapBeam.Segments = BEAM_SEGMENTS
			overlapBeam.Texture = BEAM_TEXTURES.gradient
			overlapBeam.TextureMode = Enum.TextureMode.Wrap
			overlapBeam.TextureLength = 3
			overlapBeam.TextureSpeed = BEAM_TEXTURE_SPEED * 0.7
			overlapBeam.LightEmission = 0.7
			overlapBeam.LightInfluence = 0
			overlapBeam.Transparency = NumberSequence.new(0.5)
			overlapBeam.ZOffset = -0.1

			overlapBeam.Color = ColorSequence.new(self:getSegmentColor(i - 2))

			overlapBeam.Parent = self.attachmentPart
			self.beams["overlap" .. (i - 2)] = overlapBeam
		end
	end

	self.visibleSegmentCount = math.min(self.visibleSegmentCount + count, MAX_SEGMENTS)
end

function Snake:grow(amount)
	-- Store pending growth for smooth animation
	self.pendingGrowth = self.pendingGrowth + (amount or 1)
	self.targetLength = math.min(self.targetLength + (amount or 1), 50000)

	-- 🎨 ENHANCED: Professional growth visual feedback
	if self.head and self.headGlow then
		-- Flash effect with color shift
		local originalBrightness = self.headGlow.Brightness
		self.headGlow.Brightness = GLOW_INTENSITY * 2.5

		-- Create growth particle burst
		local growthBurst = Instance.new("ParticleEmitter")
		growthBurst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		growthBurst.Color = ColorSequence.new(self.head.Color)
		growthBurst.Lifetime = NumberRange.new(0.3, 0.5)
		growthBurst.Rate = 0
		growthBurst.Speed = NumberRange.new(10, 20)
		growthBurst.SpreadAngle = Vector2.new(360, 360)
		growthBurst.VelocityInheritance = 0
		growthBurst.EmissionDirection = Enum.NormalId.Front
		growthBurst.Enabled = true
		growthBurst.Parent = self.head
		growthBurst:Emit(30)

		Debris:AddItem(growthBurst, 1)

		TweenService:Create(self.headGlow, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Brightness = originalBrightness
		}):Play()
	end

	if self.player then
		local leaderstats = self.player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue then
				lengthValue.Value = math.floor(self.targetLength)
			end
		end
	end
end

function Snake:setBoosting(boosting)
	self.isBoosting = boosting

	if boosting then
		self.boostParticles.Enabled = true

		-- 🚀 ENHANCED: Professional speed effects
		for i = 1, 8 do -- More speed lines
			local speedLine = Instance.new("Part")
			speedLine.Name = "SpeedLine"
			speedLine.Size = Vector3.new(0.2, 0.2, math.random(8, 15))
			speedLine.Material = Enum.Material.Neon
			speedLine.Color = self.head.Color
			speedLine.CanCollide = false
			speedLine.Anchored = true
			speedLine.CFrame = self.head.CFrame * CFrame.new(
				math.random(-4, 4),
				math.random(-4, 4),
				5
			) * CFrame.Angles(0, 0, math.random() * math.pi * 2)
			speedLine.Parent = self.model

			-- Add glow to speed lines
			local speedGlow = Instance.new("PointLight")
			speedGlow.Brightness = 1
			speedGlow.Range = 5
			speedGlow.Color = speedLine.Color
			speedGlow.Parent = speedLine

			local tween = TweenService:Create(speedLine,
				TweenInfo.new(0.4, Enum.EasingStyle.Linear),
				{
					Transparency = 1,
					Size = Vector3.new(0.05, 0.05, 25),
					CFrame = speedLine.CFrame * CFrame.new(0, 0, -20)
				}
			)
			tween:Play()
			Debris:AddItem(speedLine, 0.4)
		end

		-- Camera shake effect for local player
		if self.isLocalPlayer then
			local camera = workspace.CurrentCamera
			local originalCF = camera.CFrame

			spawn(function()
				for i = 1, 10 do
					if not self.isBoosting then break end
					camera.CFrame = originalCF * CFrame.Angles(
						math.rad(math.random(-1, 1) * 0.5),
						math.rad(math.random(-1, 1) * 0.5),
						0
					)
					wait(0.03)
				end
				camera.CFrame = originalCF
			end)
		end
	else
		self.boostParticles.Enabled = false
	end
end

function Snake:sendNetworkUpdate()
	if remoteEvents.positionupdate then
		remoteEvents.positionupdate:FireServer({
			position = self.rootPart.Position,
			lookVector = self.rootPart.CFrame.LookVector,
			length = self.targetLength,
			boosting = self.isBoosting,
			rainbowMode = self.rainbowMode -- Include visual mode
		})
	end
end

function Snake:updateLength(newLength)
	self.targetLength = math.min(newLength, 50000)
end

function Snake:GetSegments()
	local collisionSegments = {}
	for i = 1, math.min(50, self.visibleSegmentCount) do
		if self.segments[i] and self.segments[i].Parent then
			table.insert(collisionSegments, self.segments[i])
		end
	end
	return collisionSegments
end

function Snake:GetLength()
	return math.floor(self.targetLength)
end

function Snake:destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

-- Module
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	createNetworkEvents()
	print("✅ Snake System V9 ULTIMATE - HYPER-ENHANCED WITH PROFESSIONAL VISUALS")
	print("🐍 Features: Fixed Gap Issues | Enhanced LOD | Stable at Extreme Lengths")
	print("🔧 Improvements: Smart Visibility | Forced Rendering | Beam-Part Sync")
	print("🎨 Visual Enhancements: Rainbow Mode | Professional Textures | Advanced Particles")
	print("📊 Performance: Mobile Optimization | Draw Call Reduction | Smart LOD")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
	local snake = Snake.new(character, config)
	
	if savedState and snake then
		-- Restore snake properties
		snake.targetLength = savedState.targetLength or savedState.length or config.length
		snake.actualLength = savedState.length or config.length
		snake.pendingGrowth = 0
		
		-- Restore position history if available
		if savedState.positionHistory and #savedState.positionHistory > 0 then
			snake.positionHistory = {}
			-- Only restore recent history to avoid lag
			local startIdx = math.max(1, #savedState.positionHistory - 500)
			for i = startIdx, #savedState.positionHistory do
				local entry = savedState.positionHistory[i]
				table.insert(snake.positionHistory, {
					position = entry.position,
					lookVector = entry.lookVector,
					time = tick()
				})
			end
			snake.historyIndex = 1
		end
		
		-- Recreate segments at saved positions efficiently
		if savedState.segments and #savedState.segments > 0 then
			-- First, ensure we have enough segments
			local neededSegments = math.min(#savedState.segments, MAX_SEGMENTS)
			
			-- Add segments in batches for performance
			local segmentsToAdd = neededSegments - snake.visibleSegmentCount
			while segmentsToAdd > 0 do
				local batchSize = math.min(20, segmentsToAdd)
				snake:addSegments(batchSize)
				segmentsToAdd = segmentsToAdd - batchSize
				
				-- Small yield to prevent lag
				if segmentsToAdd > 0 then
					task.wait()
				end
			end
			
			-- Position segments at saved locations efficiently
			task.spawn(function()
				for i, segmentData in ipairs(savedState.segments) do
					if i <= snake.visibleSegmentCount and snake.segments[i] then
						snake.segments[i].Position = segmentData.position
						snake.segments[i].Size = segmentData.size
						snake.segments[i].Color = segmentData.color
						snake.segments[i].Transparency = 0 -- Make visible again
						
						-- Update attachment positions for beams
						if snake.attachments[i] then
							snake.attachments[i].WorldPosition = segmentData.position
						end
						
						-- Yield every few segments to prevent lag
						if i % 10 == 0 then
							task.wait()
						end
					end
				end
				
				-- Update beams after all segments are positioned
				snake:updateBeamConnections()
			end)
		end
		
		-- Update leaderstats to reflect restored length
		if snake.player then
			local leaderstats = snake.player:FindFirstChild("leaderstats")
			if leaderstats then
				local lengthValue = leaderstats:FindFirstChild("Length")
				if lengthValue then
					lengthValue.Value = math.floor(snake.targetLength)
				end
			end
		end
		
		print("✅ Snake restored from saved state with length:", snake.targetLength)
	end
	
	return snake
end

-- Add method to Snake class for updating beam connections
function Snake:updateBeamConnections()
	-- Update all beam connections to match current segment positions
	for i = 1, self.visibleSegmentCount - 1 do
		if self.beams[i] and self.attachments[i] and self.attachments[i + 1] then
			self.beams[i].Attachment0 = self.attachments[i]
			self.beams[i].Attachment1 = self.attachments[i + 1]
		end
	end
end

-- 🎨 Separate visual effects update for throttling
function Snake:updateVisualEffects()
	-- Update rainbow mode
	if self.rainbowMode then
		self.currentHue = (self.currentHue + 0.01) % 1
	end
	
	-- Update visual animations
	self.glowPulsePhase = (self.glowPulsePhase + 0.1) % (math.pi * 2)
	self.beamAnimationOffset = (self.beamAnimationOffset + BEAM_TEXTURE_SPEED * 0.1) % 10
	
	-- Update glow effects based on LOD
	if self.currentLODMode == "HIGH" then
		-- Full glow updates
		for i = 0, math.min(50, self.visibleSegmentCount) do
			local glow = self.glows[i]
			if glow and glow.Parent then
				glow.Brightness = GLOW_INTENSITY * (1 + math.sin(self.glowPulsePhase) * 0.1)
			end
		end
	elseif self.currentLODMode == "MEDIUM" then
		-- Sparse glow updates (every 5th)
		for i = 0, math.min(50, self.visibleSegmentCount), 5 do
			local glow = self.glows[i]
			if glow and glow.Parent then
				glow.Brightness = GLOW_INTENSITY
			end
		end
	end
end

-- 🎯 Separate particle update for throttling
function Snake:updateParticles()
	-- Only update particles in HIGH LOD mode
	if self.currentLODMode ~= "HIGH" then
		return
	end
	
	-- Update boost particles
	if self.boostParticles and self.boostParticles.Parent then
		self.boostParticles.Enabled = self.isBoosting
	end
	
	-- Update segment particles (if any)
	-- Add particle logic here if needed
end

-- System management functions

return OptimizedSnakeSystemV9