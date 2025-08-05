--[[
    SIMPLE REVIVE FIX
    
    Place this in ServerScriptService alongside your MainServer.
    This ensures revives work by directly handling the flow.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

warn("🔧 SIMPLE REVIVE FIX: Loading...")

-- Get remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local promptRevive = remotes:WaitForChild("PromptRevive")

-- Track who we're waiting for a response from
local waitingForResponse = {}

-- Listen for revive responses
promptRevive.OnServerEvent:Connect(function(player, response)
    -- Only process if we're waiting for this player
    if not waitingForResponse[player] then
        return
    end
    
    warn("✅ SIMPLE REVIVE: Got response from", player.Name, ":", response)
    waitingForResponse[player] = nil
    
    if response == "revive" then
        -- Get current revives
        local revivesLeft = player:GetAttribute("RevivesAvailable") or 0
        if revivesLeft <= 0 then
            warn("❌ SIMPLE REVIVE: No revives left!")
            return
        end
        
        -- Use a revive
        player:SetAttribute("RevivesAvailable", revivesLeft - 1)
        warn("✅ SIMPLE REVIVE: Used revive. Remaining:", revivesLeft - 1)
        
        -- Store revival data
        local character = player.Character
        local deathPos = Vector3.new(0, 5, 0)
        local snakeLength = 55
        
        if character and character:FindFirstChild("HumanoidRootPart") then
            deathPos = character.HumanoidRootPart.Position
        end
        
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats and leaderstats:FindFirstChild("Length") then
            snakeLength = leaderstats.Length.Value
        end
        
        player:SetAttribute("ReviveSnakeLength", snakeLength)
        player:SetAttribute("RevivePosition", string.format("%.2f, %.2f, %.2f", deathPos.X, deathPos.Y, deathPos.Z))
        player:SetAttribute("JustRevived", true)
        player:SetAttribute("RevivingNow", true)
        
        -- Show countdown (optional)
        local countdown = remotes:FindFirstChild("UpdateReviveCountdown")
        if countdown then
            for i = 3, 1, -1 do
                countdown:FireClient(player, {
                    timeRemaining = i,
                    isReviving = true
                })
                task.wait(1)
            end
        else
            task.wait(3) -- Just wait 3 seconds
        end
        
        -- Respawn the player
        warn("🔄 SIMPLE REVIVE: Respawning", player.Name, "with length", snakeLength)
        player:LoadCharacter()
    end
end)

-- Monitor player deaths
local function onCharacterAdded(character)
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end
    
    local humanoid = character:WaitForChild("Humanoid")
    
    -- Watch for death
    local deathConnection
    deathConnection = humanoid.Died:Connect(function()
        -- Disconnect to prevent multiple fires
        deathConnection:Disconnect()
        
        -- Check if FSM already handled it (look for the prompt attributes)
        task.wait(0.5) -- Give FSM a chance
        
        if player:GetAttribute("RevivePromptActive") then
            -- FSM is handling it, just track that we're waiting
            waitingForResponse[player] = true
            warn("🔍 SIMPLE REVIVE: FSM is showing prompt, waiting for response")
            
            -- Timeout after 15 seconds
            task.wait(15)
            waitingForResponse[player] = nil
        else
            -- FSM didn't handle it, we'll do it ourselves
            local revivesLeft = player:GetAttribute("RevivesAvailable") or 0
            if revivesLeft > 0 then
                warn("🔧 SIMPLE REVIVE: FSM didn't show prompt, showing it ourselves")
                waitingForResponse[player] = true
                
                promptRevive:FireClient(player, {
                    revivesLeft = revivesLeft,
                    deathCause = player:GetAttribute("KilledBy") or "Unknown"
                })
                
                -- Timeout after 15 seconds
                task.wait(15)
                waitingForResponse[player] = nil
            end
        end
    end)
end

-- Connect to players
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(onCharacterAdded)
end)

-- Handle existing players
for _, player in pairs(Players:GetPlayers()) do
    if player.Character then
        onCharacterAdded(player.Character)
    end
end

warn("✅ SIMPLE REVIVE FIX: Ready!")
warn("📝 This ensures revives work even if the FSM fails")