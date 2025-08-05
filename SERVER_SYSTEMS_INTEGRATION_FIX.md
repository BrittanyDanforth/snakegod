# Server Systems Integration Fixes

This document explains the fixes applied to integrate the four server-side systems properly.

## Overview

The four systems that needed integration:
1. **MainServer** - Core FSM controller
2. **GamepassHandler** - Manages perks and revives
3. **SnakeSystemIntegration** - Creates/destroys snake models
4. **RevivingState** - Handles revive countdown

## Issues Fixed

### 1. PlayerController Token Integration
**Problem**: PlayerController was using internal `reviveTokens` instead of GamepassHandler's `RevivesAvailable` attribute.

**Fix**: Updated `hasReviveToken()` and `useReviveToken()` methods to read/write the `RevivesAvailable` attribute:
```lua
function PlayerController:hasReviveToken()
    -- Read from GamepassHandler's attribute
    return (self.player:GetAttribute("RevivesAvailable") or 0) > 0
end

function PlayerController:useReviveToken()
    -- Decrement GamepassHandler's attribute
    local currentRevives = self.player:GetAttribute("RevivesAvailable") or 0
    if currentRevives > 0 then
        self.player:SetAttribute("RevivesAvailable", currentRevives - 1)
        return true
    end
    return false
end
```

### 2. DyingState Revive Flow
**Problem**: DyingState wasn't handling the revive prompt flow, leaving a gap between collision and revival.

**Fix**: Completely rewrote `OnEnter()` to:
- Store death position and snake length
- Check for revive tokens using the fixed `hasReviveToken()`
- Fire `PromptRevive` remote to show UI
- Listen for player response with timeout
- Set revival attributes before transitioning states
- Return a Promise that resolves to either "Reviving" or "Spectating"

### 3. SpawningState Revival Support
**Problem**: SpawningState didn't handle revival spawns differently from normal spawns.

**Fix**: Added revival detection and proper attribute setting:
- Detects if previous state was "Reviving"
- Sets `JustRevived` and `RevivingNow` attributes
- Calls `player:LoadCharacter()` for revival spawns
- Lets SnakeSystemIntegration handle snake creation with saved length

### 4. Death Orb Conflict Resolution
**Status**: The conflict exists between MainServer and SnakeCollisionHandler_FINAL. 
**Recommendation**: Disable SnakeCollisionHandler_FINAL to prevent duplicate death orb spawning.

## Complete Revive Flow

1. **Collision** → MainServer detects fatal hit
2. **Dying State** → Checks revives, shows prompt, waits for response
3. **Player Choice**:
   - **Accept** → Transition to RevivingState
   - **Decline/Timeout** → Transition to Spectating
4. **RevivingState** → Countdown, use token, transition to Spawning
5. **SpawningState** → Set revival attributes, call LoadCharacter()
6. **SnakeSystemIntegration** → Detects CharacterAdded, reads revival attributes, creates snake with saved length

## Attributes Used

The systems communicate via these player attributes:
- `RevivesAvailable` - Number of revives (set by GamepassHandler)
- `RevivePromptActive` - Revive UI is showing
- `AwaitingReviveResponse` - Waiting for player choice
- `JustRevived` - Player just revived (for spawn effects)
- `RevivingNow` - Currently in revival process
- `ReviveSnakeLength` - Snake length to restore
- `RevivePosition` - Position to spawn at

## Testing Checklist

- [ ] Player with Revive gamepass gets 2 revives
- [ ] Collision triggers Dying state
- [ ] Revive prompt appears with correct count
- [ ] Accepting revive shows countdown
- [ ] Snake respawns with full length
- [ ] Snake respawns at death position
- [ ] Declining/timeout transitions to spectating
- [ ] Revive count decrements properly
- [ ] No duplicate death orbs spawn
- [ ] No race conditions between systems

## Potential Issues

1. **SnakeCollisionHandler_FINAL conflict** - This old system may interfere. Consider disabling it.
2. **Race conditions** - Multiple systems listening to humanoid.Died could cause issues.
3. **Attribute timing** - Revival attributes must be set before LoadCharacter() is called.

## Next Steps

1. Test the complete flow in-game
2. Monitor for any race conditions
3. Consider disabling old collision handler
4. Add visual effects for revival (client-side)
5. Add sound effects for revival events