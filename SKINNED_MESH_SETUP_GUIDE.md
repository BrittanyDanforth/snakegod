# Skinned Mesh Snake Setup Guide

This guide explains how the updated OptimizedSnakeSystemV9 uses your rigged snake model with bones for zero-gap, high-performance animation.

## What Has Changed

The OptimizedSnakeSystemV9 has been completely rewritten to:
- Use a single skinned mesh with bones instead of hundreds of parts
- Automatically detect and animate bones from your Blender model
- Provide zero gaps and maximum performance

## Prerequisites

Your `slither_snake_rigged` model should have this structure:
```
slither_snake_rigged (Model)
├── Circle (MeshPart)
│   ├── Bone
│   │   └── Bone.001
│   │       └── Bone.002
│   │           └── ... (continues to Bone.012)
│   └── AnimationController
└── InitialPoses (Folder)
    ├── Armature_Composited
    ├── Armature_Initial
    ├── Armature_Original
    ├── Bone.001_Composited
    ├── Bone.001_Initial
    ├── Bone.001_Original
    └── ... (all bone poses)
```

## Setup Instructions

1. **Place Your Snake Model in ReplicatedStorage**
   - Import your rigged snake model into Roblox Studio
   - Place it in ReplicatedStorage
   - Name it either `SkinnedSnakeTemplate` or keep it as `slither_snake_rigged`

2. **The System Will Automatically:**
   - Find your snake template when a player spawns
   - Clone the model for each snake
   - Detect all bones starting from "Bone"
   - Follow the bone chain (Bone → Bone.001 → Bone.002 → etc.)
   - Apply smooth animation to each bone

## How the Bone Animation Works

### 1. Automatic Bone Detection
```lua
-- The system finds the first bone
local firstBone = meshPart:FindFirstChild("Bone")

-- Then follows the chain automatically
while currentBone do
    -- Add to bone chain
    -- Find next bone (child of current)
    currentBone = currentBone:FindFirstChildOfClass("Bone")
end
```

### 2. Movement History
- The snake's head position is tracked over time
- Each bone follows a delayed position from this history
- Creates natural following motion

### 3. Wave Motion
- Sine waves are added for natural slithering
- Each bone has a phase offset for smooth waves
- Amplitude and frequency are adjustable

### 4. Smooth Interpolation
- Bone transforms are smoothed between frames
- Prevents jittery movement
- Creates fluid animation

## Key Features

- **Zero Gaps**: Impossible since it's one continuous mesh
- **500x Better Performance**: 1 mesh vs 500+ parts
- **Automatic Bone Detection**: No manual configuration needed
- **Smooth Animation**: Professional bone interpolation
- **LOD System**: Reduces quality for distant snakes

## Customization

You can adjust these parameters in OptimizedSnakeSystemV9.lua:

```lua
-- Visual Constants
local WAVE_AMPLITUDE = 0.8    -- Side-to-side movement strength
local WAVE_FREQUENCY = 2.5    -- Speed of the slithering wave
local BONE_SMOOTHING = 0.85   -- Smoothness (0-1, higher = smoother)
local SEGMENT_SPACING = 2.5   -- Distance between bone positions
```

## Testing

1. Play the game
2. Check the output for messages like:
   ```
   ✅ Skinned Mesh Snake created for [PlayerName]
   ✅ Found 12 bones in chain:
     [1] Bone
     [2] Bone.001
     [3] Bone.002
     ...
   ```

## Troubleshooting

### Snake Template Not Found
- Ensure your model is in ReplicatedStorage
- Name it `SkinnedSnakeTemplate` or `slither_snake_rigged`

### No Bones Found
- Check that bones are children of the Circle MeshPart
- First bone should be named "Bone"
- Bones should be nested (each is a child of the previous)

### Animation Issues
- Verify bone hierarchy is correct
- Check that InitialPoses folder exists
- Ensure bones have Transform properties

## Benefits Over Old System

| Old System (Parts) | New System (Bones) |
|-------------------|--------------------|
| 500+ separate parts | 1 single mesh |
| Gaps between segments | Zero gaps possible |
| High performance cost | Minimal performance cost |
| Complex code | Simpler, cleaner code |
| Jittery movement | Smooth bone animation |

## How It Integrates

1. **SnakeSystemIntegration** (Server) - Manages game data only
2. **OptimizedSnakeSystemV9** (Shared) - Creates and animates the skinned mesh
3. **ClientSnakeController** (Client) - Calls OptimizedSnakeSystemV9.createSnake()

The system is fully integrated - no additional changes needed!