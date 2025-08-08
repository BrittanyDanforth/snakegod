# Skinned Mesh Animation Fix

## The Problem: WorldCFrame vs Transform

### What We Were Doing Wrong
```lua
bone.WorldCFrame = bone.WorldCFrame:Lerp(targetCFrame, interpSpeed)
```
- This moves bones to specific world positions
- BREAKS the skinned mesh deformation
- Makes the snake look disconnected and ugly

### Why It Looked Bad
1. **Skinned meshes** work by having vertices weighted to bones
2. When you move bones with `WorldCFrame`, you're teleporting them
3. This breaks the parent-child relationships
4. The mesh gets stretched and torn apart

## The Solution: Use Transform Property

### What Transform Does
```lua
bone.Transform = bone.Transform:Lerp(bentTransform, SMOOTHING)
```
- `Transform` is RELATIVE to the parent bone
- Maintains the bone chain integrity
- Preserves the smooth mesh deformation from Blender

### The New Approach
Instead of positioning each bone at a world location, we:
1. **Detect turning** - How much is the snake turning?
2. **Bend bones** - Each bone bends a little based on the turn
3. **Cascade effect** - Each bone bends less than the previous
4. **Smooth result** - The mesh deforms naturally

## Key Differences

### Old (Broken) Method
- Tried to place each bone at historical positions
- Used `WorldCFrame` (absolute positioning)
- Result: Disconnected, ugly segments

### New (Correct) Method
- Bends bones based on movement direction
- Uses `Transform` (relative positioning)
- Result: Smooth, continuous deformation

## How It Works Now

```lua
-- 1. Detect how much we're turning
local turnAmount = 1 - currentDir:Dot(previousDir)

-- 2. Each bone bends proportionally
local bendFactor = (1 - (i / #self.boneChain)) * BEND_STRENGTH

-- 3. Apply the bend as a rotation
bentTransform = bentTransform * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), bendAngle)

-- 4. Smooth interpolation
bone.Transform = bone.Transform:Lerp(bentTransform, SMOOTHING)
```

## Tuning Parameters

### BEND_STRENGTH (0.3)
- How much bones can bend
- Higher = more extreme curves
- Lower = stiffer snake

### SMOOTHING (0.15)
- How quickly bones respond
- Higher = snappier movement
- Lower = more delayed, smooth

## The Result

Your snake should now:
- ✅ Look like one continuous mesh (like in Blender)
- ✅ Bend smoothly when turning
- ✅ Maintain proper deformation
- ✅ Have subtle organic motion

## If It Still Looks Wrong

1. **Check bone weights in Blender**
   - Each vertex should be weighted to nearby bones
   - No vertices should be unweighted

2. **Verify bone hierarchy**
   - Bones must be parented correctly
   - Each bone should be child of the previous

3. **Adjust parameters**
   ```lua
   BEND_STRENGTH = 0.5  -- Try different values
   SMOOTHING = 0.2      -- Experiment with responsiveness
   ```

4. **Add more bones in Blender**
   - 13 bones might not be enough
   - Try 20-30 bones for smoother curves

## The Core Lesson

**Skinned meshes are NOT like part-based snakes!**
- Don't position bones in world space
- Work with relative transforms
- Let the mesh deformation do the work
- Think "bending" not "positioning"