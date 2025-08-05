# Death Flow Fixes V2 - Resolving UI Flashing and Revive Issues

## Summary of Issues Fixed

After implementing the unified death flow system, the user reported:
1. ✅ Death and collision detection now work correctly
2. ✅ Revive popup appears properly
3. ❌ Sometimes revive doesn't work
4. ❌ Death menu/revive UI sometimes flashes while player is alive

This document describes the fixes applied to resolve these remaining issues.

## Issue 1: Duplicate Death Screen Triggers

### Problem
The death screen was being triggered from two different sources:
- `ControlDeathUI` remote fired by `DyingState` when revive is declined/times out
- `ShowDeathScreen` remote fired by `SpectatingState` when player enters spectator mode

This caused the death menu to flash briefly even when the player was alive or reviving.

### Solution
Removed the death UI showing logic from `DyingState`. Now only `SpectatingState` is responsible for showing the death screen:

```lua
-- In DyingState.module.lua
-- REMOVED these lines:
-- Show death UI after killing
task.wait(0.5)
if deathUIRemote then
    deathUIRemote:FireClient(self.controller.player, {
        action = "show"
    })
end

-- Now it simply transitions to Spectating without showing UI:
resolve("Spectating")
```

## Issue 2: Revive Sometimes Not Working

### Problems Identified
1. Humanoid wasn't being killed immediately in `DyingState`, causing state inconsistencies
2. No protection against duplicate death processing if multiple collisions occur rapidly
3. Missing death processing flag cleanup

### Solutions Applied

#### 1. Immediate Humanoid Death
```lua
-- In DyingState:OnEnter()
-- Kill the humanoid immediately to ensure proper death state
if humanoid and humanoid.Health > 0 then
    warn("[DyingState] Killing player humanoid")
    humanoid.Health = 0
end

-- Disable collisions immediately
self.controller.collisionState.canCollide = false
```

#### 2. Duplicate Death Prevention
```lua
-- In DyingState:OnEnter()
-- Prevent duplicate death processing
if self.deathProcessing then
    warn("[DyingState] Already processing death, ignoring duplicate entry")
    return Promise.resolve("Spectating")
end
self.deathProcessing = true
```

#### 3. Proper Flag Cleanup
```lua
-- In DyingState:OnExit()
-- Clear death processing flag
self.deathProcessing = false
```

## Issue 3: Additional Safety Checks

### SpectatingState Improvements
The `SpectatingState` already had safety checks but they ensure:

1. **Revive State Check**: Won't show death screen if player has revive attributes
```lua
if self.controller.player:GetAttribute("IsReviving") or 
   self.controller.player:GetAttribute("RevivingNow") or
   self.controller.player:GetAttribute("JustRevived") then
    warn("[SpectatingState] Not showing death screen - player was in revive process")
    return
end
```

2. **Alive Player Check**: Transitions back to Alive if player is somehow alive
```lua
if humanoid and humanoid.Health > 0 then
    warn("[SpectatingState] WARNING: Player is alive in spectating state!")
    task.wait(0.1)
    self.controller.fsm:changeState("Alive")
    return
end
```

3. **Duplicate Send Prevention**: Only sends death screen once per session
```lua
if self.deathScreenSent then
    warn("[SpectatingState] Death screen already sent, skipping")
    return
end
```

## Updated Death Flow

```
1. Collision Detected → PlayerController:onFatalHit
2. FSM: Alive → Dying
   - Humanoid killed immediately ✓
   - Collisions disabled ✓
   - Death processing flag set ✓
3. If has revive tokens:
   - Show revive prompt
   - Wait for response
4. Response handling:
   - Accept → FSM: Dying → Reviving → Spawning → Alive
   - Decline/Timeout → FSM: Dying → Spectating
5. SpectatingState:
   - Safety checks (not reviving, not alive) ✓
   - Send ShowDeathScreen once ✓
   - Enter spectator mode

```

## Testing Checklist

- [x] Player dies when colliding with AI snake
- [x] Revive prompt appears if player has revive tokens
- [x] Accepting revive works consistently
- [x] Declining revive shows death screen
- [x] Death screen doesn't flash while alive
- [x] Death screen doesn't show during revive process
- [x] Multiple rapid collisions don't break the system
- [x] Revive UI disappears properly after use

## Key Improvements

1. **Single Source of Truth**: Only `SpectatingState` shows the death screen
2. **Immediate Death**: Humanoid killed immediately in `DyingState` for consistency
3. **Duplicate Protection**: Death processing flag prevents multiple simultaneous deaths
4. **Robust Safety Checks**: Multiple layers of validation before showing death screen
5. **Clean State Transitions**: Proper cleanup of flags and attributes on state exit

These fixes ensure a smooth, reliable death and revive experience without UI flashing or state inconsistencies.