-- Test Script for Skinned Mesh Snake System
-- Place this in ServerScriptService to test the implementation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for the system to load
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the system
local success, err = pcall(function()
	OptimizedSnakeSystemV9.init()
end)

if not success then
	warn("Failed to initialize snake system:", err)
	return
end

print("✅ Snake system initialized successfully!")

-- Function to create a test snake for a player
local function createTestSnake(player)
	local character = player.Character or player.CharacterAdded:Wait()
	
	-- Wait for character to load
	character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")
	
	wait(1) -- Give character time to fully load
	
	-- Configuration for the snake
	local config = {
		initialLength = 30,
		speed = 16,
		turnSpeed = 3,
		primaryColor = Color3.fromRGB(85, 170, 255),
		secondaryColor = Color3.fromRGB(170, 255, 127),
		patternType = "gradient",
		rainbowMode = false
	}
	
	-- Create the snake
	local snake = OptimizedSnakeSystemV9.createSnake(character, config)
	
	if snake then
		print("✅ Created snake for", player.Name)
		
		-- Test some functions after a delay
		wait(3)
		
		-- Test growth
		snake:grow(10)
		print("🌱 Snake grew by 10 units")
		
		wait(2)
		
		-- Test boost
		snake:boost(true)
		print("🚀 Boost activated")
		
		wait(3)
		
		snake:boost(false)
		print("🛑 Boost deactivated")
		
		-- Test rainbow mode
		wait(2)
		snake:setRainbowMode(true)
		print("🌈 Rainbow mode activated")
		
		wait(5)
		snake:setRainbowMode(false)
		print("🎨 Rainbow mode deactivated")
		
		-- Test color change
		snake:setPrimaryColor(Color3.fromRGB(255, 100, 100))
		print("🎨 Changed primary color to red")
		
	else
		warn("Failed to create snake for", player.Name)
	end
end

-- Connect to player joining
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		-- Delay to ensure character is ready
		wait(2)
		createTestSnake(player)
	end)
end)

-- Create snakes for existing players
for _, player in pairs(Players:GetPlayers()) do
	if player.Character then
		createTestSnake(player)
	end
end

print("🐍 Skinned Mesh Snake Test Script loaded!")
print("Instructions:")
print("1. Make sure your slither_snake_rigged model is in ReplicatedStorage")
print("2. The model should be named 'SkinnedSnakeTemplate' or 'slither_snake_rigged'")
print("3. Join the game to see your snake automatically created")
print("4. The script will test various features like growth, boost, and colors")