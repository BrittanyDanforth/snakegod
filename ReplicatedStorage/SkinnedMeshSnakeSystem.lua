-- SkinnedMeshSnakeSystem.lua
-- Professional skinned mesh snake system using bone-based animation
-- Automatically detects and animates bones from your Blender-imported snake model

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Constants
local BONE_UPDATE_RATE = 60 -- Hz for smooth bone updates
local WAVE_AMPLITUDE = 0.8 -- Side-to-side movement amplitude
local WAVE_FREQUENCY = 2.5 -- How fast the wave travels down the body
local BONE_SMOOTHING = 0.85 -- Smoothing factor for bone movement (0-1)
local SEGMENT_SPACING = 2.5 -- Distance between bone positions along the path

-- LOD System
local LOD_DISTANCES = {
    HIGH = 100,    -- Full quality
    MEDIUM = 250,  -- Reduced quality
    LOW = 500,     -- Minimal quality
    CULLED = 1000  -- Not rendered
}

local SkinnedMeshSnakeSystem = {}
SkinnedMeshSnakeSystem.__index = SkinnedMeshSnakeSystem

function SkinnedMeshSnakeSystem.new(character, config)
    local self = setmetatable({}, SkinnedMeshSnakeSystem)
    
    -- Core properties
    self.character = character
    self.rootPart = character:WaitForChild("HumanoidRootPart")
    self.humanoid = character:WaitForChild("Humanoid")
    self.player = Players:GetPlayerFromCharacter(character)
    self.config = config or {}
    
    -- State
    self.isAlive = true
    self.length = config.InitialLength or 85
    self.positionHistory = {}
    self.historySize = 500
    self.historyIndex = 0
    self.wavePhase = 0
    
    -- Visual state
    self.lodLevel = "HIGH"
    self.isLocalPlayer = (self.player == Players.LocalPlayer)
    
    -- Performance
    self.frameCount = 0
    self.lastUpdate = tick()
    
    -- Create the skinned mesh snake
    self:createSkinnedMesh()
    
    -- Initialize position history
    self:initializeHistory()
    
    -- Start update loop
    self:startUpdateLoop()
    
    print("✅ Skinned Mesh Snake created for", self.player.Name)
    return self
end

function SkinnedMeshSnakeSystem:createSkinnedMesh()
    -- Get the snake template from ReplicatedStorage
    local templateModel = ReplicatedStorage:WaitForChild("SkinnedSnakeTemplate", 5)
    if not templateModel then
        warn("❌ SkinnedSnakeTemplate not found in ReplicatedStorage!")
        warn("Please ensure your slither_snake_rigged model is in ReplicatedStorage and named 'SkinnedSnakeTemplate'")
        return
    end
    
    -- Clone the template
    self.model = templateModel:Clone()
    self.model.Name = "Snake_" .. self.player.Name
    self.model.Parent = workspace
    
    -- Find the main mesh part (should be named "Circle" based on your screenshots)
    self.meshPart = self.model:FindFirstChild("Circle")
    if not self.meshPart then
        -- Try alternative names
        self.meshPart = self.model:FindFirstChildOfClass("MeshPart")
    end
    
    if not self.meshPart then
        warn("❌ No MeshPart found in snake model!")
        return
    end
    
    -- Setup mesh properties
    self.meshPart.Anchored = false
    self.meshPart.CanCollide = false
    self.meshPart.CanQuery = true
    self.meshPart.CanTouch = true
    
    -- Tag for collision detection
    CollectionService:AddTag(self.meshPart, "SnakeBody")
    self.meshPart:SetAttribute("OwnerName", self.player.Name)
    self.meshPart:SetAttribute("PlayerUserId", self.player.UserId)
    
    -- Find and organize bones
    self:findAndOrganizeBones()
    
    -- Store initial poses
    self:storeInitialPoses()
    
    -- Weld to character
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = self.meshPart
    weld.Part1 = self.rootPart
    weld.Parent = self.meshPart
    
    -- Position at character
    self.meshPart.CFrame = self.rootPart.CFrame
    
    -- Add visual effects
    self:addVisualEffects()
    
    -- Hide original character
    self:hideCharacter()
end

function SkinnedMeshSnakeSystem:findAndOrganizeBones()
    self.bones = {}
    self.boneChain = {}
    
    -- Find the first bone (should be named "Bone" based on your structure)
    local firstBone = self.meshPart:FindFirstChild("Bone")
    if not firstBone then
        warn("❌ No root bone found! Looking for any bone...")
        firstBone = self.meshPart:FindFirstChildOfClass("Bone")
    end
    
    if not firstBone then
        warn("❌ No bones found in the mesh!")
        return
    end
    
    -- Follow the bone chain automatically
    local currentBone = firstBone
    local boneIndex = 1
    
    while currentBone do
        table.insert(self.boneChain, currentBone)
        self.bones[currentBone.Name] = {
            bone = currentBone,
            index = boneIndex,
            originalTransform = currentBone.Transform
        }
        
        -- Find the next bone in the chain (child of current bone)
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

function SkinnedMeshSnakeSystem:storeInitialPoses()
    -- The InitialPoses folder contains the reference poses
    local initialPosesFolder = self.model:FindFirstChild("InitialPoses")
    if not initialPosesFolder then
        warn("⚠️ InitialPoses folder not found, using current transforms")
        return
    end
    
    self.initialPoses = {}
    
    -- Store each bone's initial pose data
    for _, boneData in pairs(self.bones) do
        local bone = boneData.bone
        local boneName = bone.Name
        
        -- Look for pose data in InitialPoses folder
        local composited = initialPosesFolder:FindFirstChild(boneName .. "_Composited")
        local initial = initialPosesFolder:FindFirstChild(boneName .. "_Initial")
        local original = initialPosesFolder:FindFirstChild(boneName .. "_Original")
        
        self.initialPoses[boneName] = {
            composited = composited,
            initial = initial,
            original = original,
            transform = bone.Transform
        }
    end
end

function SkinnedMeshSnakeSystem:hideCharacter()
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
    self.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function SkinnedMeshSnakeSystem:addVisualEffects()
    -- Add glow light
    local light = Instance.new("PointLight")
    light.Brightness = 2
    light.Range = 15
    light.Color = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
    light.Parent = self.meshPart
    
    -- Add particle emitter for boost effect
    self.boostParticles = Instance.new("ParticleEmitter")
    self.boostParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    self.boostParticles.Rate = 0
    self.boostParticles.Lifetime = NumberRange.new(0.5, 1)
    self.boostParticles.Speed = NumberRange.new(5, 10)
    self.boostParticles.SpreadAngle = Vector2.new(15, 15)
    self.boostParticles.Color = ColorSequence.new(light.Color)
    self.boostParticles.LightEmission = 1
    self.boostParticles.Parent = self.meshPart
end

function SkinnedMeshSnakeSystem:initializeHistory()
    local startPos = self.rootPart.Position
    local startDir = self.rootPart.CFrame.LookVector
    
    -- Pre-fill history for smooth start
    for i = 1, self.historySize do
        self.positionHistory[i] = {
            position = startPos - startDir * (i * 0.5),
            direction = startDir,
            time = tick() - (i * 0.016) -- 60fps timing
        }
    end
end

function SkinnedMeshSnakeSystem:updateHistory()
    self.historyIndex = (self.historyIndex % self.historySize) + 1
    
    self.positionHistory[self.historyIndex] = {
        position = self.rootPart.Position,
        direction = self.rootPart.CFrame.LookVector,
        time = tick()
    }
end

function SkinnedMeshSnakeSystem:getHistoricalData(stepsBack)
    local index = ((self.historyIndex - stepsBack - 1) % self.historySize) + 1
    return self.positionHistory[index] or self.positionHistory[self.historyIndex]
end

function SkinnedMeshSnakeSystem:updateBones(deltaTime)
    if not self.boneChain or #self.boneChain == 0 then return end
    
    -- Update wave phase for natural movement
    self.wavePhase = self.wavePhase + WAVE_FREQUENCY * deltaTime
    
    -- Calculate segment spacing based on snake length
    local segmentSpacing = SEGMENT_SPACING * (self.length / 85) -- Scale with length
    local stepsPerBone = math.ceil(segmentSpacing / 0.5) -- History steps per bone
    
    -- Update each bone in the chain
    for i, bone in ipairs(self.boneChain) do
        local boneData = self.bones[bone.Name]
        if not boneData then continue end
        
        -- Get historical position for this bone segment
        local historySteps = (i - 1) * stepsPerBone
        local historicalData = self:getHistoricalData(historySteps)
        
        -- Calculate target position
        local targetPos = historicalData.position
        local targetDir = historicalData.direction
        
        -- Add wave motion for natural slithering
        local waveOffset = math.sin(self.wavePhase - (i * 0.5)) * WAVE_AMPLITUDE
        local perpendicular = targetDir:Cross(Vector3.new(0, 1, 0)).Unit
        local wavePos = targetPos + (perpendicular * waveOffset)
        
        -- Calculate bone transform relative to mesh
        local meshInverse = self.meshPart.CFrame:Inverse()
        local targetCFrame = CFrame.lookAt(wavePos, wavePos + targetDir)
        local relativeCFrame = meshInverse * targetCFrame
        
        -- Add some rotation for more natural movement
        local twist = math.sin(self.wavePhase - (i * 0.3)) * 0.1
        relativeCFrame = relativeCFrame * CFrame.Angles(0, 0, twist)
        
        -- Get the original transform
        local originalTransform = boneData.originalTransform
        
        -- Calculate the final transform
        -- This is the key: we modify the bone's transform relative to its initial pose
        local scale = 1 - ((i - 1) / #self.boneChain) * 0.3 -- Taper toward tail
        local finalTransform = originalTransform * CFrame.new(relativeCFrame.Position * 0.1 * scale)
        
        -- Add rotation influence
        local rotationInfluence = 0.2 -- How much the bone rotates
        finalTransform = finalTransform * CFrame.Angles(
            math.rad(waveOffset * rotationInfluence * 10),
            math.rad(twist * 30),
            0
        )
        
        -- Smooth the transform
        if self.previousTransforms and self.previousTransforms[bone.Name] then
            local prevTransform = self.previousTransforms[bone.Name]
            -- Decompose for smooth interpolation
            local prevPos = prevTransform.Position
            local newPos = finalTransform.Position
            local smoothPos = prevPos:Lerp(newPos, 1 - BONE_SMOOTHING)
            
            -- Smooth rotation
            local prevRot = prevTransform - prevTransform.Position
            local newRot = finalTransform - finalTransform.Position
            local smoothRot = prevRot:Lerp(newRot, 1 - BONE_SMOOTHING)
            
            finalTransform = CFrame.new(smoothPos) * smoothRot
        end
        
        -- Apply the transform
        bone.Transform = finalTransform
        
        -- Store for next frame
        self.previousTransforms = self.previousTransforms or {}
        self.previousTransforms[bone.Name] = finalTransform
    end
end

function SkinnedMeshSnakeSystem:updateLOD()
    if not workspace.CurrentCamera then return end
    
    local camera = workspace.CurrentCamera
    local distance = (camera.CFrame.Position - self.meshPart.Position).Magnitude
    
    local newLOD = "CULLED"
    for lodName, maxDist in pairs({"HIGH", "MEDIUM", "LOW"}) do
        if distance < LOD_DISTANCES[lodName] then
            newLOD = lodName
            break
        end
    end
    
    if newLOD ~= self.lodLevel then
        self.lodLevel = newLOD
        self:applyLODSettings()
    end
end

function SkinnedMeshSnakeSystem:applyLODSettings()
    if self.lodLevel == "CULLED" then
        self.model.Parent = nil
    else
        self.model.Parent = workspace
        
        -- Adjust update frequency based on LOD
        if self.lodLevel == "LOW" then
            self.updateFrequency = 4 -- Update every 4 frames
        elseif self.lodLevel == "MEDIUM" then
            self.updateFrequency = 2 -- Update every 2 frames
        else
            self.updateFrequency = 1 -- Update every frame
        end
    end
end

function SkinnedMeshSnakeSystem:startUpdateLoop()
    self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not self.isAlive then return end
        
        self.frameCount = self.frameCount + 1
        
        -- Update history
        self:updateHistory()
        
        -- Update bones based on LOD frequency
        if self.frameCount % (self.updateFrequency or 1) == 0 then
            self:updateBones(deltaTime)
        end
        
        -- Update LOD every 10 frames
        if self.frameCount % 10 == 0 then
            self:updateLOD()
        end
        
        -- Keep mesh attached to character
        if self.meshPart and self.meshPart.Parent then
            self.meshPart.CFrame = self.rootPart.CFrame
        end
    end)
end

function SkinnedMeshSnakeSystem:setBoost(boosting)
    if self.boostParticles then
        self.boostParticles.Rate = boosting and 100 or 0
    end
end

function SkinnedMeshSnakeSystem:grow(amount)
    self.length = self.length + amount
    -- Could add scaling animation here if needed
end

function SkinnedMeshSnakeSystem:destroy()
    self.isAlive = false
    
    if self.updateConnection then
        self.updateConnection:Disconnect()
    end
    
    if self.model then
        self.model:Destroy()
    end
end

-- Static method to initialize the system
function SkinnedMeshSnakeSystem.init()
    print("✅ SkinnedMeshSnakeSystem initialized")
end

-- Static method to create a snake
function SkinnedMeshSnakeSystem.createSnake(character, config)
    return SkinnedMeshSnakeSystem.new(character, config)
end

return SkinnedMeshSnakeSystem