-- OptimizedSnakeSystemV9.lua
-- Redirects to the new SkinnedMeshSnakeSystem for bone-based animation
-- This maintains backward compatibility while using the new system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkinnedMeshSnakeSystem = require(ReplicatedStorage:WaitForChild("SkinnedMeshSnakeSystem"))

-- Export the same interface as before for compatibility
local OptimizedSnakeSystemV9 = {}

function OptimizedSnakeSystemV9.init()
    SkinnedMeshSnakeSystem.init()
end

function OptimizedSnakeSystemV9.createSnake(character, config)
    return SkinnedMeshSnakeSystem.createSnake(character, config)
end

function OptimizedSnakeSystemV9.createSnakeFromSavedState(character, config, savedState)
    -- Create a snake with the saved state
    local snake = SkinnedMeshSnakeSystem.createSnake(character, config)
    
    -- Apply saved state if provided
    if savedState and snake then
        if savedState.length then
            snake.length = savedState.length
        end
        if savedState.isAlive ~= nil then
            snake.isAlive = savedState.isAlive
        end
    end
    
    return snake
end

print("✅ OptimizedSnakeSystemV9 redirecting to SkinnedMeshSnakeSystem")

return OptimizedSnakeSystemV9