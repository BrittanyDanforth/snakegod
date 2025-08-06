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
    "ResumeSnakeMovement",   -- For resuming snake movement after revive
    "PromptRevive",          -- For prompting player to revive
    "ReviveResponse",        -- For player's response to revive prompt
    "ControlDeathUI",        -- For controlling death UI visibility
    "UpdateMouseDirection",  -- For client sending mouse direction to server
    "UpdateBoostState"       -- For client sending boost state to server
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

-- Also create RemoteEvents folder for backward compatibility
local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not remoteEventsFolder then
    remoteEventsFolder = Instance.new("Folder")
    remoteEventsFolder.Name = "RemoteEvents"
    remoteEventsFolder.Parent = ReplicatedStorage
end

-- Create the specific events that some scripts look for in RemoteEvents folder
local backwardCompatEvents = {"UpdateMouseDirection", "UpdateBoostState"}
for _, eventName in ipairs(backwardCompatEvents) do
    if not remoteEventsFolder:FindFirstChild(eventName) then
        local remoteEvent = Instance.new("RemoteEvent")
        remoteEvent.Name = eventName
        remoteEvent.Parent = remoteEventsFolder
        print("Created RemoteEvent in RemoteEvents folder:", eventName)
    end
end

print("RemoteEvents setup complete")