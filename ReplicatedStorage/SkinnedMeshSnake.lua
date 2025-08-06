-- SkinnedMeshSnake.lua
-- Procedural animation system for skinned mesh snakes
-- Works with Catmull-Rom splines for seamless, gap-free rendering

local RunService = game:GetService("RunService")

local SkinnedMeshSnake = {}
SkinnedMeshSnake.__index = SkinnedMeshSnake

-- Constants
local BONE_UPDATE_RATE = 1 -- Update bones every frame for smoothness
local MAX_BONES = 50 -- Maximum bones to process
local BONE_BLEND_FACTOR = 0.8 -- Smoothing between bone updates

function SkinnedMeshSnake.new(meshModel, splineModule)
    local self = setmetatable({}, SkinnedMeshSnake)
    
    self.model = meshModel
    self.meshPart = meshModel:FindFirstChildOfClass("MeshPart")
    
    if not self.meshPart then
        warn("SkinnedMeshSnake: No MeshPart found in model")
        return nil
    end
    
    self.bones = {}
    self.previousTransforms = {}
    self.boneOffsets = {}
    
    -- Collect all bones in order
    local function collectBones(parent, prefix)
        for i = 1, MAX_BONES do
            local boneName = prefix .. string.format("%02d", i)
            local bone = parent:FindFirstChild(boneName) or parent:FindFirstChild(prefix .. i)
            
            if bone and bone:IsA("Bone") then
                table.insert(self.bones, bone)
                -- Store initial offset for each bone
                self.boneOffsets[bone] = bone.Transform
                self.previousTransforms[bone] = bone.Transform
            else
                -- Try alternative naming schemes
                bone = parent:FindFirstChild("Bone_" .. i) or parent:FindFirstChild("Joint" .. i)
                if bone and bone:IsA("Bone") then
                    table.insert(self.bones, bone)
                    self.boneOffsets[bone] = bone.Transform
                    self.previousTransforms[bone] = bone.Transform
                else
                    break -- No more bones found
                end
            end
        end
    end
    
    -- Try different bone naming conventions
    collectBones(self.meshPart, "Bone")
    if #self.bones == 0 then
        collectBones(self.meshPart, "Joint")
    end
    
    print(string.format("SkinnedMeshSnake: Found %d bones", #self.bones))
    
    self.spline = splineModule
    self.boneSpacing = 2 -- Studs between each bone
    self.updateCounter = 0
    self.enabled = true
    
    -- LOD settings
    self.lodDistance = 0
    self.lodMode = "HIGH"
    
    return self
end

function SkinnedMeshSnake:SetSpline(spline)
    self.spline = spline
end

function SkinnedMeshSnake:SetBoneSpacing(spacing)
    self.boneSpacing = spacing
end

function SkinnedMeshSnake:SetLOD(distance, camera)
    self.lodDistance = distance
    
    if distance > 200 then
        self.lodMode = "LOW"
    elseif distance > 100 then
        self.lodMode = "MEDIUM"
    else
        self.lodMode = "HIGH"
    end
end

function SkinnedMeshSnake:UpdateBones(deltaTime)
    if not self.enabled or not self.spline or #self.bones == 0 then
        return
    end
    
    -- LOD-based update frequency
    self.updateCounter = self.updateCounter + 1
    local updateFrequency = 1
    
    if self.lodMode == "MEDIUM" then
        updateFrequency = 2
    elseif self.lodMode == "LOW" then
        updateFrequency = 4
    end
    
    if self.updateCounter % updateFrequency ~= 0 then
        return
    end
    
    local splineLength = self.spline:GetLength()
    if splineLength <= 0 then return end
    
    -- Calculate total length needed for all bones
    local totalBoneLength = (#self.bones - 1) * self.boneSpacing
    local startOffset = math.max(0, splineLength - totalBoneLength)
    
    for i, bone in ipairs(self.bones) do
        -- Calculate position along spline for this bone
        local distance = startOffset + (i - 1) * self.boneSpacing
        local t = math.clamp(distance / splineLength, 0, 1)
        
        -- Get position and tangent from spline
        local position = self.spline:GetPoint(t)
        local tangent = self.spline:GetTangent(t)
        
        -- Calculate world space transform for the bone
        local worldCFrame = CFrame.lookAt(position, position + tangent)
        
        -- Add some twist for more natural movement
        local twist = math.sin(t * math.pi * 4 + tick() * 2) * 0.1
        worldCFrame = worldCFrame * CFrame.Angles(0, 0, twist)
        
        -- Convert to bone space (relative to mesh part)
        local meshCFrame = self.meshPart.CFrame
        local relativeTransform = meshCFrame:Inverse() * worldCFrame
        
        -- Apply the initial bone offset
        relativeTransform = relativeTransform * self.boneOffsets[bone]
        
        -- Smooth the transform for less jittery movement
        local previousTransform = self.previousTransforms[bone]
        if previousTransform then
            -- Decompose CFrames for smooth interpolation
            local prevPos = previousTransform.Position
            local newPos = relativeTransform.Position
            local smoothedPos = prevPos:Lerp(newPos, BONE_BLEND_FACTOR)
            
            -- Slerp rotation
            local prevRot = previousTransform - previousTransform.Position
            local newRot = relativeTransform - relativeTransform.Position
            local smoothedRot = prevRot:Lerp(newRot, BONE_BLEND_FACTOR)
            
            relativeTransform = CFrame.new(smoothedPos) * smoothedRot
        end
        
        -- Apply to bone
        bone.Transform = relativeTransform
        self.previousTransforms[bone] = relativeTransform
    end
end

function SkinnedMeshSnake:StartAnimation()
    if self.connection then
        self.connection:Disconnect()
    end
    
    self.connection = RunService.Heartbeat:Connect(function(deltaTime)
        self:UpdateBones(deltaTime)
    end)
end

function SkinnedMeshSnake:StopAnimation()
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

function SkinnedMeshSnake:SetEnabled(enabled)
    self.enabled = enabled
end

function SkinnedMeshSnake:Destroy()
    self:StopAnimation()
    self.bones = {}
    self.previousTransforms = {}
    self.boneOffsets = {}
end

-- Utility function to create a debug visualization
function SkinnedMeshSnake:DebugVisualizeBones()
    local debugFolder = workspace:FindFirstChild("SnakeBoneDebug") or Instance.new("Folder")
    debugFolder.Name = "SnakeBoneDebug"
    debugFolder.Parent = workspace
    
    -- Clear old debug parts
    debugFolder:ClearAllChildren()
    
    for i, bone in ipairs(self.bones) do
        local part = Instance.new("Part")
        part.Name = "BoneDebug_" .. i
        part.Size = Vector3.new(0.5, 0.5, 0.5)
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.new("Bright red")
        part.Anchored = true
        part.CanCollide = false
        part.Parent = debugFolder
        
        -- Update position in heartbeat
        RunService.Heartbeat:Connect(function()
            if bone and bone.Parent then
                part.CFrame = bone.WorldCFrame
            else
                part:Destroy()
            end
        end)
    end
end

return SkinnedMeshSnake