--!strict
-- Server Initialization Script
-- Sets up the server-side snake replication system

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Ensure shared modules are replicated
local srcFolder = script.Parent.Parent
local sharedFolder = srcFolder:FindFirstChild("Shared")
if sharedFolder then
	sharedFolder.Parent = ReplicatedStorage
end

-- Initialize server modules
local ServerModules = script.Parent
local SnakeReplication = require(ServerModules:WaitForChild("SnakeReplication"))

-- Start the replication system
local replicationSystem = SnakeReplication.new()

print("Procedural Snake Server initialized")