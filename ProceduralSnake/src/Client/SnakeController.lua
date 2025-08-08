--!strict
-- Snake Controller: Main client-side procedural animation system
-- Manages head tracking, spline generation, and body articulation

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CatmullRomSpline = require(Shared:WaitForChild("CatmullRomSpline"))
local CFrameUtils = require(Shared:WaitForChild("CFrameUtils"))

-- Types
type SnakeConfig = {
	segmentCount: number,
	segmentLength: number,
	historySize: number,
	smoothingFactor: number,
	splineAlpha: number,
	splineTension: number,
	updateRate: number,
	lodDistances: {near: number, medium: number, far: number}
}

type SnakeData = {
	model: Model,
	meshPart: MeshPart,
	bones: {Bone},
	ikControls: {IKControl},
	ikTargets: {Attachment},
	headHistory: {CFrame},
	spline: any,
	lastUpdateTime: number,
	distanceToCamera: number,
	lodLevel: number
}

local SnakeController = {}
SnakeController.__index = SnakeController

-- Default configuration
local DEFAULT_CONFIG: SnakeConfig = {
	segmentCount = 20,
	segmentLength = 0.5,
	historySize = 30,
	smoothingFactor = 0.85,
	splineAlpha = 0.5,
	splineTension = 0,
	updateRate = 60,
	lodDistances = {
		near = 50,
		medium = 100,
		far = 200
	}
}

-- Create a new snake controller instance
function SnakeController.new(character: Model, config: SnakeConfig?)
	local self = setmetatable({}, SnakeController)
	
	self.config = config or DEFAULT_CONFIG
	self.character = character
	self.snakes = {} :: {[Model]: SnakeData}
	self.camera = workspace.CurrentCamera
	
	-- Initialize controller
	self:_initialize()
	
	return self
end

-- Initialize the controller
function SnakeController:_initialize()
	-- Setup local player's snake
	local player = Players.LocalPlayer
	if player.Character == self.character then
		self:SetupSnake(self.character)
	end
	
	-- Connect update loop to PreRender for visual smoothness
	self.renderConnection = RunService.PreRender:Connect(function(deltaTime)
		self:Update(deltaTime)
	end)
	
	-- Listen for other players joining
	Players.PlayerAdded:Connect(function(newPlayer)
		newPlayer.CharacterAdded:Connect(function(character)
			task.wait(0.5) -- Wait for character to load
			self:SetupSnake(character)
		end)
	end)
	
	-- Setup existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character ~= self.character then
			self:SetupSnake(player.Character)
		end
	end
end

-- Setup a snake for a character
function SnakeController:SetupSnake(character: Model)
	local snakeMesh = character:FindFirstChild("SnakeMeshPart") :: MeshPart?
	if not snakeMesh then
		warn("SnakeMeshPart not found in character")
		return
	end
	
	-- Collect bones
	local bones: {Bone} = {}
	for i = 1, self.config.segmentCount do
		local bone = snakeMesh:FindFirstChild("Bone_" .. i, true)
		if bone and bone:IsA("Bone") then
			table.insert(bones, bone)
		end
	end
	
	if #bones == 0 then
		warn("No bones found in snake mesh")
		return
	end
	
	-- Create IK targets and controls
	local ikTargets: {Attachment} = {}
	local ikControls: {IKControl} = {}
	
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then
		warn("Humanoid not found in character")
		return
	end
	
	-- Create IK chain
	for i = 1, #bones - 1 do
		-- Create target attachment
		local target = Instance.new("Attachment")
		target.Name = "IKTarget_" .. i
		target.Parent = workspace.Terrain -- Parent to terrain for world-space positioning
		table.insert(ikTargets, target)
		
		-- Create IK control
		local ikControl = Instance.new("IKControl")
		ikControl.Name = "IKControl_" .. i
		ikControl.Type = Enum.IKControlType.Transform
		ikControl.ChainRoot = bones[i]
		ikControl.EndEffector = bones[i + 1]
		ikControl.Target = target
		ikControl.SmoothTime = 0.05
		ikControl.Weight = 1
		ikControl.Parent = humanoid
		
		-- Add constraints for natural bending
		local constraint = Instance.new("BallSocketConstraint")
		constraint.Name = "JointConstraint_" .. i
		constraint.Attachment0 = bones[i]
		constraint.Attachment1 = bones[i + 1]
		constraint.LimitsEnabled = true
		constraint.UpperAngle = 45 -- Maximum bend angle
		constraint.Parent = snakeMesh
		
		table.insert(ikControls, ikControl)
	end
	
	-- Initialize snake data
	local snakeData: SnakeData = {
		model = character,
		meshPart = snakeMesh,
		bones = bones,
		ikControls = ikControls,
		ikTargets = ikTargets,
		headHistory = {},
		spline = nil,
		lastUpdateTime = 0,
		distanceToCamera = 0,
		lodLevel = 1
	}
	
	-- Initialize head history with current position
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if head then
		for i = 1, self.config.historySize do
			table.insert(snakeData.headHistory, head.CFrame)
		end
		
		-- Create initial spline
		snakeData.spline = CatmullRomSpline.new(
			snakeData.headHistory,
			self.config.splineAlpha,
			self.config.splineTension
		)
		snakeData.spline:PrecomputeUnitSpeedData()
	end
	
	self.snakes[character] = snakeData
end

-- Main update loop
function SnakeController:Update(deltaTime: number)
	if not self.camera then
		return
	end
	
	local cameraPos = self.camera.CFrame.Position
	
	for character, snakeData in pairs(self.snakes) do
		-- Update distance to camera for LOD
		local head = character:FindFirstChild("Head") or character.PrimaryPart
		if head then
			snakeData.distanceToCamera = (head.Position - cameraPos).Magnitude
			
			-- Determine LOD level
			local lodDistances = self.config.lodDistances
			if snakeData.distanceToCamera < lodDistances.near then
				snakeData.lodLevel = 1 -- Full quality
			elseif snakeData.distanceToCamera < lodDistances.medium then
				snakeData.lodLevel = 2 -- Medium quality
			elseif snakeData.distanceToCamera < lodDistances.far then
				snakeData.lodLevel = 3 -- Low quality
			else
				snakeData.lodLevel = 4 -- Culled
			end
			
			-- Update based on LOD
			if snakeData.lodLevel < 4 then
				self:UpdateSnake(snakeData, deltaTime)
			end
		end
	end
end

-- Update individual snake
function SnakeController:UpdateSnake(snakeData: SnakeData, deltaTime: number)
	local head = snakeData.model:FindFirstChild("Head") or snakeData.model.PrimaryPart
	if not head then
		return
	end
	
	-- LOD-based update frequency
	local updateInterval = 1 / self.config.updateRate
	if snakeData.lodLevel == 2 then
		updateInterval = updateInterval * 2 -- Half rate for medium distance
	elseif snakeData.lodLevel == 3 then
		updateInterval = updateInterval * 5 -- Fifth rate for far distance
	end
	
	local currentTime = tick()
	if currentTime - snakeData.lastUpdateTime < updateInterval then
		return
	end
	snakeData.lastUpdateTime = currentTime
	
	-- Update head history
	local headCFrame = head.CFrame
	table.insert(snakeData.headHistory, 1, headCFrame)
	if #snakeData.headHistory > self.config.historySize then
		table.remove(snakeData.headHistory)
	end
	
	-- Update spline
	snakeData.spline:UpdatePoints(snakeData.headHistory)
	snakeData.spline:PrecomputeUnitSpeedData()
	
	-- Update IK targets along the spline
	local numTargets = #snakeData.ikTargets
	local segmentSpacing = 1 / (numTargets + 1)
	
	for i = 1, numTargets do
		local t = 1 - (i * segmentSpacing) -- Start from the head (t=1) and work backwards
		
		-- Get position on spline with unit-speed parametrization
		local targetPos = snakeData.spline:SolvePosition(t, true)
		
		-- Get tangent for orientation
		local tangent = snakeData.spline:SolveTangent(t, true)
		
		-- Calculate stable orientation
		local nextPos = if i < numTargets 
			then snakeData.spline:SolvePosition(t - segmentSpacing, true)
			else targetPos - tangent * self.config.segmentLength
		
		local targetCFrame = CFrameUtils.createStableCFrame(targetPos, nextPos)
		
		-- Apply smoothing for LOD 1 (near distance)
		if snakeData.lodLevel == 1 then
			local currentCFrame = snakeData.ikTargets[i].WorldCFrame
			targetCFrame = CFrameUtils.damp(currentCFrame, targetCFrame, self.config.smoothingFactor, deltaTime)
		end
		
		-- Update IK target
		snakeData.ikTargets[i].WorldCFrame = targetCFrame
	end
end

-- Cleanup snake data
function SnakeController:RemoveSnake(character: Model)
	local snakeData = self.snakes[character]
	if not snakeData then
		return
	end
	
	-- Clean up IK controls and targets
	for _, ikControl in ipairs(snakeData.ikControls) do
		ikControl:Destroy()
	end
	
	for _, target in ipairs(snakeData.ikTargets) do
		target:Destroy()
	end
	
	self.snakes[character] = nil
end

-- Cleanup the controller
function SnakeController:Destroy()
	if self.renderConnection then
		self.renderConnection:Disconnect()
	end
	
	-- Clean up all snakes
	for character, _ in pairs(self.snakes) do
		self:RemoveSnake(character)
	end
end

return SnakeController