# Migration Guide: From Monolithic to Modular Snake Architecture

## Overview

This guide will help you transition from the old 2000-line `SnakeCollisionHandler_FINAL.lua` to the new modular architecture. The new system eliminates the ReviveUI bug, race conditions, and provides a robust foundation for future development.

## Key Changes

### 1. **Architecture Transformation**
- **Old**: Single 2000-line script with global state (`_G`)
- **New**: Modular system with Single-Script Architecture (SSA)

### 2. **State Management**
- **Old**: Boolean flags (`isDead`, `isReviving`, etc.) with complex if/else logic
- **New**: Finite State Machine with explicit states (Spawning, Alive, Dying, Reviving, Spectating)

### 3. **Asynchronous Operations**
- **Old**: Unmanaged `wait()` calls causing race conditions
- **New**: Promise-based system with cancellation support

### 4. **Collision Detection**
- **Old**: Unreliable `.Touched` events and name-based loops
- **New**: Modern spatial queries with CollectionService optimization

## Migration Steps

### Step 1: Backup Your Project
Before making any changes, create a full backup of your game.

### Step 2: Install the New Architecture

1. Copy the new directory structure:
   ```
   ServerScriptService/
   └─ MainServer.server.lua
   
   ServerStorage/
   └─ ServerModules/
      ├─ PlayerController.module.lua
      ├─ FSM.module.lua
      ├─ CollisionModule.module.lua
      ├─ States/
      │  ├─ SpawningState.module.lua
      │  ├─ AliveState.module.lua
      │  ├─ DyingState.module.lua
      │  ├─ RevivingState.module.lua
      │  └─ SpectatingState.module.lua
      └─ Lib/
         ├─ Promise.module.lua
         └─ Maid.module.lua
   
   ReplicatedStorage/
   └─ SharedModules/
      └─ Config.module.lua
   ```

2. Disable the old `SnakeCollisionHandler_FINAL.lua` script (don't delete it yet).

### Step 3: Update Dependencies

The new system integrates with your existing modules:
- `OptimizedSnakeSystemV9.lua` - Used by SpawningState
- `OrbUtils` - Used by DyingState for death orb spawning
- `AISnake` - Can be integrated with MainServer

### Step 4: Tag Your Game Objects

The new system uses CollectionService for efficient queries. Add these tags to your objects:

```lua
-- In your map/object setup scripts:
CollectionService:AddTag(wallPart, "Obstacle")
CollectionService:AddTag(orbPart, "Orb")
-- Snake parts are tagged automatically by PlayerController
```

### Step 5: Update Remote Events

The new system uses cleaner remote event communication. Update your client scripts:

#### Old Pattern:
```lua
-- Client
PromptRevive.OnClientEvent:Connect(function(data)
    if data == "show" then
        -- Show UI
    end
end)
```

#### New Pattern:
```lua
-- Client
PromptRevive.OnClientEvent:Connect(function(data)
    if data.show then
        -- Show UI
        -- data.hasToken tells if player can revive
    end
end)
```

### Step 6: Update Snake Creation

#### Old Pattern:
```lua
-- Direct snake creation with global state
local snake = createSnake(player)
_G.PlayerSnakes[player] = snake
```

#### New Pattern:
```lua
-- Snake creation is managed by SpawningState
-- Access via PlayerController:
local controller = playerControllers[player]
local snakeObject = controller.snakeObject
```

### Step 7: Handle State Transitions

#### Old Pattern:
```lua
-- Complex death handling
player:SetAttribute("IsDead", true)
wait(2)
showReviveUI(player)
wait(10)
-- etc...
```

#### New Pattern:
```lua
-- Simple state transition
controller.fsm:changeState("Dying", collisionData)
-- Everything else is handled automatically
```

## Common Integration Patterns

### Accessing Player Data
```lua
-- Old way
local score = _G.PlayerScores[player] or 0

-- New way
local controller = playerControllers[player]
local score = controller:getScore()
```

### Handling Collisions
```lua
-- Old way: Manual collision checks scattered throughout
-- New way: Centralized in CollisionModule, events fire to controllers
controller.events.onFatalHit:Connect(function(collisionData)
    -- Handle collision
end)
```

### Power-Ups Integration
```lua
-- Add to PlayerController data
controller.data.powerUps.speed = {
    active = true,
    endTime = os.clock() + 10
}

-- Check in AliveState:OnExecute
if controller.data.powerUps.speed and 
   os.clock() > controller.data.powerUps.speed.endTime then
    controller.data.powerUps.speed = nil
    controller:setSpeed(Config.Snake.baseSpeed)
end
```

## Testing Checklist

After migration, test these critical paths:

- [ ] Player spawning creates snake correctly
- [ ] Movement and controls work as expected
- [ ] Collision with walls kills player
- [ ] Collision with other snakes works
- [ ] Orb collection increases score and length
- [ ] Death sequence plays correctly
- [ ] ReviveUI appears and disappears properly
- [ ] ReviveUI is hidden when player leaves (bug fix verification)
- [ ] Spectator mode works after death
- [ ] Memory is cleaned up when players leave

## Troubleshooting

### Issue: Snake doesn't spawn
- Check that `OptimizedSnakeSystemV9` is in ReplicatedStorage
- Verify MainServer.server.lua is running
- Check output for error messages

### Issue: Collisions not detected
- Ensure objects are tagged properly with CollectionService
- Check that CollisionModule is started in MainServer
- Verify snake head has proper collision properties

### Issue: ReviveUI still stuck
- Ensure you're using the new Promise-based DyingState
- Check that PlayerController:destroy() is called on player leaving
- Verify client is updated to handle new remote format

## Performance Improvements

The new architecture provides several performance benefits:

1. **Spatial Query Optimization**: Uses whitelisted queries instead of checking all parts
2. **Frame Skipping**: Collision checks run every 3 frames instead of every frame
3. **Caching**: Orb and obstacle lists are cached and updated periodically
4. **No Global State**: Eliminates expensive `_G` lookups

## Next Steps

Once the migration is complete:

1. Delete the old `SnakeCollisionHandler_FINAL.lua`
2. Remove any `_G` references from other scripts
3. Update your admin commands to use the new PlayerController API
4. Consider implementing additional features like:
   - Round system in MainServer
   - More power-ups in Config
   - AI snake integration

## Support

If you encounter issues during migration:

1. Check the console for error messages
2. Verify all modules are properly required
3. Ensure RemoteEvents exist in ReplicatedStorage/Remotes
4. Test with a single player first before multiplayer testing

The new architecture is designed to be debuggable - each module has a clear responsibility, making it easy to isolate and fix issues.