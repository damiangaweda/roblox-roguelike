--!strict
-- Every tunable number of the game, in one place (AGENTS.md rule 3).
-- Distances are studs, times are seconds.

local Types = require("./Core/Types")

local Config: Types.Config = {
	run = {
		durationSeconds = 15 * 60,
		zonesOpenAtSeconds = 10 * 60,
		zoneCount = 2,
		zoneRadius = 8,
		extractSeconds = 5,
		zonePoints = {
			{ x = -95, z = -95 },
			{ x = 95, z = -95 },
			{ x = -95, z = 95 },
			{ x = 95, z = 95 },
			{ x = 0, z = -105 },
			{ x = 0, z = 105 },
		},
		summarySeconds = 10,
		lateJoinSeconds = 60,
	},
	arena = {
		halfSize = 120,
	},
	player = {
		radius = 1.5,
		walkSpeed = 16,
		maxHealth = 100,
		downedSeconds = 15,
		reviveSeconds = 3,
		reviveRadius = 8,
		reviveHealthFraction = 0.5,
	},
	basicAttack = {
		damage = 10,
		intervalSeconds = 0.6,
		range = 40,
	},
	activeSkill = {
		damage = 40,
		cooldownSeconds = 6,
		range = 40,
		radius = 10,
	},
	horde = {
		maxAlive = 150,
		spawnPerSecondAtStart = 1.5,
		spawnPerSecondGrowthPerMinute = 0.6,
		spawnRingMin = 50,
		spawnRingMax = 70,
		bruteShareAtStart = 0,
		bruteShareGrowthPerMinute = 0.03,
		bruteShareMax = 0.3,
		separationRadius = 2.5,
		kinds = {
			grunt = { health = 20, speed = 10, contactDps = 6, xp = 1, radius = 1.5 },
			brute = { health = 80, speed = 7, contactDps = 20, xp = 4, radius = 2.5 },
		},
	},
	statuses = {
		burnSeconds = 3,
		burnDps = 4,
		chillSeconds = 2,
		chillSlow = 0.4,
	},
	synergy = {
		shatterMultiplier = 2,
	},
	perks = {
		offerSize = 3,
		quickHandsIntervalFactor = 0.85,
		toughnessHealth = 20,
		pool = {
			searingBolts = { name = "Searing Bolts", tags = { "fire" }, maxStacks = 1 },
			frostBolts = { name = "Frost Bolts", tags = { "ice" }, maxStacks = 1 },
			fireBlast = { name = "Fire Blast", tags = { "fire" }, maxStacks = 1 },
			iceBlast = { name = "Ice Blast", tags = { "ice" }, maxStacks = 1 },
			quickHands = { name = "Quick Hands", tags = {}, maxStacks = 5 },
			toughness = { name = "Toughness", tags = {}, maxStacks = 5 },
		},
	},
	progression = {
		xpToSecondLevel = 5,
		xpGrowth = 1.3,
	},
	net = {
		stepHz = 30,
		snapshotHz = 10,
		intentsPerSecond = 20,
	},
}

return Config
