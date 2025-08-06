# Slither.io Scripts Integration Guide

## Overview
This guide ensures the three core scripts work perfectly together:
1. **SnakeCollisionHandler_FINAL.lua** - Handles collision detection, death, and respawn
2. **SlitherIOMenu** - Client-side death menu and UI
3. **GamePassHandler** - Manages gamepasses and revive purchases

## Script Locations
- **SnakeCollisionHandler_FINAL.lua** → ServerScriptService
- **SlitherIOMenu** → StarterPlayer > StarterPlayerScripts
- **GamePassHandler** → ServerScriptService
- **ReviveUI** → StarterPlayer > StarterPlayerScripts

## Key Integration Points

### 1. Death Flow
```
Player Collision → SnakeCollisionHandler queues death
→ Sets Humanoid.Health = 0
→ Sets AwaitingReviveResponse attribute (if has revives)
→ SlitherIOMenu detects Humanoid.Died
→ Checks AwaitingReviveResponse attribute
→ If true, waits for ReviveUI
→ If false, shows death menu immediately
```

### 2. Revive Flow
```
SnakeCollisionHandler fires PromptRevive to client
→ ReviveUI shows prompt
→ Player clicks revive/buy
→ If buy: MarketplaceService purchase
→ GamePassHandler ProcessReceipt grants revive
→ ReviveUI fires back to PromptRevive with response
→ SnakeCollisionHandler handles revive/decline
```

### 3. Respawn Flow
```
SlitherIOMenu shows death screen
→ Player clicks respawn button
→ Fires RespawnSnake RemoteEvent
→ SnakeCollisionHandler receives and handles respawn
→ Resets collision state
→ Loads new character
→ Grants spawn invincibility
```

## Critical Attributes

### Player Attributes Set by Scripts:
- **AwaitingReviveResponse** - Prevents race condition between ReviveUI and death menu
- **IsDying** - Signals player is in death process
- **IsDead** - Player has died
- **RevivePromptActive** - ReviveUI is showing
- **JustRevived** - Player just used a revive
- **RevivingNow** - Currently in revive process
- **HasRevive** - Player has revive gamepass
- **RevivesAvailable** - Number of revives available
- **SlitherUsername** - Player's display name

## Remote Events Created

### By SnakeCollisionHandler:
- **PromptRevive** (in Remotes folder) - Server→Client revive prompt
- **RespawnSnake** (in ReplicatedStorage) - Client→Server respawn request
- **FreezeCamera** (in Remotes folder) - Stop camera movement
- **StopCameraMovement** (in Remotes folder) - Additional camera control

### Used by Scripts:
- **PromptRevive** - Two-way communication for revive system
- **RespawnSnake** - Menu requests respawn from server

## Common Issues & Solutions

### Issue: Death menu shows before ReviveUI
**Solution**: AwaitingReviveResponse is set BEFORE Humanoid.Health = 0

### Issue: Player gets stuck after death
**Solution**: processingPlayers table prevents duplicate processing

### Issue: Revive purchase doesn't work
**Solution**: GamePassHandler ProcessReceipt handles product ID 3356734577

### Issue: Camera doesn't stop on death
**Solution**: Multiple redundant camera freeze methods used

### Issue: Orbs spawn in circle
**Solution**: Captures visual snake model segments before destruction

## Testing Checklist

1. **Normal Death (No Revive)**
   - [ ] Player dies → Death menu shows → Respawn works
   - [ ] Camera freezes properly
   - [ ] Orbs spawn along snake body

2. **Death with Revive Available**
   - [ ] Player dies → ReviveUI shows → Can revive
   - [ ] Death menu doesn't interfere
   - [ ] Snake respawns at death location

3. **Revive Purchase**
   - [ ] No revives → Buy button shows → Purchase works
   - [ ] RevivesAvailable increments
   - [ ] Can use purchased revive

4. **Multiple Deaths**
   - [ ] Die → Respawn → Die again works
   - [ ] No stuck states
   - [ ] All attributes reset properly

5. **Edge Cases**
   - [ ] Revive timeout (60s) works
   - [ ] Disconnect during death handled
   - [ ] Rapid deaths don't break system

## Performance Notes

- Collision checks run every 5 frames
- Death queue processes every 0.05 seconds
- Caches clear every 45 seconds
- Invincibility lasts 5 seconds after spawn

## Debug Commands

In game, create a StringValue in workspace named "ToggleCollisionDebug" and set its value to "debug" to enable collision debugging.

## Final Notes

All three scripts are designed to work together seamlessly. The key is proper attribute management and ensuring the death flow respects the revive system priority.