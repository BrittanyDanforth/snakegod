-- VFXHandler_Client LocalScript
-- Place this in: StarterPlayer > StarterPlayerScripts
-- Handles client-side visual effects for revive and other events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Wait for the Remotes folder and the specific event to exist
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveEffectRemote = remotes:WaitForChild("PlayerRevivedEffect")

-- This LocalScript is on the client, so it can correctly listen for OnClientEvent
reviveEffectRemote.OnClientEvent:Connect(function()
    print("✅ VFXHandler_Client received the 'PlayerRevivedEffect' command from the server.")
    
    -- To keep the orb GONE, this function remains empty. This is your
    -- master "OFF" switch, and it is now in the correct location (a LocalScript).
    
    -- If you ever wanted to add a revive effect (particles, sounds, lights),
    -- you would write that code right here. For example:
    --[[
    local player = Players.LocalPlayer
    local character = player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        -- Create a sphere part
        local orb = Instance.new("Part")
        orb.Name = "ReviveOrb"
        orb.Shape = Enum.PartType.Ball
        orb.Material = Enum.Material.ForceField
        orb.Size = Vector3.new(4, 4, 4)
        orb.Color = Color3.fromRGB(100, 200, 255)
        orb.Anchored = true
        orb.CanCollide = false
        orb.Position = character.HumanoidRootPart.Position
        orb.Parent = workspace
        
        -- Add PointLight
        local light = Instance.new("PointLight")
        light.Brightness = 3
        light.Range = 20
        light.Color = Color3.fromRGB(100, 200, 255)
        light.Parent = orb
        
        -- Animate the orb
        local startTime = tick()
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local elapsed = tick() - startTime
            if elapsed > 2 then
                orb:Destroy()
                connection:Disconnect()
                return
            end
            
            -- Expand and fade
            local scale = 1 + (elapsed * 2)
            orb.Size = Vector3.new(4, 4, 4) * scale
            orb.Transparency = elapsed / 2
            light.Brightness = 3 * (1 - elapsed / 2)
        end)
    end
    ]]
end)

print("VFXHandler_Client loaded and listening for revive effects")