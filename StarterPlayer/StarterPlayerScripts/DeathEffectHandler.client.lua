--[[
    DeathEffectHandler - Handles visual death effects on the client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Wait for remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotes then
    warn("[DeathEffectHandler] Could not find Remotes folder")
    return
end

local deathEffectRemote = remotes:WaitForChild("PlayerDeathEffect", 5)
if not deathEffectRemote then
    warn("[DeathEffectHandler] Could not find PlayerDeathEffect remote")
    return
end

-- Handle death effect
deathEffectRemote.OnClientEvent:Connect(function(deadPlayer, deathPosition)
    -- Create a simple particle effect at death position
    local effectPart = Instance.new("Part")
    effectPart.Name = "DeathEffect"
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.Size = Vector3.new(1, 1, 1)
    effectPart.Position = deathPosition
    effectPart.Transparency = 1
    effectPart.Parent = workspace
    
    -- Create particle emitter for death effect
    local particleEmitter = Instance.new("ParticleEmitter")
    particleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particleEmitter.Rate = 100
    particleEmitter.Lifetime = NumberRange.new(0.5, 1)
    particleEmitter.VelocityInheritance = 0
    particleEmitter.EmissionDirection = Enum.NormalId.Top
    particleEmitter.Speed = NumberRange.new(5, 15)
    particleEmitter.SpreadAngle = Vector2.new(360, 360)
    particleEmitter.Color = ColorSequence.new(Color3.new(1, 0.2, 0.2))
    particleEmitter.LightEmission = 1
    particleEmitter.LightInfluence = 0
    particleEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(0.5, 1.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    particleEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    particleEmitter.Parent = effectPart
    
    -- Stop emitting after a short burst
    task.wait(0.1)
    particleEmitter.Enabled = false
    
    -- Clean up after particles finish
    Debris:AddItem(effectPart, 2)
    
    -- Death sound removed - no audio on death
end)

print("[DeathEffectHandler] Death effect handler initialized")