# Tier 3: Ultimate Skinned Mesh Snake Guide for Roblox

This guide will walk you through creating a professional skinned mesh snake in Blender that can be procedurally animated in Roblox for a completely seamless, gap-free visual.

## Prerequisites
- Blender 3.0 or higher (free from blender.org)
- Basic familiarity with Blender navigation
- Roblox Studio

## Part 1: Creating the Snake Mesh in Blender

### Step 1: Initial Setup
1. Open Blender and delete the default cube (X key → Delete)
2. Press Shift+A → Mesh → UV Sphere to add a sphere
3. Press Tab to enter Edit Mode
4. Press A to select all vertices
5. Press S, then type `0.5` to scale it down to a reasonable size

### Step 2: Creating the Snake Body
1. While in Edit Mode with the sphere selected:
   - Press Shift+D to duplicate
   - Press X to constrain movement to X-axis
   - Type `1` to move it 1 unit
   - Repeat this process 20-30 times to create a chain of spheres

2. Select all spheres (A key)
3. Press Ctrl+J to join them into one mesh
4. Go to Modifier Properties → Add Modifier → Subdivision Surface
5. Set Levels Viewport to 2 for smooth appearance

### Step 3: Refining the Snake Shape
1. In Edit Mode, select all (A key)
2. Press Alt+M → By Distance to merge overlapping vertices
3. Use Proportional Editing (O key) to shape the snake:
   - Make the head slightly larger
   - Taper the tail to be thinner
   - Add slight curves for a natural look

### Step 4: UV Unwrapping (for textures)
1. Select all faces (A in Edit Mode)
2. Press U → Smart UV Project
3. In UV Editor, arrange UVs for optimal texture space

## Part 2: Rigging the Snake with Bones

### Step 1: Creating the Armature
1. Tab to exit Edit Mode
2. Position 3D cursor at snake's head (Shift+Right Click)
3. Press Shift+A → Armature to add bones
4. Tab to enter Edit Mode for the armature

### Step 2: Building the Bone Chain
1. Select the bone tip (sphere at the end)
2. Press E to extrude a new bone
3. Move it along the snake's length (about 1 unit)
4. Repeat to create 20-30 bones following the snake's shape
5. Name bones sequentially: Bone01, Bone02, etc.

### Step 3: Parenting Mesh to Armature
1. Tab to exit Edit Mode
2. Select the snake mesh first, then Shift+select the armature
3. Press Ctrl+P → With Automatic Weights
4. This automatically assigns vertex weights

### Step 4: Testing the Rig
1. Select the armature
2. Switch to Pose Mode (dropdown or Ctrl+Tab)
3. Select and rotate individual bones to test deformation
4. If needed, use Weight Paint mode to refine influence

## Part 3: Exporting for Roblox

### Step 1: Preparing for Export
1. Ensure the snake is at origin (0,0,0)
2. Apply all transforms: Select all → Ctrl+A → All Transforms
3. Set proper scale (1 Blender unit = 1 Roblox stud)

### Step 2: Export Settings
1. File → Export → FBX (.fbx)
2. Use these settings:
   - Scale: 1.0
   - Apply Scalings: FBX All
   - Forward: -Z Forward
   - Up: Y Up
   - Check "Armature" and "Mesh"
   - Uncheck "Add Leaf Bones"

### Step 3: Importing to Roblox
1. In Roblox Studio, go to Avatar tab → Import 3D
2. Select your FBX file
3. In import window:
   - Set to "Custom" rig type
   - Ensure bones are detected
   - Click Import

## Part 4: Procedural Animation Script

Here's the Luau script to animate your skinned mesh snake:

```lua
-- SkinnedMeshSnake.lua
local RunService = game:GetService("RunService")

local SkinnedMeshSnake = {}
SkinnedMeshSnake.__index = SkinnedMeshSnake

function SkinnedMeshSnake.new(meshModel, splineModule)
    local self = setmetatable({}, SkinnedMeshSnake)
    
    self.model = meshModel
    self.meshPart = meshModel:FindFirstChildOfClass("MeshPart")
    self.bones = {}
    
    -- Collect all bones in order
    for i = 1, 30 do
        local bone = self.meshPart:FindFirstChild("Bone" .. string.format("%02d", i))
        if bone then
            table.insert(self.bones, bone)
        end
    end
    
    self.spline = splineModule
    self.boneSpacing = 2 -- Studs between each bone
    
    return self
end

function SkinnedMeshSnake:UpdateBones()
    if not self.spline then return end
    
    local splineLength = self.spline:GetLength()
    
    for i, bone in ipairs(self.bones) do
        -- Calculate position along spline for this bone
        local t = (i - 1) * self.boneSpacing / splineLength
        t = math.clamp(t, 0, 1)
        
        -- Get position and tangent from spline
        local position = self.spline:GetPoint(t)
        local tangent = self.spline:GetTangent(t)
        
        -- Calculate bone transform
        local lookAt = CFrame.lookAt(position, position + tangent)
        
        -- Convert to bone space (relative to mesh origin)
        local meshCFrame = self.meshPart.CFrame
        local relativeTransform = meshCFrame:Inverse() * lookAt
        
        -- Apply to bone
        bone.Transform = relativeTransform
    end
end

function SkinnedMeshSnake:StartAnimation()
    self.connection = RunService.Heartbeat:Connect(function()
        self:UpdateBones()
    end)
end

function SkinnedMeshSnake:StopAnimation()
    if self.connection then
        self.connection:Disconnect()
    end
end

return SkinnedMeshSnake
```

## Part 5: Integration with Your Snake System

To integrate the skinned mesh with your existing snake system:

```lua
-- In OptimizedSnakeSystemV9.lua, add this option:
function Snake.new(character, config)
    -- ... existing code ...
    
    -- Check if using skinned mesh mode
    if config.UseSkinnedMesh then
        -- Load the skinned mesh model
        local meshModel = ReplicatedStorage.SnakeMeshModel:Clone()
        meshModel.Parent = self.model
        
        -- Create skinned mesh controller
        local SkinnedMeshSnake = require(ReplicatedStorage.SkinnedMeshSnake)
        self.skinnedMesh = SkinnedMeshSnake.new(meshModel, self.pathSpline)
        self.skinnedMesh:StartAnimation()
        
        -- Hide part-based segments
        self.useSkinnedMesh = true
    end
end

-- In updateUnifiedBody, add check:
function Snake:updateUnifiedBody()
    if self.useSkinnedMesh and self.skinnedMesh then
        -- Update spline as before
        -- ... spline update code ...
        
        -- Update skinned mesh instead of parts
        self.skinnedMesh.spline = self.pathSpline
        return -- Skip part-based updates
    end
    
    -- ... existing part-based code ...
end
```

## Optimization Tips

### 1. Bone Count
- Use 20-30 bones for a good balance of flexibility and performance
- More bones = smoother deformation but higher CPU cost

### 2. Mesh Complexity
- Keep polygon count under 5000 for optimal performance
- Use Level of Detail (LOD) meshes for distant snakes

### 3. Texture Optimization
- Use 512x512 or 1024x1024 textures
- Use texture atlasing for multiple snake skins

### 4. Animation Optimization
- Update bones every 2-3 frames instead of every frame for distant snakes
- Use simpler interpolation for LOD models

## Troubleshooting

### Common Issues:

1. **Mesh doesn't deform properly**
   - Check weight painting in Blender
   - Ensure bones are properly named and ordered

2. **Performance issues**
   - Reduce bone count
   - Optimize mesh polygon count
   - Implement LOD system

3. **Import errors**
   - Verify FBX export settings
   - Check that armature is properly parented
   - Ensure no duplicate bone names

## Conclusion

This skinned mesh approach provides:
- **Zero gaps** - Single continuous mesh
- **Superior performance** - One draw call vs hundreds
- **Professional quality** - Industry-standard technique
- **Smooth deformation** - Natural, organic movement
- **Easy texturing** - Single UV map for entire snake

The combination of Catmull-Rom splines (Tier 2) with skinned mesh rendering (Tier 3) represents the pinnacle of snake visualization technology in Roblox.