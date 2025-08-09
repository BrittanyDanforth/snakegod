--[[
SNAKE SYSTEM INTEGRATION (Server)
Place this in ServerScriptService
- Uses Remotes (primary) with fallback to RemoteEvents
- Fixed: initial Play button SpawnSnake handler
- Fixed: respawn event lookup and cleanup logic
- Fixed: periodic BatchSnakeUpdate broadcasting via the same remotes folder
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Server holds only data/state; clients render visuals
local activeSnakes = {}

-- Prefer Remotes; fallback to RemoteEvents for backward compatibility
local function getRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	end
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	return remotes
end

local remotesFolder = getRemotesFolder()
local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEventsFolder then
    remoteEventsFolder = Instance.new("Folder")
    remoteEventsFolder.Name = "RemoteEvents"
    remoteEventsFolder.Parent = ReplicatedStorage
end

local function ensureRemoteInFolder(folder, name)
    if not folder then
        folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "RemoteEvents"
            folder.Parent = ReplicatedStorage
        end
    end
    local ev = folder:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = folder
    end
    return ev
end

local function ensureRemoteEvent(name)
	local ev = remotesFolder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = remotesFolder
	end
	return ev
end

-- Menu / input remotes
local spawnSnake = ensureRemoteEvent("SpawnSnake")
local respawnSnake = ensureRemoteEvent("RespawnSnake")
local updateMouseDirection = ensureRemoteEvent("UpdateMouseDirection")
local updateBoostState = ensureRemoteEvent("UpdateBoostState")
-- Backward compatibility: also ensure in RemoteEvents folder
local spawnSnakeCompat = ensureRemoteInFolder(remoteEventsFolder, "SpawnSnake")
local respawnSnakeCompat = ensureRemoteInFolder(remoteEventsFolder, "RespawnSnake")
local updateMouseDirectionCompat = ensureRemoteInFolder(remoteEventsFolder, "UpdateMouseDirection")
local updateBoostStateCompat = ensureRemoteInFolder(remoteEventsFolder, "UpdateBoostState")
-- Proactively create BatchSnakeUpdate compat so clients waiting on RemoteEvents get it immediately
local batchUpdateEventCompat = ensureRemoteInFolder(remoteEventsFolder, "BatchSnakeUpdate")

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
	GlowIntensity = 2,
	GlowRange = 6,
	-- New: pass mesh selection and radius to client
	MeshName = "untitledsnakeeeee",
	Radius = 1.0,
}

local function getSkinConfig(player)
	local skinName = player:GetAttribute("SelectedSkin") or "Default"
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

	-- Simple revive teleport
	if player:GetAttribute("JustRevived") then
		local revivePos = player:GetAttribute("RevivePosition")
		if revivePos then
			local x, y, z = revivePos:match("([%d.-]+),%s*([%d.-]+),%s*([%d.-]+)")
			if x and y and z then
				local deathPos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
				local rootPart = character:WaitForChild("HumanoidRootPart")
				if rootPart then
					rootPart.CFrame = CFrame.new(deathPos)
					print("✅ Revived at:", deathPos)
				end
			end
		end
	end

	-- Clean up old server-side data
	if activeSnakes[player] then
		local old = activeSnakes[player]
		if old.connections then
			for _, conn in pairs(old.connections) do
				if conn then conn:Disconnect() end
			end
		end
		activeSnakes[player] = nil
	end

	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local reviveSnakeLength = player:GetAttribute("ReviveSnakeLength")
	local isReviving = player:GetAttribute("RevivingNow") or player:GetAttribute("JustRevived")
	if reviveSnakeLength and reviveSnakeLength > 0 then
		print("🔄 Found revive snake length:", reviveSnakeLength, "for", player.Name)
	elseif isReviving then
		warn("⚠️ ReviveSnakeLength attribute missing during revive! Checking leaderstats...")
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local lengthValue = leaderstats:FindFirstChild("Length")
			if lengthValue and lengthValue.Value > 55 then
				reviveSnakeLength = lengthValue.Value
				print("🔄 Using leaderstats length as fallback:", reviveSnakeLength)
			end
		end
	end

	wait(0.2)

	local config = getSkinConfig(player)
	if reviveSnakeLength and reviveSnakeLength > 0 then
		config.InitialLength = reviveSnakeLength
		print("✅ Applying revive snake length:", reviveSnakeLength)
		player:SetAttribute("ReviveSnakeLength", nil)
	end

	print("[Server] Setting up snake data for", player.Name)
	character:SetAttribute("SnakeConfig", HttpService:JSONEncode(config))
	character:SetAttribute("SnakeLength", config.InitialLength)
	character:SetAttribute("SnakeActive", true)

	local snakeData = {
		player = player,
		character = character,
		length = config.InitialLength,
		isAlive = true,
		config = config,
	}
	activeSnakes[player] = snakeData

	-- Boost state updates
	local boostConn = updateBoostState.OnServerEvent:Connect(function(eventPlayer, isBoosting)
		if eventPlayer == player and activeSnakes[player] then
			activeSnakes[player].isBoosting = isBoosting and true or false
			character:SetAttribute("IsBoosting", isBoosting and true or false)
		end
	end)

	-- Ensure leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local lengthValue = leaderstats:FindFirstChild("Length")
	if not lengthValue then
		lengthValue = Instance.new("IntValue")
		lengthValue.Name = "Length"
		lengthValue.Value = config.InitialLength or 55
		lengthValue.Parent = leaderstats
	else
		lengthValue.Value = config.InitialLength or 55
	end
	lengthValue.Changed:Connect(function(newLength)
		if activeSnakes[player] then
			activeSnakes[player].length = newLength
			character:SetAttribute("SnakeLength", newLength)
		end
	end)

	-- Skin changes
	local skinConn = player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
		if activeSnakes[player] then
			local newConfig = getSkinConfig(player)
			activeSnakes[player].config = newConfig
			character:SetAttribute("SnakeConfig", HttpService:JSONEncode(newConfig))
		end
	end)

	-- Death cleanup
	local deathConn
	deathConn = humanoid.Died:Connect(function()
		local sd = activeSnakes[player]
		if not sd then return end
		if sd.connections then
			for _, conn in pairs(sd.connections) do
				if conn then conn:Disconnect() end
			end
		end
		if deathConn then deathConn:Disconnect() end
		sd.isAlive = false
		character:SetAttribute("SnakeActive", false)
		activeSnakes[player] = nil
	end)

	snakeData.connections = {
		boost = boostConn,
		skin = skinConn,
		death = deathConn,
	}
end

-- Player lifecycle
Players.PlayerAdded:Connect(function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
		local length = Instance.new("IntValue")
		length.Name = "Length"
		length.Value = 55
		length.Parent = leaderstats
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local sd = activeSnakes[player]
	if not sd then return end
	if sd.connections then
		for _, conn in pairs(sd.connections) do
			if conn then conn:Disconnect() end
		end
	end
	activeSnakes[player] = nil
end)

-- Existing players (studio)
for _, player in pairs(Players:GetPlayers()) do
	if player.Character then
		onCharacterAdded(player.Character)
	else
		player.CharacterAdded:Connect(onCharacterAdded)
	end
end

-- Play button spawn
local function handleSpawn(player)
	print("🎮 Play button clicked - spawning", player.Name)
	if not player.Character then
		player:LoadCharacter()
	end
end
spawnSnake.OnServerEvent:Connect(handleSpawn)
if spawnSnakeCompat then spawnSnakeCompat.OnServerEvent:Connect(handleSpawn) end

-- Respawn from menu
local function handleRespawn(player, username)
	print("🎮 Respawn requested for:", player.Name)
	if username and type(username) == "string" then
		player:SetAttribute("SlitherUsername", username)
		print("📝 Username set to:", username)
	end
	if player.Character then
		player.Character:Destroy()
	end
	task.wait(0.1)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn("❌ Failed to load character:", err)
	else
		print("✅ Character loaded for:", player.Name)
	end
	print("🐍 Respawned player:", player.Name)
end
respawnSnake.OnServerEvent:Connect(handleRespawn)
if respawnSnakeCompat then respawnSnakeCompat.OnServerEvent:Connect(handleRespawn) end

-- Also listen for root-level remotes created by legacy UIs
local function hookRootRemote(name, handler)
    local existing = ReplicatedStorage:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        existing.OnServerEvent:Connect(handler)
    end
    ReplicatedStorage.ChildAdded:Connect(function(child)
        if child.Name == name and child:IsA("RemoteEvent") then
            child.OnServerEvent:Connect(handler)
        end
    end)
end

hookRootRemote("RespawnSnake", handleRespawn)
hookRootRemote("SpawnSnake", handleSpawn)

-- Mouse direction updates
local function handleMouseDir(player, direction)
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
end
updateMouseDirection.OnServerEvent:Connect(handleMouseDir)
if updateMouseDirectionCompat then updateMouseDirectionCompat.OnServerEvent:Connect(handleMouseDir) end

-- Broadcast optimized batched data to clients
local BROADCAST_RATE = 20
local lastBroadcast = 0
local batchUpdateEvent = ensureRemoteEvent("BatchSnakeUpdate")
-- batchUpdateEventCompat ensured above at startup

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastBroadcast < (1 / BROADCAST_RATE) then return end
	lastBroadcast = now

	local allSnakeData = {}
	for player, snakeData in pairs(activeSnakes) do
		if player.Parent and snakeData and snakeData.character and snakeData.character.Parent then
			local rootPart = snakeData.character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local mouseDirection = snakeData.character:GetAttribute("MouseDirection") or Vector3.new(0, 0, -1)
				table.insert(allSnakeData, {
					PlayerId = player.UserId,
					Position = rootPart.Position,
					LookVector = mouseDirection,
					Length = snakeData.length or 55,
					Name = player.Name,
				})
			end
		end
	end
	if #allSnakeData > 0 then
		batchUpdateEvent:FireAllClients(allSnakeData)
		if batchUpdateEventCompat then batchUpdateEventCompat:FireAllClients(allSnakeData) end
	end
end)

print("✅ Snake System Integration (Server) loaded!")