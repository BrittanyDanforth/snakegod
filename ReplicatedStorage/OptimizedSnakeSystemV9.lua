-- Optimized Snake System V9 - SKINNED MESH VERSION
-- Uses a single skinned mesh with bones instead of hundreds of parts
-- Provides massive performance improvements and perfectly smooth rendering

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Catmull-Rom Spline Module for smooth path interpolation
local CatmullRomSpline
local hasCatmullRomSpline = false
local success = pcall(function()
	CatmullRomSpline = require(ReplicatedStorage:WaitForChild("CatmullRomSpline", 2))
	hasCatmullRomSpline = true
end)
if not success then
	warn("CatmullRomSpline module not found - using fallback positioning")
end

-- Performance Settings
local SEGMENT_UPDATE_RATE = 75
local NETWORK_UPDATE_RATE = 25
local HISTORY_SIZE = 2000
local GROWTH_CHECK_INTERVAL = 10

-- Visual Constants
local BASE_SIZE = 3.5 -- Base size for the snake
local MAX_SIZE_MULTIPLIER = 3.5 -- Maximum size growth
local GLOW_INTENSITY = 2
local GLOW_RANGE_BASE = 15
local HEAD_SIZE_MULTIPLIER = 1.05
local VISUAL_SMOOTHING_FACTOR = 0.6

-- Growth Animation Constants
local GROWTH_SPEED = 0.15
local GROWTH_PULSE_STRENGTH = 0.1

-- Bone Animation Constants
local BONE_SPACING = 2.0 -- Distance between bones in world units
local BONE_BLEND_FACTOR = 0.8 -- Smoothing between bone updates
local MAX_BONES = 50 -- Maximum bones we'll animate

-- Rainbow Mode Constants
local RAINBOW_SPEED = 2
local RAINBOW_SEGMENT_OFFSET = 0.1

-- Cached frequently used values
local mathSin = math.sin
local mathCos = math.cos
local mathMin = math.min
local mathMax = math.max
local mathClamp = math.clamp
local mathCeil = math.ceil
local mathFloor = math.floor
local mathRad = math.rad
local tickCount = tick
local v3New = Vector3.new
local cfNew = CFrame.new
local cfLookAt = CFrame.lookAt
local cfAngles = CFrame.Angles

local function getSkinnedSnakeTemplate()
	-- Look for the template in ReplicatedStorage
	local template = ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate") or 
	                ReplicatedStorage:FindFirstChild("slither_snake_rigged")
	
	if not template then
		warn("⚠️ SkinnedSnakeTemplate not found in ReplicatedStorage!")
		warn("Please ensure your rigged snake model is in ReplicatedStorage and named 'SkinnedSnakeTemplate'")
		return nil
	end
	
	return template
end

-- Snake Class Definition
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	local self = setmetatable({}, Snake)
	
	-- Core properties
	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	
	-- Configuration
	self.config = config or {}
	self.length = self.config.initialLength or 30
	self.actualLength = self.length
	self.targetLength = self.length
	self.speed = self.config.speed or 16
	self.baseSpeed = self.speed
	self.turnSpeed = self.config.turnSpeed or 3
	self.growthFactor = 1
	self.sizeLevel = 1
	
	-- Visual settings
	self.primaryColor = self.config.primaryColor or Color3.fromRGB(85, 170, 255)
	self.secondaryColor = self.config.secondaryColor or Color3.fromRGB(170, 255, 127)
	self.patternType = self.config.patternType or "gradient"
	self.rainbowMode = self.config.rainbowMode or false
	self.useCustomSkin = self.config.useCustomSkin or false
	self.customSkinId = self.config.customSkinId
	
	-- State tracking
	self.isAlive = true
	self.isBoosting = false
	self.isDead = false
	self.frameCount = 0
	self.lastUpdateTime = tickCount()
	self.lastGrowthUpdate = tickCount()
	self.isGrowing = false
	self.lastSegmentAddTime = tickCount()
	
	-- Position tracking for smooth movement
	self.positionHistory = {}
	self.directionHistory = {}
	
	-- Skinned mesh components
	self.model = nil
	self.meshPart = nil
	self.bones = {}
	self.boneTransforms = {}
	self.initialPoses = {}
	self.headBone = nil
	self.boostParticles = nil
	self.headGlow = nil
	
	-- Eyes
	self.leftEye = nil
	self.rightEye = nil
	self.leftPupil = nil
	self.rightPupil = nil
	
	-- Spline for smooth path
	self.pathSpline = nil
	
	-- Create the snake model
	self:createUnifiedBody()
	
	-- Hide character parts
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") then
			part.Transparency = 1
		end
	end
	
	-- Disable default animations
	local animator = self.humanoid:FindFirstChild("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end
	end
	
	self.humanoid.PlatformStand = true
	
	-- Setup update connections
	self:setupUpdateConnections()
	
	return self
end

function Snake:createUnifiedBody()
	-- Get the skinned snake template
	local template = getSkinnedSnakeTemplate()
	if not template then
		warn("Failed to create snake: Template not found")
		return
	end
	
	-- Clone the template
	self.model = template:Clone()
	self.model.Name = self.player.Name .. "_Snake"
	self.model.Parent = workspace
	
	-- Find the mesh part (should be named "Circle" based on your description)
	self.meshPart = self.model:FindFirstChild("Circle")
	if not self.meshPart then
		-- Try alternative names
		self.meshPart = self.model:FindFirstChildOfClass("MeshPart")
	end
	
	if not self.meshPart then
		warn("No MeshPart found in snake template!")
		return
	end
	
	-- Set mesh properties
	self.meshPart.Color = self.primaryColor
	self.meshPart.Material = Enum.Material.Neon
	self.meshPart.CanCollide = false
	self.meshPart.CanTouch = true
	self.meshPart.CanQuery = true
	self.meshPart.Anchored = false
	
	-- Create a WeldConstraint to attach mesh to character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart
	
	-- Find and store all bones
	self:collectBones()
	
	-- Store initial poses from the InitialPoses folder
	local initialPosesFolder = self.model:FindFirstChild("InitialPoses")
	if initialPosesFolder then
		for _, poseValue in ipairs(initialPosesFolder:GetChildren()) do
			if poseValue:IsA("CFrameValue") or poseValue.ClassName == "Pose" then
				local boneName = poseValue.Name:match("(.+)_") or poseValue.Name
				self.initialPoses[boneName] = poseValue.Value or poseValue.CFrame
			end
		end
	end
	
	-- Add head glow
	self.headGlow = Instance.new("PointLight")
	self.headGlow.Name = "HeadGlow"
	self.headGlow.Brightness = GLOW_INTENSITY
	self.headGlow.Range = GLOW_RANGE_BASE * 1.1
	self.headGlow.Color = self.primaryColor
	self.headGlow.Shadows = false
	self.headGlow.Parent = self.meshPart
	
	-- Add boost particles
	self.boostParticles = Instance.new("ParticleEmitter")
	self.boostParticles.Name = "BoostParticles"
	self.boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	self.boostParticles.Color = ColorSequence.new(self.primaryColor)
	self.boostParticles.Lifetime = NumberRange.new(0.5, 1)
	self.boostParticles.Rate = 0
	self.boostParticles.Speed = NumberRange.new(5, 10)
	self.boostParticles.SpreadAngle = Vector2.new(180, 180)
	self.boostParticles.VelocityInheritance = 0.7
	self.boostParticles.Drag = 3
	self.boostParticles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0)
	}
	self.boostParticles.Rotation = NumberRange.new(0, 360)
	self.boostParticles.RotSpeed = NumberRange.new(-180, 180)
	self.boostParticles.Enabled = false
	self.boostParticles.LightEmission = 1
	self.boostParticles.LightInfluence = 0
	self.boostParticles.ZOffset = 1
	self.boostParticles.Parent = self.meshPart
	
	-- Create eyes
	self:createEyes()
	
	-- Tag for collision
	CollectionService:AddTag(self.meshPart, "SnakeHead")
	self.meshPart:SetAttribute("PlayerId", self.player.UserId)
	self.meshPart:SetAttribute("OwnerName", self.player.Name)
end

function Snake:collectBones()
	-- Find the first bone (should be just "Bone" based on your hierarchy)
	local firstBone = self.meshPart:FindFirstChild("Bone")
	if not firstBone then
		warn("No bones found in mesh!")
		return
	end
	
	-- Follow the bone chain and collect all bones in order
	local currentBone = firstBone
	while currentBone do
		table.insert(self.bones, currentBone)
		-- Store the initial transform
		self.boneTransforms[currentBone] = currentBone.Transform
		
		-- Find the next bone (should be a child named like "Bone.001", "Bone.002", etc.)
		local nextBone = nil
		for _, child in ipairs(currentBone:GetChildren()) do
			if child:IsA("Bone") then
				nextBone = child
				break
			end
		end
		currentBone = nextBone
	end
	
	-- Store reference to head bone
	self.headBone = firstBone
	
	print(string.format("Found %d bones in snake skeleton", #self.bones))
end

function Snake:createEyes()
	-- Create eye parts that will be positioned relative to the head
	local function createEye(xOffset)
		local eye = Instance.new("Part")
		eye.Name = xOffset > 0 and "RightEye" or "LeftEye"
		eye.Shape = Enum.PartType.Ball
		eye.Material = Enum.Material.Neon
		eye.Color = Color3.fromRGB(255, 255, 255)
		eye.Size = v3New(0.5, 0.5, 0.5)
		eye.Transparency = 0
		eye.CanCollide = false
		eye.Anchored = true
		eye.Parent = self.model
		
		local pupil = Instance.new("Part")
		pupil.Name = eye.Name .. "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Material = Enum.Material.Neon
		pupil.Color = Color3.fromRGB(0, 0, 0)
		pupil.Size = v3New(0.25, 0.25, 0.25)
		pupil.Transparency = 0
		pupil.CanCollide = false
		pupil.Anchored = true
		pupil.Parent = self.model
		
		return eye, pupil
	end
	
	self.leftEye, self.leftPupil = createEye(-0.6)
	self.rightEye, self.rightPupil = createEye(0.6)
end

function Snake:setupUpdateConnections()
	-- Main update loop
	self.updateConnection = RunService.Heartbeat:Connect(function()
		if self.isDead then return end
		
		self.frameCount = self.frameCount + 1
		local currentTime = tickCount()
		local deltaTime = currentTime - self.lastUpdateTime
		self.lastUpdateTime = currentTime
		
		-- Track position history
		self:updatePositionHistory()
		
		-- Update the snake body
		self:updateUnifiedBody()
		
		-- Update effects
		if self.frameCount % 3 == 0 then
			self:updateVisualEffects()
		end
		
		-- Update length/growth
		if self.frameCount % GROWTH_CHECK_INTERVAL == 0 then
			self:updateGrowth(deltaTime)
		end
	end)
end

function Snake:updatePositionHistory()
	-- Add current position to history
	local currentPos = self.rootPart.Position
	local currentDir = self.rootPart.CFrame.LookVector
	
	table.insert(self.positionHistory, 1, {
		position = currentPos,
		direction = currentDir,
		time = tickCount()
	})
	
	-- Trim history
	while #self.positionHistory > HISTORY_SIZE do
		table.remove(self.positionHistory)
	end
end

function Snake:updateUnifiedBody()
	if not self.meshPart or #self.bones == 0 then return end
	
	-- Update spline if we have enough history
	if hasCatmullRomSpline and #self.positionHistory >= 4 then
		local splinePoints = {}
		for i = 1, mathMin(#self.positionHistory, 100) do
			table.insert(splinePoints, self.positionHistory[i].position)
		end
		
		if #splinePoints >= 4 then
			self.pathSpline = CatmullRomSpline.new(splinePoints)
			self.pathSpline:SetUniform(true)
		end
	end
	
	-- Position the mesh at the character position
	self.meshPart.CFrame = self.rootPart.CFrame
	
	-- Calculate bone positions along the snake's path
	local boneCount = #self.bones
	if boneCount == 0 then return end
	
	-- Calculate spacing based on snake length
	local totalLength = self.actualLength
	local boneSpacing = totalLength / mathMax(boneCount - 1, 1)
	
	-- Update each bone
	for i, bone in ipairs(self.bones) do
		local boneTransform
		
		if i == 1 then
			-- Head bone follows the character directly
			boneTransform = cfNew()
		else
			-- Calculate position along the path
			local distanceBack = (i - 1) * boneSpacing
			
			if self.pathSpline and self.pathSpline:GetLength() > 0 then
				-- Use spline for smooth positioning
				local splineLength = self.pathSpline:GetLength()
				local t = mathClamp(distanceBack / splineLength, 0, 1)
				local worldPos = self.pathSpline:GetPoint(t)
				local tangent = self.pathSpline:GetTangent(t)
				
				-- Convert world position to bone-relative transform
				local worldCFrame = cfLookAt(worldPos, worldPos + tangent)
				local relativeCFrame = self.meshPart.CFrame:Inverse() * worldCFrame
				
				-- Add some natural movement
				local wave = mathSin(t * math.pi * 4 + tickCount() * 2) * 0.05
				relativeCFrame = relativeCFrame * cfAngles(0, 0, wave)
				
				boneTransform = relativeCFrame
			else
				-- Fallback: simple follow behavior
				local histIndex = mathFloor(distanceBack / 2) + 1
				if histIndex <= #self.positionHistory then
					local histData = self.positionHistory[histIndex]
					local worldPos = histData.position
					local worldCFrame = cfLookAt(worldPos, worldPos + histData.direction)
					local relativeCFrame = self.meshPart.CFrame:Inverse() * worldCFrame
					boneTransform = relativeCFrame
				else
					-- Default position
					boneTransform = cfNew(0, 0, -distanceBack)
				end
			end
		end
		
		-- Smooth the transform
		local previousTransform = self.boneTransforms[bone] or bone.Transform
		local smoothedTransform = previousTransform:Lerp(boneTransform, BONE_BLEND_FACTOR)
		
		-- Apply the transform
		bone.Transform = smoothedTransform
		self.boneTransforms[bone] = smoothedTransform
	end
	
	-- Update eyes position
	self:updateEyes()
end

function Snake:updateEyes()
	if not self.leftEye or not self.rightEye then return end
	
	local headCFrame = self.rootPart.CFrame
	local headSize = BASE_SIZE * HEAD_SIZE_MULTIPLIER * self.growthFactor
	local eyeScale = headSize / BASE_SIZE * 0.5
	local eyeOffset = headSize * 0.3
	local eyeForward = -headSize * 0.35
	
	self.leftEye.Size = v3New(eyeScale, eyeScale, eyeScale)
	self.rightEye.Size = v3New(eyeScale, eyeScale, eyeScale)
	self.leftPupil.Size = v3New(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	self.rightPupil.Size = v3New(eyeScale * 0.5, eyeScale * 0.5, eyeScale * 0.5)
	
	self.leftEye.CFrame = headCFrame * cfNew(-eyeOffset, eyeOffset * 0.5, eyeForward)
	self.rightEye.CFrame = headCFrame * cfNew(eyeOffset, eyeOffset * 0.5, eyeForward)
	self.leftPupil.CFrame = self.leftEye.CFrame * cfNew(0, 0, -eyeScale * 0.3)
	self.rightPupil.CFrame = self.rightEye.CFrame * cfNew(0, 0, -eyeScale * 0.3)
end

function Snake:updateVisualEffects()
	-- Update colors for rainbow mode
	if self.rainbowMode and self.meshPart then
		local hue = (tickCount() * RAINBOW_SPEED) % 360
		local color = Color3.fromHSV(hue / 360, 0.8, 1)
		self.meshPart.Color = color
		if self.headGlow then
			self.headGlow.Color = color
		end
	end
	
	-- Update boost particles
	if self.boostParticles then
		self.boostParticles.Enabled = self.isBoosting
		if self.isBoosting then
			self.boostParticles.Rate = 200
		else
			self.boostParticles.Rate = 0
		end
	end
end

function Snake:updateGrowth(deltaTime)
	-- Smooth length interpolation
	if math.abs(self.targetLength - self.actualLength) > 0.1 then
		self.actualLength = self.actualLength + (self.targetLength - self.actualLength) * GROWTH_SPEED
		self.isGrowing = true
	else
		self.isGrowing = false
	end
	
	-- Update growth factor for visual scaling
	local newGrowthFactor = 1 + (self.sizeLevel - 1) * 0.1
	if math.abs(newGrowthFactor - self.growthFactor) > 0.01 then
		self.growthFactor = self.growthFactor + (newGrowthFactor - self.growthFactor) * 0.1
	end
end

function Snake:grow(amount)
	self.length = self.length + amount
	self.targetLength = self.length
end

function Snake:setLength(newLength)
	self.length = newLength
	self.targetLength = newLength
end

function Snake:setSizeLevel(level)
	self.sizeLevel = mathMax(1, level)
end

function Snake:boost(active)
	self.isBoosting = active
	if active then
		self.speed = self.baseSpeed * 1.75
		self.humanoid.WalkSpeed = self.speed
	else
		self.speed = self.baseSpeed
		self.humanoid.WalkSpeed = self.speed
	end
end

function Snake:setRainbowMode(enabled)
	self.rainbowMode = enabled
	if not enabled and self.meshPart then
		self.meshPart.Color = self.primaryColor
		if self.headGlow then
			self.headGlow.Color = self.primaryColor
		end
	end
end

function Snake:setPrimaryColor(color)
	self.primaryColor = color
	if not self.rainbowMode and self.meshPart then
		self.meshPart.Color = color
		if self.headGlow then
			self.headGlow.Color = color
		end
	end
end

function Snake:die()
	self.isDead = true
	self.isAlive = false
	
	-- Stop updates
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
	
	-- Clean up model after a delay
	if self.model then
		Debris:AddItem(self.model, 3)
	end
end

function Snake:destroy()
	self:die()
	
	-- Immediate cleanup
	if self.model then
		self.model:Destroy()
	end
	
	-- Clear references
	self.bones = {}
	self.boneTransforms = {}
	self.initialPoses = {}
	self.positionHistory = {}
end

-- Module Functions
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	-- Check for required template
	local template = getSkinnedSnakeTemplate()
	if not template then
		error("SkinnedSnakeTemplate not found! Please add your rigged snake model to ReplicatedStorage.")
	end
	
	print("✅ OptimizedSnakeSystemV9 (Skinned Mesh Version) initialized!")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
	local snake = Snake.new(character, config)
	
	-- Restore saved state
	if savedState then
		snake:setLength(savedState.length or config.initialLength)
		snake:setSizeLevel(savedState.sizeLevel or 1)
		if savedState.primaryColor then
			snake:setPrimaryColor(savedState.primaryColor)
		end
		if savedState.rainbowMode ~= nil then
			snake:setRainbowMode(savedState.rainbowMode)
		end
	end
	
	return snake
end

return OptimizedSnakeSystemV9