# Fix for Orb-Like Segmented Snake Body

## The Problem
Your snake looks like connected orbs/bubbles instead of a smooth tube because the bone weights in Blender aren't blending properly between bones.

## Visual Diagnosis
- ❌ Current: Each bone creates a distinct "bubble" or "orb"
- ✅ Goal: Smooth, continuous tube with no visible segments

## The Fix: Proper Weight Painting in Blender

### Step 1: Open Your Snake in Blender
1. Open your snake .blend file
2. Select your snake mesh
3. Select your armature
4. Enter Weight Paint mode (Ctrl+Tab → Weight Paint)

### Step 2: Check Current Weights
1. Select each bone one by one
2. You'll likely see sharp color transitions (red to blue)
3. This creates the "orb" effect in Roblox

### Step 3: Fix the Weight Painting

#### Method 1: Automatic Weights (Quick Fix)
1. Exit Weight Paint mode
2. Select mesh, then armature
3. Ctrl+P → "With Automatic Weights"
4. In the popup, set:
   - **Bone Heat Weighting**
   - Check "Normalize All"

#### Method 2: Manual Weight Smoothing (Better Control)
1. In Weight Paint mode
2. Select the Blur brush
3. For each bone transition area:
   - Paint over the harsh edges
   - Blend the weights between bones
   - Each vertex should be influenced by 2-3 bones

### Step 4: Verify Smooth Weights
1. Select a bone in the middle
2. The weight should fade gradually:
   - Red (1.0) at the bone center
   - Orange (0.7) slightly away
   - Yellow (0.5) at the transition
   - Green (0.3) into the next bone
   - Blue (0.0) two bones away

### Step 5: Export Settings
1. File → Export → FBX
2. Important settings:
   - **Smoothing: Face**
   - **Apply Modifiers: ON**
   - **Bake Animation: OFF**
   - **Leaf Bones: OFF**

## Quick Code Adjustment (Temporary)

While you fix the Blender model, you can also try adjusting the bone animation to be more subtle:

```lua
-- In updateBones function, change:
local rotation = CFrame.fromAxisAngle(axis, angle * 0.5)

-- To:
local rotation = CFrame.fromAxisAngle(axis, angle * 0.2) -- Much subtler bending
```

## The Root Cause

The "orb" appearance happens because:
1. Each bone has 100% influence only on nearby vertices
2. No smooth transition between bone influences
3. When bones bend, each section moves independently
4. Creates visible "segments" instead of smooth deformation

## Testing the Fix

1. Re-import your fixed model to Roblox
2. The snake should now bend smoothly
3. No visible segments or orbs
4. Continuous tube appearance

## Alternative: Add More Bones

If weight painting doesn't fix it:
1. Add more bones (20-30 instead of 13)
2. Smaller bone sections = less noticeable segments
3. Re-do automatic weights with more bones

The key is that each vertex needs to be influenced by multiple bones with smooth gradients between them!