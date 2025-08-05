-- DisableOldCollisionHandler
-- This script MUST be placed in ServerScriptService to disable the old collision system
-- It needs to run BEFORE the old handler starts its loops

local RunService = game:GetService("RunService")

-- Set a global flag to stop the old handler
_G.DISABLE_OLD_COLLISION_HANDLER = true

-- Wait one frame to ensure this runs first
RunService.Heartbeat:Wait()

-- Find and disable any old collision handler scripts
local function disableOldHandlers()
    -- Check workspace
    local oldHandler = workspace:FindFirstChild("SnakeCollisionHandler_FINAL")
    if oldHandler and oldHandler:IsA("Script") then
        oldHandler.Disabled = true
        warn("✅ Disabled SnakeCollisionHandler_FINAL in workspace")
    end
    
    -- Check ServerScriptService
    oldHandler = game.ServerScriptService:FindFirstChild("SnakeCollisionHandler_FINAL")
    if oldHandler and oldHandler:IsA("Script") then
        oldHandler.Disabled = true
        warn("✅ Disabled SnakeCollisionHandler_FINAL in ServerScriptService")
    end
    
    -- Also check for the initialization script
    local initHandler = game.ServerScriptService:FindFirstChild("InitializeCollisionHandler")
    if initHandler and initHandler:IsA("Script") then
        initHandler.Disabled = true
        warn("✅ Disabled InitializeCollisionHandler")
    end
end

disableOldHandlers()

print("🎯 Old collision handler disabled - New modular system is now the only active system")