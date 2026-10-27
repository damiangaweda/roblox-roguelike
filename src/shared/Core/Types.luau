--!strict
-- Types shared by the pure rules core (ADR-0002) for the survivors-like run
-- (stage 3; ADR-0013 to ADR-0015). Positions are on the flat ground plane: x
-- and z in studs. Angles are radians on that plane, measured from +x toward
-- +z. Times are run seconds since the run started. Every number that tunes
-- play lives in the configuration (AGENTS.md rule 3); the core reads it.

export type Point = { x: number, z: number }

-- An element or property a skill carries; synergies key on it (GLOSSARY: tag).
export type Tag =
	"fire"
	| "ice"
	| "lightning"
	| "arcane"
	| "physical"
	| "bleed"
	| "poison"
	| "nature"

-- A temporary condition a hit puts on an enemy (GLOSSARY: status). `chilled`
-- is the slow an ice hit leaves, which shatter keys on; `burning`, `bleeding`
-- and `poisoned` are the damage-over-time statuses, stacked per enemy.
export type Status =
	"slowed"
	| "chilled"
	| "rooted"
	| "stunned"
	| "feared"
	| "weakened"
	| "burning"
	| "bleeding"
	| "poisoned"

-- The condition a hit applies, as the configuration states it.
export type EffectConfig = {
	kind: "slow" | "root" | "stun" | "fear" | "weaken" | "drain" | "execute" | "dot",
	-- slow and weaken: the multiplier (0.5 halves speed or damage); drain: the
	-- share of damage healed; execute: the health share below which a
	-- non-boss dies; dot: unused.
	factor: number?,
	-- slow, root, stun, fear, weaken, dot: how long it lasts.
	seconds: number?,
	-- dot: damage per second, and the status it shows as.
	dps: number?,
	status: ("burning" | "bleeding" | "poisoned")?,
}

-- How a skill picks what it lands on (ADR-0013; GLOSSARY: targeting).
--   bolt: a projectile at each of the `count` nearest (or toughest) enemies
--     in range; `radius` > 0 splashes around the struck enemy.
--   strike: an instant hit on the `count` nearest (or toughest) in range.
--   melee: an instant hit on the `count` nearest within melee reach (range).
--   nova: everything within `radius` of the hero.
--   cone: everything within `radius` inside a cone toward the nearest enemy.
--   ground: an area of `radius` at the densest cluster within `range`,
--     ticking for `duration`; `duration` 0 is one burst with a dot.
--   groundSelf: the same area under the hero, when an enemy is close.
--   chain: the nearest in range, then jumps to the nearest unstruck within
--     `radius`, `count` + 1 targets in all, damage falling per jump.
--   scatter: `count` random enemies among the nearest in range.
--   aura: every cooldown, everything within `radius` of the hero.
--   orbit: every cooldown, the `count` nearest within `radius` of the hero.
--   totem: a totem placed by the hero that fires at the nearest enemy in
--     `range` for `duration`.
--   shield: a barrier on the hero absorbing `damage` for `duration`.
--   heal: heals the hero `damage` over `duration` when below the threshold.
--   thorns: returns `damage` to every attacker for `duration` when enemies
--     are close.
export type Targeting =
	"bolt"
	| "strike"
	| "melee"
	| "nova"
	| "cone"
	| "ground"
	| "groundSelf"
	| "chain"
	| "scatter"
	| "aura"
	| "orbit"
	| "totem"
	| "shield"
	| "heal"
	| "thorns"

export type SkillConfig = {
	id: string,
	name: string,
	targeting: Targeting,
	-- bolt, strike, melee: prefer the toughest (most health) over the nearest.
	toughest: boolean?,
	-- Direct damage; per tick for areas, auras and totems; the absorb, heal or
	-- reflect for the self kinds. Rank 1, before the hero's might.
	damage: number,
	cooldownSeconds: number,
	-- How far it reaches from the hero (bolt, strike, melee, ground, chain's
	-- first target, scatter, totem).
	range: number,
	-- Area kinds: the area; bolt and strike: the splash; chain: the jump.
	radius: number,
	-- Targets at rank 1 (ranks 3, 5 and 7 add one); 0 for area kinds.
	count: number,
	-- Areas, totems and the self kinds: how long it lasts.
	durationSeconds: number,
	-- bolt: studs per second; 0 is instant.
	speed: number,
	-- Studs struck enemies are pushed.
	knockback: number,
	tags: { Tag },
	effect: EffectConfig?,
}

-- A skill's numbers at a rank, after the hero's stats: what Casting fires.
export type EffectiveSkill = {
	id: string,
	targeting: Targeting,
	toughest: boolean,
	damage: number,
	cooldownSeconds: number,
	range: number,
	radius: number,
	count: number,
	durationSeconds: number,
	speed: number,
	knockback: number,
	tags: { Tag },
	effect: EffectConfig?,
	critChance: number,
}

export type RankConfig = {
	maxRank: number,
	-- Multipliers per rank above 1: damage × (1 + damagePerRank × (rank - 1)),
	-- cooldown × cooldownFactorPerRank ^ (rank - 1), radius and duration likewise.
	damagePerRank: number,
	cooldownFactorPerRank: number,
	radiusPerRank: number,
	durationPerRank: number,
	-- Ranks that add one target.
	extraTargetRanks: { number },
	-- Haste never cuts a cooldown below this share, nor below the floor.
	minCooldownShare: number,
	minCooldownSeconds: number,
	-- Damage falls by this factor per chain jump.
	chainFalloff: number,
	-- Splash deals this share of the hit.
	splashShare: number,
	-- A skill with no target retries after this long without spending its cooldown.
	retrySeconds: number,
	-- The cooldown a skill starts with when gained.
	firstCooldownSeconds: number,
	-- An area's first tick comes after this, then every tickSeconds.
	areaFirstTickSeconds: number,
	areaTickSeconds: number,
	-- A burst area (duration 0) leaves its dot for this long.
	burstDotSeconds: number,
	-- Cone half angle in degrees; groundSelf fires when an enemy is within
	-- radius + groundSelfMargin; a totem stands this far from the hero.
	coneHalfAngleDegrees: number,
	groundSelfMargin: number,
	totemOffset: number,
	totemFirstShotSeconds: number,
	totemShotSeconds: number,
	-- The heal fires below this share of max health.
	healBelowShare: number,
	-- Ground kinds consider at most this many nearest enemies for the cluster.
	clusterCandidates: number,
	critMultiplier: number,
	-- How much of an enemy's body counts toward a skill's reach: the nearest
	-- kinds count it whole, areas half.
	nearestBodyShare: number,
	areaBodyShare: number,
	-- Scatter picks its targets from this many times `count` nearest enemies.
	scatterPoolFactor: number,
	-- A shield or thorns skill fires only when the nearest enemy is within this distance.
	selfTriggerRange: number,
}

-- A stat passives raise (GLOSSARY: passive).
export type Stat =
	"damage"
	| "maxHealth"
	| "speed"
	| "regeneration"
	| "haste"
	| "area"
	| "pickupRange"
	| "experience"
	| "armour"
	| "critChance"

export type PassiveConfig = {
	id: string,
	name: string,
	stat: Stat,
	-- Per rank: added to an additive stat, or the share a multiplicative stat
	-- grows by (maxHealth, speed, pickupRange).
	perRank: number,
	maxRank: number,
}

-- A bonus when a hit carrying `tag` lands on an enemy with `status`
-- (GLOSSARY: synergy): `multiply` scales the hit, `spread` copies
-- `spreadStatus` to enemies within `radius`.
export type SynergyConfig = {
	id: string,
	name: string,
	tag: Tag,
	status: Status,
	kind: "multiply" | "spread",
	multiplier: number?,
	spreadStatus: Status?,
	spreadSeconds: number?,
	spreadDps: number?,
	radius: number?,
}

export type ClassConfig = {
	id: string,
	name: string,
	-- The skill every run starts with; the pool its cards draw from.
	startSkill: string,
	pool: { string },
	maxHealth: number,
	walkSpeed: number,
	synergies: { SynergyConfig },
	-- The colour the hero is drawn in (0xRRGGBB) and its weapon look.
	colour: number,
	weapon: string,
}

export type UtilityConfig = {
	id: string,
	name: string,
	kind: "sprint" | "barrier" | "heal",
	cooldownSeconds: number,
	-- sprint: the speed multiplier for `seconds`; barrier: the absorb for
	-- `seconds`; heal: the health restored at once.
	factor: number?,
	amount: number?,
	seconds: number?,
}

-- The hero's derived numbers, from the class and the passives.
export type HeroStats = {
	-- A multiplier on every skill's damage.
	damage: number,
	maxHealth: number,
	speed: number,
	-- Health per second.
	regeneration: number,
	-- The share cut from cooldowns.
	haste: number,
	-- A multiplier on areas and splashes.
	area: number,
	pickupRange: number,
	-- A multiplier on experience.
	experience: number,
	-- Flat damage taken off every hit (at least 1 is taken).
	armour: number,
	critChance: number,
}

export type AttackKind =
	"melee"
	| "projectile"
	| "burst"
	| "heal"
	| "charge"
	| "leap"
	| "summon"
	| "ground"

-- An enemy's telegraphed attack. melee: an arc in front; projectile: shots
-- at the aim; burst: an area around the enemy; heal: heals enemies around;
-- charge: a rush along the line to the aim, hitting what it crosses; leap: a
-- jump onto the aim with a burst there; summon: spawns `summonCount` grunts
-- around the enemy; ground: leaves an area at the aim that hurts players
-- inside for `groundSeconds`.
export type AttackConfig = {
	kind: AttackKind,
	-- The telegraph: how long the wind-up before the attack lands is visible.
	telegraphSeconds: number,
	-- How long the enemy stands still after the attack.
	recoverSeconds: number,
	cooldownSeconds: number,
	-- The attack starts when the target is this close (a heal: always; a
	-- summon: always).
	range: number,
	damage: number,
	-- melee, burst, leap: the area hit; projectile: the area where it lands
	-- (0 hits only what it strikes); heal: who is healed; charge: half the
	-- width of the rush; ground: the area left behind.
	radius: number,
	-- Studs a hit player is pushed away.
	knockback: number,
	-- melee: the frontal arc hit, in degrees; 360 hits all around.
	arcDegrees: number?,
	projectileSpeed: number?,
	projectileCount: number?,
	spreadDegrees: number?,
	-- heal: health restored to each enemy in radius, and how long they stay buffed.
	heal: number?,
	buffSeconds: number?,
	-- charge: studs per second of the rush, and how far past the aim it runs.
	chargeSpeed: number?,
	chargeOvershoot: number?,
	summonCount: number?,
	-- ground: how long the area stays and how often it hurts.
	groundSeconds: number?,
	groundTickSeconds: number?,
}

-- A kind of enemy: a grunt of the roster, an elite archetype or a boss
-- (GLOSSARY: archetype, roster, elite, boss).
export type EnemyKindConfig = {
	id: string,
	name: string,
	-- The silhouette the client draws: an archetype's (grunt, brute, spitter,
	-- exploder, shieldbearer, shaman) or a boss's own.
	look: string,
	role: "grunt" | "elite" | "boss" | "finalBoss",
	health: number,
	speed: number,
	radius: number,
	-- Contact damage of a grunt; the damage an elite's or boss's attacks scale from.
	damage: number,
	xp: number,
	-- The client's tint (0xRRGGBB) and size multiplier for this kind.
	colour: number,
	scale: number,
	-- An elite or boss keeps this distance when it fights at range.
	preferredRange: number?,
	-- Telegraphed attacks, used in turn; a grunt has none and hits on contact.
	attacks: { AttackConfig },
	-- Hits from within this frontal arc (degrees) are blocked (the shieldbearer).
	blockArcDegrees: number?,
	-- The enemy dies when its attack lands (the exploder).
	diesOnAttack: boolean?,
	-- A boss's second phase, entered at `phaseHealthShare` of max health:
	-- attacks from `phaseAttacks` onward unlock, cooldowns are multiplied by
	-- `phaseCooldownFactor`, speed by `phaseSpeedFactor`.
	phaseHealthShare: number?,
	phaseAttackIndex: number?,
	phaseCooldownFactor: number?,
	phaseSpeedFactor: number?,
}

export type BossScheduleEntry = { kind: string, atSeconds: number }

-- One map: its ground, obstacles, roster and bosses (ADR-0014, ADR-0015).
export type MapConfig = {
	id: string,
	name: string,
	radius: number,
	-- Obstacles: how many the scatter tries to place, their kinds with radii
	-- and weights, the minimum gap between them and the clear ground around
	-- the start and the extraction chest.
	obstacleCount: number,
	obstacleKinds: { { id: string, radius: number, weight: number } },
	obstacleSpacing: number,
	startClearRadius: number,
	chestClearRadius: number,
	placementAttempts: number,
	-- The chest lies at least this far from the start and this far inside the edge.
	chestMinDistance: number,
	edgeMargin: number,
	-- Grunt kinds from weakest to strongest.
	roster: { string },
	-- Elite kinds the horde may spawn.
	elites: { string },
	bosses: { BossScheduleEntry },
	finalBoss: string,
}

export type HordeConfig = {
	-- Alive grunts and elites wanted: from aliveAtStart rising by aliveGrowth
	-- over the run's duration, capped at maxAlive.
	aliveAtStart: number,
	aliveGrowth: number,
	maxAlive: number,
	spawnIntervalSeconds: number,
	-- At most this many per spawn; the shortfall is divided by spawnShare.
	spawnBatchMax: number,
	spawnShare: number,
	-- The ring around the hero spawns land on.
	ringMin: number,
	ringMax: number,
	-- The window of adjacent kinds slides up the roster: `windowSize` kinds,
	-- stepping every windowStepSeconds of run time after the first.
	windowSize: number,
	windowStepSeconds: number,
	-- The window reaches the top of the roster after this many steps.
	windowSteps: number,
	-- Health and damage multipliers reach these at the run's duration.
	healthGrowth: number,
	damageGrowth: number,
	-- The share of spawns that are elites, at the start and at the end.
	eliteShareStart: number,
	eliteShareEnd: number,
	-- A closing ring halfway between bosses: count rising with time on a circle.
	ringCountStart: number,
	ringCountGrowth: number,
	ringRadius: number,
	-- Enemies farther than strayDistance are moved to strayReturnDistance
	-- beyond the hero on the far side.
	strayDistance: number,
	strayReturnDistance: number,
	-- Grunts hit on contact: first after contactFirstSeconds, then every
	-- contactSeconds.
	contactFirstSeconds: number,
	contactSeconds: number,
	separationRadius: number,
	-- An enemy stops closing in at this share of its attack's range.
	approachFactor: number,
	buffSpeedFactor: number,
	buffDamageFactor: number,
	-- How far a boss spawns from the hero.
	bossDistance: number,
	-- The final boss's phase and time limit.
	finalBossSeconds: number,
	-- Bosses: the slow floor, the control duration share, fear immunity.
	bossSlowFloor: number,
	bossControlShare: number,
	-- Food: the chance a grunt drops it and what it heals; a boss drops a full heal.
	foodChance: number,
	foodHeal: number,
	-- How far an enemy walks past an obstacle's edge when steering around it.
	steerMargin: number,
	-- A grunt's contact hit reaches this far beyond the touching bodies.
	contactMargin: number,
}

export type StatusConfig = {
	-- Damage-over-time stacks per enemy; the oldest goes when exceeded.
	maxDotStacks: number,
	dotTickSeconds: number,
	-- How long an ice hit leaves an enemy chilled, and its slow factor.
	chillSeconds: number,
	chillFactor: number,
}

export type CardsConfig = {
	offerSize: number,
	maxSkills: number,
	maxPassives: number,
	-- Draw weights.
	weightSkillRank: number,
	weightNewSkill: number,
	weightPassiveRank: number,
	weightNewPassive: number,
	-- The share of health a heal card restores.
	healShare: number,
}

export type ProgressionConfig = {
	-- Experience to the next level: three bands, each `base + perLevel ×
	-- (level - from)` from its first level.
	bands: { { fromLevel: number, base: number, perLevel: number } },
	-- A crystal carries the enemy's xp times this.
	crystalFactor: number,
	maxCrystals: number,
	-- How far beyond the hero's body food is eaten.
	eatRadius: number,
}

export type ExtractionConfig = {
	-- The compass points at the chest from this run minute.
	compassMinute: number,
	-- Standing within openRadius and holding for openSeconds opens the chest.
	openRadius: number,
	openSeconds: number,
	castSeconds: number,
	portalSeconds: number,
	portalRadius: number,
}

export type Config = {
	run: {
		durationSeconds: number,
		summarySeconds: number,
		lateJoinSeconds: number,
	},
	player: {
		radius: number,
		moveTolerance: number,
		moveBurstSeconds: number,
		correctionDistance: number,
		knockbackSeconds: number,
		baseCritChance: number,
		-- A hit never takes less than this after armour.
		minDamage: number,
		-- How far a crystal is drawn in from, before the pickup passive.
		pickupRange: number,
	},
	projectiles: {
		touchMargin: number,
		overshoot: number,
	},
	ranks: RankConfig,
	skills: { [string]: SkillConfig },
	passives: { [string]: PassiveConfig },
	classes: { [string]: ClassConfig },
	-- In order: the three buttons.
	utilities: { UtilityConfig },
	enemies: { [string]: EnemyKindConfig },
	maps: { [string]: MapConfig },
	-- The map stage 3 plays (one map: simplification register).
	map: string,
	horde: HordeConfig,
	statuses: StatusConfig,
	cards: CardsConfig,
	progression: ProgressionConfig,
	extraction: ExtractionConfig,
	net: {
		stepHz: number,
		snapshotHz: number,
		intentsPerSecond: number,
	},
}

-- An obstacle scattered on the map: a circle that blocks movement (ADR-0014).
export type Obstacle = {
	id: number,
	kind: string,
	x: number,
	z: number,
	radius: number,
	rotation: number,
}

export type Arena = {
	radius: number,
	obstacles: { Obstacle },
	-- Where the hero starts and where the chest lies.
	startX: number,
	startZ: number,
	chestX: number,
	chestZ: number,
}

-- A damage-over-time stack on an enemy.
export type Dot = {
	dps: number,
	until_: number,
	nextTickAt: number,
	status: "burning" | "bleeding" | "poisoned",
	-- The player credited with its damage and kill.
	source: number,
	tags: { Tag },
}

export type EnemyState = "chase" | "telegraph" | "charge" | "recover"

export type Enemy = {
	id: number,
	kind: string,
	x: number,
	z: number,
	facing: number,
	health: number,
	maxHealth: number,
	-- The damage multiplier fixed when it spawned (horde growth).
	damageFactor: number,
	state: EnemyState,
	-- When a telegraph lands, a charge ends or a recovery ends.
	stateUntil: number,
	target: number?,
	-- Index into the kind's attacks of the attack being telegraphed, or the next one.
	attack: number,
	-- The point locked when the telegraph started.
	aimX: number,
	aimZ: number,
	attackReadyAt: number,
	-- When the next contact hit may land (grunts).
	contactReadyAt: number,
	-- Statuses: the slow factor and when it ends; control ends; weaken.
	slowFactor: number,
	slowUntil: number,
	chilledUntil: number,
	rootedUntil: number,
	stunnedUntil: number,
	fearedUntil: number,
	weakenFactor: number,
	weakenUntil: number,
	buffedUntil: number,
	dots: { Dot },
	knockX: number,
	knockZ: number,
	knockUntil: number,
	-- A boss in its second phase.
	phase: number,
	-- Players already hit by the charge in progress.
	chargedPlayers: { [number]: boolean },
	-- charge: where the rush ends.
	chargeEndX: number,
	chargeEndZ: number,
	-- The summoner or spawner's time of birth, for the oldest-first culls.
	bornAt: number,
}

export type Projectile = {
	id: number,
	owner: "player" | "enemy",
	source: number,
	-- The skill id or enemy kind that fired it.
	kind: string,
	x: number,
	z: number,
	dirX: number,
	dirZ: number,
	speed: number,
	remaining: number,
	damage: number,
	radius: number,
	knockback: number,
	tags: { Tag },
	effect: EffectConfig?,
	-- player: the enemy it flies at (it hits when it arrives), nil for a straight shot.
	targetId: number?,
	-- player: the skill's crit chance, rolled on arrival.
	critChance: number,
}

-- A ground area ticking damage: a player's skill area, or an enemy's left
-- behind by a ground attack.
export type Area = {
	id: number,
	owner: "player" | "enemy",
	source: number,
	kind: string,
	x: number,
	z: number,
	radius: number,
	damage: number,
	until_: number,
	nextTickAt: number,
	tickSeconds: number,
	tags: { Tag },
	effect: EffectConfig?,
	critChance: number,
	knockback: number,
}

export type Totem = {
	id: number,
	source: number,
	skill: string,
	x: number,
	z: number,
	until_: number,
	nextShotAt: number,
}

export type Crystal = { id: number, x: number, z: number, xp: number }

export type Food = { id: number, x: number, z: number, heal: number }

export type OwnedSkill = { id: string, rank: number, readyAt: number }

export type Card =
	{ kind: "skillRank", skill: string, rank: number }
	| { kind: "newSkill", skill: string }
	| { kind: "passiveRank", passive: string, rank: number }
	| { kind: "newPassive", passive: string }
	| { kind: "heal" }

export type PlayerState = "alive" | "dead" | "extracted"

export type Player = {
	id: number,
	class: string,
	x: number,
	z: number,
	facing: number,
	state: PlayerState,
	health: number,
	level: number,
	xp: number,
	skills: { OwnedSkill },
	-- Passive id to its rank.
	passives: { [string]: number },
	-- Offers waiting for a choice, oldest first.
	offers: { { Card } },
	-- Utility cooldowns, by button index.
	utilityReadyAt: { number },
	sprintUntil: number,
	sprintFactor: number,
	-- The barrier absorbing damage and when it drops (utility and shield skills).
	barrier: number,
	barrierUntil: number,
	thorns: number,
	thornsUntil: number,
	-- Health still to be restored by a heal skill, at this rate.
	healPending: number,
	healRate: number,
	kills: number,
	moveBudget: number,
	-- Whether the player holds the open button at the chest, and the hold so far.
	opening: boolean,
	openProgress: number,
	-- Set while casting the extraction spell; nil otherwise.
	castingUntil: number?,
	-- Whether the player holds the extraction spell.
	hasSpell: boolean,
	hurtAt: number,
	knockX: number,
	knockZ: number,
	knockUntil: number,
	damageDone: number,
}

export type Event =
	-- A skill hit an enemy; `crit` doubled it; `synergy` names the synergy that fired.
	{
		kind: "hit",
		source: number,
		enemyId: number,
		amount: number,
		skill: string,
		crit: boolean,
		synergy: string?,
		blocked: boolean,
	}
	| { kind: "kill", source: number, enemyId: number, enemyKind: string, x: number, z: number }
	| { kind: "playerHurt", player: number, amount: number, enemyId: number?, absorbed: number }
	| { kind: "knockback", player: number, dx: number, dz: number }
	| { kind: "healed", player: number, amount: number }
	| { kind: "levelUp", player: number, level: number }
	| { kind: "offer", player: number, cards: { Card } }
	| { kind: "cardTaken", player: number, card: Card }
	| { kind: "died", player: number }
	| { kind: "extracted", player: number }
	| { kind: "ended", reason: "allDead" | "extracted" | "finalBossKilled" | "mapClosed" }
	-- A skill fired: where from and what it aimed at, for the client's effect.
	| {
		kind: "cast",
		player: number,
		skill: string,
		x: number,
		z: number,
		targetX: number?,
		targetZ: number?,
		radius: number,
		-- The enemies struck, in order (a chain's path).
		targets: { number },
	}
	-- A projectile or area landed: the area to draw.
	| { kind: "burst", x: number, z: number, radius: number, skill: string }
	| {
		kind: "areaPlaced",
		id: number,
		owner: "player" | "enemy",
		areaKind: string,
		x: number,
		z: number,
		radius: number,
		seconds: number,
	}
	| { kind: "totemPlaced", id: number, skill: string, x: number, z: number, seconds: number }
	| { kind: "utility", player: number, utility: string }
	| { kind: "statusApplied", enemyId: number, status: Status, seconds: number }
	-- An enemy started winding up: the marker to draw, where and for how long.
	| {
		kind: "telegraph",
		enemyId: number,
		attackKind: AttackKind,
		x: number,
		z: number,
		radius: number,
		seconds: number,
		-- charge: where the rush ends.
		endX: number?,
		endZ: number?,
	}
	| {
		kind: "enemyAttack",
		enemyId: number,
		enemyKind: string,
		attackKind: AttackKind,
		x: number,
		z: number,
		radius: number,
	}
	| { kind: "exploded", enemyId: number, x: number, z: number, radius: number }
	| { kind: "enemyHealed", enemyId: number, by: number, amount: number }
	| { kind: "bossSpawned", enemyId: number, enemyKind: string, final: boolean }
	| { kind: "bossPhase", enemyId: number, phase: number }
	| { kind: "closingRing", count: number }
	| { kind: "crystalDropped", id: number, x: number, z: number, xp: number }
	| { kind: "crystalCollected", id: number, player: number, xp: number }
	| { kind: "foodDropped", id: number, x: number, z: number }
	| { kind: "foodEaten", id: number, player: number, amount: number }
	| { kind: "compass", x: number, z: number }
	| { kind: "chestOpened", player: number }
	| { kind: "castStarted", player: number, seconds: number }
	| { kind: "castInterrupted", player: number }
	| { kind: "portalOpened", x: number, z: number, seconds: number }
	| { kind: "portalClosed" }
	| { kind: "finalBossTimer", seconds: number }

export type Rng = {
	-- A float in [0, 1).
	next: (self: Rng) -> number,
	-- An integer in [min, max].
	integer: (self: Rng, min: number, max: number) -> number,
}

export type Portal = { x: number, z: number, until_: number }

export type Run = {
	config: Config,
	map: MapConfig,
	rng: Rng,
	seed: number,
	time: number,
	arena: Arena,
	nextId: number,
	enemies: { Enemy },
	projectiles: { Projectile },
	areas: { Area },
	totems: { Totem },
	crystals: { Crystal },
	foods: { Food },
	players: { [number]: Player },
	-- The horde's bookkeeping: when it next spawns, which bosses and closing
	-- rings have come, whether the final boss is up and when it must be dead.
	nextSpawnAt: number,
	bossesSpawned: number,
	ringsSpawned: number,
	finalBossId: number?,
	finalBossDeadline: number?,
	-- The extraction chest and the portal (ADR-0015).
	chestOpened: boolean,
	compassOn: boolean,
	portal: Portal?,
	-- The run stands still while a solo player chooses a card.
	paused: boolean,
	ended: boolean,
	events: { Event },
}

-- What the adapter tells the core about one player in one step: where the
-- character stands.
export type PlayerInput = { x: number, z: number }

return nil
