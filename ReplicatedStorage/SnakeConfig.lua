
-- Player snake config is in SnakeSystemIntegration's DEFAULT_CONFIG
-- This is a ModuleScript inside ReplicatedStorage

return {
	-- SNAKE DIMENSIONS
	HeadSize = Vector3.new(3, 3, 3),
	SegmentSize = Vector3.new(2.5, 2.5, 2.5),
	SegmentSpacing = 2.2,
	SegmentGap = 3.0, -- For SnakeMovement path system

	-- BODY SETTINGS (FOR AI ONLY - Players use SnakeSystemIntegration)
	InitialLength = 100,      -- AI spawns with 100 segments for proper visual size
	MaxSegments = 2450,

	-- ENHANCED COLORS (Default skin - better green gradient)
	HeadColor = Color3.fromRGB(76, 217, 100),
	BodyColors = {
		Color3.fromRGB(60, 180, 80),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(100, 220, 120),
		Color3.fromRGB(80, 200, 100),
		Color3.fromRGB(60, 180, 80),
	},
	SegmentColor = Color3.fromRGB(80, 200, 100), -- For SnakeMovement

	-- MOVEMENT SETTINGS
	FollowSpeed = 0.95,
	BoostFollowSpeed = 0.99,
	UpdateRate = 1,
	MinDistance = 0.02,
	PathSmoothness = 0.9,

	-- MATERIALS
	HeadMaterial = Enum.Material.ForceField,
	BodyMaterial = Enum.Material.Neon,

	-- VISUAL ENHANCEMENTS
	GlowIntensity = 1.5,
	GlowRange = 4,
	LODDistance = 120, -- Level of detail distance

	-- GAMEPLAY SETTINGS
	OrbValue = 5,           -- Each orb gives 5 segments (was 1)
	BoostDrainRate = 3,     -- Boost drains faster

	-- DEATH ORB VALUES (percentage of snake length returned as orbs)
	DeathOrbReturn = {
		small = 0.30,       -- Small snakes (< 100): return 30%
		medium = 0.25,      -- Medium snakes (100-200): return 25%
		large = 0.20,       -- Large snakes (200-500): return 20%
		huge = 0.15,        -- Huge snakes (500+): return 15%
		cap = 150           -- Max value from death orbs
	},

	-- AI SNAKE SPECIFIC SETTINGS
	AI = {
		-- Movement
		BaseSpeed = 10,          -- Base movement speed for AI
		BoostSpeed = 24,         -- Boost speed for AI
		TurnSpeed = 1.8,         -- Turn rate for AI (higher = sharper turns)

		-- Visual adjustments
		BeamWidthMultiplier = 0.9,  -- Slightly smaller beams for AI
		GlowIntensity = 1.8,        -- Slightly dimmer glow for AI

		-- Behavior settings
		OrbSeekRange = 80,       -- How far AI looks for orbs
		ThreatDetectionRange = 60, -- How far AI detects threats
		BoostChance = 0.15,      -- Base chance to boost per frame

		-- Growth settings
		MaxLength = 2000,        -- AI max length (capped for performance)
	}
}
