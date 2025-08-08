# Project Overview

This project implements a high-performance, skinned-mesh snake system with procedural bone animation.

## Stability Improvements (v11.2.0)
- Robust, NaN-safe bone animation:
  - Parallel-transport style up-vector propagation to eliminate roll jitter and vertex explosions
  - Safe normalization and orthonormal basis to prevent divide-by-zero
  - Smoothed tangents and clamped wave rotation for stability
- Physics safety:
  - All BaseParts under the cloned snake model have `CanCollide=false`, `CanQuery=false`, and `Massless=true`
  - Mesh is welded to `HumanoidRootPart` after physics settle
- Pathing:
  - Optional Catmull–Rom spline (arc-length); distance-based fallback requires no extra modules

## Mesh Requirements
- Place your skinned snake model in `ReplicatedStorage` as `slither_snake_rigged` (recommended), or `SkinnedSnakeTemplate`.
- Preferred structure:
  - A `MeshPart` named `Circle` (used as the deforming mesh)
  - Bones under the mesh (e.g., `Bone`, `Bone.001`, `Bone.002`, …)
  - Optional: `InitialPoses` folder with saved transforms

## Getting Started
- Client requires `ReplicatedStorage/OptimizedSnakeSystemV9.lua`
- API:
  - `OptimizedSnakeSystemV9.init()`
  - `OptimizedSnakeSystemV9.createSnake(character, config)`
  - `snake:updateLength(newLength)`
  - `snake:updateConfig({ HeadColor, BodyColors })`

## Troubleshooting
- If the snake doesn’t render:
  - Confirm your model is in `ReplicatedStorage` and named `slither_snake_rigged` or `SkinnedSnakeTemplate`
  - Ensure there is a `MeshPart` (ideally named `Circle`) and it contains `Bone` instances
- If bones tilt upwards or roll:
  - The new framing stabilizes roll; adjust `DEFAULT_BONE_SPACING` and `BONE_BLEND_FACTOR` in `OptimizedSnakeSystemV9.lua` for feel