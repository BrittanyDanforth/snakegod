--[[
    REVIVE SYSTEM FIX
    
    Place this in ServerScriptService to ensure revive system works properly.
    This script patches the revive flow to work even if old handlers interfere.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Wait for systems to load
task.wait(1)

warn("🔧 REVIVE SYSTEM FIX: Starting...")

-- Get remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local promptRevive = remotes:FindFirstChild("PromptRevive")

if not promptRevive then
    warn("❌ REVIVE FIX: PromptRevive remote not found!")
    return
end

-- Track active revive sessions to prevent duplicates
local activeReviveSessions = {}
local revivedPlayers = {} -- Track who just revived

-- Override the PromptRevive handler to ensure it works
local existingConnections = getconnections(promptRevive.OnServerEvent)
warn("🔍 REVIVE FIX: Found", #existingConnections, "existing connections to PromptRevive")

-- Create our own high-priority handler
promptRevive.OnServerEvent:Connect(function(player, response)
    -- Check if this player has an active session
    if not activeReviveSessions[player] then
        return -- Not our session
    end
    
    warn("✅ REVIVE FIX: Received response from", player.Name, ":", response)
    
    -- Clear the session
    local sessionData = activeReviveSessions[player]
    activeReviveSessions[player] = nil
    
    if response == "revive" then
        warn("🔄 REVIVE FIX: Processing revive for", player.Name)
        
        -- Mark as revived
        revivedPlayers[player] = true
        
        -- Ensure revival attributes are set
        player:SetAttribute("JustRevived", true)
        player:SetAttribute("RevivingNow", true)
        
        -- Use revive token
        local currentRevives = player:GetAttribute("RevivesAvailable") or 0
        if currentRevives > 0 then
            player:SetAttribute("RevivesAvailable", currentRevives - 1)
            warn("✅ REVIVE FIX: Used revive token. Remaining:", currentRevives - 1)
        end
        
        -- Force respawn after a short delay (simulating countdown)
        task.wait(3) -- 3 second countdown
        
        warn("🔄 REVIVE FIX: Respawning", player.Name)
        player:LoadCharacter()
        
        -- Clear revived flag after spawn
        task.wait(1)
        revivedPlayers[player] = nil
    else
        warn("❌ REVIVE FIX: Player declined revive")
        -- Kill the humanoid if they haven't already died
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                humanoid.Health = 0
            end
        end
    end
end)

-- Monitor for dying players and ensure they get revive prompts
local function onCharacterAdded(character)
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end
    
    local humanoid = character:WaitForChild("Humanoid")
    
    -- Clear any revival flags on spawn
    if not revivedPlayers[player] then
        player:SetAttribute("JustRevived", false)
        player:SetAttribute("RevivingNow", false)
    end
    
    humanoid.Died:Connect(function()
        -- Check if already handling
        if activeReviveSessions[player] then
            return
        end
        
        -- Check for revives
        local revivesAvailable = player:GetAttribute("RevivesAvailable") or 0
        if revivesAvailable > 0 then
            warn("🔧 REVIVE FIX: Player", player.Name, "died with", revivesAvailable, "revives")
            
            -- Create session
            activeReviveSessions[player] = {
                startTime = tick(),
                revivesAvailable = revivesAvailable
            }
            
            -- Send revive prompt
            task.wait(0.5) -- Small delay to ensure client is ready
            promptRevive:FireClient(player, {
                revivesLeft = revivesAvailable,
                deathCause = player:GetAttribute("KilledBy") or "Unknown"
            })
            
            -- Timeout after 10 seconds
            task.wait(10)
            if activeReviveSessions[player] then
                warn("⏰ REVIVE FIX: Revive timed out for", player.Name)
                activeReviveSessions[player] = nil
                
                -- Ensure they're dead
                if player.Character then
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        hum.Health = 0
                    end
                end
            end
        end
    end)
end

-- Connect to all players
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(onCharacterAdded)
end)

-- Handle existing players
for _, player in pairs(Players:GetPlayers()) do
    if player.Character then
        onCharacterAdded(player.Character)
    end
end

-- Also try to disable the old collision handler more aggressively
task.spawn(function()
    task.wait(2) -- Wait for everything to load
    
    local oldHandler = game.ServerScriptService:FindFirstChild("SnakeCollisionHandler_FINAL")
    if oldHandler and oldHandler:IsA("Script") then
        oldHandler.Disabled = true
        warn("✅ REVIVE FIX: Disabled old SnakeCollisionHandler_FINAL")
    end
    
    -- Also check workspace
    oldHandler = workspace:FindFirstChild("SnakeCollisionHandler_FINAL")
    if oldHandler and oldHandler:IsA("Script") then
        oldHandler.Disabled = true
        warn("✅ REVIVE FIX: Disabled old handler in workspace")
    end
end)

warn("✅ REVIVE SYSTEM FIX: Loaded successfully!")
warn("📝 This fix ensures revives work even if other systems interfere")