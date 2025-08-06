# Server Collision System Debug Guide

## Overview
This guide helps debug collision and death-related issues in the Snake game server system.

## Recent Fixes (Death/Revive System)

### Issues Fixed:
1. **AliveState nil comparison error**: Added proper nil checks for controller and config initialization
2. **Remote Events not created**: Added createRemotes() function to ensure all RemoteEvents exist before use
3. **ReviveUI parameter mismatch**: Fixed ReviveUI to accept data parameter from server
4. **Wrong RemoteEvent used**: Fixed ReviveUI to use ReviveResponse instead of PromptRevive for responses
5. **Client health check**: Removed client-side health check that was preventing revive prompts

### Key Changes:
- PlayerController now has proper config validation with defaults
- MainServer creates all required RemoteEvents on startup
- ReviveUI trusts server authority for death state
- Proper RemoteEvent flow: PromptRevive (server->client), ReviveResponse (client->server)

## System Architecture