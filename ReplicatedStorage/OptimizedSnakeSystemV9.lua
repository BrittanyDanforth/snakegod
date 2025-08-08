-- Optimized Snake System V11.3 - Robust Skinned Mesh Driver
-- Fully reworked: NaN-safe, nearest-neighbor bone chain, arc-length history sampling, physics-safe assembly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

-- Optional spline dependency (safe require)
local CatmullRomSpline = nil
pcall(function()
	CatmullRomSpline = require(ReplicatedStorage:FindFirstChild("CatmullRomSpline"))
end)

-- Config
local MESH_ASSET_ID = "rbxassetid://84274514316556"
local BONE_COUNT = 12
local HISTORY_SIZE = 1200

-- Movement/animation
local DEFAULT_BONE_SPACING = 2.0
local BONE_BLEND_FACTOR = 0.45
local WAVE_AMPLITUDE = 0.6
local WAVE_FREQUENCY = 2.0
local BASE_SPEED = 20
local BOOST_MULTIPLIER = 1.5

-- Visuals
local BASE_SCALE = 1.0
local GLOW_INTENSITY = 2.0

-- LOD
local LOD_DISTANCES = { HIGH = 100, MEDIUM = 300, LOW = 600, CULLED = 1000 }

-- Math helpers
local EPS = 1e-6
local function isValidVector3(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
end
local function safeNormalize(v, fallback)
	if not isValidVector3(v) then return fallback end
	local m = v.Magnitude
	if not m or m ~= m or m < EPS then return fallback end
	return v / m
end
local WORLD_AXES = { Vector3.new(1,0,0), Vector3.new(0,1,0), Vector3.new(0,0,1) }
local function orthonormalBasis(prevUp, tangent)
	local t = safeNormalize(tangent, Vector3.new(0,0,-1))
	local up = prevUp - t * prevUp:Dot(t)
	up = safeNormalize(up, Vector3.new(0,1,0))
	if up.Magnitude < 0.5 then
		local best = WORLD_AXES[1]
		local bd = math.abs(t:Dot(best))
		for i=2,#WORLD_AXES do
			local d = math.abs(t:Dot(WORLD_AXES[i]))
			if d < bd then bd, best = d, WORLD_AXES[i] end
		end
		up = safeNormalize(best - t * best:Dot(t), Vector3.new(0,1,0))
	end
	local right = safeNormalize(t:Cross(up), Vector3.new(1,0,0))
	up = safeNormalize(right:Cross(t), Vector3.new(0,1,0))
	return t, right, up
end
local function safeCFrameFromTRU(pos, t, r, u)
	if not isValidVector3(pos) then pos = Vector3.new() end
	local tt = safeNormalize(t, Vector3.new(0,0,-1))
	local rr = r
	if not isValidVector3(rr) or rr.Magnitude < 0.5 then
		rr = tt:Cross(Vector3.new(0,1,0))
		if rr.Magnitude < EPS then rr = tt:Cross(Vector3.new(1,0,0)) end
		rr = safeNormalize(rr, Vector3.new(1,0,0))
	end
	local uu = safeNormalize(rr:Cross(tt), Vector3.new(0,1,0))
	rr = safeNormalize(tt:Cross(uu), Vector3.new(1,0,0))
	uu = safeNormalize(rr:Cross(tt), Vector3.new(0,1,0))
	return CFrame.fromMatrix(pos, rr, uu)
end

-- History sampling by distance
local function getHistoryAtBackDistance(self, targetBackDistance)
	if not self.positionHistory or self.historyIndex == 0 then return nil end
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
			local overshoot = accumulated - targetBackDistance
			local t = (segment and segment > EPS) and (1 - overshoot/segment) or 1
			t = (t ~= t) and 1 or math.clamp(t,0,1)
			local pos = prev.position:Lerp(current.position, t)
			local dir = current.position - prev.position
			dir = (dir and dir.Magnitude > EPS) and dir.Unit or (self.rootPart and self.rootPart.CFrame.LookVector or Vector3.new(0,0,-1))
			return { position = pos, direction = dir }
		end
		current = prev
		idx = prevIdx
		prevIdx = ((prevIdx - 2) % HISTORY_SIZE) + 1
		if prevIdx == idx then break end
	end
	return { position = current and current.position or self.rootPart.Position,
		direction = current and (current.direction or self.rootPart.CFrame.LookVector) or self.rootPart.CFrame.LookVector }
end

-- Build a robust bone chain using nearest-neighbor ordering between farthest endpoints
local function buildBoneChain(meshPart)
	local bones = {}
	for _, d in ipairs(meshPart:GetDescendants()) do
		if d:IsA("Bone") then table.insert(bones, d) end
	end
	if #bones < 2 then return bones end
	-- positions in object space
	local objPos = {}
	for i,b in ipairs(bones) do objPos[b] = b.CFrame.Position end
	-- find two farthest bones as endpoints
	local a, b, maxd = bones[1], bones[2], -1
	for i=1,#bones do
		for j=i+1,#bones do
			local d = (objPos[bones[i]] - objPos[bones[j]]).Magnitude
			if d > maxd then maxd = d; a = bones[i]; b = bones[j] end
		end
	end
	-- choose start closest to mesh origin
	local start = (objPos[a].Magnitude <= objPos[b].Magnitude) and a or b
	local used = {}
	local chain = { start }
	used[start] = true
	while #chain < #bones do
		local last = chain[#chain]
		local best, bestd = nil, 1e9
		for _, cand in ipairs(bones) do
			if not used[cand] then
				local d = (objPos[cand] - objPos[last]).Magnitude
				if d < bestd then bestd, best = d, cand end
			end
		end
		if not best then break end
		used[best] = true
		table.insert(chain, best)
	end
	return chain
end

-- Class
local SkinnedSnake = {}
SkinnedSnake.__index = SkinnedSnake

function SkinnedSnake.new(character, config)
	local self = setmetatable({}, SkinnedSnake)
	self.character = character
	self.rootPart = character:WaitForChild("HumanoidRootPart")
	self.humanoid = character:WaitForChild("Humanoid")
	self.player = Players:GetPlayerFromCharacter(character)
	self.config = config or {}
	-- defaults
	self.config.HeadColor = self.config.HeadColor or Color3.fromRGB(76,217,100)
	self.config.BodyColors = (typeof(self.config.BodyColors) == "table" and #self.config.BodyColors>0) and self.config.BodyColors or { self.config.HeadColor }
	self.length = tonumber(self.config.InitialLength) or 85
	self.scale = BASE_SCALE
	self.speed = BASE_SPEED
	self.isBoosting = false
	self.isAlive = true

	-- animation state
	self.boneSpacing = DEFAULT_BONE_SPACING
	self.previousTransforms = {}
	self.previousUpVectors = {}
	self.previousTangents = {}
	self.restBoneCFrames = {}

	-- history
	self.positionHistory = {}
	self.historyIndex = 0

	-- visuals
	self.currentColorIndex = 1
	self.rainbowMode = false

	-- perf
	self.frameCount = 0
	self.lodLevel = "HIGH"

	self:hideCharacter()
	self:createSkinnedMesh()
	self:initializeHistory()
	self:startUpdateLoop()
	print("✅ Skinned Snake created for", self.player and self.player.Name or "Player")
	return self
end

function SkinnedSnake:hideCharacter()
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
	self.model = Instance.new("Model")
	self.model.Name = "SkinnedSnake_" .. (self.player and self.player.Name or "Player")
	self.model.Parent = workspace

	local templateModel = ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate")
		or ReplicatedStorage:FindFirstChild("slither_snake_rigged")
		or ReplicatedStorage:FindFirstChild("untitledsnakeeeee")
	if not templateModel then
		local meshes = ReplicatedStorage:FindFirstChild("Meshes")
		if meshes then
			templateModel = meshes:FindFirstChild("untitledsnakeeeee")
				or meshes:FindFirstChildOfClass("MeshPart")
				or meshes:FindFirstChildOfClass("Model")
		end
	end
	if not templateModel then
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child:IsA("MeshPart") or child:IsA("Model") then templateModel = child; break end
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
		for _, d in ipairs(cloned:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide=false; d.CanQuery=false; d.Massless=true end
		end
		if RunService:IsServer() and self.meshPart and self.meshPart:IsA("MeshPart") and type(MESH_ASSET_ID) == "string" and #MESH_ASSET_ID>0 then
			self.meshPart.MeshId = MESH_ASSET_ID
		end
	else
		local part = Instance.new("Part")
		part.Name = "SnakeFallback"
		part.Size = Vector3.new(4,4,4)
		part.Material = Enum.Material.Neon
		part.Color = self.config.HeadColor
		part.CanCollide = false
		part.CanQuery = false
		part.Parent = self.model
		self.meshPart = part
	end

	self.meshPart.Anchored = false
	self.meshPart.CanCollide = false
	self.meshPart.CanQuery = true
	self.meshPart.CanTouch = false
	self.meshPart.Massless = true
	self.meshPart.Size = self.meshPart.Size * self.scale
	CollectionService:AddTag(self.meshPart, "SnakeBody")

	-- build bone chain
	self.bones = buildBoneChain(self.meshPart)
	if BONE_COUNT and #self.bones > BONE_COUNT then
		local trimmed = {}
		for i=1,BONE_COUNT do trimmed[i]=self.bones[i] end
		self.bones = trimmed
	end
	print("Found", #self.bones, "bones in the mesh")
	if BONE_COUNT and #self.bones ~= BONE_COUNT then
		warn(string.format("[OptimizedSnakeSystemV9] Bone count mismatch: expected %d, found %d", BONE_COUNT, #self.bones))
	end

	-- rest poses
	self.previousTransforms = {}
	self.previousUpVectors = {}
	self.previousTangents = {}
	self.restBoneCFrames = {}
	for _, bone in ipairs(self.bones) do
		self.restBoneCFrames[bone] = bone.CFrame
		self.previousUpVectors[bone] = Vector3.new(0,1,0)
		self.previousTransforms[bone] = bone.Transform
	end

	-- derive spacing from rest if possible
	if #self.bones >= 2 then
		local sum = 0
		for i=2,#self.bones do
			sum = sum + (self.restBoneCFrames[self.bones[i]].Position - self.restBoneCFrames[self.bones[i-1]].Position).Magnitude
		end
		sum = sum / math.max(1,(#self.bones-1))
		if sum == sum and sum > EPS then self.boneSpacing = sum end
	end

	self:addVisualEffects()
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = self.meshPart
	weld.Part1 = self.rootPart
	weld.Parent = self.meshPart
	self.welded = true
	self.meshPart.CFrame = self.rootPart.CFrame
end

function SkinnedSnake:addVisualEffects()
	self.headLight = Instance.new("PointLight")
	self.headLight.Brightness = GLOW_INTENSITY
	self.headLight.Range = 20
	self.headLight.Color = self.config.HeadColor
	self.headLight.Shadows = false
	self.headLight.Parent = self.meshPart

	self.surfaceLight = Instance.new("SurfaceLight")
	self.surfaceLight.Brightness = 0.5
	self.surfaceLight.Color = self.config.HeadColor
	self.surfaceLight.Face = Enum.NormalId.Front
	self.surfaceLight.Parent = self.meshPart

	self.boostParticles = Instance.new("ParticleEmitter")
	self.boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	self.boostParticles.Rate = 0
	self.boostParticles.Lifetime = NumberRange.new(0.5,1)
	self.boostParticles.VelocityInheritance = 0.5
	self.boostParticles.EmissionDirection = Enum.NormalId.Back
	self.boostParticles.Speed = NumberRange.new(5,10)
	self.boostParticles.SpreadAngle = Vector2.new(15,15)
	self.boostParticles.Color = ColorSequence.new(self.config.HeadColor)
	self.boostParticles.LightEmission = 1
	self.boostParticles.LightInfluence = 0
	self.boostParticles.Size = NumberSequence.new{
		NumberSequenceKeypoint.new(0,0.5),
		NumberSequenceKeypoint.new(0.5,1),
		NumberSequenceKeypoint.new(1,0)
	}
	self.boostParticles.Parent = self.meshPart
end

function SkinnedSnake:initializeHistory()
	local startPos = self.rootPart.Position
	local startLook = self.rootPart.CFrame.LookVector
	for i=1,HISTORY_SIZE do
		self.positionHistory[i] = { position = startPos - startLook * (i*0.5), direction = startLook, time = tick() }
	end
	self.historyIndex = HISTORY_SIZE
end

function SkinnedSnake:updateHistory()
	self.historyIndex = (self.historyIndex % HISTORY_SIZE) + 1
	self.positionHistory[self.historyIndex] = { position = self.rootPart.Position, direction = self.rootPart.CFrame.LookVector, time = tick() }
end

function SkinnedSnake:updateBones(deltaTime)
	if not self.bones or #self.bones==0 then return end
	if not self.meshPart or not self.meshPart.Parent then return end

	local meshCFrame = self.meshPart.CFrame
	local chainPrevUp = Vector3.new(0,1,0)

	local function setBoneFromWorld(bone, position, tangent, index)
		if not isValidVector3(position) or not isValidVector3(tangent) then return end
		local prevT = self.previousTangents[bone] or tangent
		local smoothedT = safeNormalize(prevT*0.6 + tangent*0.4, tangent)
		self.previousTangents[bone] = smoothedT

		local tVec, rVec, uVec = orthonormalBasis(self.previousUpVectors[bone] or chainPrevUp, smoothedT)
		chainPrevUp = uVec
		self.previousUpVectors[bone] = uVec

		local worldCFrame = safeCFrameFromTRU(position, tVec, rVec, uVec)
		local wave = math.clamp(math.sin((tick()*WAVE_FREQUENCY) - index*0.3) * (WAVE_AMPLITUDE*0.1), -0.2, 0.2)
		worldCFrame = worldCFrame * CFrame.Angles(0, 0, wave)

		local desiredObjectCF = meshCFrame:ToObjectSpace(worldCFrame)
		local restObjectCF = self.restBoneCFrames[bone] or CFrame.new()
		local relativeTransform = restObjectCF:ToObjectSpace(desiredObjectCF)

		local prevRel = self.previousTransforms[bone]
		if prevRel then
			local maxStep = (self.boneSpacing or DEFAULT_BONE_SPACING) * 2
			local prevPos = prevRel.Position
			local newPos = relativeTransform.Position
			local delta = newPos - prevPos
			local dMag = delta.Magnitude
			if dMag and dMag == dMag and dMag > maxStep and dMag < 1e6 then
				local alpha = maxStep / dMag
				relativeTransform = CFrame.new(prevPos:Lerp(newPos, alpha)) * (prevRel.Rotation:Lerp(relativeTransform.Rotation, math.clamp(BONE_BLEND_FACTOR, 0.1, 0.9)))
			end
			relativeTransform = prevRel:Lerp(relativeTransform, BONE_BLEND_FACTOR)
		end

		bone.Transform = relativeTransform
		self.previousTransforms[bone] = relativeTransform
	end

	if CatmullRomSpline then
		local function buildPoints(count)
			local pts = {}
			if not self.positionHistory or self.historyIndex==0 then return pts end
			local step = math.max(1, math.floor(HISTORY_SIZE / math.max(4, count)))
			local idx = self.historyIndex
			for i=1,count do
				local h = self.positionHistory[idx]
				if h then table.insert(pts, 1, h.position) end
				idx = ((idx - step - 1) % HISTORY_SIZE) + 1
			end
			while #pts < 4 do table.insert(pts, pts[#pts] or self.rootPart.Position) end
			return pts
		end
		local controlPoints = buildPoints(10)
		if #controlPoints >= 4 then
			local spline = CatmullRomSpline.new(controlPoints)
			if spline then
				local splineLen = spline:GetLength()
				if splineLen and splineLen == splineLen and splineLen > EPS then
					spline:SetUniform(true)
					local totalLen = math.max(0, (#self.bones-1) * self.boneSpacing)
					local startOff = math.max(0, splineLen - totalLen)
					for i,bone in ipairs(self.bones) do
						local d = startOff + (i-1)*self.boneSpacing
						local tParam = math.clamp(d / splineLen, 0, 1)
						local pos = spline:GetPoint(tParam)
						local tan = safeNormalize(spline:GetTangent(tParam), Vector3.new(0,0,-1))
						if isValidVector3(pos) and isValidVector3(tan) then setBoneFromWorld(bone, pos, tan, i) end
					end
				end
			end
		end
	else
		for i,bone in ipairs(self.bones) do
			local back = (i-1) * self.boneSpacing
			local sample = getHistoryAtBackDistance(self, back)
			if sample and isValidVector3(sample.position) and isValidVector3(sample.direction) then
				local pos = sample.position
				local tan = safeNormalize(sample.direction, Vector3.new(0,0,-1))
				setBoneFromWorld(bone, pos, tan, i)
			end
		end
	end
end

function SkinnedSnake:updateLOD()
	local cam = workspace.CurrentCamera
	if not cam or not self.meshPart then return end
	local dist = (cam.CFrame.Position - self.meshPart.Position).Magnitude
	local newLOD = "CULLED"
	if dist < LOD_DISTANCES.HIGH then newLOD = "HIGH"
	elseif dist < LOD_DISTANCES.MEDIUM then newLOD = "MEDIUM"
	elseif dist < LOD_DISTANCES.LOW then newLOD = "LOW" end
	if newLOD ~= self.lodLevel then
		self.lodLevel = newLOD
		if self.lodLevel == "CULLED" then
			self.meshPart.Parent = nil
		else
			self.meshPart.Parent = self.model
			self.headLight.Enabled = (self.lodLevel == "HIGH")
			self.surfaceLight.Enabled = (self.lodLevel == "HIGH")
			self.boostParticles.Enabled = (self.lodLevel == "HIGH") and self.isBoosting or false
		end
	end
end

function SkinnedSnake:updateColors()
	if not self.headLight or not self.boostParticles then return end
	if self.rainbowMode then
		local hue = (tick()*0.5) % 1
		local color = Color3.fromHSV(hue,1,1)
		self.headLight.Color = color
		self.boostParticles.Color = ColorSequence.new(color)
		return
	end
	local chosen = nil
	if typeof(self.config.BodyColors) == "table" and #self.config.BodyColors>0 then
		self.currentColorIndex = (self.currentColorIndex % #self.config.BodyColors) + 1
		chosen = self.config.BodyColors[self.currentColorIndex]
	end
	if typeof(chosen) ~= "Color3" then chosen = self.config.HeadColor or Color3.fromRGB(76,217,100) end
	self.headLight.Color = chosen
	self.boostParticles.Color = ColorSequence.new(chosen)
end

function SkinnedSnake:setBoost(boost)
	self.isBoosting = boost and true or false
	self.speed = self.isBoosting and (BASE_SPEED*BOOST_MULTIPLIER) or BASE_SPEED
	if self.boostParticles then self.boostParticles.Rate = self.isBoosting and 100 or 0 end
	self.humanoid.WalkSpeed = self.speed
end

function SkinnedSnake:updateConfig(newConfig)
	if not newConfig then return end
	if newConfig.HeadColor then
		self.config.HeadColor = newConfig.HeadColor
		if self.headLight then self.headLight.Color = newConfig.HeadColor end
		if self.boostParticles then self.boostParticles.Color = ColorSequence.new(newConfig.HeadColor) end
	end
	if typeof(newConfig.BodyColors) == "table" and #newConfig.BodyColors>0 then
		self.config.BodyColors = newConfig.BodyColors
	end
end

function SkinnedSnake:startUpdateLoop()
	self.updateConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.isAlive then return end
		self.frameCount += 1
		self:updateHistory()
		self:updateBones(dt)
		if self.frameCount % 5 == 0 then self:updateLOD() end
		if self.frameCount % 30 == 0 then self:updateColors() end
		if self.meshPart and self.meshPart.Parent and not self.welded then
			self.meshPart.CFrame = self.rootPart.CFrame
		end
	end)
end

function SkinnedSnake:destroy()
	self.isAlive = false
	if self.updateConnection then self.updateConnection:Disconnect() end
	if self.model then self.model:Destroy() end
	print("❌ Skinned Snake destroyed for", self.player and self.player.Name or "Player")
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
	if savedState and savedState.length then snake.length = savedState.length end
	return snake
end
return OptimizedSnakeSystemV9