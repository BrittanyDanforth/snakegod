--!strict
-- Snake Replication: Server-side authority for multiplayer snake synchronization
-- Manages head position validation and state broadcasting

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create remote events for snake communication
local remotes = Instance.new("Folder")
remotes.Name = "SnakeRemotes"
remotes.Parent = ReplicatedStorage

local updateHeadRemote = Instance.new("RemoteEvent")
updateHeadRemote.Name = "UpdateSnakeHead"
updateHeadRemote.Parent = remotes

local snakeStateRemote = Instance.new("RemoteEvent")
snakeStateRemote.Name = "SnakeStateChanged"
snakeStateRemote.Parent = remotes

-- Types
type SnakeState = {
	headCFrame: CFrame,
	velocity: Vector3,
	length: number,
	lastUpdate: number,
	isAlive: boolean
}

local SnakeReplication = {}
SnakeReplication.__index = SnakeReplication

-- Constants
local UPDATE_RATE = 20 -- Updates per second
local MAX_SPEED = 50 -- Maximum allowed speed (studs/second)
local POSITION_TOLERANCE = 5 -- Maximum allowed position difference

function SnakeReplication.new()
	local self = setmetatable({}, SnakeReplication)
	
	self.snakeStates = {} :: {[Player]: SnakeState}
	self.lastBroadcast = 0
	
	self:_initialize()
	
	return self
end

function SnakeReplication:_initialize()
	-- Handle player joining
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	
	-- Handle player leaving
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
	
	-- Process head position updates from clients
	updateHeadRemote.OnServerEvent:Connect(function(player, headCFrame: CFrame, velocity: Vector3)
		self:ValidateAndUpdateHead(player, headCFrame, velocity)
	end)
	
	-- Broadcast snake states periodically
	RunService.Heartbeat:Connect(function()
		self:BroadcastStates()
	end)
end

function SnakeReplication:OnPlayerAdded(player: Player)
	-- Initialize snake state for new player
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5) -- Wait for character to load
		
		local head = character:FindFirstChild("Head") or character.PrimaryPart
		if head then
			self.snakeStates[player] = {
				headCFrame = head.CFrame,
				velocity = Vector3.new(0, 0, 0),
				length = 20, -- Default snake length
				lastUpdate = tick(),
				isAlive = true
			}
			
			-- Notify all clients about new snake
			snakeStateRemote:FireAllClients(player, self.snakeStates[player])
		end
	end)
	
	player.CharacterRemoving:Connect(function()
		if self.snakeStates[player] then
			self.snakeStates[player].isAlive = false
			snakeStateRemote:FireAllClients(player, self.snakeStates[player])
		end
	end)
end

function SnakeReplication:OnPlayerRemoving(player: Player)
	-- Clean up snake state
	self.snakeStates[player] = nil
	
	-- Notify clients to remove this snake
	snakeStateRemote:FireAllClients(player, nil)
end

function SnakeReplication:ValidateAndUpdateHead(player: Player, headCFrame: CFrame, velocity: Vector3)
	local state = self.snakeStates[player]
	if not state or not state.isAlive then
		return
	end
	
	local currentTime = tick()
	local deltaTime = currentTime - state.lastUpdate
	
	-- Validate position (basic anti-cheat)
	local expectedMaxDistance = MAX_SPEED * deltaTime + POSITION_TOLERANCE
	local actualDistance = (headCFrame.Position - state.headCFrame.Position).Magnitude
	
	if actualDistance > expectedMaxDistance then
		-- Position is too far, likely cheating
		warn("Player", player.Name, "moved too fast! Expected max:", expectedMaxDistance, "Actual:", actualDistance)
		-- Rubber-band them back
		local character = player.Character
		if character and character.PrimaryPart then
			character:SetPrimaryPartCFrame(state.headCFrame)
		end
		return
	end
	
	-- Validate velocity
	if velocity.Magnitude > MAX_SPEED then
		velocity = velocity.Unit * MAX_SPEED
	end
	
	-- Update state
	state.headCFrame = headCFrame
	state.velocity = velocity
	state.lastUpdate = currentTime
end

function SnakeReplication:BroadcastStates()
	local currentTime = tick()
	local broadcastInterval = 1 / UPDATE_RATE
	
	if currentTime - self.lastBroadcast < broadcastInterval then
		return
	end
	
	self.lastBroadcast = currentTime
	
	-- Prepare compact state data for all snakes
	local stateData = {}
	for player, state in pairs(self.snakeStates) do
		if state.isAlive then
			-- Only send essential data to minimize bandwidth
			stateData[player] = {
				h = state.headCFrame, -- headCFrame abbreviated
				v = state.velocity,   -- velocity abbreviated
				l = state.length,     -- length abbreviated
			}
		end
	end
	
	-- Broadcast to all clients
	if next(stateData) then
		snakeStateRemote:FireAllClients(stateData)
	end
end

-- Admin commands for testing
function SnakeReplication:SetSnakeLength(player: Player, length: number)
	local state = self.snakeStates[player]
	if state then
		state.length = math.clamp(length, 5, 100)
		snakeStateRemote:FireAllClients(player, state)
	end
end

function SnakeReplication:RespawnSnake(player: Player)
	local state = self.snakeStates[player]
	if state and player.Character then
		state.isAlive = true
		state.headCFrame = player.Character:GetPrimaryPartCFrame()
		state.velocity = Vector3.new(0, 0, 0)
		snakeStateRemote:FireAllClients(player, state)
	end
end

return SnakeReplication