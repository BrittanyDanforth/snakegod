--[[
    ReviveSystemTest.server.lua
    Debug script to test and fix the revive system
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for systems to initialize
task.wait(2)

-- Monitor player attributes
local function monitorPlayer(player)
    local function checkAttribute(name)
        player:GetAttributeChangedSignal(name):Connect(function()
            warn("[ReviveTest]", player.Name, name, "=", player:GetAttribute(name))
        end)
    end
    
    -- Monitor important attributes
    checkAttribute("RevivesAvailable")
    checkAttribute("RevivePromptActive")
    checkAttribute("AwaitingReviveResponse")
    checkAttribute("JustRevived")
    checkAttribute("RevivingNow")
    checkAttribute("IsReviving")
    checkAttribute("IsDead")
    checkAttribute("IsSpectating")
    checkAttribute("ReviveSnakeLength")
    checkAttribute("RevivePosition")
end

-- Monitor remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function monitorRemote(name)
    local remote = remotes:WaitForChild(name, 5)
    if remote then
        if remote:IsA("RemoteEvent") then
            warn("[ReviveTest] Found RemoteEvent:", name)
        elseif remote:IsA("RemoteFunction") then
            warn("[ReviveTest] Found RemoteFunction:", name)
        end
    else
        warn("[ReviveTest] Remote not found:", name)
    end
end

-- Check for important remotes
monitorRemote("PromptRevive")
monitorRemote("ReviveResponse")
monitorRemote("UpdateReviveCountdown")
monitorRemote("CancelRevive")
monitorRemote("SetSpectatorCamera")
monitorRemote("ControlDeathUI")

-- Monitor existing players
for _, player in ipairs(Players:GetPlayers()) do
    monitorPlayer(player)
end

-- Monitor new players
Players.PlayerAdded:Connect(monitorPlayer)

-- Test command to force revive attributes (for debugging)
Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        if msg == "/testrevive" then
            warn("[ReviveTest] Setting test revive attributes for", player.Name)
            player:SetAttribute("RevivesAvailable", 2)
            player:SetAttribute("HasRevive", true)
            warn("[ReviveTest] Revives set to 2")
        elseif msg == "/checkstates" then
            -- Try to get player controller
            local playerControllers = _G.PlayerControllers or {}
            local controller = playerControllers[player]
            if controller and controller.fsm then
                warn("[ReviveTest] Current FSM state:", controller.fsm:getCurrentState())
                warn("[ReviveTest] Available states:", table.concat(controller.fsm:getStateNames(), ", "))
            else
                warn("[ReviveTest] No controller found for player")
            end
        end
    end)
end)

warn("[ReviveTest] Revive system test script loaded")
warn("[ReviveTest] Commands: /testrevive (set revives), /checkstates (check FSM)")