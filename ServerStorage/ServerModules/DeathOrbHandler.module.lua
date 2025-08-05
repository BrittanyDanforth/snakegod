--[[
    DeathOrbHandler.module - Handles death orb spawning and cleanup
    Replaces the old SnakeCollisionHandler orb spawning
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")

local DeathOrbHandler = {}
DeathOrbHandler.__index = DeathOrbHandler

-- Configuration
local ORB_CONFIG = {
    SPAWN_HEIGHT = 5,
    MAX_ORBS_PER_SNAKE = 50,
    ORB_LIFETIME = 60, -- seconds
    CLEANUP_RADIUS = 100, -- studs around revive position
    MIN_ORBS = 3,
    ORB_VALUE_MULTIPLIER = 0.3
}

-- Track spawned orbs for cleanup
local spawnedOrbs = {}

function DeathOrbHandler.new()
    local self = setmetatable({}, DeathOrbHandler)
    self:setupOrbFolder()
    self:setupOrbCleanup()
    return self
end

function DeathOrbHandler:setupOrbFolder()
    if not workspace:FindFirstChild("Orbs") then
        local orbsFolder = Instance.new("Folder")
        orbsFolder.Name = "Orbs"
        orbsFolder.Parent = workspace
    end
end

function DeathOrbHandler:setupOrbCleanup()
    -- Monitor for new orbs and add auto-cleanup
    workspace.Orbs.ChildAdded:Connect(function(orb)
        if orb.Name == "DeathOrb" and orb:IsA("BasePart") then
            -- Schedule auto-cleanup
            task.spawn(function()
                task.wait(ORB_CONFIG.ORB_LIFETIME)
                if orb and orb.Parent then
                    orb:Destroy()
                end
            end)
        end
    end)
end

function DeathOrbHandler:spawnDeathOrb(position, value)
    local orbsFolder = workspace:FindFirstChild("Orbs")
    if not orbsFolder then return end
    
    -- Create orb part
    local orb = Instance.new("Part")
    orb.Name = "DeathOrb"
    orb.Size = Vector3.new(3, 3, 3)
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Neon
    orb.TopSurface = Enum.SurfaceType.Smooth
    orb.BottomSurface = Enum.SurfaceType.Smooth
    orb.Anchored = true
    orb.CanCollide = false
    
    -- Purple color for death orbs
    orb.BrickColor = BrickColor.new("Royal purple")
    
    -- Position
    orb.Position = Vector3.new(position.X, ORB_CONFIG.SPAWN_HEIGHT, position.Z)
    
    -- Add value attribute
    orb:SetAttribute("OrbValue", value)
    orb:SetAttribute("IsDeathOrb", true)
    
    -- Add to workspace
    orb.Parent = orbsFolder
    
    -- Add floating effect
    local floatHeight = 0.5
    local floatSpeed = 2
    local startY = orb.Position.Y
    
    task.spawn(function()
        while orb and orb.Parent do
            orb.Position = orb.Position + Vector3.new(0, math.sin(tick() * floatSpeed) * 0.01, 0)
            task.wait()
        end
    end)
    
    return orb
end

function DeathOrbHandler:spawnDeathOrbsForPlayer(player, snakeLength, deathPosition)
    -- Calculate orb distribution
    local totalOrbs = math.clamp(
        math.floor(snakeLength * 0.4), 
        ORB_CONFIG.MIN_ORBS, 
        ORB_CONFIG.MAX_ORBS_PER_SNAKE
    )
    local orbValue = math.max(1, math.floor(snakeLength * ORB_CONFIG.ORB_VALUE_MULTIPLIER / totalOrbs))
    
    print(string.format("💎 Spawning %d death orbs for %s (length: %d, value: %d each)", 
        totalOrbs, player.Name, snakeLength, orbValue))
    
    -- Get snake segments if available
    local snakeFolder = workspace:FindFirstChild("SnakeFolder")
    local visualSnake = snakeFolder and snakeFolder:FindFirstChild("Snake_" .. player.Name)
    local segments = {}
    
    if visualSnake then
        -- Collect segment positions
        for _, child in ipairs(visualSnake:GetChildren()) do
            if child:IsA("BasePart") and child.Name:match("^Segment%d+") then
                table.insert(segments, child.Position)
            end
        end
    end
    
    -- Spawn orbs along snake body or at death position
    if #segments > 0 then
        -- Distribute along snake body
        local step = math.max(1, math.floor(#segments / totalOrbs))
        for i = 1, totalOrbs do
            local segmentIndex = math.min(i * step, #segments)
            local position = segments[segmentIndex]
            
            -- Small random offset
            local offset = Vector3.new(
                (math.random() - 0.5) * 2,
                0,
                (math.random() - 0.5) * 2
            )
            
            self:spawnDeathOrb(position + offset, orbValue)
            
            if i % 5 == 0 then
                task.wait() -- Small yield to prevent lag
            end
        end
    else
        -- Fallback: spawn in spiral pattern around death position
        local angleStep = (math.pi * 2) / totalOrbs
        local radius = 3
        
        for i = 1, totalOrbs do
            local angle = i * angleStep
            local offset = Vector3.new(
                math.cos(angle) * radius * (i / totalOrbs * 2),
                0,
                math.sin(angle) * radius * (i / totalOrbs * 2)
            )
            
            self:spawnDeathOrb(deathPosition + offset, orbValue)
            
            if i % 5 == 0 then
                task.wait()
            end
        end
    end
end

function DeathOrbHandler:cleanupOrbsNearPosition(position, radius)
    radius = radius or ORB_CONFIG.CLEANUP_RADIUS
    local orbsFolder = workspace:FindFirstChild("Orbs")
    if not orbsFolder then return end
    
    local cleaned = 0
    for _, orb in ipairs(orbsFolder:GetChildren()) do
        if orb.Name == "DeathOrb" and orb:IsA("BasePart") then
            local distance = (orb.Position - position).Magnitude
            if distance <= radius then
                orb:Destroy()
                cleaned = cleaned + 1
            end
        end
    end
    
    if cleaned > 0 then
        print("🧹 Cleaned", cleaned, "death orbs near position")
    end
end

return DeathOrbHandler