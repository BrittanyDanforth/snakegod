--[[
    RemoteEventsSetup - Creates necessary RemoteEvents for the game systems
    This script should run before other systems to ensure RemoteEvents exist
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Add a small delay to ensure ReplicatedStorage is ready
RunService.Heartbeat:Wait()

-- Create Remotes folder if it doesn't exist
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage
end

-- List of RemoteEvents to create
local remoteEvents = {
    "ShowDeathScreen",        -- For showing death menu
    "SetSpectatorCamera",     -- For spectator camera control
    "RespawnSnake",          -- For respawning player
    "PlayerRevivedEffect",   -- For revive VFX
    "PlayerDeathEffect",     -- For death VFX
    "StopSnakeMovement",     -- For stopping client-side snake control
    "ResumeSnakeMovement"    -- For resuming snake movement after revive
}

-- Create each RemoteEvent if it doesn't exist
for _, eventName in ipairs(remoteEvents) do
    if not remotes:FindFirstChild(eventName) then
        local remoteEvent = Instance.new("RemoteEvent")
        remoteEvent.Name = eventName
        remoteEvent.Parent = remotes
        print("Created RemoteEvent:", eventName)
    end
end

print("RemoteEvents setup complete")