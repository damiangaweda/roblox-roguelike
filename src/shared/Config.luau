--!strict
-- Every tunable number of the game, in one place (AGENTS.md rule 3), and the
-- data the run is made of: skills, passives, classes, enemy kinds and the
-- map (stage 3, criterion 2). Distances are studs, times seconds, angles
-- degrees, colours 0xRRGGBB. The mechanics and numbers start from Azeroth
-- Survivors scaled at 2.25 studs per yard; the names are ours.

local Types = require("./Core/Types")

local function skill(
	id: string,
	name: string,
	targeting: Types.Targeting,
	fields: { [string]: any }
): Types.SkillConfig
	local base: Types.SkillConfig = {
		id = id,
		name = name,
		targeting = targeting,
		toughest = false,
		damage = 0,
		cooldownSeconds = 2,
		range = 45,
		radius = 0,
		count = 1,
		durationSeconds = 0,
		speed = 0,
		knockback = 0,
		tags = {},
		effect = nil,
	}
	for key, value in fields do
		(base :: any)[key] = value
	end
	return base
end

local function passive(
	id: string,
	name: string,
	stat: Types.Stat,
	perRank: number
): Types.PassiveConfig
	return { id = id, name = name, stat = stat, perRank = perRank, maxRank = 5 }
end

-- An enemy kind; `fields` overrides the defaults of a grunt.
local function enemy(id: string, name: string, fields: { [string]: any }): Types.EnemyKindConfig
	local base: Types.EnemyKindConfig = {
		id = id,
		name = name,
		look = "grunt",
		role = "grunt",
		health = 10,
		speed = 9,
		radius = 1.5,
		damage = 2,
		xp = 1,
		colour = 0x8a9a5b,
		scale = 1,
		preferredRange = nil,
		attacks = {},
		blockArcDegrees = nil,
		diesOnAttack = nil,
		phaseHealthShare = nil,
		phaseAttackIndex = nil,
		phaseCooldownFactor = nil,
		phaseSpeedFactor = nil,
	}
	for key, value in fields do
		(base :: any)[key] = value
	end
	return base
end

local function attack(kind: Types.AttackKind, fields: { [string]: any }): Types.AttackConfig
	local base: Types.AttackConfig = {
		kind = kind,
		telegraphSeconds = 0.8,
		recoverSeconds = 0.5,
		cooldownSeconds = 3,
		range = 6,
		damage = 10,
		radius = 5,
		knockback = 0,
	}
	for key, value in fields do
		(base :: any)[key] = value
	end
	return base
end

local function slow(factor: number, seconds: number): Types.EffectConfig
	return { kind = "slow", factor = factor, seconds = seconds }
end

local function dot(
	status: "burning" | "bleeding" | "poisoned",
	dps: number,
	seconds: number
): Types.EffectConfig
	return { kind = "dot", status = status, dps = dps, seconds = seconds }
end

local skills: { Types.SkillConfig } = {
	-- Mage: frost, fire, arcane and one lightning chain.
	skill("rimeDart", "Rime Dart", "bolt", {
		damage = 12,
		cooldownSeconds = 1.3,
		range = 54,
		speed = 70,
		tags = { "ice" },
		effect = slow(0.5, 2.5),
	}),
	skill("emberOrb", "Ember Orb", "bolt", {
		damage = 20,
		cooldownSeconds = 2.4,
		range = 58,
		radius = 8,
		speed = 55,
		tags = { "fire" },
		effect = dot("burning", 3, 3),
	}),
	skill("glintVolley", "Glint Volley", "bolt", {
		damage = 6,
		cooldownSeconds = 1.9,
		range = 50,
		count = 3,
		speed = 90,
		tags = { "arcane" },
	}),
	skill("hoarfrostRing", "Hoarfrost Ring", "nova", {
		damage = 8,
		cooldownSeconds = 7,
		radius = 20,
		tags = { "ice" },
		effect = { kind = "root", seconds = 2.5 },
	}),
	skill("pulseBurst", "Pulse Burst", "nova", {
		damage = 10,
		cooldownSeconds = 2.8,
		radius = 16,
		knockback = 4,
		tags = { "arcane" },
	}),
	skill("sleetfall", "Sleetfall", "ground", {
		damage = 7,
		cooldownSeconds = 9,
		range = 45,
		radius = 16,
		durationSeconds = 6,
		tags = { "ice" },
		effect = slow(0.6, 1.5),
	}),
	skill("pyreCircle", "Pyre Circle", "ground", {
		damage = 14,
		cooldownSeconds = 8,
		range = 45,
		radius = 11,
		durationSeconds = 4,
		tags = { "fire" },
	}),
	skill("cinderSnap", "Cinder Snap", "strike", {
		damage = 26,
		cooldownSeconds = 3.5,
		range = 40,
		tags = { "fire" },
	}),
	skill("frostBreath", "Frost Breath", "cone", {
		damage = 14,
		cooldownSeconds = 4.5,
		radius = 25,
		tags = { "ice" },
		effect = slow(0.5, 3),
	}),
	skill("arcLash", "Arc Lash", "chain", {
		damage = 22,
		cooldownSeconds = 6,
		range = 35,
		radius = 14,
		count = 3,
		tags = { "lightning" },
	}),
	skill("sunflare", "Sunflare", "bolt", {
		toughest = true,
		damage = 70,
		cooldownSeconds = 6,
		range = 68,
		speed = 45,
		tags = { "fire" },
		effect = dot("burning", 6, 6),
	}),

	-- Warrior: steel, bleeding and the roar.
	skill("wideCut", "Wide Cut", "melee", {
		damage = 14,
		cooldownSeconds = 1.1,
		range = 12,
		count = 3,
		tags = { "physical" },
	}),
	skill("heavyBlow", "Heavy Blow", "melee", {
		damage = 28,
		cooldownSeconds = 1.6,
		range = 12,
		knockback = 6,
		tags = { "physical" },
		effect = { kind = "stun", seconds = 0.8 },
	}),
	skill("steelCyclone", "Steel Cyclone", "nova", {
		damage = 16,
		cooldownSeconds = 4,
		radius = 16,
		tags = { "physical", "bleed" },
		effect = dot("bleeding", 3, 4),
	}),
	skill("groundShock", "Ground Shock", "nova", {
		damage = 10,
		cooldownSeconds = 5,
		radius = 18,
		knockback = 5,
		tags = { "physical" },
		effect = slow(0.5, 3),
	}),
	skill("relentlessEdge", "Relentless Edge", "aura", {
		damage = 6,
		cooldownSeconds = 0.6,
		radius = 12,
		tags = { "physical" },
	}),
	skill("warRoar", "War Roar", "nova", {
		damage = 4,
		cooldownSeconds = 8,
		radius = 25,
		tags = { "physical" },
		effect = { kind = "weaken", factor = 0.5, seconds = 5 },
	}),
	skill("reaperStroke", "Reaper's Stroke", "strike", {
		damage = 40,
		cooldownSeconds = 2,
		range = 18,
		count = 2,
		tags = { "physical" },
		effect = { kind = "execute", factor = 0.3 },
	}),
	skill("cripplingStrike", "Crippling Strike", "melee", {
		damage = 48,
		cooldownSeconds = 3,
		range = 13,
		tags = { "physical", "bleed" },
		effect = dot("bleeding", 6, 5),
	}),
	skill("ironRiposte", "Iron Riposte", "thorns", {
		damage = 14,
		cooldownSeconds = 18,
		durationSeconds = 8,
		tags = { "physical" },
	}),
	skill("bulwark", "Bulwark", "shield", {
		damage = 40,
		cooldownSeconds = 20,
		durationSeconds = 6,
		tags = { "physical" },
	}),

	-- Archer: arrows, poison, traps and the falcon.
	skill("swiftArrow", "Swift Arrow", "bolt", {
		damage = 13,
		cooldownSeconds = 1,
		range = 63,
		speed = 110,
		tags = { "physical" },
	}),
	skill("fanOfArrows", "Fan of Arrows", "bolt", {
		damage = 10,
		cooldownSeconds = 2,
		range = 58,
		count = 3,
		speed = 100,
		tags = { "physical" },
	}),
	skill("viperArrow", "Viper Arrow", "bolt", {
		damage = 2,
		cooldownSeconds = 2.6,
		range = 58,
		count = 2,
		speed = 90,
		tags = { "poison" },
		effect = dot("poisoned", 4, 9),
	}),
	skill("arrowRain", "Arrow Rain", "ground", {
		damage = 8,
		cooldownSeconds = 9,
		range = 54,
		radius = 16,
		durationSeconds = 5,
		tags = { "physical" },
	}),
	skill("blastSnare", "Blast Snare", "ground", {
		damage = 22,
		cooldownSeconds = 8,
		range = 32,
		radius = 11,
		durationSeconds = 0,
		tags = { "fire" },
		effect = dot("burning", 4, 5),
	}),
	skill("dazingShot", "Dazing Shot", "bolt", {
		damage = 8,
		cooldownSeconds = 3,
		range = 63,
		speed = 100,
		tags = { "physical" },
		effect = slow(0.5, 4),
	}),
	skill("deadeye", "Deadeye", "bolt", {
		toughest = true,
		damage = 48,
		cooldownSeconds = 4,
		range = 72,
		speed = 140,
		tags = { "physical" },
	}),
	skill("thornSnare", "Thorn Snare", "groundSelf", {
		damage = 5,
		cooldownSeconds = 10,
		radius = 14,
		durationSeconds = 4,
		tags = { "nature" },
		effect = { kind = "root", seconds = 1.5 },
	}),
	skill("falconPerch", "Falcon Perch", "totem", {
		damage = 10,
		cooldownSeconds = 14,
		range = 45,
		durationSeconds = 8,
		tags = { "physical" },
	}),
}

local skillsById: { [string]: Types.SkillConfig } = {}
for _, entry in skills do
	skillsById[entry.id] = entry
end

local passives: { Types.PassiveConfig } = {
	passive("vigor", "Vigor", "damage", 0.10),
	passive("stamina", "Stamina", "maxHealth", 0.20),
	passive("fleetness", "Fleetness", "speed", 0.10),
	passive("mending", "Mending", "regeneration", 0.5),
	passive("alacrity", "Alacrity", "haste", 0.08),
	passive("reach", "Reach", "area", 0.10),
	passive("lodestone", "Lodestone", "pickupRange", 0.40),
	passive("insight", "Insight", "experience", 0.08),
	passive("hide", "Hide", "armour", 1),
	passive("precision", "Precision", "critChance", 0.05),
}

local passivesById: { [string]: Types.PassiveConfig } = {}
for _, entry in passives do
	passivesById[entry.id] = entry
end

-- Elite archetypes (stage 2a's telegraphs), stronger than grunts and rarer.
local elites: { Types.EnemyKindConfig } = {
	enemy("brute", "Oak Brute", {
		look = "brute",
		role = "elite",
		health = 160,
		speed = 8.5,
		radius = 2.5,
		damage = 25,
		xp = 8,
		colour = 0x7a5230,
		scale = 1.3,
		attacks = {
			attack("melee", {
				telegraphSeconds = 0.9,
				recoverSeconds = 0.8,
				cooldownSeconds = 2.5,
				range = 5,
				damage = 25,
				radius = 7,
				knockback = 12,
				arcDegrees = 150,
			}),
		},
	}),
	enemy("spitter", "Bog Spitter", {
		look = "spitter",
		role = "elite",
		health = 60,
		speed = 10,
		radius = 1.5,
		damage = 12,
		xp = 6,
		colour = 0x5f8f3a,
		scale = 1,
		preferredRange = 16,
		attacks = {
			attack("projectile", {
				telegraphSeconds = 0.6,
				recoverSeconds = 0.5,
				cooldownSeconds = 2,
				range = 30,
				damage = 12,
				radius = 0,
				projectileSpeed = 32,
				projectileCount = 1,
				spreadDegrees = 0,
			}),
		},
	}),
	enemy("exploder", "Spore Bloater", {
		look = "exploder",
		role = "elite",
		health = 40,
		speed = 15,
		radius = 1.5,
		damage = 35,
		xp = 6,
		colour = 0xb7c94a,
		scale = 1,
		diesOnAttack = true,
		attacks = {
			attack("burst", {
				telegraphSeconds = 0.8,
				recoverSeconds = 0,
				cooldownSeconds = 0,
				range = 4,
				damage = 35,
				radius = 7,
				knockback = 8,
			}),
		},
	}),
	enemy("shieldbearer", "Barkshield", {
		look = "shieldbearer",
		role = "elite",
		health = 140,
		speed = 9,
		radius = 2,
		damage = 12,
		xp = 8,
		colour = 0x6b4f2a,
		scale = 1.15,
		blockArcDegrees = 150,
		attacks = {
			attack("melee", {
				telegraphSeconds = 0.6,
				recoverSeconds = 0.5,
				cooldownSeconds = 1.8,
				range = 4,
				damage = 12,
				radius = 5,
				knockback = 5,
				arcDegrees = 100,
			}),
		},
	}),
	enemy("shaman", "Moss Shaman", {
		look = "shaman",
		role = "elite",
		health = 80,
		speed = 10,
		radius = 1.5,
		damage = 0,
		xp = 9,
		colour = 0x3f8f7a,
		scale = 1,
		preferredRange = 18,
		attacks = {
			attack("heal", {
				telegraphSeconds = 1,
				recoverSeconds = 0.5,
				cooldownSeconds = 6,
				range = 40,
				damage = 0,
				radius = 18,
				heal = 20,
				buffSeconds = 4,
			}),
		},
	}),
}

-- The forest's grunts, weakest first (GLOSSARY: roster). They hit on contact.
local roster: { Types.EnemyKindConfig } = {
	enemy(
		"sproutImp",
		"Sprout Imp",
		{ health = 8, speed = 8, damage = 2, xp = 1, colour = 0x9ccc65, scale = 1.2 }
	),
	enemy(
		"thicketRat",
		"Thicket Rat",
		{ health = 10, speed = 7.5, damage = 2, xp = 1, colour = 0x8d6e63, scale = 1.27 }
	),
	enemy(
		"greyWolf",
		"Grey Wolf",
		{ health = 16, speed = 10.4, damage = 3, xp = 2, colour = 0x9e9e9e, scale = 1.5 }
	),
	enemy(
		"wildBoar",
		"Wild Boar",
		{ health = 22, speed = 9, damage = 4, xp = 2, colour = 0x6d4c41, scale = 1.58 }
	),
	enemy(
		"bogHound",
		"Bog Hound",
		{ health = 30, speed = 11.2, damage = 6, xp = 3, colour = 0x33691e, scale = 1.5 }
	),
	enemy(
		"cutthroat",
		"Cutthroat",
		{ health = 40, speed = 8.5, damage = 8, xp = 3, colour = 0xb71c1c, scale = 1.5 }
	),
	enemy(
		"forestSpider",
		"Forest Spider",
		{ health = 55, speed = 10.4, damage = 10, xp = 4, colour = 0x4a148c, scale = 1.65 }
	),
	enemy(
		"hollowStalker",
		"Hollow Stalker",
		{ health = 75, speed = 11.2, damage = 12, xp = 5, colour = 0x37474f, scale = 1.65 }
	),
	enemy("mossTroll", "Moss Troll", {
		health = 100,
		speed = 9,
		damage = 16,
		xp = 6,
		colour = 0x558b2f,
		scale = 2.25,
		radius = 2.86,
	}),
	enemy("brambleBeast", "Bramble Beast", {
		health = 150,
		speed = 9.5,
		damage = 20,
		xp = 8,
		colour = 0x795548,
		scale = 2.25,
		radius = 2.86,
	}),
	enemy(
		"direWolf",
		"Dire Wolf",
		{ health = 200, speed = 13.5, damage = 26, xp = 10, colour = 0x424242, scale = 1.88 }
	),
	enemy("elderTreant", "Elder Treant", {
		health = 300,
		speed = 7.6,
		damage = 34,
		xp = 14,
		colour = 0x3e2723,
		scale = 2.7,
		radius = 3.38,
	}),
}

-- Six bosses on the clock and the forest's final boss, each with its own
-- telegraphed attacks (ADR-0015). Health and damage grow with the horde.
local bosses: { Types.EnemyKindConfig } = {
	enemy("thornback", "Thornback", {
		look = "thornback",
		role = "boss",
		health = 700,
		speed = 11.5,
		radius = 3.2,
		damage = 20,
		xp = 60,
		colour = 0x5d4037,
		scale = 1.8,
		attacks = {
			attack("charge", {
				telegraphSeconds = 1,
				recoverSeconds = 0.8,
				cooldownSeconds = 6,
				range = 40,
				damage = 30,
				radius = 4,
				knockback = 14,
				chargeSpeed = 60,
				chargeOvershoot = 10,
			}),
			attack("burst", {
				telegraphSeconds = 0.9,
				recoverSeconds = 0.6,
				cooldownSeconds = 5,
				range = 8,
				damage = 24,
				radius = 10,
				knockback = 12,
			}),
		},
	}),
	enemy("mossmaw", "Mossmaw", {
		look = "mossmaw",
		role = "boss",
		health = 1800,
		speed = 9,
		radius = 3.5,
		damage = 32,
		xp = 120,
		colour = 0x558b2f,
		scale = 2,
		preferredRange = 20,
		attacks = {
			attack("projectile", {
				telegraphSeconds = 0.8,
				recoverSeconds = 0.5,
				cooldownSeconds = 4,
				range = 40,
				damage = 18,
				radius = 3,
				projectileSpeed = 32,
				projectileCount = 5,
				spreadDegrees = 50,
			}),
			attack("leap", {
				telegraphSeconds = 1.1,
				recoverSeconds = 0.7,
				cooldownSeconds = 7,
				range = 30,
				damage = 35,
				radius = 9,
				knockback = 10,
			}),
		},
	}),
	enemy("hollowShade", "Hollow Shade", {
		archetype = "hollowShade",
		role = "boss",
		health = 4200,
		speed = 10,
		radius = 3,
		damage = 45,
		xp = 200,
		colour = 0x263238,
		scale = 1.9,
		attacks = {
			attack("ground", {
				telegraphSeconds = 0.8,
				recoverSeconds = 0.4,
				cooldownSeconds = 6,
				range = 30,
				damage = 12,
				radius = 9,
				groundSeconds = 6,
				groundTickSeconds = 0.5,
			}),
			attack("summon", {
				telegraphSeconds = 1.5,
				recoverSeconds = 0.5,
				cooldownSeconds = 14,
				range = 60,
				damage = 0,
				radius = 8,
				summonCount = 8,
			}),
		},
	}),
	enemy("brambleMatron", "Bramble Matron", {
		archetype = "brambleMatron",
		role = "boss",
		health = 7000,
		speed = 12,
		radius = 3.5,
		damage = 55,
		xp = 300,
		colour = 0x4a148c,
		scale = 2.2,
		preferredRange = 18,
		attacks = {
			attack("projectile", {
				telegraphSeconds = 0.7,
				recoverSeconds = 0.4,
				cooldownSeconds = 3.5,
				range = 45,
				damage = 25,
				radius = 5,
				projectileSpeed = 40,
				projectileCount = 3,
				spreadDegrees = 30,
			}),
			attack("leap", {
				telegraphSeconds = 1,
				recoverSeconds = 0.6,
				cooldownSeconds = 8,
				range = 35,
				damage = 50,
				radius = 10,
				knockback = 12,
			}),
		},
	}),
	enemy("ironbarkWarden", "Ironbark Warden", {
		archetype = "ironbarkWarden",
		role = "boss",
		health = 12000,
		speed = 8,
		radius = 4,
		damage = 70,
		xp = 400,
		colour = 0x3e2723,
		scale = 2.6,
		attacks = {
			attack("burst", {
				telegraphSeconds = 1.2,
				recoverSeconds = 0.8,
				cooldownSeconds = 5,
				range = 10,
				damage = 60,
				radius = 14,
				knockback = 16,
			}),
			attack("projectile", {
				telegraphSeconds = 1,
				recoverSeconds = 0.5,
				cooldownSeconds = 7,
				range = 50,
				damage = 30,
				radius = 3,
				projectileSpeed = 30,
				projectileCount = 8,
				spreadDegrees = 360,
			}),
		},
	}),
	enemy("ashenStag", "Ashen Stag", {
		archetype = "ashenStag",
		role = "boss",
		health = 20000,
		speed = 13,
		radius = 3.2,
		damage = 90,
		xp = 500,
		colour = 0xbf360c,
		scale = 2,
		attacks = {
			attack("charge", {
				telegraphSeconds = 0.9,
				recoverSeconds = 0.6,
				cooldownSeconds = 4,
				range = 50,
				damage = 60,
				radius = 4,
				knockback = 16,
				chargeSpeed = 80,
				chargeOvershoot = 15,
			}),
			attack("ground", {
				telegraphSeconds = 0.6,
				recoverSeconds = 0.3,
				cooldownSeconds = 5,
				range = 20,
				damage = 12,
				radius = 7,
				groundSeconds = 8,
				groundTickSeconds = 0.5,
			}),
		},
	}),
	enemy("forestHeart", "The Forest Heart", {
		archetype = "forestHeart",
		role = "finalBoss",
		health = 35000,
		speed = 7,
		radius = 5,
		damage = 100,
		xp = 1000,
		colour = 0x1b5e20,
		scale = 3.2,
		phaseHealthShare = 0.5,
		phaseCooldownFactor = 0.7,
		phaseSpeedFactor = 1.3,
		attacks = {
			attack("burst", {
				telegraphSeconds = 1.3,
				recoverSeconds = 0.8,
				cooldownSeconds = 6,
				range = 12,
				damage = 70,
				radius = 16,
				knockback = 18,
			}),
			attack("projectile", {
				telegraphSeconds = 1,
				recoverSeconds = 0.5,
				cooldownSeconds = 8,
				range = 60,
				damage = 35,
				radius = 3.5,
				projectileSpeed = 28,
				projectileCount = 10,
				spreadDegrees = 360,
			}),
			attack("charge", {
				telegraphSeconds = 1.2,
				recoverSeconds = 0.8,
				cooldownSeconds = 9,
				range = 60,
				damage = 60,
				radius = 5,
				knockback = 16,
				chargeSpeed = 50,
				chargeOvershoot = 12,
			}),
		},
	}),
}

local enemies: { [string]: Types.EnemyKindConfig } = {}
for _, list in { roster, elites, bosses } do
	for _, entry in list do
		enemies[entry.id] = entry
	end
end

local rosterIds = {}
for _, entry in roster do
	table.insert(rosterIds, entry.id)
end

local function synergy(
	id: string,
	name: string,
	tag: Types.Tag,
	status: Types.Status,
	fields: { [string]: any }
): Types.SynergyConfig
	local base: Types.SynergyConfig = {
		id = id,
		name = name,
		tag = tag,
		status = status,
		kind = "multiply",
		multiplier = 1.5,
	}
	for key, value in fields do
		(base :: any)[key] = value
	end
	return base
end

local Config: Types.Config = {
	run = {
		durationSeconds = 15 * 60,
		summarySeconds = 10,
		lateJoinSeconds = 60,
	},
	player = {
		radius = 1.5,
		moveTolerance = 1.25,
		moveBurstSeconds = 0.5,
		correctionDistance = 3,
		knockbackSeconds = 0.25,
		baseCritChance = 0.05,
		minDamage = 1,
		pickupRange = 10,
		dashDistance = 14,
		dashSeconds = 0.25,
		dashCharges = 2,
		dashCooldownSeconds = 3,
		dashInputMax = 1000,
	},
	projectiles = {
		touchMargin = 0.5,
		overshoot = 1.5,
	},
	ranks = {
		maxRank = 8,
		damagePerRank = 0.3,
		cooldownFactorPerRank = 0.93,
		radiusPerRank = 0.08,
		durationPerRank = 0.1,
		extraTargetRanks = { 3, 5, 7 },
		minCooldownShare = 0.35,
		minCooldownSeconds = 0.2,
		chainFalloff = 0.85,
		splashShare = 0.7,
		retrySeconds = 0.2,
		firstCooldownSeconds = 0.3,
		areaFirstTickSeconds = 0.4,
		areaTickSeconds = 1,
		burstDotSeconds = 5,
		coneHalfAngleDegrees = 37,
		groundSelfMargin = 9,
		totemOffset = 4.5,
		totemFirstShotSeconds = 0.3,
		totemShotSeconds = 1,
		healBelowShare = 0.85,
		clusterCandidates = 40,
		critMultiplier = 2,
		nearestBodyShare = 1,
		areaBodyShare = 0.5,
		scatterPoolFactor = 3,
		selfTriggerRange = 18,
	},
	skills = skillsById,
	passives = passivesById,
	classes = {
		mage = {
			id = "mage",
			name = "Mage",
			startSkill = "rimeDart",
			pool = {
				"rimeDart",
				"emberOrb",
				"glintVolley",
				"hoarfrostRing",
				"pulseBurst",
				"sleetfall",
				"pyreCircle",
				"cinderSnap",
				"frostBreath",
				"arcLash",
				"sunflare",
			},
			maxHealth = 120,
			walkSpeed = 17,
			synergies = {
				synergy("shatter", "Shatter", "fire", "chilled", { multiplier = 1.5 }),
				synergy("conduct", "Conduct", "lightning", "burning", {
					kind = "spread",
					spreadStatus = "burning",
					spreadSeconds = 3,
					spreadDps = 4,
					radius = 8,
				}),
			},
			colour = 0x42a5f5,
			weapon = "staff",
		},
		warrior = {
			id = "warrior",
			name = "Warrior",
			startSkill = "wideCut",
			pool = {
				"wideCut",
				"heavyBlow",
				"steelCyclone",
				"groundShock",
				"relentlessEdge",
				"warRoar",
				"reaperStroke",
				"cripplingStrike",
				"ironRiposte",
				"bulwark",
			},
			maxHealth = 160,
			walkSpeed = 16,
			synergies = {
				synergy("openWound", "Open Wound", "physical", "bleeding", { multiplier = 1.3 }),
				synergy(
					"crushingBlow",
					"Crushing Blow",
					"physical",
					"stunned",
					{ multiplier = 1.5 }
				),
			},
			colour = 0xef5350,
			weapon = "sword",
		},
		archer = {
			id = "archer",
			name = "Archer",
			startSkill = "swiftArrow",
			pool = {
				"swiftArrow",
				"fanOfArrows",
				"viperArrow",
				"arrowRain",
				"blastSnare",
				"dazingShot",
				"deadeye",
				"thornSnare",
				"falconPerch",
			},
			maxHealth = 135,
			walkSpeed = 16,
			synergies = {
				synergy("markedPrey", "Marked Prey", "physical", "slowed", { multiplier = 1.3 }),
				synergy("toxicFlare", "Toxic Flare", "fire", "poisoned", { multiplier = 1.6 }),
			},
			colour = 0x66bb6a,
			weapon = "bow",
		},
	},
	utilities = {
		{
			id = "sprint",
			name = "Sprint",
			kind = "sprint",
			cooldownSeconds = 12,
			factor = 1.6,
			seconds = 4,
		},
		{
			id = "barrier",
			name = "Barrier",
			kind = "barrier",
			cooldownSeconds = 20,
			amount = 50,
			seconds = 5,
		},
		{ id = "heal", name = "Mend", kind = "heal", cooldownSeconds = 25, amount = 40 },
	},
	enemies = enemies,
	maps = {
		forest = {
			id = "forest",
			name = "Whisperwood",
			radius = 400,
			-- Props with a footprint take one circle per entry (stage 3b).
			obstacleKinds = {
				{ id = "pine", radius = 4, weight = 10 },
				{ id = "oak", radius = 5, weight = 5 },
				{ id = "stump", radius = 2, weight = 3 },
				{ id = "rock", radius = 2.5, weight = 5 },
				{ id = "boulder", radius = 4.5, weight = 3 },
				{
					id = "log",
					radius = 2.5,
					weight = 3,
					footprint = {
						{ dx = -5, dz = 0, radius = 2.5 },
						{ dx = 5, dz = 0, radius = 2.5 },
					},
				},
				{
					id = "fence",
					radius = 1.5,
					weight = 3,
					footprint = {
						{ dx = -3, dz = 0, radius = 1.5 },
						{ dx = 3, dz = 0, radius = 1.5 },
					},
				},
				{ id = "pond", radius = 11, weight = 0.6 },
				{
					id = "chapel",
					radius = 7,
					weight = 0.8,
					footprint = {
						{ dx = 0, dz = 0, radius = 7 },
						{ dx = -9, dz = 0, radius = 5 },
						{ dx = 9, dz = 0, radius = 5 },
					},
				},
				{ id = "tower", radius = 5, weight = 0.8 },
				{
					id = "hut",
					radius = 6,
					weight = 0.8,
					footprint = { { dx = -4, dz = 0, radius = 6 }, { dx = 5, dz = 0, radius = 5 } },
				},
				{ id = "well", radius = 3, weight = 1 },
				{
					id = "stoneCircle",
					radius = 1.5,
					weight = 0.6,
					footprint = {
						{ dx = 9, dz = 0, radius = 1.5 },
						{ dx = 4.5, dz = 7.8, radius = 1.5 },
						{ dx = -4.5, dz = 7.8, radius = 1.5 },
						{ dx = -9, dz = 0, radius = 1.5 },
						{ dx = -4.5, dz = -7.8, radius = 1.5 },
						{ dx = 4.5, dz = -7.8, radius = 1.5 },
					},
				},
			},
			obstacleSpacing = 10,
			startClearRadius = 40,
			chestClearRadius = 20,
			placementAttempts = 30,
			chestMinDistance = 200,
			edgeMargin = 30,
			-- The composition (stage 3b): places with their kits as offsets from
			-- the centre (the radius is the clearing), groves dense at the core,
			-- paths from the start to every place, sparse leftovers.
			placeCount = 7,
			placeKinds = {
				{
					id = "chapelYard",
					radius = 34,
					weight = 1,
					props = {
						{ kind = "chapel", dx = 0, dz = 0 },
						{ kind = "well", dx = 18, dz = 10 },
						{ kind = "fence", dx = -16, dz = 12, rotation = 0 },
						{ kind = "fence", dx = -16, dz = -12, rotation = 0 },
						{ kind = "oak", dx = 22, dz = -16 },
						{ kind = "oak", dx = -24, dz = 0 },
					},
				},
				{
					id = "woodcutterCamp",
					radius = 30,
					weight = 1,
					props = {
						{ kind = "hut", dx = 0, dz = 0 },
						{ kind = "stump", dx = 12, dz = 8 },
						{ kind = "stump", dx = 14, dz = -6 },
						{ kind = "stump", dx = -10, dz = 12 },
						{ kind = "log", dx = -14, dz = -8, rotation = 0.6 },
						{ kind = "fence", dx = 10, dz = -16 },
					},
				},
				{
					id = "stoneGlade",
					radius = 30,
					weight = 1,
					props = {
						{ kind = "stoneCircle", dx = 0, dz = 0 },
						{ kind = "rock", dx = 20, dz = 14 },
						{ kind = "boulder", dx = -22, dz = -10 },
					},
				},
				{
					id = "towerKnoll",
					radius = 28,
					weight = 1,
					props = {
						{ kind = "tower", dx = 0, dz = 0 },
						{ kind = "boulder", dx = 10, dz = 8 },
						{ kind = "boulder", dx = -9, dz = 10 },
						{ kind = "boulder", dx = 4, dz = -12 },
						{ kind = "rock", dx = -14, dz = -4 },
					},
				},
				{
					id = "pondShore",
					radius = 34,
					weight = 1,
					props = {
						{ kind = "pond", dx = 0, dz = 0 },
						{ kind = "oak", dx = 18, dz = 10 },
						{ kind = "oak", dx = -16, dz = 14 },
						{ kind = "log", dx = 14, dz = -14 },
						{ kind = "rock", dx = -18, dz = -8 },
					},
				},
				{
					id = "boulderField",
					radius = 30,
					weight = 1,
					props = {
						{ kind = "boulder", dx = 0, dz = 0 },
						{ kind = "boulder", dx = 12, dz = 9 },
						{ kind = "boulder", dx = -11, dz = 8 },
						{ kind = "boulder", dx = 3, dz = -13 },
						{ kind = "rock", dx = 16, dz = -6 },
						{ kind = "rock", dx = -16, dz = -4 },
						{ kind = "rock", dx = 8, dz = 16 },
					},
				},
			},
			placeSpacing = 120,
			placeStartDistance = 90,
			groveCount = 10,
			groveRadiusMin = 30,
			groveRadiusMax = 50,
			groveTreesMin = 9,
			groveTreesMax = 15,
			groveSpacing = 25,
			groveCore = 0.5,
			scatterCount = 45,
			scatterKinds = {
				{ id = "stump", weight = 3 },
				{ id = "rock", weight = 4 },
				{ id = "log", weight = 2 },
				{ id = "boulder", weight = 1 },
			},
			pathWidth = 7,
			pathSway = 12,
			northShare = 0.4,
			scaleVariation = 0.15,
			leanDegrees = 4,
			roster = rosterIds,
			elites = { "brute", "spitter", "exploder", "shieldbearer", "shaman" },
			bosses = {
				{ kind = "thornback", atSeconds = 135 },
				{ kind = "mossmaw", atSeconds = 270 },
				{ kind = "hollowShade", atSeconds = 405 },
				{ kind = "brambleMatron", atSeconds = 540 },
				{ kind = "ironbarkWarden", atSeconds = 675 },
				{ kind = "ashenStag", atSeconds = 810 },
			},
			finalBoss = "forestHeart",
		},
	},
	map = "forest",
	horde = {
		aliveAtStart = 14,
		aliveGrowth = 225,
		maxAlive = 220,
		spawnIntervalSeconds = 0.12,
		spawnBatchMax = 4,
		spawnShare = 6,
		ringMin = 77,
		ringMax = 95,
		windowSize = 3,
		windowStepSeconds = 30,
		windowSteps = 27,
		healthGrowth = 0.75,
		damageGrowth = 0.9,
		eliteShareStart = 0.02,
		eliteShareEnd = 0.12,
		ringCountStart = 28,
		ringCountGrowth = 60,
		ringRadius = 58,
		strayDistance = 170,
		strayReturnDistance = 85,
		contactFirstSeconds = 0.5,
		contactSeconds = 1.3,
		separationRadius = 3.2,
		approachFactor = 0.9,
		buffSpeedFactor = 1.3,
		buffDamageFactor = 1.3,
		bossDistance = 68,
		finalBossSeconds = 180,
		bossSlowFloor = 0.75,
		bossControlShare = 0.3,
		foodChance = 0.015,
		foodHeal = 30,
		steerMargin = 1.5,
		contactMargin = 0.35,
	},
	statuses = {
		maxDotStacks = 6,
		dotTickSeconds = 1,
		chillSeconds = 2.5,
		chillFactor = 0.5,
	},
	cards = {
		offerSize = 3,
		maxSkills = 6,
		maxPassives = 6,
		weightSkillRank = 1.2,
		weightNewSkill = 1.0,
		weightPassiveRank = 0.8,
		weightNewPassive = 0.5,
		healShare = 1,
	},
	progression = {
		bands = {
			{ fromLevel = 1, base = 5, perLevel = 10 },
			{ fromLevel = 20, base = 195, perLevel = 13 },
			{ fromLevel = 40, base = 455, perLevel = 16 },
		},
		crystalFactor = 2,
		maxCrystals = 350,
		eatRadius = 1,
	},
	shrines = {
		count = 8,
		kinds = { "boon", "pact", "trial", "spring" },
		radius = 3,
		reach = 7,
		startMinDistance = 90,
		chestMinDistance = 40,
		spacing = 70,
		holdSeconds = 1.5,
		boons = {
			{ id = "might", name = "Boon of Might", stat = "damage", amount = 0.15 },
			{ id = "wind", name = "Boon of Wind", stat = "speed", amount = 0.1 },
			{ id = "oak", name = "Boon of the Oak", stat = "maxHealth", amount = 0.2 },
			{ id = "quickening", name = "Boon of Quickening", stat = "haste", amount = 0.1 },
			{ id = "lodestar", name = "Boon of the Lodestar", stat = "pickupRange", amount = 0.25 },
		},
		pacts = {
			{
				id = "blood",
				name = "Pact of Blood",
				up = "damage",
				upAmount = 0.3,
				down = "maxHealth",
				downAmount = 0.15,
			},
			{
				id = "haste",
				name = "Pact of Haste",
				up = "haste",
				upAmount = 0.25,
				down = "speed",
				downAmount = 0.1,
			},
			{
				id = "reach",
				name = "Pact of Reach",
				up = "area",
				upAmount = 0.3,
				down = "armour",
				downAmount = 3,
			},
		},
		trialRingCount = 24,
		trialEliteCount = 1,
		trialRingRadius = 40,
		greatOfferRanks = 2,
		springRechargeSeconds = 180,
		pactMinShare = -0.9,
	},
	-- The forest's meshes, generated with the Studio MCP and published under
	-- the owner's account (stage 3b): obstacle kind -> variants, and the
	-- shrines, the chest and the portal by their own keys.
	props = {
		pine = {
			{
				meshId = "rbxassetid://134556219086855",
				textureId = "rbxassetid://97260680051100",
				scale = 1.3,
				yOffset = 0,
			},
			{
				meshId = "rbxassetid://98896018378309",
				textureId = "rbxassetid://80821783400224",
				scale = 1.5,
				yOffset = 0,
			},
		},
		oak = {
			{
				meshId = "rbxassetid://134108452664098",
				textureId = "rbxassetid://76726940919653",
				scale = 1.4,
				yOffset = 0,
			},
			{
				meshId = "rbxassetid://135341017659030",
				textureId = "rbxassetid://93886118302237",
				scale = 1.2,
				yOffset = 0,
			},
		},
		stump = {
			{
				meshId = "rbxassetid://86611941717787",
				textureId = "rbxassetid://85594539609993",
				scale = 1.2,
				yOffset = 0,
			},
		},
		rock = {
			{
				meshId = "rbxassetid://80502154918010",
				textureId = "rbxassetid://73909649707441",
				scale = 2,
				yOffset = 0,
			},
		},
		boulder = {
			{
				meshId = "rbxassetid://96976847723730",
				textureId = "rbxassetid://139192831019512",
				scale = 1.8,
				yOffset = 0,
			},
		},
		log = {
			{
				meshId = "rbxassetid://78001596990169",
				textureId = "rbxassetid://89581060934702",
				scale = 3,
				yOffset = 0,
			},
		},
		fence = {
			{
				meshId = "rbxassetid://83287335679028",
				textureId = "rbxassetid://126726711977586",
				scale = 1.4,
				yOffset = 0,
			},
		},
		chapel = {
			{
				meshId = "rbxassetid://119053733006555",
				textureId = "rbxassetid://95005558929654",
				scale = 1.5,
				yOffset = 0,
			},
		},
		tower = {
			{
				meshId = "rbxassetid://136187997302979",
				textureId = "rbxassetid://120467866165576",
				scale = 1.3,
				yOffset = 0,
			},
		},
		hut = {
			{
				meshId = "rbxassetid://116367906850144",
				textureId = "rbxassetid://99315963574295",
				scale = 1.8,
				yOffset = 0,
			},
		},
		well = {
			{
				meshId = "rbxassetid://81862051689760",
				textureId = "rbxassetid://84575440262481",
				scale = 1,
				yOffset = 0,
			},
		},
		stoneCircle = {
			{
				meshId = "rbxassetid://85701500845752",
				textureId = "rbxassetid://78892024846147",
				scale = 1.4,
				yOffset = 0,
			},
		},
		shrineBoon = {
			{
				meshId = "rbxassetid://125471366291195",
				textureId = "rbxassetid://134050172235837",
				scale = 1,
				yOffset = 0,
			},
		},
		shrinePact = {
			{
				meshId = "rbxassetid://111929074219784",
				textureId = "rbxassetid://128331075410472",
				scale = 1,
				yOffset = 0,
			},
		},
		shrineTrial = {
			{
				meshId = "rbxassetid://85743903322667",
				textureId = "rbxassetid://71428052898405",
				scale = 1,
				yOffset = 0,
			},
		},
		shrineSpring = {
			{
				meshId = "rbxassetid://118362653309604",
				textureId = "rbxassetid://74187154815065",
				scale = 1,
				yOffset = 0,
			},
		},
		chest = {
			{
				meshId = "rbxassetid://124124109819626",
				textureId = "rbxassetid://76372908960944",
				scale = 1.4,
				yOffset = 0,
			},
		},
		portal = {
			{
				meshId = "rbxassetid://70820691152381",
				textureId = "rbxassetid://138616235010728",
				scale = 1.8,
				yOffset = 0,
			},
		},
	},
	-- Skill, passive, utility and dash icons (stage 3b): the game-icons.net
	-- set (CC BY 3.0, CREDITS.md), rasterised in the class colours and
	-- published under the owner's account.
	icons = {
		alacrity = "rbxassetid://125004087768719",
		arcLash = "rbxassetid://102090669341417",
		arrowRain = "rbxassetid://109297608538461",
		barrier = "rbxassetid://129672181530095",
		blastSnare = "rbxassetid://93412778183502",
		bulwark = "rbxassetid://79555595891966",
		cinderSnap = "rbxassetid://119682849406005",
		cripplingStrike = "rbxassetid://91187767672283",
		dash = "rbxassetid://99467295983161",
		dazingShot = "rbxassetid://104825330205767",
		deadeye = "rbxassetid://88969505175547",
		emberOrb = "rbxassetid://131349679826453",
		falconPerch = "rbxassetid://95971114836407",
		fanOfArrows = "rbxassetid://114173181643648",
		fleetness = "rbxassetid://70710617130922",
		frostBreath = "rbxassetid://79118755115474",
		glintVolley = "rbxassetid://102943771964796",
		groundShock = "rbxassetid://79074143148822",
		heal = "rbxassetid://132485509144430",
		heavyBlow = "rbxassetid://103067422436615",
		hide = "rbxassetid://117056553160400",
		hoarfrostRing = "rbxassetid://139020826718970",
		insight = "rbxassetid://100407699227119",
		ironRiposte = "rbxassetid://118566319642015",
		lodestone = "rbxassetid://99979880015853",
		mending = "rbxassetid://119385016644755",
		precision = "rbxassetid://120393335263665",
		pulseBurst = "rbxassetid://123421434542693",
		pyreCircle = "rbxassetid://128659189886156",
		reach = "rbxassetid://105341213942703",
		reaperStroke = "rbxassetid://99569229315235",
		relentlessEdge = "rbxassetid://127106317933074",
		rimeDart = "rbxassetid://73244944261108",
		sleetfall = "rbxassetid://92300037050925",
		sprint = "rbxassetid://78486271982071",
		stamina = "rbxassetid://83441247622854",
		steelCyclone = "rbxassetid://70681280205732",
		sunflare = "rbxassetid://124901819325105",
		swiftArrow = "rbxassetid://106837162733024",
		thornSnare = "rbxassetid://101039449790133",
		vigor = "rbxassetid://83760139402690",
		viperArrow = "rbxassetid://134097166096998",
		warRoar = "rbxassetid://133510941517636",
		wideCut = "rbxassetid://136820166390280",
	},
	extraction = {
		compassMinute = 5,
		openRadius = 6,
		openSeconds = 2,
		castSeconds = 5,
		portalSeconds = 20,
		portalRadius = 6,
	},
	net = {
		stepHz = 30,
		snapshotHz = 10,
		intentsPerSecond = 30,
	},
}

return Config
