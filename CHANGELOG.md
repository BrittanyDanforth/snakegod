# Changelog

All notable changes to this project will be documented in this file.

## [11.2.0] - 2025-08-08
- Skinned snake bone animation rewritten with NaN-safe framing:
  - Introduced safeNormalize and orthonormal basis helpers to avoid divide-by-zero and invalid CFrames
  - Implemented parallel-transport-style up-vector propagation to lock roll and eliminate “poking” artifacts
  - Smoothed per-bone tangents to avoid sudden flips on tight turns
  - Added clamped wave offset to prevent extreme rotations
- Robust pathing:
  - Optional Catmull–Rom spline with arc-length sampling; non-spline distance-based fallback added
  - History sampling now guards zero-length segments and uses safe fallbacks
- Mesh and bones:
  - Auto-detect MeshPart named `Circle` with fallback to first MeshPart
  - Collect all `Bone` descendants; numeric-aware sorting for names like `Bone`, `Bone.001`, `Bone.002`, …
- Physics safety:
  - Disabled collisions (`CanCollide=false`, `CanQuery=false`, `Massless=true`) for all `BasePart` descendants of the cloned snake model to prevent flinging
  - Explicit weld to `HumanoidRootPart` after settling
- Visual stability:
  - Color cycling hardened: falls back to `HeadColor` when `BodyColors` missing/empty
- API compatibility:
  - Expose `init`, `createSnake`, `createSnakeFromSavedState`, plus `updateLength` and `updateConfig`

## [11.1.0] - 2025-08-07
- Initial skinned mesh migration and bone-following using position history
- Added LOD with frequency throttling
- Introduced head light and boost particles