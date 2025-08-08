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

-- Optional Catmull-Rom Spline for stabilized turning
local CatmullRomSpline
local HAS_SPLINE = false
local okSpline, resSpline = pcall(function()
	return require(ReplicatedStorage:WaitForChild("CatmullRomSpline", 2))
end)
if okSpline and resSpline then
	CatmullRomSpline = resSpline
	HAS_SPLINE = true
end

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

    -- Spline state (optional)
    self.splineAvailable = HAS_SPLINE
    self.spline = nil
    self.splineDirty = false
    self.lastSplineBuildTick = 0
    self.splineBuildInterval = 0.05 -- seconds
    
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
    
    -- Try to load the skinned mesh from ReplicatedStorage
    local meshTemplate
    local meshesFolder = ReplicatedStorage:FindFirstChild("Meshes")
    if meshesFolder then
        meshTemplate = meshesFolder:FindFirstChild("untitledsnakeeeee")
    end
    
    if meshTemplate then
        -- Skinned mesh path
        self.meshPart = meshTemplate:Clone()
        self.meshPart.Name = "SnakeBody"
        self.meshPart.Parent = self.model
        
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
        
        -- Find the armature and bones
        self.armature = self.meshPart:FindFirstChildOfClass("Humanoid") or self.meshPart:FindFirstChildOfClass("AnimationController")
        if not self.armature then
            -- Look for bones directly
            self.bones = {}
            local function findBones(parent)
                for _, child in pairs(parent:GetChildren()) do
                    if child:IsA("Bone") then
                        table.insert(self.bones, child)
                    elseif child:IsA("Model") or child:IsA("Folder") then
                        findBones(child)
                    end
                end
            end
            findBones(self.meshPart)
            
            -- Sort bones by name or position
            table.sort(self.bones, function(a, b)
                return a.Name < b.Name
            end)
        else
            -- Get bones from armature
            self.bones = {}
            local rootBone = self.armature:FindFirstChild("Bone")
            if rootBone then
                local currentBone = rootBone
                while currentBone do
                    table.insert(self.bones, currentBone)
                    currentBone = currentBone:FindFirstChildOfClass("Bone")
                end
            end
        end
        
        print("Found", #self.bones, "bones in the mesh")
        
        -- Store original bone transforms
        self.originalBoneTransforms = {}
        for i, bone in ipairs(self.bones) do
            self.originalBoneTransforms[i] = bone.Transform
        end
        
        -- Create a WeldConstraint to attach mesh to root part
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = self.meshPart
        weld.Part1 = self.rootPart
        weld.Parent = self.meshPart
        
        -- Position the mesh at the character
        self.meshPart.CFrame = self.rootPart.CFrame
        
        -- Not using fallback
        self.isFallbackSegments = false
    else
        -- Fallback path: create visible segmented body so the player always sees a snake
        self.isFallbackSegments = true
        self.segmentParts = {}
        self.segmentCount = 28
        
        for i = 1, self.segmentCount do
            local seg = Instance.new("Part")
            seg.Name = string.format("SnakeSeg_%02d", i)
            seg.Shape = Enum.PartType.Ball
            -- Size: head uses HeadSize if provided, body uses SegmentSize or scaled head
            local headSize = (self.config.HeadSize and Vector3.new(self.config.HeadSize.X, self.config.HeadSize.Y, self.config.HeadSize.Z)) or Vector3.new(3, 3, 3)
            local bodySize = (self.config.SegmentSize and Vector3.new(self.config.SegmentSize.X, self.config.SegmentSize.Y, self.config.SegmentSize.Z)) or (headSize * 0.6)
            seg.Size = (i == 1) and (headSize) or (bodySize)
            seg.Material = Enum.Material.Neon
            -- Color: head uses HeadColor, body uses first body color
            local headColor = (self.config.HeadColor and typeof(self.config.HeadColor) == "Color3") and self.config.HeadColor or Color3.fromRGB(255, 255, 0)
            local bodyColor = (self.config.BodyColors and typeof(self.config.BodyColors[1]) == "Color3") and self.config.BodyColors[1] or Color3.fromRGB(76, 217, 100)
            seg.Color = (i == 1) and headColor or bodyColor
            seg.Anchored = true
            seg.CanCollide = false
            seg.CanQuery = false
            seg.CanTouch = false
            seg.Parent = self.model
            self.segmentParts[i] = seg
            if i == 1 then
                self.meshPart = seg -- Use head segment as the reference for lights/LOD
            end
        end
        
        self.bones = {}
        self.originalBoneTransforms = {}
        print("[Snake] Using fallback segmented body (no skinned mesh found)")

        -- Immediately position segments so the player sees the body before first heartbeat
        self:rebuildSpline()
        local useSpline = (self.splineAvailable and self.spline ~= nil)
        local count = #self.segmentParts
        for i = 1, count do
            local targetPos, targetLook
            if useSpline then
                local t = count > 1 and math.max(0, 1 - (i - 1) / (count - 1)) or 1
                local pos = self.spline:GetPoint(t)
                local tan = self.spline:GetTangent(t)
                targetPos = pos
                targetLook = tan
            else
                local segmentOffset = (i - 1) * math.max(1, self.length / count)
                local historicalData = self:getHistoricalPosition(segmentOffset)
                targetPos = historicalData.position
                targetLook = historicalData.lookVector
            end
            if targetLook.Magnitude < 1e-6 then
                targetLook = Vector3.new(0, 0, -1)
            end
            self.segmentParts[i].CFrame = CFrame.lookAt(targetPos, targetPos + targetLook)
        end

        -- Ensure selection box is visible on fallback head (local player only)
        if self.isLocalPlayer and self.meshPart then
            if not self.selectionBox then
                self.selectionBox = Instance.new("SelectionBox")
                self.selectionBox.Adornee = self.meshPart
                self.selectionBox.Color3 = headColor
                self.selectionBox.LineThickness = 0.1
                self.selectionBox.Transparency = 0.5
                self.selectionBox.Parent = self.meshPart
            else
                self.selectionBox.Adornee = self.meshPart
                self.selectionBox.Color3 = headColor
                self.selectionBox.LineThickness = 0.1
                self.selectionBox.Transparency = 0.5
            end
        end
    end
    
    -- Add visual effects (attach to self.meshPart, which is head in both cases)
    self:addVisualEffects()
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
    -- Mark spline dirty so the first build samples from initialized history
    self.splineDirty = true
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
    -- Defer spline rebuild to avoid per-frame allocations
    self.splineDirty = true
end

function SkinnedSnake:getHistoricalPosition(segmentsBack)
    -- Get position from history for smooth following
    local targetIndex = ((self.historyIndex - segmentsBack - 1) % HISTORY_SIZE) + 1
    return self.positionHistory[targetIndex] or self.positionHistory[self.historyIndex]
end

function SkinnedSnake:rebuildSpline()
    if not self.splineAvailable then return end
    -- Build control points from recent history (coarsened)
    local controlPoints = {}
    local stride = 4 -- take every Nth history sample
    local maxPoints = 24
    local added = 0
    for offset = 0, (HISTORY_SIZE - 1), stride do
        local idx = ((self.historyIndex - offset - 1) % HISTORY_SIZE) + 1
        local entry = self.positionHistory[idx]
        if entry then
            table.insert(controlPoints, 1, entry.position)
            added += 1
            if added >= maxPoints then break end
        end
    end
    if #controlPoints < 4 then
        self.spline = nil
        self.splineDirty = false
        self.lastSplineBuildTick = tick()
        return
    end
    local ok, splineOrErr = pcall(function()
        local s = CatmullRomSpline.new(controlPoints, { tension = 0.1, uniform = true })
        s:SetUniform(true)
        return s
    end)
    if ok then
        self.spline = splineOrErr
    else
        warn("Spline build failed:", splineOrErr)
        self.spline = nil
    end
    self.splineDirty = false
    self.lastSplineBuildTick = tick()
end

function SkinnedSnake:updateBones(deltaTime)
    if not self.bones or #self.bones == 0 then
        -- Fallback segmented body update using spline/history
        -- Update wave phase for natural movement
        self.wavePhase = self.wavePhase + WAVE_FREQUENCY * deltaTime
        
        -- Rebuild spline lazily when new history arrives
        if self.splineAvailable and self.splineDirty and (tick() - self.lastSplineBuildTick) >= self.splineBuildInterval then
            self:rebuildSpline()
        end
        local useSpline = (self.splineAvailable and self.spline ~= nil)
        
        if not self.segmentParts or #self.segmentParts == 0 then return end
        local count = #self.segmentParts
        for i = 1, count do
            local targetPos, targetLook
            if useSpline then
                local t = count > 1 and math.max(0, 1 - (i - 1) / (count - 1)) or 1
                local pos = self.spline:GetPoint(t)
                local tan = self.spline:GetTangent(t)
                targetPos = pos
                targetLook = tan
            else
                local segmentOffset = (i - 1) * math.max(1, self.length / count)
                local historicalData = self:getHistoricalPosition(segmentOffset)
                targetPos = historicalData.position
                targetLook = historicalData.lookVector
            end
            
            local waveOffset = math.sin(self.wavePhase - (i * 0.5)) * WAVE_AMPLITUDE
            local up = Vector3.new(0, 1, 0)
            local perpendicular = targetLook:Cross(up)
            if perpendicular.Magnitude > 1e-6 then
                perpendicular = perpendicular.Unit
            else
                perpendicular = Vector3.new(1, 0, 0)
            end
            local wavePosition = targetPos + perpendicular * waveOffset
            
            local part = self.segmentParts[i]
            if part and part.Parent then
                part.CFrame = CFrame.lookAt(wavePosition, wavePosition + targetLook)
                -- Optional taper
                local lerpAlpha = (i - 1) / math.max(1, count - 1)
                local scale = 1 - lerpAlpha * 0.4
                part.Size = Vector3.new(1.2, 1.2, 1.2) * self.scale * scale
            end
        end
        return
    end
    
    -- Original bone-driven path replaced with robust CFrame-based posing
    
    -- Update wave phase for natural movement
    self.wavePhase = self.wavePhase + WAVE_FREQUENCY * deltaTime

    -- Rebuild spline lazily when new history arrives
    if self.splineAvailable and self.splineDirty and (tick() - self.lastSplineBuildTick) >= self.splineBuildInterval then
        self:rebuildSpline()
    end
    local useSpline = (self.splineAvailable and self.spline ~= nil)
    
    local boneCount = #self.bones
    if boneCount == 0 then return end

    -- For spline sampling: use arc-length-uniform t across bones (head at t=1)
    for i, bone in ipairs(self.bones) do
        local targetPos, targetTan
        if useSpline then
            local t = (boneCount > 1) and math.max(0, 1 - (i - 1) / (boneCount - 1)) or 1
            targetPos = self.spline:GetPoint(t)
            targetTan = self.spline:GetTangent(t)
        else
            -- History fallback orientation from neighbors
            local segmentOffset = (i - 1) * math.max(1, self.length / boneCount)
            local curr = self:getHistoricalPosition(segmentOffset)
            local nextH = self:getHistoricalPosition(segmentOffset - 1)
            local prevH = self:getHistoricalPosition(segmentOffset + 1)
            targetPos = curr.position
            local dir = (nextH.position - prevH.position)
            if dir.Magnitude < 1e-6 then dir = curr.lookVector end
            targetTan = dir.Unit
        end

        -- Build a stable frame: compute a consistent up to avoid roll issues
        local worldUp = Vector3.new(0, 1, 0)
        local forward = targetTan.Magnitude > 1e-6 and targetTan.Unit or Vector3.new(0, 0, -1)
        local right = forward:Cross(worldUp)
        if right.Magnitude < 1e-6 then
            -- Forward is near-parallel to world up; choose another up
            worldUp = Vector3.new(1, 0, 0)
            right = forward:Cross(worldUp)
        end
        right = right.Unit
        local up = right:Cross(forward).Unit

        -- Wave offset laterally along right vector for natural slither
        local waveOffset = math.sin(self.wavePhase - (i * 0.5)) * WAVE_AMPLITUDE
        local wavePosition = targetPos + right * waveOffset

        -- World CFrame aligned to the path
        local worldCFrame = CFrame.lookAt(wavePosition, wavePosition + forward, up)

        -- Convert to mesh local space and apply to bone
        local localCFrame = self.meshPart.CFrame:ToObjectSpace(worldCFrame)
        bone.Transform = localCFrame
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
        if self.isFallbackSegments and self.segmentParts then
            for _, p in ipairs(self.segmentParts) do
                p.Parent = nil
            end
        elseif self.meshPart then
            self.meshPart.Parent = nil
        end
    else
        if self.isFallbackSegments and self.segmentParts then
            for _, p in ipairs(self.segmentParts) do
                p.Parent = self.model
            end
        elseif self.meshPart then
            self.meshPart.Parent = self.model
        end
        
        -- Adjust quality based on LOD
        if self.lodLevel == "HIGH" then
            if self.headLight then self.headLight.Enabled = true end
            if self.surfaceLight then self.surfaceLight.Enabled = true end
            if self.boostParticles then self.boostParticles.Enabled = self.isBoosting end
        elseif self.lodLevel == "MEDIUM" then
            if self.headLight then self.headLight.Enabled = true end
            if self.surfaceLight then self.surfaceLight.Enabled = false end
            if self.boostParticles then self.boostParticles.Enabled = false end
        else -- LOW
            if self.headLight then self.headLight.Enabled = false end
            if self.surfaceLight then self.surfaceLight.Enabled = false end
            if self.boostParticles then self.boostParticles.Enabled = false end
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
    -- Cycle through body colors or apply rainbow mode
    if self.rainbowMode then
        local hue = (tick() * 0.5) % 1
        local color = Color3.fromHSV(hue, 1, 1)
        if self.headLight then self.headLight.Color = color end
        if self.boostParticles then self.boostParticles.Color = ColorSequence.new(color) end
        return
    end

    -- Build a safe palette
    local palette = {}
    if self.config and self.config.BodyColors then
        for _, c in ipairs(self.config.BodyColors) do
            if typeof(c) == "Color3" then
                table.insert(palette, c)
            end
        end
    end
    if #palette == 0 then
        local fallback = (self.config and typeof(self.config.HeadColor) == "Color3") and self.config.HeadColor or Color3.fromRGB(76, 217, 100)
        palette = { fallback }
        self.currentColorIndex = 1
    end

    -- Advance index and apply
    self.currentColorIndex = (self.currentColorIndex % #palette) + 1
    local color = palette[self.currentColorIndex]
    if self.headLight then self.headLight.Color = color end
    if self.boostParticles then self.boostParticles.Color = ColorSequence.new(color) end
end

-- Minimal update methods to satisfy client optional calls
function SkinnedSnake:updateConfig(newConfig)
    if not newConfig then return end
    if newConfig.HeadColor and typeof(newConfig.HeadColor) == "Color3" then
        self.config.HeadColor = newConfig.HeadColor
        if self.headLight then self.headLight.Color = newConfig.HeadColor end
        if self.boostParticles then self.boostParticles.Color = ColorSequence.new(newConfig.HeadColor) end
    end
    if newConfig.BodyColors and #newConfig.BodyColors > 0 then
        local sanitized = {}
        for _, c in ipairs(newConfig.BodyColors) do
            if typeof(c) == "Color3" then
                table.insert(sanitized, c)
            end
        end
        if #sanitized > 0 then
            self.config.BodyColors = sanitized
            self.currentColorIndex = 0 -- reset cycle to start of new palette
        end
    end
end

function SkinnedSnake:updateLength(newLength)
    if typeof(newLength) == "number" then
        self.length = math.clamp(newLength, MIN_SNAKE_LENGTH, MAX_SNAKE_LENGTH)
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
        if self.meshPart and self.meshPart.Parent and not self.isFallbackSegments then
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

-- Public module API expected by client
local Module = {}

function Module.init()
    -- Reserved for future initialization
end

function Module.createSnake(character, config)
    return SkinnedSnake.new(character, config)
end

return Module