--[[
    RemoteEvents Configuration
    This file documents all RemoteEvents used in the game for direct server-client communication
]]

local RemoteEvents = {
    -- Direct command from SnakeCollisionHandler to GamepassHandler
    -- Fired when a player successfully revives, ensuring perfect timing
    PlayerRevivedEffect = "PlayerRevivedEffect",
    
    -- Additional aggressive cleanup signals
    ForceCleanupEffects = "ForceCleanupEffects",
    EmergencyOrbRemoval = "EmergencyOrbRemoval",
    
    -- Status confirmation events
    EffectCleanupConfirmed = "EffectCleanupConfirmed"
}

return RemoteEvents