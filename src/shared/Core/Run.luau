--!strict
-- One run, advanced by the server adapter in fixed steps (ADR-0002). The core
-- never reads time, randomness or the world itself: the adapter passes them in.

local Combat = require("./Combat")
local Extraction = require("./Extraction")
local Horde = require("./Horde")
local Life = require("./Life")
local Perks = require("./Perks")
local Rng = require("./Rng")
local Types = require("./Types")

local Run = {}

function Run.new(config: Types.Config, seed: number): Types.Run
	return {
		config = config,
		rng = Rng.new(seed),
		time = 0,
		nextEnemyId = 1,
		spawnDebt = 0,
		enemies = {},
		players = {},
		zones = {},
		zonesOpen = false,
		flooded = false,
		ended = false,
		events = {},
	}
end

function Run.addPlayer(run: Types.Run, id: number, x: number, z: number): Types.Player
	local config = run.config
	local player: Types.Player = {
		id = id,
		x = x,
		z = z,
		state = "alive",
		health = config.player.maxHealth,
		maxHealth = config.player.maxHealth,
		downedAt = nil,
		reviveProgress = 0,
		extractProgress = 0,
		level = 1,
		xp = 0,
		perks = {},
		offers = {},
		basicReadyAt = 0,
		activeSkillReadyAt = 0,
		kills = 0,
		moveBudget = 0,
	}
	run.players[id] = player
	return player
end

-- A player who leaves the server leaves the run.
function Run.removePlayer(run: Types.Run, id: number)
	run.players[id] = nil
end

function Run.useActiveSkill(
	run: Types.Run,
	playerId: number,
	aim: { x: number, z: number }?
): boolean
	if run.ended then
		return false
	end
	return Combat.useActiveSkill(run, playerId, aim)
end

function Run.choosePerk(run: Types.Run, playerId: number, index: number): boolean
	if run.ended then
		return false
	end
	return Perks.choose(run, playerId, index)
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Positions come from the client's character, so the run accepts only what
-- walking could reach: anything not finite is dropped, the rest is held inside
-- the arena and to the player's movement budget (rule 1). The budget refills
-- at walking speed with a tolerance and banks a short burst, which absorbs
-- late updates but not a teleport.
local function move(run: Types.Run, player: Types.Player, input: Types.PlayerInput?, dt: number)
	local config = run.config.player
	local speed = config.walkSpeed * config.moveTolerance
	player.moveBudget = math.min(player.moveBudget + speed * dt, speed * config.moveBurstSeconds)
	if input == nil or not (isFinite(input.x) and isFinite(input.z)) then
		return
	end

	local half = run.config.arena.halfSize
	local dx = math.clamp(input.x, -half, half) - player.x
	local dz = math.clamp(input.z, -half, half) - player.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > player.moveBudget then
		local scale = player.moveBudget / distance
		dx *= scale
		dz *= scale
		distance = player.moveBudget
	end
	player.x += dx
	player.z += dz
	player.moveBudget -= distance
end

local function checkEnded(run: Types.Run)
	local any = false
	for _, player in run.players do
		any = true
		if player.state == "alive" or player.state == "downed" then
			return
		end
	end
	if any then
		run.ended = true
		table.insert(run.events, { kind = "ended" })
	end
end

-- Advances the run by `dt` seconds. `inputs` carries the positions of players
-- the adapter reports; only alive players move.
function Run.step(run: Types.Run, dt: number, inputs: { [number]: Types.PlayerInput })
	if run.ended then
		return
	end
	run.time += dt

	for id, player in run.players do
		if player.state == "alive" then
			move(run, player, inputs[id], dt)
		end
	end

	Horde.spawn(run, dt)
	Horde.move(run, dt)
	Combat.basicAttacks(run)
	Combat.burn(run, dt)

	for id, amount in Horde.contact(run, dt) do
		local player = run.players[id]
		if player and amount > 0 then
			Life.damage(run, player, amount)
		end
	end

	Life.update(run, dt)
	Extraction.update(run, dt)
	if run.time >= run.config.run.durationSeconds then
		Extraction.flood(run)
	end
	checkEnded(run)
end

-- Returns the events produced since the last call and forgets them.
function Run.drainEvents(run: Types.Run): { Types.Event }
	local events = run.events
	run.events = {}
	return events
end

return Run
