-- Optimized Snake System V11 - SKINNED MESH REVOLUTION
-- Complete rewrite to use a single skinned mesh with bone-based animation
-- Zero gaps, maximum performance, and professional-grade visuals

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = RunService:IsClient() and game:GetService("UserInputService") or nil

-- Add spline dependency for smooth, arc-length based sampling (safe require with timeout)
local CatmullRomSpline = nil
pcall(function()
	CatmullRomSpline = require(ReplicatedStorage:WaitForChild("CatmullRomSpline", 1))
end)

-- Constants for the skinned mesh system
local MESH_ASSET_ID = "rbxassetid://84274514316556" -- Your mesh asset ID
local BONE_COUNT = 13 -- Updated to match actual bone count in the mesh
local MAX_SNAKE_LENGTH = 500 -- Maximum segments the snake can grow to
local MIN_SNAKE_LENGTH = 10 -- Starting length

-- Performance Constants
local UPDATE_RATE = 60 -- Hz for bone updates
local NETWORK_UPDATE_RATE = 20 -- Hz for network sync
local HISTORY_SIZE = 1000 -- Position history for smooth following

-- Visual Constants
local BASE_SCALE = 1.0 -- Base scale of the mesh
local MAX_SCALE = 3.5 -- Maximum scale when fully grown
local GLOW_INTENSITY = 2.0
local PARTICLE_RATE = 100 -- Base particle emission rate

-- Movement Constants
local BASE_SPEED = 20 -- Base movement speed
local BOOST_MULTIPLIER = 1.5 -- Speed multiplier when boosting
local TURN_RATE = 2.5 -- Radians per second
local WAVE_AMPLITUDE = 0.5 -- Reduced from 1.2 to prevent extreme positions
local WAVE_FREQUENCY = 2.0 -- How fast the wave travels down the body

-- Growth Constants
local GROWTH_RATE = 0.1 -- How fast the snake grows (units per food)
local SCALE_PER_LENGTH = 0.005 -- How much the scale increases per length unit

-- NEW smoothing/spacing constants for bones
local DEFAULT_BONE_SPACING = 0.5 -- Much smaller for tight snake body
local BONE_BLEND_FACTOR = 0.9 -- Even smoother transitions
local CONTROL_POINT_COUNT = 10 -- Control points to build the spline from recent motion

-- NEW: Transform limits to prevent explosion
local MAX_BONE_OFFSET = 5 -- Reduced - keeps bones closer together
local MAX_ROTATION_ANGLE = math.rad(30) -- Reduced rotation limit

-- LOD System for performance
local LOD_DISTANCES = {
	HIGH = 100,    -- Full quality within 100 studs
	MEDIUM = 300,  -- Reduced quality 100-300 studs
	LOW = 600,     -- Minimal quality 300-600 studs
	CULLED = 1000  -- Not rendered beyond 1000 studs
}

-- Skinned Mesh Snake Class
local SkinnedSnake = {}
SkinnedSnake.__index = SkinnedSnake

function SkinnedSnake.new(character, config)
	local self = setmetatable({}, SkinnedSnake)

	-- Core properties
	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config or {}

	-- Ensure default configuration
	self.config.HeadColor = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
	self.config.BodyColors = self.config.BodyColors or {
		Color3.fromRGB(76, 217, 100),
		Color3.fromRGB(51, 163, 75)
	}
	self.config.InitialLength = self.config.InitialLength or MIN_SNAKE_LENGTH

	-- Snake state
	self.length = self.config.InitialLength
	self.scale = BASE_SCALE
	self.speed = BASE_SPEED
	self.isBoosting = false
	self.isAlive = true

	-- Movement state
	self.positionHistory = {}
	self.historyIndex = 0
	self.wavePhase = 0
	self.targetDirection = self.rootPart.CFrame.LookVector

	-- Bone animation state
	self.boneSpacing = DEFAULT_BONE_SPACING
	self.originalBoneTransforms = {}
	self.previousTransforms = {}
	self.boneOffsets = {}
	self.previousUpVectors = {}
	self.restBoneCFrames = {}
	self.previousTangents = {}
	self.debugMode = false -- Set to true to see bone debug info

	-- Visual state
	self.currentColorIndex = 1
	self.rainbowMode = false
	self.glowEnabled = true
	self.particlesEnabled = true

	-- Performance state
	self.frameCount = 0
	self.lastUpdate = tick()
	self.lodLevel = "HIGH"
	self.isLocalPlayer = (self.player == Players.LocalPlayer)

	-- Hide original character
	self:hideCharacter()

	-- Create the skinned mesh
	self:createSkinnedMesh()

	-- Initialize position history
	self:initializeHistory()

	-- Start update loops
	self:startUpdateLoop()

	print("✅ Skinned Snake created for", self.player and self.player.Name or "Unknown")
	return self
end

function SkinnedSnake:hideCharacter()
	-- Make all character parts invisible
	for _, part in pairs(self.character:GetDescendants()) do
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
	self.rootPart.CanCollide = false
	self.rootPart.CanQuery = false
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function SkinnedSnake:createSkinnedMesh()
	-- Create the model container
	self.model = Instance.new("Model")
	self.model.Name = "SkinnedSnake_" .. (self.player and self.player.Name or "Unknown")
	self.model.Parent = workspace

	-- Try to locate a skinned mesh template in ReplicatedStorage first
	local templateModel = ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate")
		or ReplicatedStorage:FindFirstChild("slither_snake_rigged")
		or ReplicatedStorage:FindFirstChild("untitledsnakeeeee")

	if not templateModel then
		local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
		if meshesFolder then
			templateModel = meshesFolder:FindFirstChild("untitledsnakeeeee")
				or meshesFolder:FindFirstChildOfClass("MeshPart")
				or meshesFolder:FindFirstChildOfClass("Model")
		end
	end

	if not templateModel then
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child:IsA("MeshPart") or child:IsA("Model") then
				templateModel = child
				break
			end
		end
	end

	if templateModel then
		local cloned = templateModel:Clone()
		cloned.Name = "SnakeBody"
		cloned.Parent = self.model
		if cloned:IsA("Model") then
			self.meshPart = cloned:FindFirstChild("Circle") or cloned:FindFirstChildOfClass("MeshPart")
		else
			self.meshPart = cloned
		end
		-- If we resolved a MeshPart and have an asset id, apply it on the server only
		if RunService:IsServer() and self.meshPart and self.meshPart:IsA("MeshPart") and typeof(MESH_ASSET_ID) == "string" and #MESH_ASSET_ID > 0 then
			self.meshPart.MeshId = MESH_ASSET_ID
		end
	else
		-- As a last resort, create a simple neon fallback so client always sees something
		local part = Instance.new("Part")
		part.Name = "SnakeFallback"
		part.Size = Vector3.new(4, 4, 4)
		part.Material = Enum.Material.Neon
		part.Color = self.config.HeadColor or Color3.fromRGB(76,217,100)
		part.CanCollide = false
		part.CanQuery = false
		part.Parent = self.model
		self.meshPart = part
	end

	-- Set up the mesh properties
	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false
	self.meshPart.CanQuery = true
	self.meshPart.CanTouch = true
	self.meshPart.Massless = true -- CRITICAL: Prevents physics conflicts with character

	-- Apply initial scale
	self.meshPart.Size = self.meshPart.Size * self.scale

	-- Set up collision detection
	CollectionService:AddTag(self.meshPart, "SnakeBody")
	self.meshPart:SetAttribute("OwnerName", self.player and self.player.Name or "Unknown")
	self.meshPart:SetAttribute("PlayerUserId", self.player and self.player.UserId or 0)

	-- Find bones: collect all Bone descendants under the mesh
	self.bones = {}
	for _, desc in ipairs(self.meshPart:GetDescendants()) do
		if desc:IsA("Bone") then
			table.insert(self.bones, desc)
		end
	end
	-- If not found under mesh, fallback: search entire cloned model
	if #self.bones < 2 then
		self.bones = {}
		for _, desc in ipairs(self.model:GetDescendants()) do
			if desc:IsA("Bone") then
				table.insert(self.bones, desc)
			end
		end
	end

	-- Numeric-aware sort: Bone, Bone.001, Bone.002, ...
	local function boneOrder(name)
		if name == "Bone" then return -1 end
		local n = name:match("Bone%.(%d+)") or name:match("Bone[_ ]?(%d+)")
		return tonumber(n) or math.huge
	end
	table.sort(self.bones, function(a, b)
		local oa, ob = boneOrder(a.Name), boneOrder(b.Name)
		if oa ~= ob then return oa < ob end
		return a.Name < b.Name
	end)

	print("Found", #self.bones, "bones in the mesh")
	if #self.bones ~= BONE_COUNT then
		warn(string.format("[OptimizedSnakeSystemV9] Bone count mismatch: expected %d, found %d", BONE_COUNT, #self.bones))
	end

	-- Store rest pose and initialize smoothing state
	self.originalBoneTransforms = {}
	self.previousTransforms = {}
	self.previousUpVectors = {}
	self.restBoneCFrames = {}
	self.previousTangents = {}
	
	-- Important: Store the initial transforms correctly
	for i, bone in ipairs(self.bones) do
		self.originalBoneTransforms[bone] = bone.Transform
		self.previousTransforms[bone] = bone.Transform -- Start with rest pose
		self.previousUpVectors[bone] = Vector3.new(0, 1, 0)
		self.restBoneCFrames[bone] = bone.CFrame
		self.previousTangents[bone] = Vector3.new(0, 0, -1)
		
		if self.debugMode then
			print(string.format("Bone %d (%s) rest transform:", i, bone.Name))
			print("  Position:", bone.Transform.Position)
			print("  Rotation:", bone.Transform.Rotation)
		end
	end

	-- Add visual effects
	self:addVisualEffects()

	-- Create a WeldConstraint to attach mesh to root part
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart

	-- Position the mesh at the character initially
	self.meshPart.CFrame = self.rootPart.CFrame
end

function SkinnedSnake:addVisualEffects()
	-- Add main glow light
	self.headLight = Instance.new("PointLight")
	self.headLight.Brightness = GLOW_INTENSITY
	self.headLight.Range = 20
	self.headLight.Color = self.config.HeadColor
	self.headLight.Shadows = false
	self.headLight.Parent = self.meshPart

	-- Add surface light for better visibility
	self.surfaceLight = Instance.new("SurfaceLight")
	self.surfaceLight.Brightness = 0.5
	self.surfaceLight.Color = self.config.HeadColor
	self.surfaceLight.Face = Enum.NormalId.Front
	self.surfaceLight.Parent = self.meshPart

	-- Add particle emitter for boost effects
	self.boostParticles = Instance.new("ParticleEmitter")
	self.boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	self.boostParticles.Rate = 0 -- Start disabled
	self.boostParticles.Lifetime = NumberRange.new(0.5, 1)
	self.boostParticles.VelocityInheritance = 0.5
	self.boostParticles.EmissionDirection = Enum.NormalId.Back
	self.boostParticles.Speed = NumberRange.new(5, 10)
	self.boostParticles.SpreadAngle = Vector2.new(15, 15)
	self.boostParticles.Color = ColorSequence.new(self.config.HeadColor)
	self.boostParticles.LightEmission = 1
	self.boostParticles.LightInfluence = 0
	self.boostParticles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0)
	}
	self.boostParticles.Parent = self.meshPart

	-- Add selection box for better visibility (optional)
	if self.isLocalPlayer then
		self.selectionBox = Instance.new("SelectionBox")
		self.selectionBox.Adornee = self.meshPart
		self.selectionBox.Color3 = self.config.HeadColor
		self.selectionBox.LineThickness = 0.05
		self.selectionBox.Transparency = 0.8
		self.selectionBox.Parent = self.meshPart
	end
end

function SkinnedSnake:initializeHistory()
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector

	-- Initialize with positions very close to the character
	for i = 1, HISTORY_SIZE do
		-- Much smaller offset - keep the snake close to the body
		local offset = (i - 1) * 0.1 -- Changed from 0.5 to 0.1
		self.positionHistory[i] = {
			position = startPos - startLook * offset,
			lookVector = startLook,
			time = tick()
		}
	end
end

function SkinnedSnake:updateHistory()
	-- Shift history forward
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1

	-- Store current position
	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector,
		time = tick()
	}
end

function SkinnedSnake:getHistoricalPosition(segmentsBack)
	-- Get position from history for smooth following
	local targetIndex = ((self.historyIndex - segmentsBack - 1) % HISTORY_SIZE) + 1
	return self.positionHistory[targetIndex] or self.positionHistory[self.historyIndex]
end

-- Helper: sample history by traveled distance backwards from current index
local function getHistoryAtBackDistance(self, targetBackDistance)
	if not self.positionHistory or self.historyIndex == 0 then
		return nil
	end
	local accumulated = 0
	local idx = self.historyIndex
	local current = self.positionHistory[idx]
	local prevIdx = ((idx - 2) % HISTORY_SIZE) + 1
	while accumulated < targetBackDistance do
		local prev = self.positionHistory[prevIdx]
		if not prev then break end
		local segment = (current.position - prev.position).Magnitude
		accumulated = accumulated + segment
		if accumulated >= targetBackDistance then
			-- Interpolate between prev and current to hit exact distance
			local overshoot = accumulated - targetBackDistance
			local t = segment > 0 and (1 - overshoot / segment) or 1
			local pos = prev.position:Lerp(current.position, t)
			local dir = (current.position - prev.position)
			dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, 0, -1)
			return { position = pos, direction = dir }
		end
		-- step back
		current = prev
		idx = prevIdx
		prevIdx = ((prevIdx - 2) % HISTORY_SIZE) + 1
		if prevIdx == idx then break end
	end
	-- Fallback to oldest available
	return {
		position = current and current.position or self.rootPart.Position,
		direction = current and (current.direction or self.rootPart.CFrame.LookVector) or self.rootPart.CFrame.LookVector
	}
end

-- === Robust, NaN-safe vector and frame helpers ===
local EPS = 1e-6

local function isValidVector3(v)
	return v and (v.X == v.X) and (v.Y == v.Y) and (v.Z == v.Z) and 
	       math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function isValidCFrame(cf)
	local pos = cf.Position
	local look = cf.LookVector
	return isValidVector3(pos) and isValidVector3(look)
end

local function clampVector3(v, maxMagnitude)
	if not isValidVector3(v) then
		return Vector3.new()
	end
	local mag = v.Magnitude
	if mag > maxMagnitude then
		return v.Unit * maxMagnitude
	end
	return v
end

local function safeNormalize(v, fallback)
	if not isValidVector3(v) then return fallback end
	local m = v.Magnitude
	if not m or m < EPS or m ~= m then
		return fallback
	end
	return v / m
end

local WORLD_AXES = {
	Vector3.new(1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, 0, 1)
}

local function orthonormalBasis(prevUp, tangent)
	local t = safeNormalize(tangent, Vector3.new(0, 0, -1))

	-- Try parallel transport from previous up
	local up = prevUp - t * prevUp:Dot(t)
	up = safeNormalize(up, Vector3.new(0, 1, 0))

	-- If still near-degenerate, choose the world axis least parallel to t
	if up.Magnitude < 0.5 then
		local bestAxis = WORLD_AXES[1]
		local bestDot = math.abs(t:Dot(bestAxis))
		for i = 2, #WORLD_AXES do
			local dotv = math.abs(t:Dot(WORLD_AXES[i]))
			if dotv < bestDot then
				bestDot = dotv
				bestAxis = WORLD_AXES[i]
			end
		end
		up = bestAxis - t * bestAxis:Dot(t)
		up = safeNormalize(up, Vector3.new(0, 1, 0))
	end

	local right = t:Cross(up)
	right = safeNormalize(right, Vector3.new(1, 0, 0))
	up = right:Cross(t)
	up = safeNormalize(up, Vector3.new(0, 1, 0))

	return t, right, up
end

local function safeCFrameFromTRU(pos, t, r, u)
	-- Validate vectors; rebuild basis if necessary
	if not isValidVector3(pos) then pos = Vector3.new() end
	local tt = safeNormalize(t, Vector3.new(0, 0, -1))
	local rr = r
	local uu = u

	-- Ensure rr, uu are valid and orthonormal to t
	if not isValidVector3(rr) or rr.Magnitude < 0.5 then
		rr = tt:Cross(Vector3.new(0, 1, 0))
		if rr.Magnitude < EPS then
			rr = tt:Cross(Vector3.new(1, 0, 0))
		end
		rr = safeNormalize(rr, Vector3.new(1, 0, 0))
	end
	uu = rr:Cross(tt)
	uu = safeNormalize(uu, Vector3.new(0, 1, 0))

	-- Final re-orthogonalization
	rr = tt:Cross(uu)
	rr = safeNormalize(rr, Vector3.new(1, 0, 0))
	uu = rr:Cross(tt)
	uu = safeNormalize(uu, Vector3.new(0, 1, 0))

	local cf = CFrame.fromMatrix(pos, rr, uu)
	return cf
end

local function buildControlPointsFromHistory(self, count)
	local points = {}
	if not self.positionHistory or self.historyIndex == 0 then
		return points
	end

	-- Sample evenly from recent history
	local step = math.max(1, math.floor(HISTORY_SIZE / math.max(4, count)))
	local idx = self.historyIndex
	for i = 1, count do
		local h = self.positionHistory[idx]
		if h then
			table.insert(points, 1, h.position) -- prepend to keep chronological order
		end
		idx = ((idx - step - 1) % HISTORY_SIZE) + 1
	end

	-- Ensure at least 4 points by duplicating ends if needed
	while #points < 4 do
		if #points == 0 then
			table.insert(points, self.rootPart.Position)
		else
			table.insert(points, points[#points])
		end
	end

	return points
end

function SkinnedSnake:updateBones(deltaTime)
	if not self.bones or #self.bones == 0 then return end
	if not self.meshPart or not self.meshPart.Parent then return end

	local meshCFrame = self.meshPart.CFrame
	if not isValidCFrame(meshCFrame) then
		warn("Invalid mesh CFrame detected!")
		return
	end

	-- For the first few frames, keep bones close to rest pose
	if self.frameCount < 30 then
		-- Gradually transition from rest pose to following pose
		local transitionFactor = self.frameCount / 30
		
		for i, bone in ipairs(self.bones) do
			local restTransform = self.originalBoneTransforms[bone] or CFrame.new()
			
			if i == 1 then
				-- Head bone stays at rest pose
				bone.Transform = restTransform
			else
				-- Other bones gradually start following
				local currentTransform = bone.Transform
				bone.Transform = currentTransform:Lerp(restTransform, 1 - transitionFactor)
			end
			
			self.previousTransforms[bone] = bone.Transform
		end
		
		return
	end

	local chainPrevUp = Vector3.new(0, 1, 0)

	local function setBoneFromWorld(bone, position, tangent, index)
		-- Validate inputs
		if not isValidVector3(position) or not isValidVector3(tangent) then
			warn(string.format("Invalid bone data for bone %d", index))
			return
		end

		-- Get the mesh position to calculate relative offset
		local meshPos = self.meshPart.Position
		local relativePos = position - meshPos
		
		-- Limit how far bones can be from the mesh center
		local maxDistance = 20 -- Maximum distance from mesh center
		if relativePos.Magnitude > maxDistance then
			relativePos = relativePos.Unit * maxDistance
			position = meshPos + relativePos
		end

		-- Smooth tangent to prevent flips
		local prevT = self.previousTangents[bone] or tangent
		local smoothedT = safeNormalize(prevT * 0.7 + tangent * 0.3, tangent)
		self.previousTangents[bone] = smoothedT

		-- Build stable frame by parallel transport
		local tVec, rVec, uVec = orthonormalBasis(self.previousUpVectors[bone] or chainPrevUp, smoothedT)
		chainPrevUp = uVec
		self.previousUpVectors[bone] = uVec

		-- World frame
		local worldCFrame = safeCFrameFromTRU(position, tVec, rVec, uVec)

		-- Much more subtle wave (reduced amplitude)
		local wave = math.clamp(math.sin((tick() * WAVE_FREQUENCY) - index * 0.3) * (WAVE_AMPLITUDE * 0.05), -0.1, 0.1)
		worldCFrame = worldCFrame * CFrame.Angles(0, 0, wave)

		-- Convert to object space, then to relative transform from rest pose
		local desiredObjectCF = meshCFrame:ToObjectSpace(worldCFrame)
		local restObjectCF = self.restBoneCFrames[bone] or CFrame.new()
		
		-- CRITICAL: Ensure we're getting valid transform
		if not isValidCFrame(desiredObjectCF) or not isValidCFrame(restObjectCF) then
			warn(string.format("Invalid CFrame for bone %d", index))
			return
		end
		
		local relativeTransform = restObjectCF:ToObjectSpace(desiredObjectCF)
		
		-- Clamp the transform to prevent extreme values
		local pos = relativeTransform.Position
		pos = clampVector3(pos, MAX_BONE_OFFSET)
		
		-- Extract and limit rotation
		local x, y, z = relativeTransform:ToEulerAnglesYXZ()
		x = math.clamp(x, -MAX_ROTATION_ANGLE, MAX_ROTATION_ANGLE)
		y = math.clamp(y, -MAX_ROTATION_ANGLE, MAX_ROTATION_ANGLE)
		z = math.clamp(z, -MAX_ROTATION_ANGLE, MAX_ROTATION_ANGLE)
		
		-- Reconstruct limited transform
		relativeTransform = CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(x, y, z)

		-- Smooth transform with stronger blending
		local prevRel = self.previousTransforms[bone]
		if prevRel and isValidCFrame(prevRel) then
			relativeTransform = prevRel:Lerp(relativeTransform, BONE_BLEND_FACTOR)
		end

		-- Final validation
		if not isValidCFrame(relativeTransform) then
			warn(string.format("Invalid final transform for bone %d, using identity", index))
			relativeTransform = CFrame.new()
		end

		bone.Transform = relativeTransform
		self.previousTransforms[bone] = relativeTransform
		
		if self.debugMode and index % 3 == 0 then
			print(string.format("Bone %d transform: Pos: %.2f, %.2f, %.2f", 
				index, relativeTransform.Position.X, relativeTransform.Position.Y, relativeTransform.Position.Z))
		end
	end

	-- Use simpler history-based approach without spline for now
	for i, bone in ipairs(self.bones) do
		-- Much smaller bone spacing for a tighter snake
		local spacingMultiplier = 0.8 + (i - 1) * 0.02 -- Reduced from 1 + 0.05
		local backDistance = (i - 1) * self.boneSpacing * spacingMultiplier * 0.5 -- Added 0.5 multiplier
		
		local sample = getHistoryAtBackDistance(self, backDistance)
		if sample then
			local pos = sample.position
			local tan = safeNormalize(sample.direction, Vector3.new(0, 0, -1))
			setBoneFromWorld(bone, pos, tan, i)
		else
			-- If no valid sample, reset to rest pose
			if self.previousTransforms[bone] then
				local restTransform = self.originalBoneTransforms[bone] or CFrame.new()
				bone.Transform = self.previousTransforms[bone]:Lerp(restTransform, 0.1)
				self.previousTransforms[bone] = bone.Transform
			end
		end
	end
end

function SkinnedSnake:updateLOD()
	if not self.isLocalPlayer or not workspace.CurrentCamera then return end

	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - self.meshPart.Position).Magnitude

	-- Determine LOD level based on distance
	local newLOD = "CULLED"
	if distance < LOD_DISTANCES.HIGH then
		newLOD = "HIGH"
	elseif distance < LOD_DISTANCES.MEDIUM then
		newLOD = "MEDIUM"
	elseif distance < LOD_DISTANCES.LOW then
		newLOD = "LOW"
	end

	-- Apply LOD changes if needed
	if newLOD ~= self.lodLevel then
		self.lodLevel = newLOD
		self:applyLODSettings()
	end
end

function SkinnedSnake:applyLODSettings()
	if self.lodLevel == "CULLED" then
		self.meshPart.Parent = nil
	else
		self.meshPart.Parent = self.model

		-- Adjust quality based on LOD
		if self.lodLevel == "HIGH" then
			self.headLight.Enabled = true
			self.surfaceLight.Enabled = true
			self.boostParticles.Enabled = self.isBoosting
		elseif self.lodLevel == "MEDIUM" then
			self.headLight.Enabled = true
			self.surfaceLight.Enabled = false
			self.boostParticles.Enabled = false
		else -- LOW
			self.headLight.Enabled = false
			self.surfaceLight.Enabled = false
			self.boostParticles.Enabled = false
		end
	end
end

function SkinnedSnake:grow(amount)
	self.length = math.min(self.length + amount, MAX_SNAKE_LENGTH)

	-- Update scale based on length
	local targetScale = BASE_SCALE + (self.length - MIN_SNAKE_LENGTH) * SCALE_PER_LENGTH
	self.scale = math.min(targetScale, MAX_SCALE)

	-- Smoothly scale the mesh
	local tween = TweenService:Create(
		self.meshPart,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = self.meshPart.Size * (self.scale / self.meshPart.Size.Magnitude)}
	)
	tween:Play()
end

function SkinnedSnake:setBoost(boosting)
	self.isBoosting = boosting
	self.speed = boosting and (BASE_SPEED * BOOST_MULTIPLIER) or BASE_SPEED

	-- Update boost particles
	if self.boostParticles then
		self.boostParticles.Rate = boosting and PARTICLE_RATE or 0
	end

	-- Update humanoid speed
	self.humanoid.WalkSpeed = self.speed
end

function SkinnedSnake:updateColors()
	-- Ensure we have valid body colors
	if not self.config.BodyColors or #self.config.BodyColors == 0 then
		self.config.BodyColors = {
			Color3.fromRGB(76, 217, 100),
			Color3.fromRGB(51, 163, 75)
		}
	end
	
	-- Cycle through body colors or apply rainbow mode
	if self.rainbowMode then
		local hue = (tick() * 0.5) % 1
		local color = Color3.fromHSV(hue, 1, 1)
		if self.headLight then
			self.headLight.Color = color
		end
		if self.boostParticles then
			self.boostParticles.Color = ColorSequence.new(color)
		end
		-- Update mesh part color if it exists
		if self.meshPart and self.meshPart:IsA("BasePart") then
			self.meshPart.Color = color
		end
	else
		-- Normal color cycling
		self.currentColorIndex = (self.currentColorIndex % #self.config.BodyColors) + 1
		local color = self.config.BodyColors[self.currentColorIndex]
		
		-- Make sure color is valid
		if not color then
			color = Color3.fromRGB(76, 217, 100) -- Default fallback color
		end
		
		if self.headLight then
			self.headLight.Color = color
		end
		if self.boostParticles then
			self.boostParticles.Color = ColorSequence.new(color)
		end
		-- Update mesh part color if it exists
		if self.meshPart and self.meshPart:IsA("BasePart") then
			self.meshPart.Color = color
		end
	end
end

function SkinnedSnake:startUpdateLoop()
	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.isAlive then return end

		self.frameCount = self.frameCount + 1

		-- Update position history
		self:updateHistory()

		-- Update bone positions for slithering animation
		self:updateBones(deltaTime)

		-- Update LOD every few frames
		if self.frameCount % 5 == 0 then
			self:updateLOD()
		end

		-- Update colors periodically
		if self.frameCount % 30 == 0 then
			self:updateColors()
		end

		-- REMOVED: Manual CFrame setting that was fighting the WeldConstraint
		-- The WeldConstraint automatically handles positioning the mesh to follow the rootPart
	end)
end

function SkinnedSnake:destroy()
	self.isAlive = false

	if self.updateConnection then
		self.updateConnection:Disconnect()
	end

	if self.model then
		self.model:Destroy()
	end

	print("❌ Skinned Snake destroyed for", self.player and self.player.Name or "Unknown")
end

-- Module API
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	print("[OptimizedSnakeSystemV9] Initialized (Skinned Mesh, Bone-driven)")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return SkinnedSnake.new(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
	local snake = SkinnedSnake.new(character, config)
	if savedState and snake and savedState.length then
		snake:grow(savedState.length - snake.length)
	end
	return snake
end

-- Add method to update snake length (for compatibility)
function SkinnedSnake:updateLength(newLength)
	if newLength and newLength > self.length then
		self:grow(newLength - self.length)
	end
end

return OptimizedSnakeSystemV9