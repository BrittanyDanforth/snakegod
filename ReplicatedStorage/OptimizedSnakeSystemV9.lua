-- Optimized Snake System V11.2 - SKINNED MESH WITH PARALLEL-TRANSPORT FRAMING
-- Stable, NaN-safe bone animation with roll-lock and collision-safe assembly
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
local MESH_ASSET_ID = "rbxassetid://YOUR_MESH_ID" -- Will be replaced with actual asset ID
local BONE_COUNT = 15 -- Should match the number of bones in your Blender model
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
local WAVE_AMPLITUDE = 1.2 -- Side-to-side movement amplitude
local WAVE_FREQUENCY = 2.0 -- How fast the wave travels down the body

-- Growth Constants
local GROWTH_RATE = 0.1 -- How fast the snake grows (units per food)
local SCALE_PER_LENGTH = 0.005 -- How much the scale increases per length unit

-- NEW smoothing/spacing constants for bones
local DEFAULT_BONE_SPACING = 2.5 -- Studs between bones along the spline
local BONE_BLEND_FACTOR = 0.6 -- 0..1 smoothing each frame (higher = snappier)
local CONTROL_POINT_COUNT = 10 -- Control points to build the spline from recent motion

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
    
    print("✅ Skinned Snake created for", self.player.Name)
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
    self.rootPart.CanCollide = true
    self.rootPart.CanQuery = false
    self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function SkinnedSnake:createSkinnedMesh()
    -- Create the model container
    self.model = Instance.new("Model")
    self.model.Name = "SkinnedSnake_" .. self.player.Name
    self.model.Parent = workspace
    
    -- Try to locate a skinned mesh template in ReplicatedStorage
    local templateModel = ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate")
        or ReplicatedStorage:FindFirstChild("slither_snake_rigged")
        or ReplicatedStorage:FindFirstChild("untitledsnakeeeee")

    -- Fallback: look under a Meshes folder or any MeshPart child
    if not templateModel then
        local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
        if meshesFolder then
            templateModel = meshesFolder:FindFirstChildOfClass("MeshPart")
                or meshesFolder:FindFirstChildOfClass("Model")
        end
    end

    -- Final fallback: search any MeshPart directly under ReplicatedStorage
    if not templateModel then
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            if child:IsA("MeshPart") or child:IsA("Model") then
                templateModel = child
                break
            end
        end
    end

    if not templateModel then
        warn("[OptimizedSnakeSystemV9] No skinned mesh template found in ReplicatedStorage. Using fallback part.")
        -- Minimal fallback visual so game continues without errors
        local fallback = Instance.new("Part")
        fallback.Name = "SnakeFallback"
        fallback.Size = Vector3.new(4, 4, 4)
        fallback.Material = Enum.Material.Neon
        fallback.Color = self.config.HeadColor
        fallback.CanCollide = false
        fallback.CanQuery = false
        fallback.Anchored = false
        fallback.Parent = self.model
        self.meshPart = fallback

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = self.meshPart
        weld.Part1 = self.rootPart
        weld.Parent = self.meshPart
        self.meshPart.CFrame = self.rootPart.CFrame

        self.bones = {}
        self:addVisualEffects()
        return
    end

    -- Clone the template
    local cloned
    if templateModel:IsA("MeshPart") then
        cloned = templateModel:Clone()
    elseif templateModel:IsA("Model") then
        cloned = templateModel:Clone()
    else
        warn("[OptimizedSnakeSystemV9] Template found but not a Model/MeshPart. Using fallback part.")
        local fallback = Instance.new("Part")
        fallback.Name = "SnakeFallback"
        fallback.Size = Vector3.new(4, 4, 4)
        fallback.Material = Enum.Material.Neon
        fallback.Color = self.config.HeadColor
        fallback.CanCollide = false
        fallback.CanQuery = false
        fallback.Anchored = false
        fallback.Parent = self.model
        self.meshPart = fallback
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = self.meshPart
        weld.Part1 = self.rootPart
        weld.Parent = self.meshPart
        self.meshPart.CFrame = self.rootPart.CFrame
        self.bones = {}
        self:addVisualEffects()
        return
    end

    -- Adopt cloned asset
    cloned.Name = "SnakeBody"
    cloned.Parent = self.model

    -- Disable collisions on all BaseParts to avoid physics conflicts
    for _, d in ipairs(cloned:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanQuery = false
            d.Massless = true
        end
    end

    -- If it's a model, prefer MeshPart named 'Circle', else first MeshPart
    if cloned:IsA("Model") then
        self.meshPart = cloned:FindFirstChild("Circle")
            or cloned:FindFirstChildOfClass("MeshPart")
    else
        self.meshPart = cloned
    end

    if not self.meshPart then
        warn("[OptimizedSnakeSystemV9] Cloned template does not contain a MeshPart. Using fallback part.")
        local fallback = Instance.new("Part")
        fallback.Name = "SnakeFallback"
        fallback.Size = Vector3.new(4, 4, 4)
        fallback.Material = Enum.Material.Neon
        fallback.Color = self.config.HeadColor
        fallback.CanCollide = false
        fallback.CanQuery = false
        fallback.Anchored = false
        fallback.Parent = self.model
        self.meshPart = fallback
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = self.meshPart
        weld.Part1 = self.rootPart
        weld.Parent = self.meshPart
        self.meshPart.CFrame = self.rootPart.CFrame
        self.bones = {}
        self:addVisualEffects()
        return
    end
    
    -- Set up the mesh properties
    self.meshPart.Anchored = false
    self.meshPart.CanCollide = false
    self.meshPart.CanQuery = true
    self.meshPart.CanTouch = true
    
    -- Apply initial scale
    self.meshPart.Size = self.meshPart.Size * self.scale
    
    -- Set up collision detection
    CollectionService:AddTag(self.meshPart, "SnakeBody")
    self.meshPart:SetAttribute("OwnerName", self.player.Name)
    self.meshPart:SetAttribute("PlayerUserId", self.player.UserId)
    
    -- Find bones: collect all Bone descendants under the mesh; if too few, search whole model
    self.bones = {}
    for _, desc in ipairs(self.meshPart:GetDescendants()) do
        if desc:IsA("Bone") then
            table.insert(self.bones, desc)
        end
    end
    if #self.bones < 2 then
        -- Fallback: search entire cloned model in case bones aren't strictly under selected mesh
        self.bones = {}
        for _, desc in ipairs(cloned:GetDescendants()) do
            if desc:IsA("Bone") then
                table.insert(self.bones, desc)
            end
        end
    end

    -- Numeric-aware sort: Bone, Bone.001, Bone.002, ...
    local function boneOrder(name)
        if name == "Bone" then return 0 end
        local n = name:match("Bone%%.(%d+)") or name:match("Bone[_ ]?(%d+)")
        return tonumber(n) or math.huge
    end
    table.sort(self.bones, function(a, b)
        local oa, ob = boneOrder(a.Name), boneOrder(b.Name)
        if oa ~= ob then return oa < ob end
        return a.Name < b.Name
    end)

    print("Found", #self.bones, "bones in the mesh")

    -- Store original bone transforms and initialize smoothing state
    self.originalBoneTransforms = {}
    self.previousTransforms = {}
    self.boneOffsets = {}
    self.previousUpVectors = {}
    for i, bone in ipairs(self.bones) do
        self.originalBoneTransforms[i] = bone.Transform
        self.boneOffsets[bone] = bone.Transform
        self.previousTransforms[bone] = bone.Transform
        self.previousUpVectors[bone] = Vector3.new(0, 1, 0)
    end
    
    -- Add visual effects
    self:addVisualEffects()
    
    -- Create a WeldConstraint to attach mesh to root part
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = self.meshPart
    weld.Part1 = self.rootPart
    weld.Parent = self.meshPart
    
    -- Position the mesh at the character
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
    
    for i = 1, HISTORY_SIZE do
        self.positionHistory[i] = {
            position = startPos - startLook * (i * 0.5),
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

function SkinnedSnake:getHistoricalData(stepsBack)
    -- Existing helper kept for simple fallback usage
    local targetIndex = ((self.historyIndex - stepsBack - 1) % HISTORY_SIZE) + 1
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

local function isValidVector3(v: Vector3): boolean
    return v and (v.X == v.X) and (v.Y == v.Y) and (v.Z == v.Z)
end

local function safeNormalize(v: Vector3, fallback: Vector3): Vector3
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

local function orthonormalBasis(prevUp: Vector3, tangent: Vector3)
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

local function safeCFrameFromTRU(pos: Vector3, t: Vector3, r: Vector3, u: Vector3)
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

    local meshCFrame = self.meshPart.CFrame

    if CatmullRomSpline then
        -- Build a spline from recent motion for arc-length sampling
        local controlPoints = buildControlPointsFromHistory(self, CONTROL_POINT_COUNT)
        if #controlPoints < 4 then return end

        local spline = CatmullRomSpline.new(controlPoints)
        if not spline then return end
        spline:SetUniform(true)

        -- Determine total spline length
        local splineLength = spline:GetLength()
        if splineLength <= 0 then return end

        -- Total length needed for all bones along body
        local totalBoneLength = math.max(0, (#self.bones - 1) * self.boneSpacing)
        local startOffset = math.max(0, splineLength - totalBoneLength)

        -- Propagate stable frame along the chain
        local chainPrevUp = Vector3.new(0, 1, 0)

        for i, bone in ipairs(self.bones) do
            local distance = startOffset + (i - 1) * self.boneSpacing
            local tParam = math.clamp(distance / splineLength, 0, 1)

            local position = spline:GetPoint(tParam)
            local rawTangent = spline:GetTangent(tParam)

            -- Smooth tangent to reduce sudden flips
            local prevT = self.previousTangents and self.previousTangents[bone] or rawTangent
            local smoothedT = (prevT * 0.6 + rawTangent * 0.4)
            smoothedT = safeNormalize(smoothedT, rawTangent)
            self.previousTangents = self.previousTangents or {}
            self.previousTangents[bone] = smoothedT

            -- Robust orthonormal basis
            local tVec, rVec, uVec = orthonormalBasis(self.previousUpVectors[bone] or chainPrevUp, smoothedT)
            chainPrevUp = uVec
            self.previousUpVectors[bone] = uVec

            local worldCFrame = safeCFrameFromTRU(position, tVec, rVec, uVec)

            -- Subtle wave, clamped
            local wave = math.clamp(math.sin((tick() * WAVE_FREQUENCY) - i * 0.3) * (WAVE_AMPLITUDE * 0.1), -0.2, 0.2)
            worldCFrame = worldCFrame * CFrame.Angles(0, 0, wave)

            -- Convert to mesh-local space
            local relativeTransform = meshCFrame:Inverse() * worldCFrame

            -- Apply initial bone offset from rig
            local initialOffset = self.boneOffsets[bone] or CFrame.new()
            relativeTransform = relativeTransform * initialOffset

            -- Smooth the transform to avoid jitter
            local previous = self.previousTransforms[bone]
            if previous then
                relativeTransform = previous:Lerp(relativeTransform, BONE_BLEND_FACTOR)
            end

            bone.Transform = relativeTransform
            self.previousTransforms[bone] = relativeTransform
        end
        return
    end

    -- Fallback path: sample history by distance without spline module
    local chainPrevUp = Vector3.new(0, 1, 0)
    for i, bone in ipairs(self.bones) do
        local backDistance = (i - 1) * self.boneSpacing
        local sample = getHistoryAtBackDistance(self, backDistance)
        local pos = sample.position
        local rawTangent = sample.direction

        local prevT = self.previousTangents and self.previousTangents[bone] or rawTangent
        local smoothedT = (prevT * 0.6 + rawTangent * 0.4)
        smoothedT = safeNormalize(smoothedT, rawTangent)
        self.previousTangents = self.previousTangents or {}
        self.previousTangents[bone] = smoothedT

        local tVec, rVec, uVec = orthonormalBasis(self.previousUpVectors[bone] or chainPrevUp, smoothedT)
        chainPrevUp = uVec
        self.previousUpVectors[bone] = uVec

        local worldCFrame = safeCFrameFromTRU(pos, tVec, rVec, uVec)
        local wave = math.clamp(math.sin((tick() * WAVE_FREQUENCY) - i * 0.3) * (WAVE_AMPLITUDE * 0.1), -0.2, 0.2)
        worldCFrame = worldCFrame * CFrame.Angles(0, 0, wave)

        local relativeTransform = meshCFrame:Inverse() * worldCFrame
        local initialOffset = self.boneOffsets[bone] or CFrame.new()
        relativeTransform = relativeTransform * initialOffset

        local previous = self.previousTransforms[bone]
        if previous then
            relativeTransform = previous:Lerp(relativeTransform, BONE_BLEND_FACTOR)
        end

        bone.Transform = relativeTransform
        self.previousTransforms[bone] = relativeTransform
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
    if not self.headLight or not self.boostParticles then return end

    -- Cycle through body colors or apply rainbow mode
    if self.rainbowMode then
        local hue = (tick() * 0.5) % 1
        local color = Color3.fromHSV(hue, 1, 1)
        self.headLight.Color = color
        self.boostParticles.Color = ColorSequence.new(color)
        return
    end

    -- Normal color cycling with robust fallbacks
    local colors = self.config and self.config.BodyColors or nil
    local count = (type(colors) == "table") and #colors or 0
    local color
    if count > 0 then
        self.currentColorIndex = (self.currentColorIndex % count) + 1
        color = colors[self.currentColorIndex]
    end
    if typeof(color) ~= "Color3" then
        color = self.config and self.config.HeadColor or Color3.fromRGB(76, 217, 100)
    end

    self.headLight.Color = color
    self.boostParticles.Color = ColorSequence.new(color)
end

function SkinnedSnake:updateLength(newLength)
    self.length = math.clamp(tonumber(newLength) or self.length, MIN_SNAKE_LENGTH, MAX_SNAKE_LENGTH)
end

function SkinnedSnake:updateConfig(newConfig)
    if not newConfig then return end
    if newConfig.HeadColor then
        self.config.HeadColor = newConfig.HeadColor
        if self.headLight then self.headLight.Color = newConfig.HeadColor end
        if self.boostParticles then self.boostParticles.Color = ColorSequence.new(newConfig.HeadColor) end
    end
    if newConfig.BodyColors and typeof(newConfig.BodyColors) == "table" and #newConfig.BodyColors > 0 then
        self.config.BodyColors = newConfig.BodyColors
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
        
        -- Position mesh at root part
        if self.meshPart and self.meshPart.Parent then
            self.meshPart.CFrame = self.rootPart.CFrame
        end
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
    
    print("❌ Skinned Snake destroyed for", self.player.Name)
end

-- Module return
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
    print("[OptimizedSnakeSystemV9] Initialized (Skinned Mesh, Bone-driven)")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
    return SkinnedSnake.new(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
    local snake = SkinnedSnake.new(character, config)
    if savedState and snake then
        if savedState.length then
            snake:updateLength(savedState.length)
        end
    end
    return snake
end

return OptimizedSnakeSystemV9