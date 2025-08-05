-- DeathVFXConfig.lua
-- Easy configuration for death visual effects

local DeathVFXConfig = {
	-- Main death particle colors (can be any colors you want)
	DEATH_COLORS = {
		primary = Color3.fromRGB(147, 51, 255),    -- Purple (change to any color)
		secondary = Color3.fromRGB(0, 255, 127),   -- Green (change to any color)
		glow = Color3.fromRGB(255, 255, 255),      -- White glow
	},
	
	-- Particle settings
	PARTICLES = {
		count = 30,               -- Number of particles
		lifetime = 1.5,           -- How long particles last
		speed = 50,              -- Particle speed
		spread = 360,            -- Spread angle
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 1.5),
			NumberSequenceKeypoint.new(1, 0)
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1)
		})
	},
	
	-- Death orb spawn settings
	DEATH_ORBS = {
		color = Color3.fromRGB(255, 215, 0),      -- Gold orbs
		glowColor = Color3.fromRGB(255, 255, 150), -- Light yellow glow
		material = Enum.Material.Neon,
		transparency = 0.3
	},
	
	-- Revival effect colors
	REVIVAL_COLORS = {
		primary = Color3.fromRGB(100, 255, 100),   -- Light green
		secondary = Color3.fromRGB(50, 200, 50),   -- Darker green
		glow = Color3.fromRGB(150, 255, 150)       -- Bright green glow
	}
}

return DeathVFXConfig