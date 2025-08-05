# Revive System Fix Instructions

## The Problem
Your game is running BOTH the old `SnakeCollisionHandler_FINAL` AND the new modular collision system (`CollisionModule`). This causes:
1. **Duplicate revive prompts** - Both systems detect death and send revive prompts
2. **Death orbs (purple stuff) not cleaning up** - No cleanup mechanism exists
3. **Revive not working** - Conflicting death handlers prevent proper revival

## The Solution

### Step 1: Add the Complete Fix Script
1. Copy `COMPLETE_REVIVE_FIX.lua` to `ServerScriptService`
2. This script will:
   - Disable the old collision handler
   - Add automatic death orb cleanup (60 second timer)
   - Clean up orbs when players revive
   - Prevent duplicate revive prompts

### Step 2: Files Already Updated
The following files have been updated with fixes:

1. **ServerStorage/ServerModules/CollisionModule.module.lua**
   - Added checks to skip collision detection during revive states
   - Prevents death during revive prompt

2. **ServerScriptService/MainServer.server.lua**
   - Added active revive session tracking
   - Prevents multiple death events for same player

3. **ReviveUI (Client Script)**
   - Added duplicate prompt prevention
   - Added safety checks for alive players
   - Added debug logging

### Step 3: Remove Old Collision Handler
If the automatic disabling doesn't work, manually remove/disable:
- Any script that requires `SnakeCollisionHandler_FINAL`
- The `InitializeCollisionHandler.lua` script if it's loading the old handler

### Step 4: Testing
1. **Test Revive**: Die with revives available, click revive - should work without duplicates
2. **Test Orb Cleanup**: Die and check that purple orbs disappear when you revive
3. **Test Auto-cleanup**: Any remaining orbs will disappear after 60 seconds

## How It Works Now

### Death Flow:
1. Player collides → `CollisionModule` detects it
2. `MainServer` receives `onFatalHit` event
3. Checks if revive prompt is already active (prevents duplicates)
4. If player has revives, shows ONE prompt
5. Death orbs spawn at death location

### Revive Flow:
1. Player clicks revive
2. Death orbs within 100 studs are cleaned up
3. Player respawns with stored snake length
4. All revive attributes are cleared

## Debug Commands
If issues persist, check console for:
- `"⚠️ DISABLING OLD COLLISION HANDLER"` - Confirms old system disabled
- `"⚠️ Duplicate revive prompt blocked"` - Shows duplicate prevention working
- `"🧹 Cleaned X death orbs"` - Shows orb cleanup working

## Architecture Notes
Your game uses:
- **New System**: `CollisionModule` → `PlayerController` → `FSM States` (Dying, Reviving, etc.)
- **Old System**: `SnakeCollisionHandler_FINAL` (should be disabled by fix)
- **Snake Creation**: `SnakeSystemIntegration` + `OptimizedSnakeSystemV9`

The fix ensures only the new modular system handles deaths and revives.