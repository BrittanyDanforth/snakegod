-- VFXHandler_Client LocalScript
-- Place this in: StarterPlayer > StarterPlayerScripts
-- Handles client-side visual effects for revive and other events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Get VFXManager module
local VFXManager = require(ReplicatedStorage:WaitForChild("VFXManager"))

-- Wait for the Remotes folder and the specific event to exist
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveEffectRemote = remotes:WaitForChild("PlayerRevivedEffect")

-- Function to create revival VFX using VFXManager's style
local function createReviveVFX()
    local player = Players.LocalPlayer
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    -- Check if effects are disabled
    if player:GetAttribute("NoDeathEffects") or player:GetAttribute("DisableClientOrbs") then
        return
    end
    
    -- Get graphics settings
    local graphicsMode = player:GetAttribute("GraphicsMode") or "High"
    local settings = VFXManager.getGraphicsSettings(graphicsMode)
    
    if not settings.enabled then
        return -- Effects disabled for this graphics mode
    end
    
    local position = character.HumanoidRootPart.Position
    
    -- Create revival effect based on graphics settings
    if settings.orbGlow or settings.lightingEnabled then
        -- Create a glowing orb effect
        local part = Instance.new("Part")
        part.Name = "ReviveEffect"
        part.Shape = Enum.PartType.Ball
        part.Material = Enum.Material.ForceField
        part.Size = Vector3.new(6, 6, 6)
        part.Color = Color3.fromRGB(100, 255, 100) -- Green for revival
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Position = position
        part.Transparency = 0.3
        part.Parent = workspace.CurrentCamera or workspace
        
        if settings.lightingEnabled then
            local light = Instance.new("PointLight")
            light.Brightness = settings.glowBrightness * 1.5
            light.Range = settings.glowRange * 2
            light.Color = Color3.fromRGB(100, 255, 100)
            light.Parent = part
        end
        
        -- Animate expansion and fade
        local startTime = tick()
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local elapsed = tick() - startTime
            if elapsed > 1.5 then
                part:Destroy()
                connection:Disconnect()
                return
            end
            
            local scale = 1 + (elapsed * 2)
            part.Size = Vector3.new(6, 6, 6) * scale
            part.Transparency = 0.3 + (elapsed * 0.5)
        end)
    end
    
    -- Add particles if enabled
    if settings.orbParticles and settings.particleCount > 0 then
        local attachment = Instance.new("Attachment")
        attachment.Position = position
        attachment.Parent = workspace.CurrentCamera or workspace
        
        local emitter = Instance.new("ParticleEmitter")
        emitter.Color = ColorSequence.new(Color3.fromRGB(100, 255, 100), Color3.fromRGB(50, 200, 50))
        emitter.LightEmission = 1
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 2),
            NumberSequenceKeypoint.new(1, 0)
        })
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.8, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        })
        emitter.Speed = NumberRange.new(10, 20)
        emitter.Lifetime = NumberRange.new(0.5, 1)
        emitter.Rate = 0
        emitter.SpreadAngle = Vector2.new(360, 360)
        emitter.Parent = attachment
        
        -- Emit burst of particles
        emitter:Emit(settings.particleCount * 2)
        
        -- Clean up
        task.delay(2, function()
            if attachment and attachment.Parent then
                attachment:Destroy()
            end
        end)
    end
end

-- This LocalScript is on the client, so it can correctly listen for OnClientEvent
reviveEffectRemote.OnClientEvent:Connect(function()
    print("✅ VFXHandler_Client received the 'PlayerRevivedEffect' command from the server.")
    
    -- To keep the revival effect GONE, leave this commented out:
    -- createReviveVFX()
    
    -- Uncomment the line above if you want to enable revival VFX
    -- The VFX will respect the player's graphics settings automatically
end)

print("VFXHandler_Client loaded and listening for revive effects")