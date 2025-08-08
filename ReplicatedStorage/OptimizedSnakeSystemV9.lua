-- Optimized Snake System V11 - SKINNED MESH WITH BONES
-- Uses a single rigged mesh with bone animation for zero gaps and maximum performance
-- Automatically detects and animates bones from your Blender model

print("🦴 Loading OptimizedSnakeSystemV9 - BONE-BASED VERSION")
print("🦴 This is the NEW skinned mesh version, not the old part-based system")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = RunService:IsClient() and game:GetService("UserInputService") or nil

-- Performance Constants
local BONE_UPDATE_RATE = 60 -- Hz for bone updates
local HISTORY_SIZE = 1000 -- Position history for smooth following
local LOD_UPDATE_RATE = 5 -- Check LOD every N frames

-- Visual Constants are now defined within functions for easier tuning

-- LOD System
local LOD_DISTANCES = {
	HIGH = 100,
	MEDIUM = 250,
	LOW = 500,
	CULLED = 1000
}

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

-- Skinned Mesh Snake Class
local Snake = {}
Snake.__index = Snake

function Snake.new(character, config)
	print("🦴 Creating new skinned mesh snake for", character.Name)
	local self = setmetatable({}, Snake)

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
	self.config.InitialLength = self.config.InitialLength or 85

	-- State
	self.isAlive = true
	self.length = self.config.InitialLength
	self.frameCount = 0
	self.lastUpdate = tick()
	self.isBoosting = false

	-- Movement history
	self.positionHistory = {}
	self.historyIndex = 0

	-- LOD state
	self.lodLevel = "HIGH"
	self.isLocalPlayer = (self.player == Players.LocalPlayer)
	self.updateFrequency = 1

	-- Hide character
	self:hideCharacter()

	-- Create the skinned mesh
	if not self:createSkinnedMesh() then
		warn("Failed to create skinned mesh snake for", self.player.Name)
		return nil
	end

	-- Initialize position history
	self:initializeHistory()

	-- Setup update connections
	self:setupUpdateConnections()

	print("✅ Skinned Mesh Snake created for", self.player.Name)
	return self
end

function Snake:createFallbackSnake()
	-- Create a simple model as fallback
	self.model = Instance.new("Model")
	self.model.Name = "FallbackSnake_" .. self.player.Name
	self.model.Parent = workspace

	-- Create a simple part
	self.meshPart = Instance.new("Part")
	self.meshPart.Name = "SnakeBody"
	self.meshPart.Size = Vector3.new(4, 4, 4)
	self.meshPart.Shape = Enum.PartType.Ball
	self.meshPart.Material = Enum.Material.Neon
	self.meshPart.BrickColor = BrickColor.new("Lime green")
	self.meshPart.TopSurface = Enum.SurfaceType.Smooth
	self.meshPart.BottomSurface = Enum.SurfaceType.Smooth
	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false
	self.meshPart.Parent = self.model

	-- Tag for collision
	CollectionService:AddTag(self.meshPart, "SnakeBody")
	self.meshPart:SetAttribute("OwnerName", self.player.Name)
	self.meshPart:SetAttribute("PlayerUserId", self.player.UserId)

	-- No bones for fallback
	self.boneChain = {}
	self.boneData = {}

	-- Weld to character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart

	-- Position at character
	self.meshPart.CFrame = self.rootPart.CFrame

	-- Add basic visual effects
	self:addVisualEffects()

	warn("⚠️ Using fallback snake - no bone animation available")
	return true
end

function Snake:hideCharacter()
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
	self.rootPart.CanCollide = true
	self.rootPart.CanQuery = false
	self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function Snake:createSkinnedMesh()
	print("🦴 Looking for skinned snake template...")

	-- Get the snake template
	local templateModel = ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate") or 
		ReplicatedStorage:FindFirstChild("slither_snake_rigged")

	if not templateModel then
		warn("❌ Snake template not found! Looking for 'SkinnedSnakeTemplate' or 'slither_snake_rigged' in ReplicatedStorage")
		warn("❌ Please ensure your rigged snake model is placed directly in ReplicatedStorage")
		warn("❌ Available items in ReplicatedStorage:")
		for _, item in pairs(ReplicatedStorage:GetChildren()) do
			warn("  - " .. item.Name .. " (" .. item.ClassName .. ")")
		end

		-- FALLBACK: Create a simple part-based snake for now
		warn("⚠️ FALLBACK: Creating simple part snake instead")
		return self:createFallbackSnake()
	end

	print("🦴 Found snake template:", templateModel.Name)

	-- Clone the template
	self.model = templateModel:Clone()
	self.model.Name = "Snake_" .. self.player.Name
	self.model.Parent = workspace

	-- Do NOT scale the model - use the size from Blender

	-- Find the mesh part (should be named "Circle" based on the structure)
	self.meshPart = self.model:FindFirstChild("Circle")
	if not self.meshPart then
		self.meshPart = self.model:FindFirstChildOfClass("MeshPart")
	end

	if not self.meshPart then
		warn("❌ No MeshPart found in snake model!")
		return false
	end

	-- Setup mesh properties for proper physics
	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false  -- No collision with world
	self.meshPart.CanQuery = false    -- Don't interfere with raycasts
	self.meshPart.CanTouch = true     -- Still detect touches for gameplay
	self.meshPart.Massless = true     -- Prevent physics issues

	-- Ensure proper collision group (if exists)
	pcall(function()
		self.meshPart.CollisionGroup = "SnakeBodies"
	end)

	-- Set network ownership to player for smooth movement
	if self.player then
		pcall(function()
			self.meshPart:SetNetworkOwner(self.player)
		end)
	end

	-- Tag for collision
	CollectionService:AddTag(self.meshPart, "SnakeBody")
	self.meshPart:SetAttribute("OwnerName", self.player.Name)
	self.meshPart:SetAttribute("PlayerUserId", self.player.UserId)

	-- Find and organize bones
	self:findAndOrganizeBones()

	-- Store initial poses from InitialPoses folder
	self:storeInitialPoses()
	
	-- CRITICAL: Initialize bones to lay flat immediately
	-- This ensures the snake spawns in the correct position
	for i, bone in ipairs(self.boneChain) do
		local boneInfo = self.boneData[bone.Name]
		if boneInfo then
			-- Reset to original transform first
			bone.Transform = boneInfo.originalTransform
		end
	end

	-- Temporarily anchor the root part to prevent flinging
	local wasAnchored = self.rootPart.Anchored
	self.rootPart.Anchored = true

	-- Position at character FIRST before welding
	-- Check if model needs rotation to lay flat (snake should be horizontal)
	-- You may need to adjust this rotation based on how your model was exported
	self.meshPart.CFrame = self.rootPart.CFrame * CFrame.Angles(0, 0, 0) -- Try different rotations if needed
	-- Common rotations to try:
	-- * CFrame.Angles(math.rad(90), 0, 0)  -- Rotate 90 degrees on X axis
	-- * CFrame.Angles(0, math.rad(90), 0)  -- Rotate 90 degrees on Y axis
	-- * CFrame.Angles(0, 0, math.rad(90))  -- Rotate 90 degrees on Z axis

	-- Ensure no velocity before welding
	self.meshPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	self.meshPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	-- Small wait to ensure physics settles
	task.wait()

	-- Now weld to character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart

	-- Restore anchor state
	self.rootPart.Anchored = wasAnchored

	-- Add visual effects
	self:addVisualEffects()

	return true
end

function Snake:findAndOrganizeBones()
	self.bones = {}
	self.boneChain = {}
	self.boneData = {}

	-- Find the first bone (should be named "Bone")
	local firstBone = self.meshPart:FindFirstChild("Bone")
	if not firstBone then
		firstBone = self.meshPart:FindFirstChildOfClass("Bone")
	end

	if not firstBone then
		warn("❌ No bones found in mesh!")
		return
	end

	-- Follow the bone chain automatically
	local currentBone = firstBone
	local boneIndex = 1

	while currentBone do
		table.insert(self.boneChain, currentBone)
		self.boneData[currentBone.Name] = {
			bone = currentBone,
			index = boneIndex,
			originalTransform = currentBone.Transform
		}

		-- Find next bone in chain (child of current)
		local nextBone = nil
		for _, child in pairs(currentBone:GetChildren()) do
			if child:IsA("Bone") then
				nextBone = child
				break
			end
		end

		currentBone = nextBone
		boneIndex = boneIndex + 1
	end

	print(string.format("✅ Found %d bones in chain:", #self.boneChain))
	for i, bone in ipairs(self.boneChain) do
		print(string.format("  [%d] %s", i, bone.Name))
	end
end

function Snake:storeInitialPoses()
	local initialPosesFolder = self.model:FindFirstChild("InitialPoses")
	if not initialPosesFolder then
		warn("⚠️ InitialPoses folder not found")
		return
	end

	self.initialPoses = {}

	-- Store pose data for each bone
	for _, boneInfo in pairs(self.boneData) do
		local bone = boneInfo.bone
		local boneName = bone.Name

		self.initialPoses[boneName] = {
			composited = initialPosesFolder:FindFirstChild(boneName .. "_Composited"),
			initial = initialPosesFolder:FindFirstChild(boneName .. "_Initial"),
			original = initialPosesFolder:FindFirstChild(boneName .. "_Original"),
			transform = bone.Transform
		}
	end
end

function Snake:addVisualEffects()
	-- Add glow light
	self.headLight = Instance.new("PointLight")
	self.headLight.Brightness = 2
	self.headLight.Range = 15
	self.headLight.Color = self.config.HeadColor
	self.headLight.Shadows = false
	self.headLight.Parent = self.meshPart

	-- Add particle emitter for boost
	self.boostParticles = Instance.new("ParticleEmitter")
	self.boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	self.boostParticles.Rate = 0
	self.boostParticles.Lifetime = NumberRange.new(0.5, 1)
	self.boostParticles.Speed = NumberRange.new(5, 10)
	self.boostParticles.SpreadAngle = Vector2.new(15, 15)
	self.boostParticles.Color = ColorSequence.new(self.config.HeadColor)
	self.boostParticles.LightEmission = 1
	self.boostParticles.Parent = self.meshPart
end

function Snake:initializeHistory()
	local startPos = self.rootPart.Position
	local startDir = self.rootPart.CFrame.LookVector

	for i = 1, HISTORY_SIZE do
		self.positionHistory[i] = {
			position = startPos - startDir * (i * 0.5),
			direction = startDir,
			time = tick() - (i * 0.016)
		}
	end
end

function Snake:updateHistory()
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1

	self.positionHistory[self.historyIndex] = {
		position = self.rootPart.Position,
		direction = self.rootPart.CFrame.LookVector,
		time = tick()
	}
end

function Snake:getHistoricalData(stepsBack)
	local index = ((self.historyIndex - stepsBack - 1) % HISTORY_SIZE) + 1
	return self.positionHistory[index] or self.positionHistory[self.historyIndex]
end

-- Helper function for stable CFrame calculation (from Section 6.1)
function Snake:createStableCFrame(position, lookAtPosition, upVector)
	local lookVector = (lookAtPosition - position).Unit
	
	-- Ensure lookVector and upVector are not parallel
	if math.abs(lookVector:Dot(upVector)) > 0.999 then
		-- If they are parallel, fallback to a different axis
		upVector = Vector3.new(1, 0, 0) 
	end

	local rightVector = upVector:Cross(lookVector).Unit
	local newUpVector = lookVector:Cross(rightVector).Unit -- Recalculate for orthogonality

	return CFrame.fromMatrix(
		position,
		rightVector,
		newUpVector,
		-lookVector -- Note: fromMatrix uses the back-vector (-Z)
	)
end

-- Frame-rate independent damping (from Section 6.2.1)
function Snake:damp(current, goal, smoothingFactor, dt)
	local alpha = 1 - (smoothingFactor ^ dt)
	return current:Lerp(goal, alpha)
end

function Snake:updateBones(deltaTime)
	if not self.boneChain or #self.boneChain == 0 then return end

	-- Following the recommended hybrid kinematic approach from Section 8.2
	local SEGMENT_DISTANCE = 2.0  -- Distance between segments
	local SMOOTHING_FACTOR = 0.85 -- Higher = slower/smoother movement
	
	-- The world up vector for stable orientation
	local worldUp = Vector3.new(0, 1, 0)
	
	for i, bone in ipairs(self.boneChain) do
		local boneInfo = self.boneData[bone.Name]
		if not boneInfo then continue end
		
		-- Calculate how far back in history this bone should look
		local stepsBack = (i - 1) * 3 -- Adjust multiplier for tighter/looser following
		local historicalData = self:getHistoricalData(stepsBack)
		
		if historicalData then
			-- Get position for this bone and the next
			local currentPos = self.rootPart.Position
			local targetPos = historicalData.position
			
			-- Calculate stable orientation using cross product method
			if i < #self.boneChain then
				-- For non-tail bones, look at the next bone's position
				local nextStepsBack = i * 3
				local nextData = self:getHistoricalData(nextStepsBack)
				if nextData then
					-- Calculate the direction this bone should face
					local direction = (targetPos - nextData.position).Unit
					
					-- Calculate bend angle relative to rest pose
					local restDirection = Vector3.new(0, 0, -1) -- Forward in bone space
					local angle = math.acos(math.clamp(direction:Dot(restDirection), -1, 1))
					
					-- Only apply rotation if there's significant bend
					if angle > 0.01 then
						local axis = restDirection:Cross(direction)
						if axis.Magnitude > 0.001 then
							axis = axis.Unit
							-- Apply rotation as offset from original transform
							local rotation = CFrame.fromAxisAngle(axis, angle * 0.3) -- Dampened rotation
							local targetTransform = boneInfo.originalTransform * rotation
							
							-- Frame-rate independent smoothing
							bone.Transform = self:damp(bone.Transform, targetTransform, SMOOTHING_FACTOR, deltaTime)
						else
							-- No rotation needed
							bone.Transform = self:damp(bone.Transform, boneInfo.originalTransform, SMOOTHING_FACTOR, deltaTime)
						end
					else
						-- Return to rest pose when straight
						bone.Transform = self:damp(bone.Transform, boneInfo.originalTransform, SMOOTHING_FACTOR, deltaTime)
					end
				end
			else
				-- Tail bone - just follow the previous bone smoothly
				bone.Transform = self:damp(bone.Transform, boneInfo.originalTransform, SMOOTHING_FACTOR, deltaTime)
			end
		else
			-- No history - maintain rest pose
			bone.Transform = self:damp(bone.Transform, boneInfo.originalTransform, SMOOTHING_FACTOR, deltaTime)
		end
	end
end

function Snake:updateLOD()
	if not workspace.CurrentCamera then return end

	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - self.meshPart.Position).Magnitude

	local newLOD = "CULLED"
	if distance < LOD_DISTANCES.HIGH then
		newLOD = "HIGH"
	elseif distance < LOD_DISTANCES.MEDIUM then
		newLOD = "MEDIUM"
	elseif distance < LOD_DISTANCES.LOW then
		newLOD = "LOW"
	end

	if newLOD ~= self.lodLevel then
		self.lodLevel = newLOD
		self:applyLODSettings()
	end
end

function Snake:applyLODSettings()
	if self.lodLevel == "CULLED" then
		self.model.Parent = nil
	else
		self.model.Parent = workspace

		if self.lodLevel == "LOW" then
			self.updateFrequency = 4
		elseif self.lodLevel == "MEDIUM" then
			self.updateFrequency = 2
		else
			self.updateFrequency = 1
		end
	end
end

function Snake:setupUpdateConnections()
	-- Main update loop
	-- Using PreRender for visual-only updates as recommended in Section 6.2.2
	local updateEvent = RunService:IsClient() and RunService.PreRender or RunService.Heartbeat
	self.updateConnection = updateEvent:Connect(function(deltaTime)
		if not self.isAlive then return end

		self.frameCount = self.frameCount + 1

		-- Update position history
		self:updateHistory()

		-- Update bones based on LOD
		if self.frameCount % self.updateFrequency == 0 then
			self:updateBones(deltaTime)
		end

		-- Update LOD
		if self.frameCount % 10 == 0 then
			self:updateLOD()
		end

		-- Keep mesh attached and check weld
		if self.meshPart and self.meshPart.Parent then
			-- Check if weld still exists
			local weld = self.meshPart:FindFirstChildOfClass("WeldConstraint")
			if not weld or not weld.Part1 or weld.Part1 ~= self.rootPart then
				-- Weld broke, recreate it
				warn("⚠️ Weld broke, recreating...")
				if weld then weld:Destroy() end

				local newWeld = Instance.new("WeldConstraint")
				newWeld.Part0 = self.meshPart
				newWeld.Part1 = self.rootPart
				newWeld.Parent = self.meshPart
			end

			-- The weld should handle positioning automatically
			-- Only update CFrame if not welded
			if not weld then
				self.meshPart.CFrame = self.rootPart.CFrame
			end
		end
	end)

	-- Network updates (client only)
	if RunService:IsClient() and self.isLocalPlayer then
		self.networkConnection = RunService.Heartbeat:Connect(function()
			if self.frameCount % 30 == 0 and remoteEvents.positionupdate then
				remoteEvents.positionupdate:FireServer(self.rootPart.Position)
			end
		end)
	end
end

function Snake:setBoost(boosting)
	self.isBoosting = boosting
	if self.boostParticles then
		self.boostParticles.Rate = boosting and 100 or 0
	end
end

function Snake:grow(amount)
	self.length = self.length + amount
	-- Could add scaling effects here
end

function Snake:destroy()
	self.isAlive = false

	if self.updateConnection then
		self.updateConnection:Disconnect()
	end

	if self.networkConnection then
		self.networkConnection:Disconnect()
	end

	if self.model then
		self.model:Destroy()
	end

	print("❌ Snake destroyed for", self.player.Name)
end

-- Module functions
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
	createNetworkEvents()
	print("🦴 ✅ OptimizedSnakeSystemV9 (Skinned Mesh with Bones) initialized")
	print("🦴 Looking for snake template: 'SkinnedSnakeTemplate' or 'slither_snake_rigged' in ReplicatedStorage")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
	return Snake.new(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
	local snake = Snake.new(character, config)

	if savedState and snake then
		if savedState.length then
			snake.length = savedState.length
		end
		if savedState.isAlive ~= nil then
			snake.isAlive = savedState.isAlive
		end
	end

	return snake
end

return OptimizedSnakeSystemV9
