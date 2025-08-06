--[[
CLIENT SNAKE INTERPOLATION
This LocalScript handles smooth visual interpolation of other players' snakes
to eliminate network lag and create fluid movement
Place in StarterPlayer > StarterPlayerScripts
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local batchUpdateEvent = remoteEvents:WaitForChild("BatchSnakeUpdate")

-- Store interpolation data for each remote snake
local snakeInterpolationData = {}
local INTERPOLATION_SPEED = 0.15 -- How quickly snakes catch up to their true position (0-1)
local POSITION_BUFFER_SIZE = 3 -- Number of position updates to store for prediction

-- Helper function to get or create interpolation data for a player
local function getInterpolationData(playerId)
	if not snakeInterpolationData[playerId] then
		snakeInterpolationData[playerId] = {
			targetPosition = Vector3.new(0, 0, 0),
			targetLookVector = Vector3.new(0, 0, -1),
			currentPosition = Vector3.new(0, 0, 0),
			currentLookVector = Vector3.new(0, 0, -1),
			positionBuffer = {},
			lastUpdateTime = tick(),
			velocity = Vector3.new(0, 0, 0)
		}
	end
	return snakeInterpolationData[playerId]
end

-- Calculate velocity for extrapolation during network delays
local function updateVelocity(data, newPosition)
	local timeDelta = tick() - data.lastUpdateTime
	if timeDelta > 0 and timeDelta < 0.5 then -- Ignore if too much time has passed
		data.velocity = (newPosition - data.targetPosition) / timeDelta
	else
		data.velocity = Vector3.new(0, 0, 0)
	end
end

-- Listen for batched snake updates from the server
batchUpdateEvent.OnClientEvent:Connect(function(allSnakeData)
	for _, snakeData in ipairs(allSnakeData) do
		-- Skip the local player's snake (they control their own)
		if snakeData.PlayerId ~= localPlayer.UserId then
			local data = getInterpolationData(snakeData.PlayerId)
			
			-- Update velocity for extrapolation
			updateVelocity(data, snakeData.Position)
			
			-- Store the new target position and orientation
			data.targetPosition = snakeData.Position
			data.targetLookVector = snakeData.LookVector
			data.lastUpdateTime = tick()
			
			-- Add to position buffer for prediction
			table.insert(data.positionBuffer, 1, {
				position = snakeData.Position,
				time = tick()
			})
			
			-- Keep buffer size limited
			if #data.positionBuffer > POSITION_BUFFER_SIZE then
				table.remove(data.positionBuffer)
			end
		end
	end
end)

-- Find the visual snake model for a player
local function findSnakeModel(playerName)
	-- Look for the snake model in workspace
	local snakeModel = workspace:FindFirstChild("Snake_" .. playerName)
	if snakeModel then
		return snakeModel
	end
	
	-- Also check if the model is directly under the player's character
	local player = Players:FindFirstChild(playerName)
	if player and player.Character then
		local model = player.Character:FindFirstChild("SnakeModel")
		if model then
			return model
		end
	end
	
	return nil
end

-- Smooth interpolation update loop
RunService.RenderStepped:Connect(function(deltaTime)
	for playerId, data in pairs(snakeInterpolationData) do
		local player = Players:GetPlayerByUserId(playerId)
		if player and player.Character then
			-- Find the visual snake model
			local snakeModel = findSnakeModel(player.Name)
			
			if snakeModel then
				-- Get the head segment (primary part)
				local headSegment = snakeModel:FindFirstChild("Segment0_Head") or snakeModel:FindFirstChild("Head")
				
				if headSegment then
					-- Extrapolate position based on velocity if we haven't received an update recently
					local timeSinceUpdate = tick() - data.lastUpdateTime
					local extrapolatedTarget = data.targetPosition
					
					if timeSinceUpdate < 0.2 then -- Only extrapolate for small time gaps
						extrapolatedTarget = data.targetPosition + (data.velocity * timeSinceUpdate)
					end
					
					-- Smoothly interpolate position
					data.currentPosition = data.currentPosition:Lerp(extrapolatedTarget, INTERPOLATION_SPEED)
					
					-- Smoothly interpolate look direction
					data.currentLookVector = data.currentLookVector:Lerp(data.targetLookVector, INTERPOLATION_SPEED * 1.5)
					
					-- Apply the interpolated position and orientation to the head
					local targetCFrame = CFrame.lookAt(
						data.currentPosition,
						data.currentPosition + data.currentLookVector
					)
					
					-- Update the head position
					headSegment.CFrame = targetCFrame
					
					-- If using a model with PrimaryPart, also update that
					if snakeModel.PrimaryPart == headSegment then
						snakeModel:SetPrimaryPartCFrame(targetCFrame)
					end
				end
			else
				-- Initialize current position to target if we just found the model
				data.currentPosition = data.targetPosition
				data.currentLookVector = data.targetLookVector
			end
		else
			-- Clean up data for disconnected players
			snakeInterpolationData[playerId] = nil
		end
	end
end)

-- Clean up when players leave
Players.PlayerRemoving:Connect(function(player)
	snakeInterpolationData[player.UserId] = nil
end)

print("✅ Client Snake Interpolation loaded!")