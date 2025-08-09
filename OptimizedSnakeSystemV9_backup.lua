-- Optimized Snake System V16 - MODEL DIMENSION FIX
-- This version reads the bone spacing directly from your Blender model to ensure a 1:1 visual match.
-- FIX: The snake's body now perfectly preserves its shape and scales correctly with the player's length.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Re-introducing the Catmull-Rom Spline for smooth curves
local CatmullRomSpline = require(ReplicatedStorage:WaitForChild("CatmullRomSpline"))

-- Constants
local HISTORY_SIZE = 1000
local INITIAL_SNAKE_LENGTH = 85 -- The base length used for scaling

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
	self.boneRestDistances = {} -- Will store the original spacing from your model
	self.boneRestPositions = {} -- Store original local positions
	self.modelOrientation = "vertical" -- Your model is vertical in Blender

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

	-- Locate `untitledsnakeeeee`
	local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
	local meshTemplate = meshesFolder and meshesFolder:FindFirstChild("untitledsnakeeeee") or ReplicatedStorage:FindFirstChild("untitledsnakeeeee")
	assert(meshTemplate, "OptimizedSnakeSystemV9: Could not find ReplicatedStorage.Meshes.untitledsnakeeeee (or root)")

	local instance = meshTemplate:Clone()
	instance.Parent = self.model

	-- Find the "Circle" MeshPart
	local circle = instance:FindFirstChild("Circle")
	if not circle then
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("MeshPart") then circle = d break end
		end
	end
	assert(circle, "OptimizedSnakeSystemV9: Could not find MeshPart 'Circle' inside 'untitledsnakeeeee'")
	self.meshPart = circle

	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false

	-- Position the mesh at the character's position
	-- Rotate it 90 degrees to lay horizontal (from vertical in Blender)
	self.meshPart.CFrame = CFrame.new(self.rootPart.Position) * CFrame.Angles(math.rad(90), 0, 0)

	-- Weld the mesh to the player's root part for stability
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart

	-- Get and sort bones
	self.bones = {}
	local function collectBones(parent)
		for _, child in pairs(parent:GetChildren()) do
			if child:IsA("Bone") then table.insert(self.bones, child) end
			collectBones(child)
		end
	end
	collectBones(instance)

	-- Sort bones by their Y position (since model is vertical)
	table.sort(self.bones, function(a, b)
		-- Get bone positions in mesh local space
		local meshCF = self.meshPart.CFrame
		local pa = meshCF:PointToObjectSpace(a.WorldPosition)
		local pb = meshCF:PointToObjectSpace(b.WorldPosition)
		-- Sort by Y position (vertical in Blender)
		return pa.Y > pb.Y -- Head is at top in Blender
	end)
	print("[OptimizedSnakeSystemV9] Found and sorted", #self.bones, "bones.")

	-- Store original bone positions and calculate distances
	if #self.bones > 0 then
		-- Store original positions in model space
		for i, bone in ipairs(self.bones) do
			-- Get the bone's original position relative to the mesh
			local boneLocalPos = self.meshPart.CFrame:PointToObjectSpace(bone.WorldPosition)
			self.boneRestPositions[i] = boneLocalPos
			
			-- Calculate distance along the Y axis (vertical model)
			if i == 1 then
				self.boneRestDistances[i] = 0
			else
				-- Distance from head bone
				self.boneRestDistances[i] = math.abs(self.boneRestPositions[1].Y - boneLocalPos.Y)
			end
		end
		
		-- The total model length is the distance from first to last bone
		local modelLength = self.boneRestDistances[#self.bones] or 27 -- Fallback to Blender dimension
		print("[OptimizedSnakeSystemV9] Model length:", modelLength, "meters")
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

	if #controlPoints < 4 then
		local first = controlPoints[1] or self.rootPart.Position
		while #controlPoints < 4 do
			table.insert(controlPoints, 1, first)
		end
		table.insert(controlPoints, #controlPoints, controlPoints[#controlPoints])
	else
		table.insert(controlPoints, 1, controlPoints[1])
		table.insert(controlPoints, #controlPoints, controlPoints[#controlPoints])
	end

	local spline = CatmullRomSpline.new(controlPoints)
	if spline then
		spline:SetUniform(true)
		self.spline = spline
	end
end

function SkinnedSnake:updateBones(deltaTime)
	if not self.bones or #self.bones == 0 or not self.spline then return end

	local boneCount = #self.bones
	local splineLength = math.max(self.spline:GetLength(), 0.001)

	-- Get the snake's current length from the game
	local currentLength = self.character:GetAttribute("SnakeLength") or INITIAL_SNAKE_LENGTH
	local lengthScale = currentLength / INITIAL_SNAKE_LENGTH

	-- Position mesh at the head - rotate it to lay horizontal since model is vertical
	local headPos = self.rootPart.Position
	local headDir = self.rootPart.CFrame.LookVector
	
	-- Rotate the mesh 90 degrees to lay it flat (from vertical to horizontal)
	-- Then orient it to face the movement direction
	local meshCFrame = CFrame.lookAt(headPos, headPos + headDir) * CFrame.Angles(math.rad(90), 0, 0)
	self.meshPart.CFrame = meshCFrame

	-- Get model dimensions
	local modelLength = self.boneRestDistances[#self.bones] or 27

	-- Process each bone
	for i, bone in ipairs(self.bones) do
		-- Calculate the target distance along the snake for this bone
		local boneRestDist = self.boneRestDistances[i] or 0
		local normalizedDist = boneRestDist / modelLength
		local targetDistance = normalizedDist * currentLength

		-- Get the spline parameter
		local t = math.clamp(targetDistance / splineLength, 0, 1)

		-- Get world position and tangent from spline
		local worldPos = self.spline:GetPoint(t)
		local worldTangent = self.spline:GetTangent(t)

		-- Convert world position to mesh-local space
		local localPos = self.meshPart.CFrame:PointToObjectSpace(worldPos)

		-- Calculate the rotation needed to align the bone with the tangent
		-- Since the model is vertical (Y-axis) and we rotated the mesh 90 degrees,
		-- the bones now need to follow the spline in their local space
		
		-- Get angle between mesh forward and world tangent
		local meshForward = self.meshPart.CFrame.LookVector
		local angle = math.atan2(worldTangent.X, worldTangent.Z) - math.atan2(meshForward.X, meshForward.Z)

		-- Create bone transform:
		-- 1. Position the bone at its location along the spline
		-- 2. Rotate it to follow the spline direction
		-- Note: Since we rotated the mesh, Y is now forward, Z is up
		local boneTransform = CFrame.new(0, -localPos.Z, localPos.Y) * CFrame.Angles(0, angle, 0)

		-- Apply transform
		bone.Transform = boneTransform
	end
end

function SkinnedSnake:applyRadiusScale(targetRadius)
	-- This function is kept to prevent errors but does nothing to the mesh size
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
	-- This function is now just a placeholder; length is read from attributes directly.
end

function SkinnedSnake:updateConfig(newConfig)
	-- Placeholder for future visual changes
end

-- Module return
local OptimizedSnakeSystemV9 = {}
function OptimizedSnakeSystemV9.init()
	print("✅ OptimizedSnakeSystemV9 (Model Dimension Fix) initialized")
end
function OptimizedSnakeSystemV9.createSnake(character, config)
	return SkinnedSnake.new(character, config)
end
return OptimizedSnakeSystemV9