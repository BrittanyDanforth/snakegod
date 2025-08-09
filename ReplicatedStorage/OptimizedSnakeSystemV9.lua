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

-- Require spline module for arc-length parameterized posing
local CatmullRomSpline = require(ReplicatedStorage:WaitForChild("CatmullRomSpline"))

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
    -- New: independent control over visual radius (mesh thickness)
    self.config.Radius = self.config.Radius or BASE_SCALE
    
    -- Snake state
    self.length = self.config.InitialLength
    self.scale = BASE_SCALE
    self.radius = self.config.Radius
    self.speed = BASE_SPEED
    self.isBoosting = false
    self.isAlive = true
    
    -- Movement state
    self.positionHistory = {}
    self.historyIndex = 0
    self.wavePhase = 0
    self.targetDirection = self.rootPart.CFrame.LookVector
    
    -- Spline/path state
    self.spline = nil
    self.controlPointCount = 24 -- number of points to build spline from history
    
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
    
    -- Bone metrics
    self.originalBoneTransforms = {}
    self.averageRestBoneSpacing = 1.0
    self.totalRestChainLength = 0
    self.initialMeshSize = nil
    
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

    -- Prefer top-level Model in ReplicatedStorage matching MeshName (your exact project layout)
    local meshName = (self.config and self.config.MeshName) or "untitledsnakeeeee"
    local repoModel = ReplicatedStorage:FindFirstChild(meshName)
    local chosenMeshPart = nil
    local chosenAnimCtrl = nil

    if repoModel and repoModel:IsA("Model") then
        -- Find Circle (MeshPart) and AnimationController in this model
        local circle = repoModel:FindFirstChild("Circle")
        if circle and circle:IsA("BasePart") then
            chosenMeshPart = circle:Clone()
        else
            -- Fallback: find any MeshPart under the model
            for _, desc in ipairs(repoModel:GetDescendants()) do
                if desc:IsA("MeshPart") then
                    chosenMeshPart = desc:Clone()
                    break
                end
            end
        end
        chosenAnimCtrl = repoModel:FindFirstChildOfClass("AnimationController")
        if chosenAnimCtrl then
            chosenAnimCtrl = chosenAnimCtrl:Clone()
        end
    end

    if chosenMeshPart then
        self.meshPart = chosenMeshPart
        self.meshPart.Name = "SnakeBody"
        self.meshPart.Parent = self.model
        if chosenAnimCtrl then
            chosenAnimCtrl.Parent = self.model
        end
    else
        -- Legacy fallback: ReplicatedStorage/Meshes/<meshName>
        local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
        local meshTemplate
        if meshesFolder then
            meshTemplate = meshesFolder:FindFirstChild(meshName)
            if not meshTemplate then
                meshTemplate = meshesFolder:FindFirstChild("SkinnedSnake")
                    or meshesFolder:FindFirstChild("SnakeMesh")
                    or meshesFolder:FindFirstChild("SnakeBody")
            end
        end
        if meshTemplate and meshTemplate:IsA("BasePart") then
            self.meshPart = meshTemplate:Clone()
            self.meshPart.Name = "SnakeBody"
            self.meshPart.Parent = self.model
        else
            warn("[SkinnedSnake] Could not find skinned mesh '" .. meshName .. "' (Model in ReplicatedStorage or item in ReplicatedStorage/Meshes). Using placeholder body.")
            local placeholder = Instance.new("Part")
            placeholder.Name = "SnakeBody_Placeholder"
            placeholder.Size = Vector3.new(4, 4, 10)
            placeholder.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
            placeholder.Material = Enum.Material.SmoothPlastic
            placeholder.TopSurface = Enum.SurfaceType.Smooth
            placeholder.BottomSurface = Enum.SurfaceType.Smooth
            placeholder.Anchored = false
            placeholder.CanCollide = false
            placeholder.Parent = self.model
            self.meshPart = placeholder
            self.bones = {}
            print("[SkinnedSnake] Placeholder body created. Add your model at ReplicatedStorage/" .. meshName .. " with a MeshPart named 'Circle' and an AnimationController to enable bone animation.")
        end
    end

    -- Set up the mesh properties
    self.meshPart.Anchored = true
    self.meshPart.CanCollide = false
    self.meshPart.CanQuery = false
    self.meshPart.CanTouch = false
    if self.meshPart:IsA("BasePart") then
        self.meshPart.Massless = true
    end

    -- Track initial size and apply independent radius
    self.initialMeshSize = self.meshPart.Size
    self:applyRadiusScale(self.radius)

    -- Set up collision detection
    CollectionService:AddTag(self.meshPart, "SnakeBody")
    self.meshPart:SetAttribute("OwnerName", self.player.Name)
    self.meshPart:SetAttribute("PlayerUserId", self.player.UserId)

    -- Find bones
    self.armature = self.model:FindFirstChildOfClass("AnimationController")
    self.bones = {}
    -- Your hierarchy: Circle -> Bone -> Bone.001 -> ... -> Bone.012
    local rootBone = self.meshPart:FindFirstChild("Bone")
    if rootBone and rootBone:IsA("Bone") then
        local currentBone = rootBone
        while currentBone do
            table.insert(self.bones, currentBone)
            currentBone = currentBone:FindFirstChildOfClass("Bone")
        end
    else
        -- Fallback: collect any bones under the mesh part
        local function collectBones(parent)
            for _, child in ipairs(parent:GetDescendants()) do
                if child:IsA("Bone") then
                    table.insert(self.bones, child)
                end
            end
        end
        collectBones(self.meshPart)
        table.sort(self.bones, function(a, b) return a.Name < b.Name end)
    end

    print("Found", self.bones and #self.bones or 0, "bones in the mesh")

    -- Store original bone transforms
    self.originalBoneTransforms = {}
    if self.bones then
        for i, bone in ipairs(self.bones) do
            self.originalBoneTransforms[i] = bone.Transform
        end
    end

    -- Add visual effects
    self:addVisualEffects()

    -- No welds: we anchor the visual mesh and drive CFrame each frame
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

function SkinnedSnake:updateBones(deltaTime)
    if not self.bones or #self.bones == 0 then return end
    
    -- Update wave phase for optional lateral undulation
    self.wavePhase = self.wavePhase + WAVE_FREQUENCY * deltaTime

    -- Ensure spline exists
    if not self.spline then return end

    -- Arc-length aware spacing along the path
    local boneCount = #self.bones
    local splineLength = math.max(self.spline:GetLength(), 0.001)
    local segmentLength = splineLength / (boneCount - 1)

    for i, bone in ipairs(self.bones) do
        local distanceAlong = (i - 1) * segmentLength
        local t = math.clamp(distanceAlong / splineLength, 0, 1)

        -- Sample point and tangent from spline
        local P = self.spline:GetPoint(t)
        local T = self.spline:GetTangent(t)

        -- Optional subtle lateral wave offset, perpendicular to tangent
        local side = T:Cross(Vector3.new(0, 1, 0))
        if side.Magnitude < 1e-3 then
            side = Vector3.new(1, 0, 0)
        else
            side = side.Unit
        end
        local waveOffset = math.sin(self.wavePhase - (i * 0.5)) * (WAVE_AMPLITUDE * 0.25)
        local Pw = P + side * waveOffset

        -- World-space frame aligned to tangent
        local C_world = CFrame.lookAt(Pw, Pw + T)

        -- Convert to MeshPart object space and apply relative to bind pose
        local desiredLocal = self.meshPart.CFrame:ToObjectSpace(C_world)

        -- Per-bone taper radius (0..1 along chain)
        local u = (i - 1) / math.max(1, (boneCount - 1))
        local taper = 0.5 + math.sin(u * math.pi) * 0.5
        local finalRadius = math.max(0.01, self.radius * taper)

        -- Apply final transform: Transform is relative to the bone's bind pose (bone.CFrame)
        bone.Transform = bone.CFrame:Inverse() * desiredLocal
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
    
    -- Decouple radius from length; keep previous radius
    -- Optionally, apply subtle radius growth if desired (disabled by default)
    local keepRadius = self.radius
    self:applyRadiusScale(keepRadius)
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
    -- Cycle through body colors or apply rainbow mode
    local color
    if self.rainbowMode then
        local hue = (tick() * 0.5) % 1
        color = Color3.fromHSV(hue, 1, 1)
    else
        -- Normal color cycling with robust fallback
        local list = (self.config and self.config.BodyColors) or {}
        local count = typeof(list) == "table" and #list or 0
        if count > 0 then
            self.currentColorIndex = (self.currentColorIndex % count) + 1
            local candidate = list[self.currentColorIndex]
            if typeof(candidate) == "Color3" then
                color = candidate
            end
        end
        if not color then
            color = (self.config and self.config.HeadColor) or Color3.fromRGB(76, 217, 100)
        end
    end
    if self.headLight then
        self.headLight.Color = color
    end
    if self.boostParticles then
        self.boostParticles.Color = ColorSequence.new(color)
    end
end

function SkinnedSnake:applyRadiusScale(targetRadius)
    -- Adjust mesh thickness independently by scaling X/Y relative to the template size
    if not self.initialMeshSize then return end
    self.radius = targetRadius
    local newSize = Vector3.new(self.initialMeshSize.X * targetRadius, self.initialMeshSize.Y * targetRadius, self.initialMeshSize.Z)
    self.meshPart.Size = newSize
end

function SkinnedSnake:computeRestBoneMetrics()
    if not self.bones or #self.bones < 2 then
        self.averageRestBoneSpacing = 1.0
        self.totalRestChainLength = 0
        return
    end
    local total = 0
    local count = 0
    for i = 1, (#self.bones - 1) do
        local a = self.originalBoneTransforms[i]
        local b = self.originalBoneTransforms[i + 1]
        if a and b then
            total += (b.Position - a.Position).Magnitude
            count += 1
        end
    end
    if count > 0 then
        self.averageRestBoneSpacing = total / count
        self.totalRestChainLength = total
    end
end

function SkinnedSnake:rebuildSpline()
    -- Build Catmull-Rom spline from recent history positions
    local controlPoints = {}
    local sampleStride = 3 -- history steps between control points
    local desired = self.controlPointCount

    -- Oldest to newest
    for idx = desired, 1, -1 do
        local offset = (idx - 1) * sampleStride
        local h = self:getHistoricalPosition(offset)
        table.insert(controlPoints, 1, h.position)
    end

    -- Ensure minimum 4 points by duplicating endpoints
    if #controlPoints < 4 then
        local first = controlPoints[1] or self.rootPart.Position
        local last = controlPoints[#controlPoints] or self.rootPart.Position
        while #controlPoints < 4 do
            table.insert(controlPoints, 1, first)
        end
        table.insert(controlPoints, last)
    else
        -- Duplicate ends once for better boundary behavior
        table.insert(controlPoints, 1, controlPoints[1])
        table.insert(controlPoints, controlPoints[#controlPoints])
    end

    local spline = CatmullRomSpline.new(controlPoints)
    if spline then
        spline:SetUniform(true)
        self.spline = spline
    end
end

function SkinnedSnake:rebuildSplineIfNeeded()
    if not self.spline then
        self:rebuildSpline()
        return
    end
    -- Periodically refresh to incorporate newest history
    if (self.frameCount % 3) == 0 then
        self:rebuildSpline()
    end
end

function SkinnedSnake:startUpdateLoop()
    self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not self.isAlive then return end
        
        self.frameCount = self.frameCount + 1
        
        -- Update position history
        self:updateHistory()
        
        -- Rebuild spline from history at a throttled cadence
        self:rebuildSplineIfNeeded()
        
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

function SkinnedSnake:setRadius(newRadius)
    -- Public API to control snake girth independently of length
    self:applyRadiusScale(newRadius)
end

function SkinnedSnake:updateLength(newLength)
    if typeof(newLength) == "number" then
        self.length = math.clamp(newLength, MIN_SNAKE_LENGTH, MAX_SNAKE_LENGTH)
    end
end

function SkinnedSnake:updateConfig(newConfig)
    if typeof(newConfig) ~= "table" then return end
    if newConfig.HeadColor then
        self.config.HeadColor = newConfig.HeadColor
        if self.headLight then
            self.headLight.Color = newConfig.HeadColor
        end
        if self.boostParticles then
            self.boostParticles.Color = ColorSequence.new(newConfig.HeadColor)
        end
    end
    if newConfig.BodyColors and #newConfig.BodyColors > 0 then
        self.config.BodyColors = newConfig.BodyColors
    end
    if newConfig.Radius then
        self:setRadius(newConfig.Radius)
    end
end

function SkinnedSnake:getTaperAt(u)
    -- u in [0,1] head->tail; default profile: thin ends, thick middle
    return 0.5 + math.sin(u * math.pi) * 0.5
end

-- Module return
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
    print("✅ OptimizedSnakeSystemV9 initialized (skinned mesh, spline-driven)")
end

function OptimizedSnakeSystemV9.createSnake(character, config)
    return SkinnedSnake.new(character, config)
end

return OptimizedSnakeSystemV9