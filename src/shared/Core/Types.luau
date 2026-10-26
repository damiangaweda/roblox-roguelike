--!strict
-- Types shared by the pure rules core (ADR-0002). Positions are on the ground
-- plane: x and z in studs. Times are run seconds since the run started.

export type Tag = "fire" | "ice"

export type EnemyKindConfig = {
	health: number,
	speed: number,
	contactDps: number,
	xp: number,
	radius: number,
}

export type PerkConfig = {
	name: string,
	tags: { Tag },
	-- How many times a player can take the perk; 1 means once.
	maxStacks: number,
}

export type Config = {
	run: {
		durationSeconds: number,
		zonesOpenAtSeconds: number,
		zoneCount: number,
		zoneRadius: number,
		extractSeconds: number,
		zonePoints: { { x: number, z: number } },
		summarySeconds: number,
		-- How long after the start a newcomer may still join the run.
		lateJoinSeconds: number,
	},
	arena: {
		halfSize: number,
	},
	player: {
		-- How far from a player's centre an enemy touches them.
		radius: number,
		walkSpeed: number,
		maxHealth: number,
		downedSeconds: number,
		reviveSeconds: number,
		reviveRadius: number,
		-- Share of max health a revived player comes back with.
		reviveHealthFraction: number,
	},
	basicAttack: {
		damage: number,
		intervalSeconds: number,
		range: number,
	},
	activeSkill: {
		damage: number,
		cooldownSeconds: number,
		range: number,
		radius: number,
	},
	horde: {
		maxAlive: number,
		spawnPerSecondAtStart: number,
		spawnPerSecondGrowthPerMinute: number,
		spawnRingMin: number,
		spawnRingMax: number,
		bruteShareAtStart: number,
		bruteShareGrowthPerMinute: number,
		bruteShareMax: number,
		separationRadius: number,
		kinds: { [string]: EnemyKindConfig },
	},
	statuses: {
		burnSeconds: number,
		burnDps: number,
		chillSeconds: number,
		chillSlow: number,
	},
	synergy: {
		-- Fire damage dealt to a chilled enemy is multiplied by this.
		shatterMultiplier: number,
	},
	perks: {
		offerSize: number,
		quickHandsIntervalFactor: number,
		toughnessHealth: number,
		pool: { [string]: PerkConfig },
	},
	progression: {
		xpToSecondLevel: number,
		xpGrowth: number,
	},
	net: {
		-- The server advances the run this many times per second.
		stepHz: number,
		-- World snapshots and event batches sent to clients per second.
		snapshotHz: number,
		-- Intents a client may send per second before extras are dropped.
		intentsPerSecond: number,
	},
}

export type Enemy = {
	id: number,
	kind: string,
	x: number,
	z: number,
	health: number,
	chilledUntil: number,
	burningUntil: number,
	-- The player credited with damage from burning, and with the kill.
	burnSource: number?,
}

export type PlayerState = "alive" | "downed" | "dead" | "extracted"

export type Player = {
	id: number,
	x: number,
	z: number,
	state: PlayerState,
	health: number,
	maxHealth: number,
	downedAt: number?,
	reviveProgress: number,
	extractProgress: number,
	level: number,
	xp: number,
	-- Perk id to the number of stacks taken.
	perks: { [string]: number },
	-- Offers waiting for a choice, oldest first; each lists perk ids.
	offers: { { string } },
	basicReadyAt: number,
	activeSkillReadyAt: number,
	kills: number,
}

export type Zone = {
	x: number,
	z: number,
	radius: number,
}

export type Event =
	{
		kind: "hit",
		source: number,
		enemyId: number,
		amount: number,
		synergy: boolean,
		activeSkill: boolean,
	}
	| { kind: "kill", source: number, enemyId: number }
	| { kind: "playerHurt", player: number, amount: number }
	| { kind: "levelUp", player: number, level: number }
	| { kind: "offer", player: number, perks: { string } }
	| { kind: "perkTaken", player: number, perk: string }
	| { kind: "downed", player: number }
	| { kind: "revived", player: number, by: number }
	| { kind: "died", player: number }
	| { kind: "extracted", player: number }
	| { kind: "zonesOpened" }
	| { kind: "flood" }
	| { kind: "ended" }

export type Rng = {
	-- A float in [0, 1).
	next: (self: Rng) -> number,
	-- An integer in [min, max].
	integer: (self: Rng, min: number, max: number) -> number,
}

export type Run = {
	config: Config,
	rng: Rng,
	time: number,
	nextEnemyId: number,
	spawnDebt: number,
	enemies: { Enemy },
	players: { [number]: Player },
	zones: { Zone },
	zonesOpen: boolean,
	flooded: boolean,
	ended: boolean,
	-- Events produced since the adapter last drained them.
	events: { Event },
}

-- What the adapter tells the core about one player in one step.
export type PlayerInput = {
	x: number,
	z: number,
}

return nil
