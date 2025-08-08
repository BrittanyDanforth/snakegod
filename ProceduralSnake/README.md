# High-Fidelity Procedural Snake System for Roblox

A sophisticated procedural animation system for creating smooth, stable snake-like creatures in Roblox, featuring advanced spline-based path generation, IK-driven body articulation, and optimized multiplayer support.

## Features

- **Smooth Path Generation**: Catmull-Rom splines with unit-speed parametrization ensure fluid, natural movement
- **Stable Orientation**: Advanced CFrame calculations prevent gimbal lock and rolling artifacts
- **Native IK Integration**: Leverages Roblox's IKControl for efficient, constraint-aware body articulation
- **Frame-Rate Independence**: All animations and interpolations scale correctly across different frame rates
- **LOD System**: Automatic level-of-detail adjustments based on distance for optimal performance
- **Multiplayer Ready**: Efficient client-server architecture minimizes bandwidth while maximizing visual quality
- **Modular Design**: Clean separation of concerns for easy customization and extension

## Architecture Overview

### Core Components

1. **CatmullRomSpline Module** (`Shared/CatmullRomSpline.lua`)
   - Generates smooth curves through control points
   - Implements unit-speed parametrization for consistent segment spacing
   - Handles both Vector3 and CFrame control points

2. **CFrameUtils Module** (`Shared/CFrameUtils.lua`)
   - Provides stable CFrame construction to prevent gimbal lock
   - Frame-rate independent damping functions
   - Advanced quaternion interpolation utilities

3. **SnakeController** (`Client/SnakeController.lua`)
   - Manages head tracking and history
   - Updates spline control points
   - Drives IK chain for body articulation
   - Implements LOD for performance optimization

4. **SnakeReplication** (`Server/SnakeReplication.lua`)
   - Server-authoritative head position validation
   - Efficient state broadcasting to clients
   - Anti-cheat protection

5. **SnakeNetworkHandler** (`Client/SnakeNetworkHandler.lua`)
   - Handles client-server communication
   - Interpolates remote snake positions
   - Predictive movement for lag compensation

## Setup Instructions

### 1. Preparing Your Snake Model

Your snake model must be a properly rigged SkinnedMesh:

1. **In Blender (or your 3D software):**
   - Create a snake mesh as a single continuous object
   - Add an armature with bones named sequentially: `Bone_1`, `Bone_2`, etc.
   - Apply weights so each mesh section is influenced by its corresponding bone
   - Export as `.fbx`

2. **In Roblox Studio:**
   - Use the Avatar Importer to import your `.fbx` file
   - Rename the imported MeshPart to `SnakeMeshPart`
   - Ensure bones are properly parented under the MeshPart

### 2. Project Structure

```
YourGame/
├── ServerScriptService/
│   └── ProceduralSnake/
│       ├── ServerInit.lua
│       └── SnakeReplication.lua
├── StarterPlayer/
│   └── StarterPlayerScripts/
│       └── ProceduralSnake/
│           ├── ClientInit.lua
│           ├── SnakeController.lua
│           └── SnakeNetworkHandler.lua
└── ReplicatedStorage/
    └── Shared/
        ├── CatmullRomSpline.lua
        └── CFrameUtils.lua
```

### 3. Installation

1. Copy all files to their respective locations in your Roblox Studio project
2. Ensure the `SnakeMeshPart` is part of your character model
3. The system will automatically initialize when players join

### 4. Configuration

The `SnakeController` accepts a configuration table:

```lua
local config = {
    segmentCount = 20,        -- Number of bones in your snake
    segmentLength = 0.5,      -- Distance between segments
    historySize = 30,         -- Number of head positions to track
    smoothingFactor = 0.85,   -- Smoothing (0-1, higher = smoother)
    splineAlpha = 0.5,        -- Spline tension (0.5 = centripetal)
    splineTension = 0,        -- Additional spline tension
    updateRate = 60,          -- Updates per second
    lodDistances = {
        near = 50,            -- Full quality distance
        medium = 100,         -- Reduced quality distance
        far = 200            -- Minimal quality distance
    }
}
```

## Troubleshooting

### Common Issues

1. **"SnakeMeshPart not found in character"**
   - Ensure your character model contains a MeshPart named exactly `SnakeMeshPart`
   - Check that the MeshPart is a direct child of the character model

2. **"No bones found in snake mesh"**
   - Verify bones are named `Bone_1`, `Bone_2`, etc.
   - Ensure bones are descendants of the SnakeMeshPart

3. **Snake body appears stiff or doesn't follow smoothly**
   - Increase `historySize` for longer, smoother trails
   - Adjust `smoothingFactor` (higher = smoother but more lag)
   - Check that IKControl instances are being created properly

4. **Segments rotating or "flipping"**
   - This indicates the stable CFrame calculation isn't being used
   - Verify CFrameUtils module is loaded correctly
   - Check that IK targets are using stable orientations

### Performance Optimization

- Adjust LOD distances based on your game's needs
- Reduce `segmentCount` for better performance
- Lower `updateRate` for distant snakes
- Consider disabling shadows on SkinnedMeshes for mobile

## Advanced Customization

### Adding Secondary Motion

For subtle idle animations, add Perlin noise to bone transforms:

```lua
local time = tick()
local noiseOffset = math.noise(time * 0.5, i * 0.1) * 0.1
bone.Transform = bone.Transform * CFrame.Angles(0, 0, noiseOffset)
```

### Physics Integration

To add physics reactions while maintaining smooth movement:

1. Create a parallel Verlet integration system
2. Use the spline as a "goal" path
3. Apply forces to pull the physics simulation toward the spline
4. Blend between kinematic and physics results based on external forces

### Custom Movement Patterns

Modify the head tracking logic to create different movement styles:
- Sine wave patterns for swimming
- Spiral patterns for burrowing
- Quick darting movements for predator behavior

## Credits

This system implements advanced techniques from procedural animation research, adapted specifically for the Roblox engine's capabilities and constraints. The architecture emphasizes stability, performance, and visual quality while working within the limitations of a networked game environment.