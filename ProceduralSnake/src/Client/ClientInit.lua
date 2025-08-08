--!strict
-- Client Initialization Script
-- Sets up the procedural snake system on the client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

-- Wait for modules
local ClientModules = script.Parent
local SnakeController = require(ClientModules:WaitForChild("SnakeController"))
local SnakeNetworkHandler = require(ClientModules:WaitForChild("SnakeNetworkHandler"))

-- Wait for player
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Initialize snake system
local snakeController = SnakeController.new(character)
local networkHandler = SnakeNetworkHandler.new(snakeController)

-- Handle character respawning
player.CharacterAdded:Connect(function(newCharacter)
	-- Clean up old instances
	snakeController:Destroy()
	networkHandler:Destroy()
	
	-- Wait a moment for character to fully load
	task.wait(0.5)
	
	-- Create new instances
	snakeController = SnakeController.new(newCharacter)
	networkHandler = SnakeNetworkHandler.new(snakeController)
end)

-- Handle player leaving
game:BindToClose(function()
	if snakeController then
		snakeController:Destroy()
	end
	if networkHandler then
		networkHandler:Destroy()
	end
end)