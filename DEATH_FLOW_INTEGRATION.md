# Death Flow Integration Guide

## Overview
This document describes the unified death handling system after integrating the FSM-based PlayerController with the SlitherIOMenu client UI. The server's FSM is now the single source of truth for player state.

## Key Changes Made

### 1. SlitherIOMenu (Client)
- **REMOVED**: Local death detection via `Humanoid.Died` event
- **ADDED**: Server command listener via `ShowDeathScreen` RemoteEvent
- **BEHAVIOR**: Now waits for server to tell it when to show the death menu

### 2. MainServer (Server)
- **ADDED**: Creation of `ShowDeathScreen` RemoteEvent in `setupRemoteHandlers()`

### 3. SpectatingState (Server)
- **ADDED**: `_sendDeathScreenCommand()` method that fires the `ShowDeathScreen` event
- **BEHAVIOR**: Automatically triggers death screen when player enters spectating state

## Complete Death Flow

### 1. Player Takes Fatal Damage
```
CollisionModule detects fatal collision
    ↓
PlayerController notified via handleDeath()
    ↓
FSM transitions: Alive → Dying
```

### 2. Dying State Processing
```
DyingState:OnEnter()
    ↓
Check revive tokens available?
    ├─ YES: Show revive prompt
    │   ├─ Player accepts → Transition to "Reviving" state
    │   ├─ Player declines → Transition to "Spectating" state
    │   └─ Timeout (30s) → Transition to "Spectating" state
    │
    └─ NO: Wait 1s → Kill humanoid → Transition to "Spectating" state
```

### 3. Spectating State & Death Menu
```
SpectatingState:OnEnter()
    ↓
1. Set attributes: IsSpectating=true, IsDead=true
2. Clean up snake object
3. Setup spectator camera
4. Call _sendDeathScreenCommand()
    ↓
ShowDeathScreen RemoteEvent fired to client
    ↓
SlitherIOMenu receives event and shows death menu
```

### 4. Respawn Flow
```
Player clicks "Play Again" in SlitherIOMenu
    ↓
Fires RespawnSnake RemoteEvent
    ↓
MainServer handles respawn
    ↓
FSM transitions: Spectating → Spawning
    ↓
SlitherIOMenu automatically hides (via CharacterAdded)
```

## State Attributes

### Server-Side (Set by PlayerController/States)
- `IsSpectating`: true when in spectating state
- `IsDead`: true when player is dead
- `RevivePromptActive`: true when revive UI is showing
- `AwaitingReviveResponse`: true when waiting for revive decision
- `Reviving`: true during revive process

### Client-Side (Used by SlitherIOMenu)
- All attributes are now read-only from client perspective
- Menu appearance is controlled by server commands

## RemoteEvents

### ShowDeathScreen
**Direction**: Server → Client
**Purpose**: Tell client to show death menu
**Data Structure**:
```lua
{
    stats = {
        score = number,  -- Final length/score
        kills = number   -- Kills this life
    },
    timestamp = number   -- OS time of death
}
```

### RespawnSnake (Existing)
**Direction**: Client → Server
**Purpose**: Request respawn after death

## Benefits of This Architecture

1. **No Race Conditions**: Server FSM is the single authority
2. **Predictable Flow**: Death → Revive Check → Spectating → Menu
3. **Clean Separation**: Server handles logic, client handles UI
4. **Extensible**: Easy to add new death-related features

## Testing Checklist

- [ ] Player death triggers Dying state
- [ ] Revive prompt appears if tokens available
- [ ] Accepting revive transitions to Reviving state
- [ ] Declining revive transitions to Spectating state
- [ ] Revive timeout transitions to Spectating state
- [ ] Death menu appears when entering Spectating state
- [ ] Stats are correctly passed to death menu
- [ ] Respawn button triggers proper state transition
- [ ] Menu hides when character spawns

## Common Issues & Solutions

### Issue: Death menu not appearing
**Solution**: Check that ShowDeathScreen remote exists in Remotes folder

### Issue: Multiple death menus
**Solution**: Ensure SlitherIOMenu's old death detection is removed

### Issue: Menu appears during revive
**Solution**: SpectatingState is only entered after revive is declined/timed out