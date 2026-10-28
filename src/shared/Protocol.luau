--!strict
-- The wire format between the server and clients. Clients only send intents,
-- which the server parses here before anything reaches the run (AGENTS.md
-- rule 1). Pure Luau, so it is tested under Lune like the core.

local Hero = require("./Core/Hero")
local Progression = require("./Core/Progression")
local State = require("./Core/State")
local Types = require("./Core/Types")

local Protocol = {}

Protocol.remotes = {
	-- Client to server: an intent.
	intent = "Intent",
	-- Server to every client: the shared state of the run.
	world = "World",
	-- Server to one client: events it may see and its own state.
	events = "Events",
	-- Server to one client: its phase (pick, run or summary) and, with the
	-- summary, how its run went.
	phase = "Phase",
}

export type Intent =
	{ kind: "pickClass", class: string }
	| { kind: "card", index: number }
	| { kind: "utility", index: number }
	| { kind: "interact", held: boolean }
	| { kind: "cast" }
	| { kind: "enter" }
	-- A dash in a direction; the run normalises it.
	| { kind: "dash", dx: number, dz: number }

-- More than any offer's cards or the utility buttons; the run checks the real count.
local MAX_INDEX = 6

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isSmallIndex(value: any, max: number): boolean
	return isFiniteNumber(value) and value == math.floor(value) and value >= 1 and value <= max
end

-- Parses the arguments of an Intent remote. Returns nil for anything malformed;
-- whether the intent applies now (an offer waiting, a cooldown, the chest in
-- reach) is the run's to check.
function Protocol.parseIntent(config: Types.Config, kind: any, a: any, b: any): Intent?
	if kind == "dash" then
		local max = config.player.dashInputMax
		if
			isFiniteNumber(a)
			and isFiniteNumber(b)
			and (a ~= 0 or b ~= 0)
			and math.abs(a) <= max
			and math.abs(b) <= max
		then
			return { kind = "dash", dx = a, dz = b }
		end
		return nil
	end
	if b ~= nil then
		return nil
	end
	if kind == "pickClass" then
		if type(a) == "string" and config.classes[a] ~= nil then
			return { kind = "pickClass", class = a }
		end
	elseif kind == "card" then
		if isSmallIndex(a, MAX_INDEX) then
			return { kind = "card", index = a }
		end
	elseif kind == "utility" then
		if isSmallIndex(a, MAX_INDEX) then
			return { kind = "utility", index = a }
		end
	elseif kind == "interact" then
		if type(a) == "boolean" then
			return { kind = "interact", held = a }
		end
	elseif kind == "cast" then
		if a == nil then
			return { kind = "cast" }
		end
	elseif kind == "enter" then
		if a == nil then
			return { kind = "enter" }
		end
	end
	return nil
end

local function sorted(names: { string }): { string }
	table.sort(names)
	return names
end

-- Enemy kinds travel as their index in the sorted list of ids.
function Protocol.enemyKinds(config: Types.Config): { string }
	local names = {}
	for id in config.enemies do
		table.insert(names, id)
	end
	return sorted(names)
end

-- Projectile kinds: every skill that flies and every enemy kind that shoots, sorted.
function Protocol.projectileKinds(config: Types.Config): { string }
	local names = {}
	for id, skill in config.skills do
		if skill.speed > 0 then
			table.insert(names, id)
		end
	end
	for id, kind in config.enemies do
		for _, attack in kind.attacks do
			if attack.kind == "projectile" then
				table.insert(names, id)
				break
			end
		end
	end
	return sorted(names)
end

local function indexOf(names: { string }): { [string]: number }
	local index = {}
	for i, name in names do
		index[name] = i
	end
	return index
end

-- Positions travel in tenths of a stud as int16, which covers +-3276 studs.
local POSITION_SCALE = 10

local function writePosition(out: buffer, offset: number, value: number)
	buffer.writei16(out, offset, math.clamp(math.round(value * POSITION_SCALE), -32768, 32767))
end

local function readPosition(data: buffer, offset: number): number
	return buffer.readi16(data, offset) / POSITION_SCALE
end

local function writeAngle(out: buffer, offset: number, angle: number)
	buffer.writeu8(out, offset, math.round((angle % (2 * math.pi)) / (2 * math.pi) * 256) % 256)
end

local function readAngle(data: buffer, offset: number): number
	return buffer.readu8(data, offset) / 256 * 2 * math.pi
end

-- The record count after a u16 header, or nil when the length does not match.
local function recordCount(data: any, recordBytes: number): number?
	if type(data) ~= "buffer" or buffer.len(data) < 2 then
		return nil
	end
	local count = buffer.readu16(data, 0)
	if buffer.len(data) ~= 2 + count * recordBytes then
		return nil
	end
	return count
end

local STATES: { Types.EnemyState } = { "chase", "telegraph", "charge", "recover" }

export type EnemyView = {
	id: number,
	kind: string,
	x: number,
	z: number,
	facing: number,
	state: Types.EnemyState,
	-- Health as a share of the maximum, in [0, 1].
	health: number,
	slowed: boolean,
	rooted: boolean,
	stunned: boolean,
	feared: boolean,
	burning: boolean,
	bleeding: boolean,
	poisoned: boolean,
	buffed: boolean,
	-- A boss's phase; 1 for everything else.
	phase: number,
	-- Asleep in its lair (a boss or a guard).
	asleep: boolean,
}

-- One enemy on the wire, after a u16 count:
--   0 u32 id, 4 u8 kind index, 5 i16 x, 7 i16 z, 9 u8 facing,
--   10 u8 state (chase 0, telegraph 1, charge 2, recover 3), 11 u8 health
--   share, 12 u8 flags, 13 u8 phase.
local ENEMY_BYTES = 14
-- The top bit of the phase byte: the enemy sleeps in its lair.
local ASLEEP_BIT = 128
local FLAG_SLOWED = 1
local FLAG_ROOTED = 2
local FLAG_STUNNED = 4
local FLAG_FEARED = 8
local FLAG_BURNING = 16
local FLAG_BLEEDING = 32
local FLAG_POISONED = 64
local FLAG_BUFFED = 128

local DOT_FLAGS = { burning = FLAG_BURNING, bleeding = FLAG_BLEEDING, poisoned = FLAG_POISONED }

local function enemyFlags(run: Types.Run, enemy: Types.Enemy): number
	local now = run.time
	local flags = 0
	if now < enemy.slowUntil or now < enemy.chilledUntil then
		flags += FLAG_SLOWED
	end
	if now < enemy.rootedUntil then
		flags += FLAG_ROOTED
	end
	if now < enemy.stunnedUntil then
		flags += FLAG_STUNNED
	end
	if now < enemy.fearedUntil then
		flags += FLAG_FEARED
	end
	for _, dot in enemy.dots do
		if now < dot.until_ then
			flags = bit32.bor(flags, DOT_FLAGS[dot.status])
		end
	end
	if now < enemy.buffedUntil then
		flags += FLAG_BUFFED
	end
	return flags
end

local function hasFlag(flags: number, flag: number): boolean
	return bit32.band(flags, flag) ~= 0
end

function Protocol.encodeEnemies(run: Types.Run, kinds: { string }): buffer
	local index = indexOf(kinds)
	local enemies = run.enemies
	local out = buffer.create(2 + #enemies * ENEMY_BYTES)
	buffer.writeu16(out, 0, #enemies)
	for i, enemy in enemies do
		local offset = 2 + (i - 1) * ENEMY_BYTES
		buffer.writeu32(out, offset, enemy.id)
		buffer.writeu8(out, offset + 4, index[enemy.kind] or 0)
		writePosition(out, offset + 5, enemy.x)
		writePosition(out, offset + 7, enemy.z)
		writeAngle(out, offset + 9, enemy.facing)
		buffer.writeu8(out, offset + 10, (table.find(STATES, enemy.state) or 1) - 1)
		local health = if enemy.maxHealth > 0 then enemy.health / enemy.maxHealth else 0
		buffer.writeu8(out, offset + 11, math.clamp(math.ceil(health * 255), 0, 255))
		buffer.writeu8(out, offset + 12, enemyFlags(run, enemy))
		-- The phase in the low bits, the sleep flag (ADR-0021) in the top one.
		buffer.writeu8(
			out,
			offset + 13,
			math.clamp(enemy.phase, 0, 127) + (if enemy.asleep then ASLEEP_BIT else 0)
		)
	end
	return out
end

-- Returns nil when the buffer is not a well-formed enemy list.
function Protocol.decodeEnemies(data: any, kinds: { string }): { EnemyView }?
	local count = recordCount(data, ENEMY_BYTES)
	if count == nil then
		return nil
	end
	local enemies: { EnemyView } = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * ENEMY_BYTES
		local kind = kinds[buffer.readu8(data, offset + 4)]
		local state: Types.EnemyState? = STATES[buffer.readu8(data, offset + 10) + 1]
		if kind == nil or state == nil then
			return nil
		end
		local flags = buffer.readu8(data, offset + 12)
		enemies[i] = {
			id = buffer.readu32(data, offset),
			kind = kind,
			x = readPosition(data, offset + 5),
			z = readPosition(data, offset + 7),
			facing = readAngle(data, offset + 9),
			state = state,
			health = buffer.readu8(data, offset + 11) / 255,
			slowed = hasFlag(flags, FLAG_SLOWED),
			rooted = hasFlag(flags, FLAG_ROOTED),
			stunned = hasFlag(flags, FLAG_STUNNED),
			feared = hasFlag(flags, FLAG_FEARED),
			burning = hasFlag(flags, FLAG_BURNING),
			bleeding = hasFlag(flags, FLAG_BLEEDING),
			poisoned = hasFlag(flags, FLAG_POISONED),
			buffed = hasFlag(flags, FLAG_BUFFED),
			phase = buffer.readu8(data, offset + 13) % ASLEEP_BIT,
			asleep = buffer.readu8(data, offset + 13) >= ASLEEP_BIT,
		}
	end
	return enemies
end

export type ProjectileView = {
	id: number,
	-- The skill id or enemy kind that fired it.
	kind: string,
	x: number,
	z: number,
	-- The direction of flight.
	angle: number,
	-- The area it bursts over when it lands; 0 strikes only what it hits.
	radius: number,
}

-- One projectile on the wire, after a u16 count:
--   0 u32 id, 4 u8 kind index, 5 i16 x, 7 i16 z, 9 u8 angle, 10 u16 radius
--   in tenths of a stud.
local PROJECTILE_BYTES = 12
local RADIUS_SCALE = 10

function Protocol.encodeProjectiles(run: Types.Run, kinds: { string }): buffer
	local index = indexOf(kinds)
	local projectiles = run.projectiles
	local out = buffer.create(2 + #projectiles * PROJECTILE_BYTES)
	buffer.writeu16(out, 0, #projectiles)
	for i, projectile in projectiles do
		local offset = 2 + (i - 1) * PROJECTILE_BYTES
		buffer.writeu32(out, offset, projectile.id)
		buffer.writeu8(out, offset + 4, index[projectile.kind] or 0)
		writePosition(out, offset + 5, projectile.x)
		writePosition(out, offset + 7, projectile.z)
		writeAngle(out, offset + 9, math.atan2(projectile.dirZ, projectile.dirX))
		buffer.writeu16(
			out,
			offset + 10,
			math.clamp(math.round(projectile.radius * RADIUS_SCALE), 0, 65535)
		)
	end
	return out
end

-- Returns nil when the buffer is not a well-formed projectile list.
function Protocol.decodeProjectiles(data: any, kinds: { string }): { ProjectileView }?
	local count = recordCount(data, PROJECTILE_BYTES)
	if count == nil then
		return nil
	end
	local projectiles: { ProjectileView } = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * PROJECTILE_BYTES
		local kind = kinds[buffer.readu8(data, offset + 4)]
		if kind == nil then
			return nil
		end
		projectiles[i] = {
			id = buffer.readu32(data, offset),
			kind = kind,
			x = readPosition(data, offset + 5),
			z = readPosition(data, offset + 7),
			angle = readAngle(data, offset + 9),
			radius = buffer.readu16(data, offset + 10) / RADIUS_SCALE,
		}
	end
	return projectiles
end

export type CrystalView = { id: number, x: number, z: number, xp: number }

-- One crystal on the wire, after a u16 count:
--   0 u32 id, 4 i16 x, 6 i16 z, 8 u16 xp (rounded).
local CRYSTAL_BYTES = 10

function Protocol.encodeCrystals(run: Types.Run): buffer
	local crystals = run.crystals
	local out = buffer.create(2 + #crystals * CRYSTAL_BYTES)
	buffer.writeu16(out, 0, #crystals)
	for i, crystal in crystals do
		local offset = 2 + (i - 1) * CRYSTAL_BYTES
		buffer.writeu32(out, offset, crystal.id)
		writePosition(out, offset + 4, crystal.x)
		writePosition(out, offset + 6, crystal.z)
		buffer.writeu16(out, offset + 8, math.clamp(math.round(crystal.xp), 0, 65535))
	end
	return out
end

-- Returns nil when the buffer is not a well-formed crystal list.
function Protocol.decodeCrystals(data: any): { CrystalView }?
	local count = recordCount(data, CRYSTAL_BYTES)
	if count == nil then
		return nil
	end
	local crystals: { CrystalView } = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * CRYSTAL_BYTES
		crystals[i] = {
			id = buffer.readu32(data, offset),
			x = readPosition(data, offset + 4),
			z = readPosition(data, offset + 6),
			xp = buffer.readu16(data, offset + 8),
		}
	end
	return crystals
end

-- The part of a player every client sees.
export type PlayerView = {
	id: number,
	class: string,
	x: number,
	z: number,
	facing: number,
	state: Types.PlayerState,
	health: number,
	maxHealth: number,
	-- The barrier still absorbing damage; 0 when none stands.
	barrier: number,
	-- Seconds left of the extraction spell's cast; 0 when not casting.
	castingLeft: number,
	-- Seconds held at the chest.
	openProgress: number,
	shrineProgress: number,
	dashing: boolean,
	sprinting: boolean,
}

export type AreaView = {
	id: number,
	areaKind: string,
	owner: "player" | "enemy",
	x: number,
	z: number,
	radius: number,
	secondsLeft: number,
}

export type TotemView = {
	id: number,
	skill: string,
	x: number,
	z: number,
	secondsLeft: number,
}

export type FoodView = { id: number, x: number, z: number }

export type ChestView = { x: number, z: number, opened: boolean }

export type PortalView = { x: number, z: number, secondsLeft: number }

-- A shrine as every client sees it: its kind from afar, the id of the boon or
-- pact it gives up close
-- (nil for a trial or a spring), whether it is spent and, for a spring, when
-- it is back. `trial` is true while its ring is being fought.
export type ShrineView = {
	id: number,
	kind: Types.ShrineKind,
	x: number,
	z: number,
	given: string?,
	used: boolean,
	readyIn: number,
	trial: boolean,
}

export type WorldView = {
	time: number,
	paused: boolean,
	ended: boolean,
	-- In id order.
	players: { PlayerView },
	areas: { AreaView },
	totems: { TotemView },
	foods: { FoodView },
	chest: ChestView,
	compassOn: boolean,
	portal: PortalView?,
	-- The bosses alive, drawn with their health bars.
	bossIds: { number },
	shrines: { ShrineView },
	lairs: { LairView },
	-- Doom (ADR-0021): whether it has begun, and seconds until the run's end time.
	doom: boolean,
	doomIn: number,
	-- Seconds until the final boss has risen, while it rises.
	finalRiseLeft: number?,
}

-- A lair as every client sees it.
export type LairView = {
	id: number,
	kind: string,
	x: number,
	z: number,
	radius: number,
	asleep: boolean,
	silenced: boolean,
	bossId: number?,
}

local function secondsLeft(run: Types.Run, until_: number): number
	return math.max(0, until_ - run.time)
end

function Protocol.worldView(run: Types.Run): WorldView
	local players = {}
	for _, player in State.sortedPlayers(run) do
		local castingUntil = player.castingUntil
		table.insert(players, {
			id = player.id,
			class = player.class,
			x = player.x,
			z = player.z,
			facing = player.facing,
			state = player.state,
			health = player.health,
			maxHealth = Hero.stats(run, player).maxHealth,
			barrier = if player.barrierUntil > run.time then player.barrier else 0,
			castingLeft = if castingUntil then secondsLeft(run, castingUntil) else 0,
			openProgress = player.openProgress,
			shrineProgress = player.shrineProgress,
			sprinting = player.sprintUntil > run.time,
			dashing = player.dashUntil > run.time,
		})
	end
	local areas = table.create(#run.areas)
	for _, area in run.areas do
		table.insert(areas, {
			id = area.id,
			areaKind = area.kind,
			owner = area.owner,
			x = area.x,
			z = area.z,
			radius = area.radius,
			secondsLeft = secondsLeft(run, area.until_),
		})
	end
	local totems = table.create(#run.totems)
	for _, totem in run.totems do
		table.insert(totems, {
			id = totem.id,
			skill = totem.skill,
			x = totem.x,
			z = totem.z,
			secondsLeft = secondsLeft(run, totem.until_),
		})
	end
	local foods = table.create(#run.foods)
	for _, food in run.foods do
		table.insert(foods, { id = food.id, x = food.x, z = food.z })
	end
	local shrines = table.create(#run.shrines)
	for _, shrine in run.shrines do
		table.insert(shrines, {
			id = shrine.id,
			kind = shrine.kind,
			x = shrine.x,
			z = shrine.z,
			given = shrine.boon or shrine.pact,
			used = shrine.used,
			readyIn = secondsLeft(run, shrine.readyAt),
			trial = shrine.trialEnemies ~= nil,
		})
	end
	local lairs = table.create(#run.lairs)
	for _, lair in run.lairs do
		table.insert(lairs, {
			id = lair.id,
			kind = lair.kind,
			x = lair.x,
			z = lair.z,
			radius = lair.radius,
			asleep = lair.asleep,
			silenced = lair.silenced,
			bossId = lair.bossId,
		})
	end
	local portal = run.portal
	local bossIds = {}
	for _, enemy in run.enemies do
		if State.isBoss(State.kind(run, enemy)) then
			table.insert(bossIds, enemy.id)
		end
	end
	return {
		time = run.time,
		paused = run.paused,
		ended = run.ended,
		players = players,
		areas = areas,
		totems = totems,
		foods = foods,
		chest = { x = run.arena.chestX, z = run.arena.chestZ, opened = run.chestOpened },
		compassOn = run.compassOn,
		portal = if portal
			then { x = portal.x, z = portal.z, secondsLeft = secondsLeft(run, portal.until_) }
			else nil,
		bossIds = bossIds,
		shrines = shrines,
		lairs = lairs,
		doom = run.doom,
		doomIn = secondsLeft(run, run.config.run.durationSeconds),
		finalRiseLeft = if run.finalRiseAt then secondsLeft(run, run.finalRiseAt) else nil,
	}
end

export type SkillView = {
	id: string,
	rank: number,
	readyIn: number,
	-- The skill's base cooldown; ranks and haste shorten the real one.
	cooldown: number,
}

export type UtilityView = {
	id: string,
	readyIn: number,
	cooldown: number,
}

-- The part of a player only that player sees.
export type SelfView = {
	level: number,
	xp: number,
	xpToNext: number,
	kills: number,
	-- The oldest offer waiting for a choice.
	offer: { Types.Card }?,
	skills: { SkillView },
	-- Passive id to its rank.
	passives: { [string]: number },
	-- In button order.
	utilities: { UtilityView },
	hasSpell: boolean,
	stats: Types.HeroStats,
	dashCharges: number,
	-- Seconds until the next dash charge is back; 0 with every charge held.
	dashReadyIn: number,
	-- The boons and pacts taken, by id, in the order taken.
	shrinesTaken: { string },
}

function Protocol.selfView(run: Types.Run, player: Types.Player): SelfView
	local config = run.config
	local skills = table.create(#player.skills)
	for _, owned in player.skills do
		table.insert(skills, {
			id = owned.id,
			rank = owned.rank,
			readyIn = secondsLeft(run, owned.readyAt),
			cooldown = config.skills[owned.id].cooldownSeconds,
		})
	end
	local utilities = table.create(#config.utilities)
	for index, utility in config.utilities do
		table.insert(utilities, {
			id = utility.id,
			readyIn = secondsLeft(run, player.utilityReadyAt[index] or 0),
			cooldown = utility.cooldownSeconds,
		})
	end
	local oldest = player.offers[1]
	return {
		level = player.level,
		xp = player.xp,
		xpToNext = Progression.xpToNext(config, player.level),
		kills = player.kills,
		offer = if oldest then oldest.cards else nil,
		skills = skills,
		passives = table.clone(player.passives),
		utilities = utilities,
		hasSpell = player.hasSpell,
		stats = Hero.stats(run, player),
		dashCharges = player.dashCharges,
		dashReadyIn = if player.dashCharges < config.player.dashCharges
			then secondsLeft(run, player.dashReadyAt)
			else 0,
		shrinesTaken = table.clone(player.shrinesTaken),
	}
end

-- How one player's run went, sent with the summary phase.
export type SummaryView = {
	-- Why the run ended (the `ended` event's reason).
	reason: string,
	extracted: boolean,
	-- The run's time when it ended, in seconds.
	time: number,
	level: number,
	kills: number,
	damageDone: number,
	class: string,
	-- Seconds until the pick screen returns.
	nextIn: number,
}

-- Whether an event goes only to the player it is about rather than to every
-- client: a player's own offers, cards, level-ups and utilities.
function Protocol.isPrivate(event: Types.Event): boolean
	local kind = event.kind
	return kind == "offer" or kind == "cardTaken" or kind == "levelUp" or kind == "utility"
end

-- The player a private event is about.
function Protocol.eventPlayer(event: Types.Event): number?
	local about = (event :: any).player
	return if type(about) == "number" then about else nil
end

return Protocol
