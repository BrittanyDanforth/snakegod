-- Optimized Snake System V17 - FINAL FIX for Vertical Blender Model
-- This version properly handles the vertical model orientation from Blender

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Re-introducing the Catmull-Rom Spline for smooth curves
local CatmullRomSpline = require(ReplicatedStorage:WaitForChild("CatmullRomSpline"))

-- Constants
local HISTORY_SIZE = 1000
local INITIAL_SNAKE_LENGTH = 85

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

	-- Snake state
	self.isAlive = true
	self.boneData = {} -- Store bone info

	-- Movement state
	self.positionHistory = {}
	self.historyIndex = 0
	self.spline = nil
	self.controlPointCount = 24

	-- Hide original character
	self:hideCharacter()

	-- Create the skinned mesh
	self:createSkinnedMesh()

	-- Initialize position history
	self:initializeHistory()

	-- Start update loops
	self:startUpdateLoop()

	print("✅ Skinned Snake created for", self.player.Name)
	return self
end

function SkinnedSnake:hideCharacter()
	for _, part in pairs(self.character:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.rootPart then
			part.Transparency = 1
			part.CanCollide = false
		elseif part:IsA("Decal") or part:IsA("Texture") or part:IsA("Accessory") then
			part:Destroy()
		end
	end
	self.rootPart.Transparency = 1
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function SkinnedSnake:createSkinnedMesh()
	self.model = Instance.new("Model")
	self.model.Name = "SkinnedSnake_" .. self.player.Name
	self.model.Parent = workspace

	-- Locate mesh template
	local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
	local meshTemplate = meshesFolder and meshesFolder:FindFirstChild("untitledsnakeeeee") or ReplicatedStorage:FindFirstChild("untitledsnakeeeee")
	assert(meshTemplate, "Could not find snake mesh template")

	local instance = meshTemplate:Clone()
	instance.Parent = self.model

	-- Find the MeshPart
	local circle = instance:FindFirstChild("Circle")
	if not circle then
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("MeshPart") then circle = d break end
		end
	end
	assert(circle, "Could not find MeshPart in snake template")
	self.meshPart = circle

	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false

	-- The model is vertical in Blender, we need to rotate it to horizontal
	self.meshPart.CFrame = self.rootPart.CFrame * CFrame.Angles(math.rad(90), 0, 0)

	-- Weld to root part
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart

	-- Collect and process bones
	self.bones = {}
	local function collectBones(parent)
		for _, child in pairs(parent:GetChildren()) do
			if child:IsA("Bone") then table.insert(self.bones, child) end
			collectBones(child)
		end
	end
	collectBones(instance)

	-- Sort bones from head to tail
	-- Store initial CFrame for reference
	local initialMeshCFrame = self.meshPart.CFrame
	
	-- Sort by Y position in object space (vertical in Blender)
	table.sort(self.bones, function(a, b)
		local posA = initialMeshCFrame:PointToObjectSpace(a.WorldPosition)
		local posB = initialMeshCFrame:PointToObjectSpace(b.WorldPosition)
		return posA.Y > posB.Y -- Head at top
	end)

	print("[Snake] Found", #self.bones, "bones")

	-- Store bone data
	if #self.bones > 0 then
		local headBone = self.bones[1]
		local headPos = initialMeshCFrame:PointToObjectSpace(headBone.WorldPosition)
		
		for i, bone in ipairs(self.bones) do
			local bonePos = initialMeshCFrame:PointToObjectSpace(bone.WorldPosition)
			
			-- Distance along Y axis (vertical in model)
			local distance = math.abs(headPos.Y - bonePos.Y)
			
			self.boneData[i] = {
				bone = bone,
				restDistance = distance,
				restLocalPos = bonePos,
				index = i
			}
		end
		
		-- Total model length
		self.modelLength = self.boneData[#self.bones].restDistance
		print("[Snake] Model length:", self.modelLength)
	end
end

function SkinnedSnake:initializeHistory()
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	local spacing = 0.5

	for i = 1, HISTORY_SIZE do
		local offset = startLook * ((i - 1) * spacing)
		self.positionHistory[i] = {
			position = startPos - offset,
			lookVector = startLook,
		}
	end
end

function SkinnedSnake:updateHistory()
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		lookVector = self.rootPart.CFrame.LookVector,
	}
end

function SkinnedSnake:getHistoricalPosition(indexBack)
	local targetIndex = ((self.historyIndex - indexBack - 1) % HISTORY_SIZE) + 1
	return self.positionHistory[targetIndex]
end

function SkinnedSnake:rebuildSpline()
	local controlPoints = {}
	local sampleStride = 3
	local desired = self.controlPointCount

	for idx = desired, 1, -1 do
		local offset = (idx - 1) * sampleStride
		local h = self:getHistoricalPosition(offset)
		table.insert(controlPoints, 1, h.position)
	end

	-- Ensure we have enough points
	while #controlPoints < 4 do
		table.insert(controlPoints, 1, controlPoints[1] or self.rootPart.Position)
	end

	-- Add padding points for Catmull-Rom
	table.insert(controlPoints, 1, controlPoints[1])
	table.insert(controlPoints, controlPoints[#controlPoints])

	local spline = CatmullRomSpline.new(controlPoints)
	if spline then
		spline:SetUniform(true)
		self.spline = spline
	end
end

function SkinnedSnake:updateBones(deltaTime)
	if not self.bones or #self.bones == 0 or not self.spline then return end

	-- Get current snake length
	local currentLength = self.character:GetAttribute("SnakeLength") or INITIAL_SNAKE_LENGTH
	local splineLength = math.max(self.spline:GetLength(), 0.001)

	-- Update mesh to follow player
	-- Rotate 90 degrees to convert vertical model to horizontal
	local playerCFrame = self.rootPart.CFrame
	self.meshPart.CFrame = playerCFrame * CFrame.Angles(math.rad(90), 0, 0)

	-- Update each bone
	for i, data in ipairs(self.boneData) do
		local bone = data.bone
		
		-- Calculate position along snake based on rest distance
		local normalizedPosition = data.restDistance / self.modelLength
		local targetDistance = normalizedPosition * currentLength
		
		-- Get spline parameter
		local t = math.clamp(targetDistance / splineLength, 0, 1)
		
		-- Get world position from spline
		local worldPos = self.spline:GetPoint(t)
		local worldTangent = self.spline:GetTangent(t)
		
		-- Convert to mesh local space
		local localPos = self.meshPart.CFrame:PointToObjectSpace(worldPos)
		
		-- Since we rotated the mesh 90 degrees:
		-- Original Y (vertical) is now -Z (backward)
		-- Original Z is now Y (up)
		
		-- Calculate bone position in rotated space
		local bonePos = Vector3.new(
			localPos.X,           -- X stays the same
			localPos.Y,           -- Y is the new vertical
			-data.restLocalPos.Y  -- Original Y becomes -Z
		)
		
		-- Calculate rotation to follow the spline
		local meshForward = self.meshPart.CFrame.LookVector
		local dotProduct = meshForward:Dot(worldTangent)
		local crossProduct = meshForward:Cross(worldTangent)
		local angle = math.atan2(crossProduct.Y, dotProduct)
		
		-- Create and apply transform
		bone.Transform = CFrame.new(bonePos) * CFrame.Angles(0, angle, 0)
	end
end

function SkinnedSnake:startUpdateLoop()
	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.isAlive then return end
		self:updateHistory()
		self:rebuildSpline()
		self:updateBones(deltaTime)
	end)
end

function SkinnedSnake:destroy()
	self.isAlive = false
	if self.updateConnection then self.updateConnection:Disconnect() end
	if self.model then self.model:Destroy() end
	print("❌ Skinned Snake destroyed for", self.player.Name)
end

function SkinnedSnake:updateLength(newLength)
	-- Length is read from attributes in updateBones
end

function SkinnedSnake:updateConfig(newConfig)
	-- Placeholder for visual updates
end

-- Module exports
local OptimizedSnakeSystemV9 = {}
function OptimizedSnakeSystemV9.init()
	print("✅ OptimizedSnakeSystemV9 initialized")
end
function OptimizedSnakeSystemV9.createSnake(character, config)
	return SkinnedSnake.new(character, config)
end
return OptimizedSnakeSystemV9