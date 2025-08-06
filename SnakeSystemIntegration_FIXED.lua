--[[
SNAKE SYSTEM INTEGRATION - SERVER ONLY
This script handles server-side game logic ONLY
Visual rendering is handled entirely by the client
Place this in ServerScriptService and DELETE the old SnakeSystemIntegration
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Create RemoteEvents folder first
local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
remoteEvents.Name = "RemoteEvents"

-- Create all necessary RemoteEvents
local spawnSnake = remoteEvents:FindFirstChild("SpawnSnake") or Instance.new("RemoteEvent", remoteEvents)
spawnSnake.Name = "SpawnSnake"

local respawnSnake = remoteEvents:FindFirstChild("RespawnSnake") or Instance.new("RemoteEvent", remoteEvents)
respawnSnake.Name = "RespawnSnake"

local updateMouseDirection = remoteEvents:FindFirstChild("UpdateMouseDirection") or Instance.new("RemoteEvent", remoteEvents)
updateMouseDirection.Name = "UpdateMouseDirection"

-- Store active snakes (server-side data only)
local activeSnakes = {}

-- Default configuration
local DEFAULT_CONFIG = {
	InitialLength = 85,
	MaxSegments = 50000,
	SegmentSpacing = 3.2,
	SegmentSize = Vector3.new(4, 4, 4),
	HeadSize = Vector3.new(4.5, 4.5, 4.5),
	HeadColor = Color3.fromRGB(76, 217, 100),
	BodyColors = {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	},
	HeadMaterial = Enum.Material.Neon,
	BodyMaterial = Enum.Material.Neon,
}

-- Get skin configuration
local function getSkinConfig(player)
	local skinName = player:GetAttribute("SelectedSkin") or "Default"
	
	-- Try to get skin data
	local skinData = nil
	pcall(function()
		local snakeSkins = require(ReplicatedStorage:WaitForChild("SnakeSkins"))
		if snakeSkins and snakeSkins[skinName] then
			skinData = snakeSkins[skinName]
		end
	end)
	
	if skinData then
		local config = {}
		for k, v in pairs(DEFAULT_CONFIG) do
			config[k] = skinData[k] or v
		end
		return config
	end
	
	return DEFAULT_CONFIG
end

-- Handle character spawning
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		wait(0.1)
		player = Players:GetPlayerFromCharacter(character)
		if not player then
			warn("Could not get player from character")
			return
		end
	end
	
	print("👤 Character added for:", player.Name)
	
	-- Clean up old snake data
	if activeSnakes[player] then
		local oldSnake = activeSnakes[player]
		if oldSnake.destroy then
			oldSnake:destroy()
		end
		activeSnakes[player] = nil
	end
	
	-- Wait for character to load
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	-- Get configuration
	local config = getSkinConfig(player)
	
	-- Check for revive
	local reviveSnakeLength = player:GetAttribute("ReviveSnakeLength")
	if reviveSnakeLength and reviveSnakeLength > 0 then
		config.InitialLength = reviveSnakeLength
		print("🔄 Reviving with length:", reviveSnakeLength)
		player:SetAttribute("ReviveSnakeLength", nil)
	end
	
	-- Store config for client
	character:SetAttribute("SnakeConfig", HttpService:JSONEncode(config))
	character:SetAttribute("SnakeLength", config.InitialLength)
	
	-- Create server-side snake data (no visuals!)
	local snake = {
		player = player,
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		length = config.InitialLength,
		config = config,
		isAlive = true,
		isBoosting = false,
		_connections = {},
		
		-- Methods for compatibility
		updateLength = function(self, newLength)
			self.length = newLength
			character:SetAttribute("SnakeLength", newLength)
		end,
		
		setBoosting = function(self, boosting)
			self.isBoosting = boosting
			character:SetAttribute("IsBoosting", boosting)
		end,
		
		destroy = function(self)
			for _, conn in pairs(self._connections) do
				if conn then conn:Disconnect() end
			end
			self.isAlive = false
		end
	}
	
	activeSnakes[player] = snake
	
	-- Global table for other systems
	if not _G.PlayerSnakes then
		_G.PlayerSnakes = {}
	end
	_G.PlayerSnakes[player] = snake
	
	-- Setup leaderstats
	local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"
	
	local lengthValue = leaderstats:FindFirstChild("Length") or Instance.new("IntValue", leaderstats)
	lengthValue.Name = "Length"
	lengthValue.Value = config.InitialLength
	
	-- Handle length changes
	lengthValue.Changed:Connect(function(newLength)
		if activeSnakes[player] == snake then
			snake:updateLength(newLength)
		end
	end)
	
	-- Handle skin changes
	snake._connections.skin = player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
		if activeSnakes[player] == snake then
			local newConfig = getSkinConfig(player)
			snake.config = newConfig
			character:SetAttribute("SnakeConfig", HttpService:JSONEncode(newConfig))
		end
	end)
	
	-- Handle death
	snake._connections.death = humanoid.Died:Connect(function()
		if activeSnakes[player] == snake then
			print("💀 Player died:", player.Name)
			snake:destroy()
			activeSnakes[player] = nil
			
			if _G.PlayerSnakes then
				_G.PlayerSnakes[player] = nil
			end
		end
	end)
	
	print("✅ Snake data created for:", player.Name)
end

-- Handle players
Players.PlayerAdded:Connect(function(player)
	print("👋 Player joined:", player.Name)
	
	-- Setup leaderstats
	local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"
	
	local length = leaderstats:FindFirstChild("Length") or Instance.new("IntValue", leaderstats)
	length.Name = "Length"
	length.Value = DEFAULT_CONFIG.InitialLength
	
	-- Connect character handler
	player.CharacterAdded:Connect(onCharacterAdded)
	
	-- Handle existing character
	if player.Character then
		onCharacterAdded(player.Character)
	end
end)

-- Cleanup on leaving
Players.PlayerRemoving:Connect(function(player)
	if activeSnakes[player] then
		activeSnakes[player]:destroy()
		activeSnakes[player] = nil
	end
end)

-- Handle spawn requests
spawnSnake.OnServerEvent:Connect(function(player)
	print("🎮 SpawnSnake - Play button clicked by:", player.Name)
	if not player.Character then
		player:LoadCharacter()
	end
end)

-- Handle respawn requests
respawnSnake.OnServerEvent:Connect(function(player, username)
	print("🎮 RespawnSnake requested for:", player.Name)
	
	if username and type(username) == "string" then
		player:SetAttribute("SlitherUsername", username)
		print("📝 Username set to:", username)
	end
	
	if player.Character then
		player.Character:Destroy()
		wait(0.1)
	end
	
	player:LoadCharacter()
	print("✅ Character loaded for:", player.Name)
end)

-- Handle mouse direction
updateMouseDirection.OnServerEvent:Connect(function(player, direction)
	if player.Character and typeof(direction) == "Vector3" then
		local validDirection = Vector3.new(
			math.clamp(direction.X, -1, 1),
			0,
			math.clamp(direction.Z, -1, 1)
		)
		
		if validDirection.Magnitude > 0 then
			player.Character:SetAttribute("MouseDirection", validDirection.Unit)
		end
	end
end)

-- Handle existing players
for _, player in pairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

print("✅ Snake System Integration (FIXED) loaded!")
print("📋 RemoteEvents created: SpawnSnake, RespawnSnake, UpdateMouseDirection")
print("🎮 Server ready - waiting for players to spawn!")