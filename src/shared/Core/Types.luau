--!strict
-- Types shared by the pure rules core (ADR-0002). Positions are on the ground
-- plane: x and z in studs. Angles are radians on that plane, measured from +x
-- toward +z. Times are run seconds since the run started.

export type Tag = "fire" | "ice" | "lightning"

export type Point = { x: number, z: number }

-- An axis-aligned rectangle given by its centre and half extents.
export type Rect = { x: number, z: number, halfWidth: number, halfDepth: number }

-- A hand-made room layout (ADR-0008): data the generator reads. Points are
-- relative to the room's centre.
export type RoomTemplate = {
	id: string,
	halfWidth: number,
	halfDepth: number,
	-- Where the camp gathers.
	camp: Point,
	-- Where a chest stands (stage 2b).
	chest: Point,
	-- Cover spots; each hides a player within config.world.coverRadius.
	cover: { Point },
}

export type Room = {
	id: number,
	-- The grid cell the room occupies.
	cellX: number,
	cellZ: number,
	-- The centre and half extents, in studs.
	x: number,
	z: number,
	halfWidth: number,
	halfDepth: number,
	template: string,
	-- Ids of the corridors leaving the room, and of the rooms they lead to,
	-- in the same order.
	corridors: { number },
	neighbours: { number },
	-- Corridors to the nearest start room; 0 for a start room.
	distance: number,
	-- 1 next to the starts, config.world.maxLevel deepest.
	level: number,
	isStart: boolean,
	-- Whether an extraction zone sits at the room's centre.
	hasZone: boolean,
	-- Absolute positions resolved from the template.
	campX: number,
	campZ: number,
	cover: { Point },
}

export type Corridor = {
	id: number,
	roomA: number,
	roomB: number,
	x: number,
	z: number,
	halfWidth: number,
	halfDepth: number,
}

export type World = {
	rooms: { Room },
	corridors: { Corridor },
	startRooms: { number },
	zoneRooms: { number },
	-- nextHop[from][to] is the neighbouring room to walk to on the way from
	-- room `from` to room `to`; nextHop[r][r] is r.
	nextHop: { { number } },
	-- hops[from][to] is the number of corridors between the rooms.
	hops: { { number } },
	bounds: Rect,
}

-- A hand-made point layout (ADR-0012): data the generator reads. Positions
-- are relative to the point's centre.
export type PointTemplate = {
	id: string,
	-- The footprint flattened on the terrain, in studs from the centre.
	radius: number,
	-- Where the camp gathers; nil for a template without a camp (entries).
	camp: Point?,
	chest: Point,
	-- Where a clue can stand (stage 2d reads it).
	clue: Point,
	-- Cover spots; each hides a player within config.map.coverRadius.
	cover: { Point },
	-- Solid props (ruin walls, a well): axis-aligned rects relative to the
	-- centre, which stop movement, shots and bursts.
	props: { Rect },
}

export type MapPoint = {
	id: number,
	x: number,
	z: number,
	template: string,
	radius: number,
	-- Ids of the paths leaving the point and of the points they lead to, in
	-- the same order.
	paths: { number },
	neighbours: { number },
	-- Paths to the nearest entry; 0 for an entry.
	distance: number,
	-- 1 next to the entries, config.map.maxLevel farthest.
	level: number,
	isEntry: boolean,
	hasZone: boolean,
	-- Absolute positions resolved from the template; campX/campZ nil for an
	-- entry.
	campX: number?,
	campZ: number?,
	cover: { Point },
	-- Absolute prop rects; a prop a path would cross is left out.
	props: { Rect },
}

export type Path = {
	id: number,
	a: number,
	b: number,
	-- Straight: from point a's centre to point b's centre; halfWidth is the
	-- band drawn on the ground and kept walkable.
	halfWidth: number,
}

export type Map = {
	-- The map is the square [-half, half] on both axes.
	half: number,
	points: { MapPoint },
	paths: { Path },
	entries: { number },
	zonePoints: { number },
	-- nextHop[from][to] is the neighbouring point to walk to on the way from
	-- point `from` to point `to`; nextHop[p][p] is p. hops[from][to] is the
	-- number of paths between the points.
	nextHop: { { number } },
	hops: { { number } },
	-- Heights on a grid of heightCell studs: heights[row][col], row along z,
	-- col along x, both from -half; a value below waterLevel is water.
	heights: { { number } },
	heightCell: number,
	waterLevel: number,
	-- Cover scattered between points (bushes), absolute.
	fieldCover: { Point },
	-- The ids of the points whose footprint overlaps a grid cell, keyed by
	-- (row - 1) * columns + col of the cell's lower corner; absent when none.
	pointCells: { [number]: { number } },
}

-- Where a point is: in a room, in a corridor, or outside the walkable world.
export type Location = { kind: "room" | "corridor" | "outside", id: number }

export type AttackKind = "melee" | "projectile" | "burst" | "heal"

export type AttackConfig = {
	kind: AttackKind,
	-- The telegraph: how long the wind-up before the attack lands is visible.
	telegraphSeconds: number,
	-- How long the enemy stands still after the attack.
	recoverSeconds: number,
	cooldownSeconds: number,
	-- The attack starts when the target is this close (a heal: always).
	range: number,
	damage: number,
	-- melee and burst: the area hit around the enemy; projectile: the area hit
	-- where it lands (0 hits only what it strikes); heal: who is healed.
	radius: number,
	-- Studs a hit player is pushed away from the enemy.
	knockback: number,
	-- melee: the frontal arc that is hit, in degrees; 360 hits all around.
	arcDegrees: number?,
	projectileSpeed: number?,
	-- projectile: how many fly at once, spread evenly over spreadDegrees.
	projectileCount: number?,
	spreadDegrees: number?,
	-- heal: health restored to each camp member in radius, and how long they
	-- stay buffed.
	heal: number?,
	buffSeconds: number?,
}

export type ArchetypeConfig = {
	name: string,
	health: number,
	speed: number,
	radius: number,
	xp: number,
	-- How close a player must come to be noticed (halved in cover).
	detectionRange: number,
	-- How far from home the enemy chases before it walks back.
	leash: number,
	-- An enemy that keeps its distance backs away when the target is closer
	-- than this.
	preferredRange: number?,
	-- The attacks used in turn; most archetypes have one, the camp leader two.
	attacks: { AttackConfig },
	-- Hits from within this frontal arc (degrees) are blocked.
	blockArcDegrees: number?,
	-- The enemy dies when its attack lands (the exploder).
	diesOnAttack: boolean?,
}

-- One group of a camp's composition.
export type CampGroup = { archetype: string, count: number }

export type CampLevelConfig = {
	groups: { CampGroup },
	-- Chance that the camp has a camp leader.
	leaderChance: number,
	-- Enemies added when one more player stands in the camp's room, and the
	-- health multiplier applied to the living members for each such player.
	extraPerPlayer: number,
	healthPerExtraPlayer: number,
}

export type SkillShape = "line" | "projectile" | "ring" | "chain"

export type SkillConfig = {
	id: string,
	name: string,
	shape: SkillShape,
	damage: number,
	-- The basic attack's interval between shots, an active skill's cooldown.
	cooldownSeconds: number,
	-- line, projectile: how far it reaches; chain: how far the first jump looks.
	range: number,
	-- projectile: the burst where it lands; ring: around the player.
	radius: number,
	-- line: how wide the burst is.
	width: number,
	-- line: how many enemies beyond the first it passes through.
	pierce: number,
	-- chain: how many enemies it jumps between, how far one jump reaches, and
	-- the cone around the aim the first target is picked from.
	jumps: number,
	jumpRange: number,
	coneDegrees: number,
	-- projectile: studs per second.
	speed: number,
	-- Studs enemies hit are pushed.
	knockback: number,
	tags: { Tag },
}

export type DashConfig = {
	distance: number,
	-- How long the burst takes; with the distance, the dash's speed.
	seconds: number,
	charges: number,
	-- Seconds for one charge to come back.
	rechargeSeconds: number,
}

export type ClassConfig = {
	name: string,
	basic: SkillConfig,
	actives: { SkillConfig },
	dash: DashConfig,
}

-- A property skills (or the player) can have, which perks modify.
export type Property =
	"damage"
	| "cooldown"
	| "attackSpeed"
	| "range"
	| "area"
	| "statusDuration"
	| "projectileSplit"
	| "pierce"
	| "chainJumps"
	| "knockback"
	| "maxHealth"
	| "moveSpeed"
	| "dashCharges"
	| "dashDistance"
	| "potionCapacity"
	| "potionHeal"
	| "burnDamage"
	| "chillSlow"
	| "synergyBonus"
	| "xpGain"

-- A skill's numbers after the player's perks: what Combat fires.
export type EffectiveSkill = {
	id: string,
	name: string,
	shape: SkillShape,
	damage: number,
	cooldownSeconds: number,
	range: number,
	radius: number,
	width: number,
	pierce: number,
	-- projectile: how many fly at once.
	count: number,
	jumps: number,
	jumpRange: number,
	coneDegrees: number,
	speed: number,
	knockback: number,
	tags: { Tag },
	-- Multiplies the durations of the statuses it applies.
	statusFactor: number,
}

-- Property name to the multiplier and addend the player's perks give it.
export type Modifiers = { [string]: { mul: number, add: number } }

export type PerkConfig = {
	name: string,
	property: Property,
	-- Each stack multiplies the property by `mul` and adds `add`.
	mul: number?,
	add: number?,
	-- How many times a player can take the perk; 1 means once.
	maxStacks: number,
}

export type MapConfig = {
	-- The half side grows with the players: studsPerPlayer * players,
	-- clamped to [minHalf, maxHalf].
	studsPerPlayer: number,
	minHalf: number,
	maxHalf: number,
	pointsPerPlayer: number,
	minPoints: number,
	maxPoints: number,
	-- Centre to centre, at least.
	pointSpacing: number,
	-- No point centre closer than this to the edge.
	edgeMargin: number,
	-- Entries lie within this many studs inward of edgeMargin.
	entryBand: number,
	-- Candidates drawn for each point, entry or bush before it is given up.
	placementAttempts: number,
	-- Chance of each link beyond the spanning tree, from the neighbour graph.
	extraLinkChance: number,
	pathHalfWidth: number,
	playersPerEntry: number,
	maxEntries: number,
	-- Entries at least this far apart, in studs.
	minEntrySpacing: number,
	maxLevel: number,
	playersPerZone: number,
	minZones: number,
	maxZones: number,
	zoneRadius: number,
	-- How much a point's depth counts against its distance from other
	-- zones when extraction zones are placed.
	zoneDepthWeight: number,
	coverRadius: number,
	-- Bushes scattered between points, per point, and how far they keep
	-- from footprints and path bands.
	fieldCoverPerPoint: number,
	fieldCoverClearance: number,
	heightCell: number,
	-- Hills from 0 to this.
	maxHeight: number,
	-- Below it water; points and paths stay at least one stud above it.
	waterLevel: number,
	-- Cycles per stud of the value noise.
	hillFrequency: number,
	campReturnMinutes: number,
	templates: { PointTemplate },
	entryTemplate: PointTemplate,
}

export type Config = {
	run: {
		durationSeconds: number,
		extractSeconds: number,
		summarySeconds: number,
		-- How long after the start a newcomer may still join the run.
		lateJoinSeconds: number,
	},
	world: {
		-- The pitch of the grid rooms sit on; a corridor spans the gap.
		cellSize: number,
		corridorHalfWidth: number,
		roomsPerPlayer: number,
		minRooms: number,
		maxRooms: number,
		-- Corridors a room may have at most.
		maxExits: number,
		-- Chance that two adjacent rooms not yet joined get a corridor.
		loopChance: number,
		playersPerStart: number,
		maxStarts: number,
		-- The fewest corridors between two start rooms.
		minStartDistance: number,
		maxLevel: number,
		playersPerZone: number,
		minZones: number,
		maxZones: number,
		zoneRadius: number,
		-- How much a room's depth counts against its distance from other zones
		-- when extraction zones are placed.
		zoneDepthWeight: number,
		coverRadius: number,
		-- A camp in a room with a zone, or none.
		campsInZoneRooms: boolean,
		templates: { RoomTemplate },
	},
	map: MapConfig,
	player: {
		-- How far from a player's centre an attack touches them.
		radius: number,
		walkSpeed: number,
		-- Movement the run accepts, as a multiple of walkSpeed, so lag is
		-- forgiven and a teleport is not.
		moveTolerance: number,
		-- Seconds of movement a player may bank while their updates are late.
		moveBurstSeconds: number,
		-- How far a character may drift from the run's position before the
		-- server puts it back.
		correctionDistance: number,
		maxHealth: number,
		downedSeconds: number,
		reviveSeconds: number,
		reviveRadius: number,
		-- Share of max health a revived player comes back with.
		reviveHealthFraction: number,
		potionCapacity: number,
		potionHeal: number,
		drinkSeconds: number,
		-- How close a player walks to a pickup to take it.
		pickupRadius: number,
		-- Over how long a knockback moves its target.
		knockbackSeconds: number,
		-- Walk speed multiplier while firing and moving against the aim, and the
		-- dot product of the move and the aim below which a move is backwards.
		backpedalFactor: number,
		backpedalDot: number,
	},
	aim: {
		-- Touch and gamepad: the aim snaps to an enemy within this cone and range.
		assistConeDegrees: number,
		assistRange: number,
	},
	projectiles: {
		-- How far beyond a body's radius a projectile still touches it.
		touchMargin: number,
		-- An enemy projectile flies this many times its attack's range.
		overshoot: number,
	},
	classes: { [string]: ClassConfig },
	enemies: {
		maxAlive: number,
		separationRadius: number,
		-- Detection range multiplier for a player in cover.
		coverDetectionFactor: number,
		-- Whether one member noticing a player wakes the whole camp.
		campAlerts: boolean,
		-- Share of max health an enemy has back when it reaches home.
		returnHealFraction: number,
		-- An enemy counts as home or at a waypoint within this distance.
		arriveDistance: number,
		-- An enemy stops closing in at this share of its attack's range.
		approachFactor: number,
		-- Speed multiplier of a buffed enemy.
		buffSpeedFactor: number,
		-- Damage multiplier of a buffed enemy.
		buffDamageFactor: number,
		archetypes: { [string]: ArchetypeConfig },
		campLeader: string,
		-- Indexed by room level.
		camps: { CampLevelConfig },
		-- Studs from the camp spot that camp members stand at.
		campSpreadRadius: number,
		patrols: {
			groupsAtStart: number,
			groupsPerMinute: number,
			sizeAtStart: number,
			sizeGrowthPerMinute: number,
			maxSize: number,
			healthGrowthPerMinute: number,
			-- Archetypes drawn from before and after `lateMinutes`.
			pool: { string },
			latePool: { string },
			lateMinutes: number,
			-- A patrol appears at least this many corridors from every player.
			minHopsFromPlayers: number,
			-- The pool a lone wanderer is drawn from, and how many roam at start.
			wandererPool: { string },
			wanderersAtStart: number,
		},
	},
	statuses: {
		burnSeconds: number,
		burnDps: number,
		chillSeconds: number,
		chillSlow: number,
		brittleSeconds: number,
		-- Damage taken by a brittle enemy is multiplied by this.
		brittleMultiplier: number,
		-- Conduct spreads burning to enemies within this distance.
		conductRadius: number,
	},
	synergy: {
		-- Fire damage dealt to a chilled enemy is multiplied by this.
		shatterMultiplier: number,
	},
	perks: {
		offerSize: number,
		splitSpreadDegrees: number,
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

export type EnemyState = "idle" | "chase" | "telegraph" | "recover" | "return" | "patrol"

export type Enemy = {
	id: number,
	archetype: string,
	level: number,
	x: number,
	z: number,
	facing: number,
	health: number,
	maxHealth: number,
	-- The camp or patrol the enemy belongs to; a wanderer is a patrol of one.
	campId: number?,
	patrolId: number?,
	-- Where the leash is measured from: the camp spot, or where a patrol
	-- member started chasing.
	homeX: number,
	homeZ: number,
	state: EnemyState,
	-- When a telegraph lands or a recovery ends.
	stateUntil: number,
	-- The player chased.
	target: number?,
	-- Index into the archetype's attacks of the attack being telegraphed, or
	-- the next one to use.
	attack: number,
	-- The point locked when the telegraph started.
	aimX: number,
	aimZ: number,
	attackReadyAt: number,
	-- A patrol member's destination room.
	routeRoom: number?,
	chilledUntil: number,
	burningUntil: number,
	-- The player credited with damage from burning, and with the kill.
	burnSource: number?,
	brittleUntil: number,
	buffedUntil: number,
	-- Knockback velocity in studs per second, applied until knockUntil.
	knockX: number,
	knockZ: number,
	knockUntil: number,
}

export type Camp = {
	id: number,
	roomId: number,
	x: number,
	z: number,
	level: number,
	-- Ids of the living members.
	members: { number },
	alerted: boolean,
	-- How many players the camp has grown for.
	scaledFor: number,
	leaderId: number?,
	-- Run time when its last member died; nil while it holds its point.
	clearedAt: number?,
	-- Whether the camp comes back after it is cleared (never at an entry).
	returns: boolean?,
}

export type Patrol = {
	id: number,
	members: { number },
	routeRoom: number,
	previousRoom: number,
	-- Multiplies the health of members spawned later in the run.
	strength: number,
}

export type Projectile = {
	id: number,
	owner: "player" | "enemy",
	-- The player or enemy id that fired it.
	source: number,
	-- The skill id or archetype that fired it.
	kind: string,
	x: number,
	z: number,
	dirX: number,
	dirZ: number,
	speed: number,
	-- Studs left to fly before it lands.
	remaining: number,
	damage: number,
	radius: number,
	knockback: number,
	tags: { Tag },
	-- Multiplies status durations of the hit (perks).
	statusFactor: number,
}

export type Pickup = {
	id: number,
	kind: "potion",
	x: number,
	z: number,
}

export type PlayerState = "alive" | "downed" | "dead" | "extracted"

export type Player = {
	id: number,
	class: string,
	x: number,
	z: number,
	-- The aim: where the character faces (ADR-0009).
	facing: number,
	-- Whether the aim snaps to the nearest enemy in the assist cone.
	assist: boolean,
	-- Whether the basic attack's input is held.
	firing: boolean,
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
	-- One entry per active skill.
	skillReadyAt: { number },
	dashCharges: number,
	-- When the next charge comes back; meaningful while charges are missing.
	dashRechargeAt: number,
	potions: number,
	-- Set while drinking; nil otherwise.
	drinkingUntil: number?,
	kills: number,
	-- Studs the player may still move before the run holds them back.
	moveBudget: number,
	-- Extra studs a dash grants, usable until boostUntil; then they lapse, so a
	-- dash not taken cannot be banked.
	boost: number,
	boostUntil: number,
	-- Whether the player holds the interact button, which revives a downed
	-- player nearby or extracts in a zone.
	interacting: boolean,
	-- Run time of the last damage taken; a hit interrupts reviving.
	hurtAt: number,
	-- Knockback velocity in studs per second, applied until knockUntil.
	knockX: number,
	knockZ: number,
	knockUntil: number,
	-- The room the player stands in, refreshed each step; nil in a corridor.
	roomId: number?,
	inCover: boolean,
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
		-- "shatter", "conduct" or "brittle" when a synergy fired.
		synergy: string?,
		skill: string,
		blocked: boolean,
	}
	| { kind: "kill", source: number, enemyId: number, archetype: string }
	| { kind: "playerHurt", player: number, amount: number, enemyId: number? }
	| { kind: "knockback", player: number, dx: number, dz: number }
	| { kind: "levelUp", player: number, level: number }
	| { kind: "offer", player: number, perks: { string } }
	| { kind: "perkTaken", player: number, perk: string }
	| { kind: "downed", player: number }
	| { kind: "revived", player: number, by: number }
	| { kind: "died", player: number }
	| { kind: "extracted", player: number }
	| { kind: "flood" }
	| { kind: "ended" }
	-- An enemy started winding up: the marker to draw, where and for how long.
	| {
		kind: "telegraph",
		enemyId: number,
		attack: number,
		x: number,
		z: number,
		radius: number,
		seconds: number,
	}
	-- The attack landed at (x, z).
	| { kind: "enemyAttack", enemyId: number, archetype: string, attack: number, x: number, z: number }
	| { kind: "exploded", enemyId: number, x: number, z: number, radius: number }
	| { kind: "healed", enemyId: number, by: number, amount: number }
	| { kind: "campAlerted", campId: number }
	| { kind: "campScaled", campId: number, players: number }
	| { kind: "patrolSpawned", patrolId: number, roomId: number }
	| { kind: "dashed", player: number }
	| { kind: "drinking", player: number }
	| { kind: "drank", player: number, amount: number }
	| { kind: "drinkInterrupted", player: number }
	| { kind: "pickedUp", player: number, pickup: "potion" }
	| { kind: "dropped", x: number, z: number, pickup: "potion" }
	| { kind: "skillUsed", player: number, skill: string, x: number, z: number, facing: number }
	-- A projectile or ring landed: the area to draw.
	| { kind: "burst", x: number, z: number, radius: number, skill: string }

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
	world: World,
	nextEnemyId: number,
	nextCampId: number,
	nextPatrolId: number,
	nextProjectileId: number,
	nextPickupId: number,
	-- Patrol groups owed by the spawn rate, carried between steps.
	patrolDebt: number,
	enemies: { Enemy },
	camps: { Camp },
	patrols: { Patrol },
	projectiles: { Projectile },
	pickups: { Pickup },
	players: { [number]: Player },
	zones: { Zone },
	flooded: boolean,
	ended: boolean,
	-- Events produced since the adapter last drained them.
	events: { Event },
}

-- What the adapter tells the core about one player in one step: where the
-- character stands. The aim arrives as an intent (ADR-0009).
export type PlayerInput = {
	x: number,
	z: number,
}

return nil
