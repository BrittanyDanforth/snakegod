--[[
    Config.module - Centralized game configuration
    Shared between client and server for consistent settings
]]

local Config = {}

-- Snake Configuration
Config.Snake = {
    baseSpeed = 16,
    baseLength = 3,
    segmentSize = Vector3.new(4, 4, 4),
    segmentSpacing = 3.5,
    turnSpeed = 0.15,
    maxLength = 1000,
    colors = {
        default = Color3.new(0, 1, 0),
        -- Add more color options
    }
}

-- Collision Configuration
Config.Collision = {
    headRadius = 3.5,
    bodyDistance = 2.8,
    orbCollectionRadius = 5,
    selfCollisionIgnoreSegments = 10,
    frameSkip = 3, -- Check every N frames
    maxChecksPerFrame = 50
}

-- Death and Respawn Configuration
Config.Death = {
    orbSpawnPercentage = 0.7, -- Spawn 70% of length as orbs
    maxDeathOrbs = 50,
    orbSpawnDelay = 0.03,
    deathAnimationDuration = 2,
    reviveCountdown = 5,
    spawnInvincibilityDuration = 3
}

-- Map Configuration
Config.Map = {
    size = 1000,
    borderThickness = 10,
    gridSize = 50 -- For spatial partitioning if needed
}

-- Orb Configuration
Config.Orbs = {
    baseValue = 1,
    spawnHeight = 5,
    minSpacing = 3,
    batchSize = 8,
    maxOrbsPerArea = 100,
    respawnDelay = 2
}

-- Performance Configuration
Config.Performance = {
    adaptiveLODThreshold = 100,
    extremeLengthThreshold = 500,
    ultraLengthThreshold = 1000,
    cacheExpiryTime = 1.5,
    yieldInterval = 150,
    networkCompensation = 0.1
}

-- AI Snake Configuration
Config.AI = {
    enabled = true,
    maxCount = 10,
    spawnDelay = 5,
    minSpeed = 12,
    maxSpeed = 20,
    behaviorUpdateRate = 0.5,
    visionRange = 50
}

-- Power-Up Configuration
Config.PowerUps = {
    speedBoost = {
        duration = 10,
        multiplier = 1.5
    },
    ghostMode = {
        duration = 5,
        cooldown = 30
    },
    -- Add more power-ups
}

-- UI Configuration
Config.UI = {
    reviveButtonTimeout = 10,
    scorePopupDuration = 1,
    leaderboardMaxEntries = 10
}

-- Debug Configuration
Config.Debug = {
    collisions = false,
    movement = false,
    stateMachine = false,
    performance = false
}

-- Get a nested config value safely
function Config:get(path, default)
    local value = self
    for key in path:gmatch("[^%.]+") do
        value = value[key]
        if value == nil then
            return default
        end
    end
    return value
end

-- Validate configuration
function Config:validate()
    assert(self.Snake.baseSpeed > 0, "Base speed must be positive")
    assert(self.Snake.baseLength > 0, "Base length must be positive")
    assert(self.Map.size > 0, "Map size must be positive")
    assert(self.Death.reviveCountdown > 0, "Revive countdown must be positive")
    return true
end

-- Initialize
Config:validate()

return Config