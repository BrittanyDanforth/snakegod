# Complete Blender Snake Mesh Guide - Zero Gaps Forever

This guide will walk you through creating a professional skinned mesh snake that will NEVER have gaps because it's a single continuous mesh.

## Why Skinned Mesh?
- **NO GAPS**: Single mesh = impossible to have gaps
- **Better Performance**: 1 draw call instead of 500+
- **Professional Quality**: Industry standard technique
- **Smooth Deformation**: Natural, organic movement

## Required Software
- Blender 3.0+ (free from blender.org)
- Roblox Studio

## PART 1: Creating the Snake Mesh

### Step 1: Initial Setup
1. Open Blender
2. Delete default cube: Click on it → Press `X` → Click "Delete"
3. Press `Numpad 7` to get top-down view

### Step 2: Create the Snake Body

#### Method A: Simple Cylinder (Recommended for beginners)
1. Press `Shift + A` → Mesh → Cylinder
2. In the bottom left, set:
   - Vertices: 12
   - Radius: 0.5
   - Depth: 30
3. Press `Tab` to enter Edit Mode
4. Press `R` then `X` then `90` to rotate it horizontal
5. Press `Tab` to exit Edit Mode

#### Method B: Sphere Chain (More detailed)
1. Press `Shift + A` → Mesh → UV Sphere
2. In the bottom left, set:
   - Segments: 16
   - Rings: 8
3. Press `Tab` to enter Edit Mode
4. Press `S` then `0.5` to scale down
5. Press `Shift + D` then `X` then `1` to duplicate along X axis
6. Repeat step 5 about 30 times
7. Press `A` to select all
8. Press `M` → By Distance to merge vertices
9. Press `Tab` to exit Edit Mode

### Step 3: Refine the Shape
1. Enter Edit Mode (`Tab`)
2. Enable Proportional Editing: Press `O`
3. Select vertices at the head (front) with Box Select (`B`)
4. Press `S` then `1.2` to make head slightly bigger
5. Select vertices at the tail (back)
6. Press `S` then `0.6` to make tail thinner
7. Exit Edit Mode (`Tab`)

### Step 4: Add Subdivision Surface (Smooth Look)
1. Select the snake mesh
2. Go to Modifier Properties (wrench icon)
3. Add Modifier → Subdivision Surface
4. Set:
   - Levels Viewport: 2
   - Levels Render: 2

## PART 2: Rigging (Adding Bones)

### Step 1: Create the Armature
1. Make sure snake is selected
2. Press `Shift + S` → Cursor to Selected
3. Press `Shift + A` → Armature
4. Enter Edit Mode (`Tab`)

### Step 2: Build the Bone Chain
1. Select the bone
2. Press `G` then `X` to move to snake's head
3. Press `E` then `X` then `1.5` to extrude new bone
4. Repeat step 3 about 20 times (one bone per 1.5 units)
5. Your bone chain should go from head to tail

### Step 3: Name the Bones (IMPORTANT!)
1. Still in Edit Mode
2. Select first bone (at head)
3. In Properties panel (press `N` if hidden)
4. Name it: `Bone01`
5. Select next bone, name it: `Bone02`
6. Continue naming: `Bone03`, `Bone04`, etc.
7. Exit Edit Mode (`Tab`)

### Step 4: Parent Mesh to Armature
1. In Object Mode, select the snake mesh FIRST
2. Hold `Shift` and select the armature SECOND
3. Press `Ctrl + P` → With Automatic Weights
4. You should see "Bone Heat Weighting: Succeeded"

### Step 5: Test the Rig
1. Select only the armature
2. Switch to Pose Mode (dropdown menu or `Ctrl + Tab`)
3. Select any bone and press `R` to rotate
4. The mesh should deform smoothly
5. Press `Alt + R` to reset rotation

## PART 3: Preparing for Export

### Step 1: Apply Transforms
1. Go back to Object Mode
2. Select both mesh and armature
3. Press `Ctrl + A` → All Transforms

### Step 2: Set Proper Scale
1. Select everything (`A`)
2. Press `S` then `0.01` (Roblox uses different scale)
3. Press `Ctrl + A` → Scale

### Step 3: Position at Origin
1. Select everything (`A`)
2. Press `Shift + S` → Selection to Cursor

## PART 4: Exporting

### Step 1: Export Settings
1. File → Export → FBX (.fbx)
2. CRITICAL Settings:
   ```
   ✓ Selected Objects
   ✓ Mesh
   ✓ Armature
   Scale: 1.0
   Apply Scalings: FBX All
   Forward: -Z Forward
   Up: Y Up
   ✗ Add Leaf Bones (UNCHECK THIS!)
   Bake Animation: Off
   ```
3. Name it: `SnakeMesh.fbx`
4. Click "Export FBX"

## PART 5: Importing to Roblox

### Step 1: Import Process
1. Open Roblox Studio
2. Go to Avatar tab → Import 3D
3. Select your `SnakeMesh.fbx`
4. In the import window:
   - Set to "Custom" rig type
   - You should see your bones listed
   - Click "Import"

### Step 2: Setup in Studio
1. The imported model will appear in workspace
2. Move it to ReplicatedStorage
3. Rename it to `SnakeMeshModel`

## PART 6: Scripting the Animation

Create this script to animate your snake:

```lua
-- SkinnedSnakeController.lua
local RunService = game:GetService("RunService")

local SkinnedSnakeController = {}
SkinnedSnakeController.__index = SkinnedSnakeController

function SkinnedSnakeController.new(character, meshModel)
    local self = setmetatable({}, SkinnedSnakeController)
    
    -- Clone the mesh
    self.model = meshModel:Clone()
    self.model.Parent = character
    
    -- Find the mesh part and bones
    self.meshPart = self.model:FindFirstChildOfClass("MeshPart")
    self.bones = {}
    
    -- Collect bones in order
    for i = 1, 50 do
        local bone = self.meshPart:FindFirstChild(string.format("Bone%02d", i))
        if bone then
            table.insert(self.bones, bone)
        else
            break
        end
    end
    
    print("Found " .. #self.bones .. " bones")
    
    -- Store character reference
    self.character = character
    self.rootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Hide the character
    for _, part in pairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= self.rootPart then
            part.Transparency = 1
        end
    end
    
    -- Movement history for smooth following
    self.positionHistory = {}
    self.maxHistory = 100
    
    return self
end

function SkinnedSnakeController:UpdateBones()
    -- Record current position
    table.insert(self.positionHistory, 1, {
        position = self.rootPart.Position,
        lookVector = self.rootPart.CFrame.LookVector
    })
    
    -- Limit history
    if #self.positionHistory > self.maxHistory then
        table.remove(self.positionHistory)
    end
    
    -- Update each bone
    for i, bone in ipairs(self.bones) do
        local historyIndex = i * 2 -- Space between bones
        
        if historyIndex <= #self.positionHistory then
            local histData = self.positionHistory[historyIndex]
            
            -- Calculate world position for this bone
            local worldPos = histData.position
            local worldLook = histData.lookVector
            
            -- Create world CFrame
            local worldCF = CFrame.lookAt(worldPos, worldPos + worldLook)
            
            -- Convert to bone-relative CFrame
            local meshCF = self.meshPart.CFrame
            local relativeCF = meshCF:Inverse() * worldCF
            
            -- Apply to bone with smoothing
            bone.Transform = bone.Transform:Lerp(relativeCF, 0.3)
        end
    end
end

function SkinnedSnakeController:Start()
    self.connection = RunService.Heartbeat:Connect(function()
        self:UpdateBones()
    end)
end

function SkinnedSnakeController:Stop()
    if self.connection then
        self.connection:Disconnect()
    end
end

return SkinnedSnakeController
```

## Integration with Your Game

In your main snake script:

```lua
-- Check if using skinned mesh
local USE_SKINNED_MESH = true -- Set this to control which system to use

if USE_SKINNED_MESH then
    local SkinnedSnakeController = require(ReplicatedStorage.SkinnedSnakeController)
    local meshModel = ReplicatedStorage:WaitForChild("SnakeMeshModel")
    
    -- Create skinned snake instead of parts
    local skinnedSnake = SkinnedSnakeController.new(character, meshModel)
    skinnedSnake:Start()
else
    -- Use your existing part-based system
end
```

## Troubleshooting

### Problem: Mesh doesn't import with bones
- Make sure you named bones correctly (Bone01, Bone02, etc.)
- Ensure "Add Leaf Bones" is UNCHECKED in export
- Try using ASCII FBX format instead

### Problem: Mesh deforms weirdly
- Check bone weights in Blender (Weight Paint mode)
- Make sure bones are inside the mesh
- Reduce subdivision surface levels

### Problem: Performance issues
- Reduce bone count (15-20 is often enough)
- Lower polygon count (use less subdivision)
- Update bones every 2-3 frames instead of every frame

## Advanced Tips

### Adding Textures
1. In Blender, UV unwrap your mesh (`U` → Smart UV Project)
2. Create/apply texture in Shading workspace
3. Bake texture if using nodes
4. Import texture separately to Roblox

### Multiple Skins
1. Create multiple textures
2. Swap TextureID on the MeshPart
3. Can even animate texture offset for flowing effects

### Optimization
- Use LOD (Level of Detail) - update distant snakes less
- Batch bone updates
- Consider bone constraints for more natural movement

## Conclusion

This skinned mesh approach completely eliminates gaps because:
1. It's a single continuous mesh
2. Bones smoothly deform the mesh
3. No separate parts that can drift apart

The result is a professional, performant snake that looks amazing at any length!