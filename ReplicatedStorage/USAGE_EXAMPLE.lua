-- HOW TO FIX YOUR SNAKE SYSTEM IN 2 LINES!

-- In your existing code where you create the snake:
local OptimizedSnakeSystem = require(ReplicatedStorage.OptimizedSnakeSystemV9)
local snake = OptimizedSnakeSystem.new(character, config)

-- ADD THESE 2 LINES TO FIX ALL PROBLEMS:
local Integration = require(ReplicatedStorage.OptimizedSnakeSystemIntegration)
local snakeFix = Integration.ApplyToSnake(snake)

-- That's it! Your snake now has:
-- ✓ No gimbal lock (parts won't stick up anymore)
-- ✓ Smooth, jitter-free movement
-- ✓ Frame-rate independent animation
-- ✓ Stable orientation (no rolling/flipping)

-- When destroying the snake, also clean up the integration:
-- snakeFix:destroy()