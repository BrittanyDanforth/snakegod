-- Server Script to Initialize Modern SnakeCollisionHandler
-- Place this in ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for modules
local SnakeCollisionHandler = require(script.Parent:WaitForChild("SnakeCollisionHandler_V10_Modern"))

-- Initialize the collision handler
local collisionHandler = SnakeCollisionHandler.new()

-- Optional: Store reference globally for other scripts
_G.CollisionHandler = collisionHandler

print("✅ Snake game collision system initialized!")
print("📋 Features:")
print("  - Modern spatial queries (no .Touched)")
print("  - Trove pattern for memory management")
print("  - Fixed death orb spawning")
print("  - Fixed ReviveUI system")
print("  - Client prediction with server validation")
print("  - Modern Luau APIs (task.wait, os.clock)")

-- Optional: Cleanup on server shutdown
game:BindToClose(function()
	if collisionHandler then
		collisionHandler:destroy()
	end
end)