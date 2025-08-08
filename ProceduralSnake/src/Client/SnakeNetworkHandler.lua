--!strict
-- Snake Network Handler: Client-side networking integration
-- Handles communication with server for multiplayer snake synchronization

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for remotes
local remotes = ReplicatedStorage:WaitForChild("SnakeRemotes")
local updateHeadRemote = remotes:WaitForChild("UpdateSnakeHead") :: RemoteEvent
local snakeStateRemote = remotes:WaitForChild("SnakeStateChanged") :: RemoteEvent

local SnakeNetworkHandler = {}
SnakeNetworkHandler.__index = SnakeNetworkHandler

-- Constants
local SEND_RATE = 20 -- How often to send updates to server (Hz)
local INTERPOLATION_TIME = 0.1 -- Time to interpolate remote snake positions

type RemoteSnakeData = {
	targetCFrame: CFrame,
	currentCFrame: CFrame,
	velocity: Vector3,
	lastUpdate: number,
	length: number
}

function SnakeNetworkHandler.new(snakeController: any)
	local self = setmetatable({}, SnakeNetworkHandler)
	
	self.snakeController = snakeController
	self.localPlayer = Players.LocalPlayer
	self.lastSendTime = 0
	self.remoteSnakes = {} :: {[Player]: RemoteSnakeData}
	
	self:_initialize()
	
	return self
end

function SnakeNetworkHandler:_initialize()
	-- Listen for snake state updates from server
	snakeStateRemote.OnClientEvent:Connect(function(data: any)
		self:OnSnakeStateUpdate(data)
	end)
	
	-- Send local player updates to server
	RunService.Heartbeat:Connect(function()
		self:SendLocalUpdate()
	end)
	
	-- Interpolate remote snake positions
	RunService.PreRender:Connect(function(deltaTime)
		self:InterpolateRemoteSnakes(deltaTime)
	end)
end

function SnakeNetworkHandler:SendLocalUpdate()
	local currentTime = tick()
	local sendInterval = 1 / SEND_RATE
	
	if currentTime - self.lastSendTime < sendInterval then
		return
	end
	
	self.lastSendTime = currentTime
	
	-- Get local player's head position
	local character = self.localPlayer.Character
	if not character then
		return
	end
	
	local head = character:FindFirstChild("Head") or character.PrimaryPart
	if not head then
		return
	end
	
	-- Calculate velocity (simple approximation)
	local velocity = head.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
	
	-- Send to server
	updateHeadRemote:FireServer(head.CFrame, velocity)
end

function SnakeNetworkHandler:OnSnakeStateUpdate(data: any)
	-- Handle batch update
	if type(data) == "table" and not data.headCFrame then
		-- This is a batch update with multiple snakes
		for player, state in pairs(data) do
			if player ~= self.localPlayer then
				self:UpdateRemoteSnake(player, {
					headCFrame = state.h,
					velocity = state.v,
					length = state.l
				})
			end
		end
	else
		-- Single snake update (used for initial state or special updates)
		for player, state in pairs(game.Players:GetPlayers()) do
			if data == nil then
				-- Remove snake
				self.remoteSnakes[player] = nil
			elseif state and player ~= self.localPlayer then
				self:UpdateRemoteSnake(player, state)
			end
		end
	end
end

function SnakeNetworkHandler:UpdateRemoteSnake(player: Player, state: any)
	-- Initialize remote snake data if needed
	if not self.remoteSnakes[player] then
		self.remoteSnakes[player] = {
			targetCFrame = state.headCFrame or state.h,
			currentCFrame = state.headCFrame or state.h,
			velocity = state.velocity or state.v or Vector3.new(0, 0, 0),
			lastUpdate = tick(),
			length = state.length or state.l or 20
		}
		
		-- Ensure snake is set up in controller
		if player.Character then
			self.snakeController:SetupSnake(player.Character)
		end
	else
		-- Update existing snake data
		local snakeData = self.remoteSnakes[player]
		snakeData.targetCFrame = state.headCFrame or state.h
		snakeData.velocity = state.velocity or state.v or Vector3.new(0, 0, 0)
		snakeData.lastUpdate = tick()
		snakeData.length = state.length or state.l or snakeData.length
	end
end

function SnakeNetworkHandler:InterpolateRemoteSnakes(deltaTime: number)
	for player, remoteData in pairs(self.remoteSnakes) do
		if player.Character then
			local head = player.Character:FindFirstChild("Head") or player.Character.PrimaryPart
			if head then
				-- Calculate interpolation progress
				local timeSinceUpdate = tick() - remoteData.lastUpdate
				local interpolationProgress = math.min(timeSinceUpdate / INTERPOLATION_TIME, 1)
				
				-- Predict position based on velocity
				local predictedOffset = remoteData.velocity * timeSinceUpdate
				local targetPosition = remoteData.targetCFrame.Position + predictedOffset
				
				-- Interpolate position
				local currentPosition = remoteData.currentCFrame.Position
				local newPosition = currentPosition:Lerp(targetPosition, interpolationProgress)
				
				-- Interpolate rotation using slerp
				local currentRotation = remoteData.currentCFrame - remoteData.currentCFrame.Position
				local targetRotation = remoteData.targetCFrame - remoteData.targetCFrame.Position
				local newRotation = currentRotation:Lerp(targetRotation, interpolationProgress)
				
				-- Update current CFrame
				remoteData.currentCFrame = CFrame.new(newPosition) * newRotation
				
				-- Apply to character (the snake controller will handle the body)
				if head.Parent and head.Parent:IsA("Model") then
					-- Use a smoother method that doesn't interfere with physics
					local rootPart = head.Parent:FindFirstChild("HumanoidRootPart")
					if rootPart then
						rootPart.CFrame = remoteData.currentCFrame
					else
						head.CFrame = remoteData.currentCFrame
					end
				end
			end
		end
	end
end

function SnakeNetworkHandler:Destroy()
	-- Cleanup if needed
	self.remoteSnakes = {}
end

return SnakeNetworkHandler