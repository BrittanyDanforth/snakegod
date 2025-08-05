-- REVIVE SYSTEM FIX
-- This script disables the old SnakeCollisionHandler_FINAL to prevent duplicate death processing
-- Place this in ServerScriptService

local RunService = game:GetService("RunService")

-- Wait a frame to ensure everything is loaded
RunService.Heartbeat:Wait()

-- Find and disable the old collision handler if it exists
local oldHandler = _G.CollisionHandler
if oldHandler and oldHandler.destroy then
    warn("⚠️ DISABLING OLD COLLISION HANDLER - Using new modular system only")
    oldHandler:destroy()
    _G.CollisionHandler = nil
end

-- Clean up any leftover connections from the old system
local function cleanupOldSystem()
    -- Remove old death queue processing if it exists
    if _G.DeathQueueConnection then
        _G.DeathQueueConnection:Disconnect()
        _G.DeathQueueConnection = nil
    end
    
    -- Clear old collision caches
    if _G.CollisionCache then
        _G.CollisionCache = nil
    end
end

cleanupOldSystem()

print("✅ Old collision system disabled - New modular system is now primary")
print("🔧 Revive system should now work without duplicates")