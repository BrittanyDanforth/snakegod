# Snake Game System Flow Documentation

## Complete Death & Revive Flow

### 1. **Collision Detection → Death**
```
CollisionModule detects collision
  ↓
Fires controller.events.onFatalHit
  ↓
MainServer receives event
  ↓
MainServer transitions FSM to "Dying" state
  ↓
MainServer sets humanoid.Health = 0
  ↓
humanoid.Died event fires
```

### 2. **Death Processing**
```
Two parallel processes:

A) MainServer.CharacterAdded.humanoid.Died handler:
   - Calls deathOrbHandler:spawnDeathOrbsForPlayer()
   - Spawns purple death orbs along snake body

B) SnakeSystemIntegration.humanoid.Died handler:
   - Destroys the visual snake model
   - Cleans up snake connections
```

### 3. **Dying State → Revive Check**
```
DyingState:OnEnter() executes
  ↓
Checks controller:hasReviveToken()
  ↓
hasReviveToken() reads player:GetAttribute("RevivesAvailable")
  (Set by GamepassHandler)
  ↓
If revives > 0:
  - Calls controller:requestReviveFromClient()
  - Sends PromptRevive remote to client
  - Waits for response
  ↓
If player chooses "revive":
  - Returns Promise resolving to "Reviving"
If player declines or no revives:
  - Returns Promise resolving to "Spectating"
```

### 4. **Reviving State → Countdown**
```
RevivingState:OnEnter() executes
  ↓
Calls controller:useReviveToken()
  ↓
useReviveToken() decrements player:SetAttribute("RevivesAvailable", current - 1)
  ↓
Starts 5-second countdown
  ↓
Fires UpdateReviveCountdown to client for UI
  ↓
After countdown completes:
  - Returns Promise resolving to "Spawning"
```

### 5. **Spawning State → Respawn**
```
SpawningState:OnEnter() executes
  ↓
If coming from "Reviving":
  - Gets current snake length
  - Sets player:SetAttribute("ReviveSnakeLength", length * 0.8)
  - Sets player:SetAttribute("JustRevived", true)
  - Sets player:SetAttribute("RevivePosition", position)
  ↓
Calls player:LoadCharacter()
  ↓
CharacterAdded event fires
  ↓
Returns Promise resolving to "Alive"
```

### 6. **Snake Recreation**
```
SnakeSystemIntegration.CharacterAdded handler:
  ↓
Checks if player:GetAttribute("JustRevived") == true
  ↓
If reviving:
  - Reads ReviveSnakeLength attribute
  - Creates snake with that length
  - Positions at RevivePosition
If normal spawn:
  - Creates snake with default length
  ↓
MainServer.CharacterAdded handler:
  - Sets up death orb spawning for next death
  - Monitors for JustRevived to clean up nearby orbs
```

### 7. **Alive State**
```
AliveState:OnEnter() executes
  ↓
Re-enables collision detection
  ↓
Player can move and play normally
```

## System Contracts

### Attributes (Set by GamepassHandler)
- `RevivesAvailable`: Number of revives player has
- `HasRevive`: Boolean if player has revive gamepass
- `MagnetRange`: Range of magnet effect
- `SpeedMultiplier`: Speed boost multiplier

### Attributes (Set by System)
- `JustRevived`: Set when player is reviving
- `RevivingNow`: Set during revive process
- `ReviveSnakeLength`: Length to restore on revive
- `RevivePosition`: Position to spawn at
- `RevivePromptActive`: Revive UI is showing

### Remote Events (Created by GamepassHandler)
- `PromptRevive`: Server → Client to show revive UI
- `UpdateReviveCountdown`: Server → Client for countdown
- `UseBoost`: Client → Server to activate boost
- `ToggleMagnet`: Client → Server to toggle magnet

### Remote Events (System)
- `RespawnSnake`: Client → Server for initial spawn/respawn

## Key Integration Points

1. **MainServer ← → GamepassHandler**
   - MainServer reads attributes set by GamepassHandler
   - Never directly modifies perk attributes

2. **MainServer ← → SnakeSystemIntegration**
   - Both listen to humanoid.Died
   - MainServer handles orbs, SnakeSystemIntegration handles snake cleanup
   - SnakeSystemIntegration reads revive attributes set by SpawningState

3. **PlayerController States ← → GamepassHandler**
   - States read RevivesAvailable to check/use tokens
   - Never directly modify the attribute except through useReviveToken()

4. **All Systems → Attributes**
   - Attributes are the primary communication method
   - Each system has clear ownership of specific attributes