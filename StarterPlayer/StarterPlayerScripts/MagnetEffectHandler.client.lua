--[[
    MagnetEffectHandler.client.lua
    Handles disabling magnet visual effects on death
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Wait for remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes then
    warn("[MagnetEffectHandler] Could not find Remotes folder")
    return
end

-- Get or create the disable magnet remote
local disableMagnetRemote = remotes:FindFirstChild("DisableMagnetEffect") or remotes:WaitForChild("DisableMagnetEffect", 5)
if not disableMagnetRemote then
    warn("[MagnetEffectHandler] Could not find DisableMagnetEffect remote")
    return
end

-- Function to disable all magnet effects
local function disableMagnetEffects()
    warn("[MagnetEffectHandler] Disabling magnet effects for local player")
    
    local character = player.Character
    if not character then return end
    
    -- Find and disable any magnet effects in the character
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            local name = desc.Name:lower()
            -- Check for magnet-related names or purple color
            if name:find("magnet") or name:find("attract") or name:find("pull") or name:find("orb") then
                desc.Enabled = false
                task.wait()
                desc:Destroy()
            end
        elseif desc:IsA("Beam") then
            local name = desc.Name:lower()
            if name:find("magnet") or name:find("attract") then
                desc.Enabled = false
                task.wait()
                desc:Destroy()
            end
        elseif desc:IsA("Attachment") then
            -- Check children of attachments
            for _, child in ipairs(desc:GetChildren()) do
                if child:IsA("ParticleEmitter") or child:IsA("Beam") then
                    child.Enabled = false
                    task.wait()
                    child:Destroy()
                end
            end
        end
    end
    
    -- Also check workspace for any lingering effects tied to the player
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") and obj:GetAttribute("PlayerOwner") == player.Name then
            obj.Enabled = false
            obj:Destroy()
        end
    end
end

-- Listen for the disable magnet effect signal
disableMagnetRemote.OnClientEvent:Connect(disableMagnetEffects)

-- Also disable on character death
player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        humanoid.Died:Connect(function()
            -- Small delay to ensure effects are created before we destroy them
            task.wait(0.1)
            disableMagnetEffects()
        end)
    end
end)

print("[MagnetEffectHandler] Magnet effect handler initialized")