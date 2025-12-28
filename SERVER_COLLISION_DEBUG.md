# Collision System Debug Checklist

## Quick Diagnosis Steps

### 1. Check if MainServer is finding your snake
In the console, you should see:
```
[MainServer] Found snake for [YourName] with head: Segment0_Head
[MainServer] State set to Alive with 3 second spawn protection
```

If you don't see this, the snake isn't being detected.

### 2. Check if CollisionModule is running
You should see periodic messages like:
```
[CollisionModule] Cache updated - Orbs: X, Obstacles: X, Snakes: X
```

If Snakes is 0, the collision system isn't finding any snakes.

### 3. Check PlayerController state
The FSM state should be "Alive" when you're playing. Check for:
```
[PlayerController] State changed to: Alive
```

## Common Issues and Fixes

### Issue 1: Snake not found by MainServer
**Symptoms**: No collision detection at all
**Cause**: Snake is in wrong location or has wrong name
**Fix**: Check where your snake is created:
- Should be named `Snake_[PlayerName]` 
- Could be in `workspace` directly or in `workspace.SnakeFolder`

### Issue 2: CollisionState.canCollide is false
**Symptoms**: Snake exists but no collisions register
**Cause**: Player is in wrong state or invincible
**Fix**: Check these attributes on your player:
- `IsReviving` should be false
- `SpawnProtection` should expire after 3 seconds

### Issue 3: Old collision handler interference
**Symptoms**: Inconsistent collision behavior
**Cause**: SnakeCollisionHandler_FINAL is still running
**Fix**: Make sure old collision handler is disabled in ServerScriptService

### Issue 4: Snake object reference mismatch
**Symptoms**: Head not found errors
**Cause**: PlayerController has wrong/outdated snake reference
**Fix**: Ensure controller.snakeObject matches actual snake model

## Debug Commands to Run

1. Check if your snake exists:
```lua
print(workspace:FindFirstChild("Snake_" .. game.Players.LocalPlayer.Name))
```

2. Check collision state:
```lua
local player = game.Players.LocalPlayer
print("RevivePromptActive:", player:GetAttribute("RevivePromptActive"))
print("AwaitingReviveResponse:", player:GetAttribute("AwaitingReviveResponse"))
print("IsReviving:", player:GetAttribute("IsReviving"))
```

3. Check if old collision handler is disabled:
```lua
local old = game.ServerScriptService:FindFirstChild("SnakeCollisionHandler_FINAL")
if old then print("Old handler enabled:", not old.Disabled) end
```

## Temporary Fix

If collisions aren't working at all, check if the old SnakeCollisionHandler_FINAL is disabled. The new MainServer tries to disable it, but it might not have permission. You may need to manually disable it in Studio.