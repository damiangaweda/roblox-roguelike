--!strict
-- The wire format between the server and clients. Clients only send intents,
-- which the server parses here before anything reaches the run (AGENTS.md
-- rule 1). Pure Luau, so it is tested under Lune like the core.

local Types = require("./Core/Types")

local Protocol = {}

Protocol.remotes = {
	-- Client to server: an intent.
	intent = "Intent",
	-- Server to every client: the shared state of the run.
	world = "World",
	-- Server to one client: events it may see and its own state.
	events = "Events",
	-- Server to one client: the run's map, once per run and on join.
	map = "Map",
}

export type Intent =
	{ kind: "aim", angle: number }
	| { kind: "fire", held: boolean }
	| { kind: "skill", index: number, aim: number?, aimDistance: number? }
	| { kind: "dash" }
	| { kind: "drink" }
	| { kind: "interact", held: boolean }
	| { kind: "perk", index: number }
	| { kind: "assist", enabled: boolean }

-- The most active skills a class may have; the server checks the real count.
local MAX_SKILLS = 8
local MAX_PERK_INDEX = 16
-- Farther than any skill reaches; an aim distance beyond it is malformed.
local MAX_AIM_DISTANCE = 1000

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isSmallIndex(value: any, max: number): boolean
	return isFiniteNumber(value) and value == math.floor(value) and value >= 1 and value <= max
end

-- An aim angle: radians from +x toward +z (ADR-0009).
local function isAngle(value: any): boolean
	return isFiniteNumber(value) and math.abs(value) <= 2 * math.pi
end

-- Parses the arguments of an Intent remote. Returns nil for anything malformed;
-- range, cooldowns and state are the run's to check.
function Protocol.parseIntent(kind: any, a: any, b: any, c: any): Intent?
	-- Only a skill takes a third argument.
	local trailing = c ~= nil
	if kind == "aim" then
		if isAngle(a) and b == nil and not trailing then
			return { kind = "aim", angle = a }
		end
	elseif kind == "fire" then
		if type(a) == "boolean" and b == nil and not trailing then
			return { kind = "fire", held = a }
		end
	elseif kind == "skill" then
		-- The index, then an optional aim angle and an optional aim distance.
		if isSmallIndex(a, MAX_SKILLS) and (b == nil or isAngle(b)) then
			if c == nil then
				return { kind = "skill", index = a, aim = b, aimDistance = nil }
			end
			if isFiniteNumber(c) and c > 0 and c <= MAX_AIM_DISTANCE then
				return { kind = "skill", index = a, aim = b, aimDistance = c }
			end
		end
	elseif kind == "dash" then
		if a == nil and b == nil and not trailing then
			return { kind = "dash" }
		end
	elseif kind == "drink" then
		if a == nil and b == nil and not trailing then
			return { kind = "drink" }
		end
	elseif kind == "interact" then
		if type(a) == "boolean" and b == nil and not trailing then
			return { kind = "interact", held = a }
		end
	elseif kind == "perk" then
		if isSmallIndex(a, MAX_PERK_INDEX) and b == nil and not trailing then
			return { kind = "perk", index = a }
		end
	elseif kind == "assist" then
		if type(a) == "boolean" and b == nil and not trailing then
			return { kind = "assist", enabled = a }
		end
	end
	return nil
end

-- Archetypes travel as their index in the sorted list of names.
function Protocol.archetypeNames(config: Types.Config): { string }
	local names = {}
	for name in config.enemies.archetypes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Projectile kinds: every skill id of every class and every archetype, sorted.
function Protocol.projectileKinds(config: Types.Config): { string }
	local names = {}
	for _, class in config.classes do
		table.insert(names, class.basic.id)
		for _, active in class.actives do
			table.insert(names, active.id)
		end
	end
	for name in config.enemies.archetypes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local STATES: { Types.EnemyState } = { "idle", "chase", "telegraph", "recover", "return", "patrol" }

export type EnemyView = {
	id: number,
	archetype: string,
	level: number,
	x: number,
	z: number,
	facing: number,
	state: Types.EnemyState,
	-- Health as a share of the maximum, in [0, 1].
	health: number,
	chilled: boolean,
	burning: boolean,
	brittle: boolean,
	buffed: boolean,
}

local ENEMY_BYTES = 14
-- Positions travel in tenths of a stud as int16, which covers +-3276 studs.
local POSITION_SCALE = 10
local FLAG_CHILLED = 1
local FLAG_BURNING = 2
local FLAG_BRITTLE = 4
local FLAG_BUFFED = 8

local function writePosition(out: buffer, offset: number, value: number)
	buffer.writei16(out, offset, math.clamp(math.round(value * POSITION_SCALE), -32768, 32767))
end

local function writeAngle(out: buffer, offset: number, angle: number)
	buffer.writeu8(out, offset, math.floor((angle % (2 * math.pi)) / (2 * math.pi) * 256) % 256)
end

local function readAngle(data: buffer, offset: number): number
	return buffer.readu8(data, offset) / 256 * 2 * math.pi
end

function Protocol.encodeEnemies(run: Types.Run, archetypeNames: { string }): buffer
	local index = {}
	for i, name in archetypeNames do
		index[name] = i
	end
	local enemies = run.enemies
	local out = buffer.create(2 + #enemies * ENEMY_BYTES)
	buffer.writeu16(out, 0, #enemies)
	for i, enemy in enemies do
		local offset = 2 + (i - 1) * ENEMY_BYTES
		local flags = 0
		if run.time < enemy.chilledUntil then
			flags += FLAG_CHILLED
		end
		if run.time < enemy.burningUntil then
			flags += FLAG_BURNING
		end
		if run.time < enemy.brittleUntil then
			flags += FLAG_BRITTLE
		end
		if run.time < enemy.buffedUntil then
			flags += FLAG_BUFFED
		end
		buffer.writeu32(out, offset, enemy.id)
		buffer.writeu8(out, offset + 4, index[enemy.archetype] or 0)
		writePosition(out, offset + 5, enemy.x)
		writePosition(out, offset + 7, enemy.z)
		writeAngle(out, offset + 9, enemy.facing)
		buffer.writeu8(out, offset + 10, table.find(STATES, enemy.state) or 1)
		local health = if enemy.maxHealth > 0 then enemy.health / enemy.maxHealth else 0
		buffer.writeu8(out, offset + 11, math.clamp(math.ceil(health * 255), 0, 255))
		buffer.writeu8(out, offset + 12, flags)
		buffer.writeu8(out, offset + 13, math.clamp(enemy.level, 0, 255))
	end
	return out
end

-- Returns nil when the buffer is not a well-formed enemy list.
function Protocol.decodeEnemies(data: any, archetypeNames: { string }): { EnemyView }?
	if type(data) ~= "buffer" or buffer.len(data) < 2 then
		return nil
	end
	local count = buffer.readu16(data, 0)
	if buffer.len(data) ~= 2 + count * ENEMY_BYTES then
		return nil
	end
	local enemies: { EnemyView } = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * ENEMY_BYTES
		local flags = buffer.readu8(data, offset + 12)
		enemies[i] = {
			id = buffer.readu32(data, offset),
			archetype = archetypeNames[buffer.readu8(data, offset + 4)] or archetypeNames[1],
			level = buffer.readu8(data, offset + 13),
			x = buffer.readi16(data, offset + 5) / POSITION_SCALE,
			z = buffer.readi16(data, offset + 7) / POSITION_SCALE,
			facing = readAngle(data, offset + 9),
			state = (STATES[buffer.readu8(data, offset + 10)] or "idle") :: Types.EnemyState,
			health = buffer.readu8(data, offset + 11) / 255,
			chilled = bit32.band(flags, FLAG_CHILLED) ~= 0,
			burning = bit32.band(flags, FLAG_BURNING) ~= 0,
			brittle = bit32.band(flags, FLAG_BRITTLE) ~= 0,
			buffed = bit32.band(flags, FLAG_BUFFED) ~= 0,
		}
	end
	return enemies
end

export type ProjectileView = {
	id: number,
	owner: "player" | "enemy",
	kind: string,
	x: number,
	z: number,
	facing: number,
}

local PROJECTILE_BYTES = 11

function Protocol.encodeProjectiles(run: Types.Run, kinds: { string }): buffer
	local index = {}
	for i, name in kinds do
		index[name] = i
	end
	local projectiles = run.projectiles
	local out = buffer.create(2 + #projectiles * PROJECTILE_BYTES)
	buffer.writeu16(out, 0, #projectiles)
	for i, projectile in projectiles do
		local offset = 2 + (i - 1) * PROJECTILE_BYTES
		buffer.writeu32(out, offset, projectile.id)
		buffer.writeu8(out, offset + 4, if projectile.owner == "player" then 0 else 1)
		buffer.writeu8(out, offset + 5, index[projectile.kind] or 0)
		writePosition(out, offset + 6, projectile.x)
		writePosition(out, offset + 8, projectile.z)
		writeAngle(out, offset + 10, math.atan2(projectile.dirZ, projectile.dirX))
	end
	return out
end

-- Returns nil when the buffer is not a well-formed projectile list.
function Protocol.decodeProjectiles(data: any, kinds: { string }): { ProjectileView }?
	if type(data) ~= "buffer" or buffer.len(data) < 2 then
		return nil
	end
	local count = buffer.readu16(data, 0)
	if buffer.len(data) ~= 2 + count * PROJECTILE_BYTES then
		return nil
	end
	local projectiles: { ProjectileView } = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * PROJECTILE_BYTES
		local owner: "player" | "enemy" = if buffer.readu8(data, offset + 4) == 0
			then "player"
			else "enemy"
		projectiles[i] = {
			id = buffer.readu32(data, offset),
			owner = owner,
			kind = kinds[buffer.readu8(data, offset + 5)] or "",
			x = buffer.readi16(data, offset + 6) / POSITION_SCALE,
			z = buffer.readi16(data, offset + 8) / POSITION_SCALE,
			facing = readAngle(data, offset + 10),
		}
	end
	return projectiles
end

-- The part of a player every client sees.
export type PlayerView = {
	id: number,
	state: Types.PlayerState,
	health: number,
	maxHealth: number,
	reviveProgress: number,
	extractProgress: number,
	downedFor: number,
	potions: number,
	-- Seconds left of the drink, 0 when not drinking.
	drinkingFor: number,
}

export type WorldView = {
	time: number,
	durationSeconds: number,
	players: { PlayerView },
	zones: { Types.Zone },
	pickups: { Types.Pickup },
}

function Protocol.worldView(run: Types.Run): WorldView
	local players = {}
	for _, player in run.players do
		table.insert(players, {
			id = player.id,
			state = player.state,
			health = player.health,
			maxHealth = player.maxHealth,
			reviveProgress = player.reviveProgress,
			extractProgress = player.extractProgress,
			downedFor = if player.downedAt then run.time - player.downedAt else 0,
			potions = player.potions,
			drinkingFor = if player.drinkingUntil
				then math.max(0, player.drinkingUntil - run.time)
				else 0,
		})
	end
	table.sort(players, function(a, b)
		return a.id < b.id
	end)
	return {
		time = run.time,
		durationSeconds = run.config.run.durationSeconds,
		players = players,
		zones = run.zones,
		pickups = run.pickups,
	}
end

export type SkillView = {
	id: string,
	name: string,
	readyIn: number,
	cooldown: number,
}

-- The part of a player only that player sees.
export type SelfView = {
	level: number,
	xp: number,
	xpToNext: number,
	kills: number,
	-- The oldest perk offer waiting for a choice.
	offer: { string }?,
	-- Perk id to stacks taken.
	perks: { [string]: number },
	skills: { SkillView },
	dashCharges: number,
	dashMaxCharges: number,
	dashRechargeIn: number,
	-- How far a dash carries, after perks: the client moves the character by it.
	dashDistance: number,
	potions: number,
	potionCapacity: number,
}

export type MapPointView = {
	id: number,
	x: number,
	z: number,
	template: string,
	radius: number,
	level: number,
	isEntry: boolean,
	hasZone: boolean,
}

export type PathView = { a: number, b: number, halfWidth: number }

-- The map as the client draws it. Heights travel as u16 tenths of a stud,
-- row-major: heights[row][col], row along z, col along x, both from -half,
-- spaced heightCell apart.
export type MapView = {
	half: number,
	heightCell: number,
	waterLevel: number,
	rows: number,
	cols: number,
	heights: buffer,
	points: { MapPointView },
	paths: { PathView },
	fieldCover: { { x: number, z: number } },
}

local HEIGHT_SCALE = 10
local HEIGHT_BYTES = 2

function Protocol.mapView(map: Types.Map): MapView
	local rows = #map.heights
	local cols = if rows > 0 then #map.heights[1] else 0
	local heights = buffer.create(rows * cols * HEIGHT_BYTES)
	for row, line in map.heights do
		for col, height in line do
			local offset = ((row - 1) * cols + col - 1) * HEIGHT_BYTES
			buffer.writeu16(
				heights,
				offset,
				math.clamp(math.round(height * HEIGHT_SCALE), 0, 65535)
			)
		end
	end
	local points: { MapPointView } = table.create(#map.points)
	for i, point in map.points do
		points[i] = {
			id = point.id,
			x = point.x,
			z = point.z,
			template = point.template,
			radius = point.radius,
			level = point.level,
			isEntry = point.isEntry,
			hasZone = point.hasZone,
		}
	end
	local paths: { PathView } = table.create(#map.paths)
	for i, path in map.paths do
		paths[i] = { a = path.a, b = path.b, halfWidth = path.halfWidth }
	end
	local fieldCover = table.create(#map.fieldCover)
	for i, spot in map.fieldCover do
		fieldCover[i] = { x = spot.x, z = spot.z }
	end
	return {
		half = map.half,
		heightCell = map.heightCell,
		waterLevel = map.waterLevel,
		rows = rows,
		cols = cols,
		heights = heights,
		points = points,
		paths = paths,
		fieldCover = fieldCover,
	}
end

local function isCount(value: any): boolean
	return isFiniteNumber(value) and value == math.floor(value) and value >= 2
end

-- The height grid of a map view; nil when the view is malformed or the
-- buffer's length does not match rows x cols.
function Protocol.decodeHeights(view: MapView): { { number } }?
	local data: any = view.heights
	if type(data) ~= "buffer" or not isCount(view.rows) or not isCount(view.cols) then
		return nil
	end
	local rows, cols = view.rows, view.cols
	if buffer.len(data) ~= rows * cols * HEIGHT_BYTES then
		return nil
	end
	local heights: { { number } } = table.create(rows)
	for row = 1, rows do
		local line = table.create(cols)
		for col = 1, cols do
			local offset = ((row - 1) * cols + col - 1) * HEIGHT_BYTES
			line[col] = buffer.readu16(data, offset) / HEIGHT_SCALE
		end
		heights[row] = line
	end
	return heights
end

-- The drawn height at (x, z): bilinear over the grid, never below the water,
-- by the same rule as Map.heightAt.
function Protocol.heightAt(
	heights: { { number } },
	heightCell: number,
	half: number,
	waterLevel: number,
	x: number,
	z: number
): number
	local rows, cols = #heights, #heights[1]
	local u = (math.clamp(x, -half, half) + half) / heightCell
	local v = (math.clamp(z, -half, half) + half) / heightCell
	local col = math.clamp(math.floor(u) + 1, 1, cols - 1)
	local row = math.clamp(math.floor(v) + 1, 1, rows - 1)
	local fx = math.clamp(u - (col - 1), 0, 1)
	local fz = math.clamp(v - (row - 1), 0, 1)
	local low = heights[row][col] * (1 - fx) + heights[row][col + 1] * fx
	local high = heights[row + 1][col] * (1 - fx) + heights[row + 1][col + 1] * fx
	return math.max(low * (1 - fz) + high * fz, waterLevel)
end

-- Whether an event goes to every client or only to the player it is about.
function Protocol.isPrivate(event: Types.Event): boolean
	local kind = event.kind
	return kind == "offer"
		or kind == "perkTaken"
		or kind == "levelUp"
		or kind == "playerHurt"
		or kind == "knockback"
		or kind == "drinking"
		or kind == "drank"
		or kind == "drinkInterrupted"
		or kind == "pickedUp"
end

-- The player a private event is about.
function Protocol.eventPlayer(event: Types.Event): number?
	local about = (event :: any).player
	return if type(about) == "number" then about else nil
end

return Protocol
