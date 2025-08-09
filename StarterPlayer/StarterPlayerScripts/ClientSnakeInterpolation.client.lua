-- ClientSnakeInterpolation: listens for BatchSnakeUpdate and caches data for interpolation
-- Prevents remote queue exhaustion by ensuring an OnClientEvent listener exists

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local lastBatch = nil
local lastBatchTime = 0

local function attachListenerTo(event)
	if not event then return end
	if event.OnClientEvent then
		event.OnClientEvent:Connect(function(allSnakes)
			lastBatch = allSnakes
			lastBatchTime = tick()
			-- Optionally: update remote snake proxies here
		end)
		return true
	end
	return false
end

local function tryAttach()
	-- Prefer Remotes
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local ev = remotes:FindFirstChild("BatchSnakeUpdate")
		if ev and attachListenerTo(ev) then return end
		remotes.ChildAdded:Connect(function(child)
			if child.Name == "BatchSnakeUpdate" then
				attachListenerTo(child)
			end
		end)
	end
	-- Fallback to RemoteEvents
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if remoteEvents then
		local ev2 = remoteEvents:FindFirstChild("BatchSnakeUpdate")
		if ev2 and attachListenerTo(ev2) then return end
		remoteEvents.ChildAdded:Connect(function(child)
			if child.Name == "BatchSnakeUpdate" then
				attachListenerTo(child)
			end
		end)
	end
	-- Root-level fallback (legacy)
	local rootEv = ReplicatedStorage:FindFirstChild("BatchSnakeUpdate")
	if rootEv then
		attachListenerTo(rootEv)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "BatchSnakeUpdate" then
			attachListenerTo(child)
		end
	end)
end

tryAttach()

-- Optional interpolation tick (no-op placeholder so we can wire later without churn)
RunService.Heartbeat:Connect(function()
	if not lastBatch then return end
	-- Interpolate remote snakes here if/when visual proxies are implemented
end)