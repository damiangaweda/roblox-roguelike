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
}

export type Intent =
	{ kind: "activeSkill", aim: { x: number, z: number }? }
	| { kind: "perk", index: number }

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Parses the arguments of an Intent remote. Returns nil for anything malformed;
-- range, cooldowns and state are the run's to check.
function Protocol.parseIntent(kind: any, a: any, b: any): Intent?
	if kind == "activeSkill" then
		if a == nil and b == nil then
			return { kind = "activeSkill", aim = nil }
		end
		if isFiniteNumber(a) and isFiniteNumber(b) then
			return { kind = "activeSkill", aim = { x = a, z = b } }
		end
		return nil
	elseif kind == "perk" then
		if isFiniteNumber(a) and a == math.floor(a) and a >= 1 and a <= 16 and b == nil then
			return { kind = "perk", index = a }
		end
		return nil
	end
	return nil
end

-- Enemy kinds travel as their index in the sorted list of kind names.
function Protocol.kindNames(config: Types.Config): { string }
	local names = {}
	for name in config.horde.kinds do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

export type EnemyView = {
	id: number,
	kind: string,
	x: number,
	z: number,
	chilled: boolean,
	burning: boolean,
}

local ENEMY_BYTES = 10
-- Positions travel in hundredths of a stud as int16, which covers +-327 studs.
local POSITION_SCALE = 100
local FLAG_CHILLED = 1
local FLAG_BURNING = 2

function Protocol.encodeEnemies(run: Types.Run, kindNames: { string }): buffer
	local kindIndex = {}
	for index, name in kindNames do
		kindIndex[name] = index
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
		buffer.writeu32(out, offset, enemy.id)
		buffer.writeu8(out, offset + 4, kindIndex[enemy.kind])
		buffer.writei16(out, offset + 5, math.round(enemy.x * POSITION_SCALE))
		buffer.writei16(out, offset + 7, math.round(enemy.z * POSITION_SCALE))
		buffer.writeu8(out, offset + 9, flags)
	end
	return out
end

-- Returns nil when the buffer is not a well-formed enemy list.
function Protocol.decodeEnemies(data: any, kindNames: { string }): { EnemyView }?
	if type(data) ~= "buffer" or buffer.len(data) < 2 then
		return nil
	end
	local count = buffer.readu16(data, 0)
	if buffer.len(data) ~= 2 + count * ENEMY_BYTES then
		return nil
	end
	local enemies = table.create(count)
	for i = 1, count do
		local offset = 2 + (i - 1) * ENEMY_BYTES
		local flags = buffer.readu8(data, offset + 9)
		enemies[i] = {
			id = buffer.readu32(data, offset),
			kind = kindNames[buffer.readu8(data, offset + 4)] or "grunt",
			x = buffer.readi16(data, offset + 5) / POSITION_SCALE,
			z = buffer.readi16(data, offset + 7) / POSITION_SCALE,
			chilled = bit32.band(flags, FLAG_CHILLED) ~= 0,
			burning = bit32.band(flags, FLAG_BURNING) ~= 0,
		}
	end
	return enemies
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
}

export type WorldView = {
	time: number,
	durationSeconds: number,
	players: { PlayerView },
	zones: { Types.Zone },
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
	}
end

-- The part of a player only that player sees.
export type SelfView = {
	level: number,
	xp: number,
	xpToNext: number,
	activeSkillReadyIn: number,
	activeSkillCooldown: number,
	kills: number,
	-- The oldest perk offer waiting for a choice.
	offer: { string }?,
}

-- Whether an event goes to every client or only to the player it is about.
function Protocol.isPrivate(event: Types.Event): boolean
	return event.kind == "offer"
		or event.kind == "perkTaken"
		or event.kind == "levelUp"
		or event.kind == "playerHurt"
end

-- The player a private event is about.
function Protocol.eventPlayer(event: Types.Event): number?
	local about = (event :: any).player
	return if type(about) == "number" then about else nil
end

return Protocol
