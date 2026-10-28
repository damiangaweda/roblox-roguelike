--!strict
-- One run, advanced by the server adapter in fixed steps (ADR-0002). The core
-- never reads time, randomness or the engine itself: the adapter passes them
-- in. Run holds the players' movement, the intents and the run's end; the
-- subsystems it steps live in their own modules.

local Arena = require("./Arena")
local Cards = require("./Cards")
local Casting = require("./Casting")
local Damage = require("./Damage")
local Enemies = require("./Enemies")
local Extraction = require("./Extraction")
local Flow = require("./Flow")
local Hero = require("./Hero")
local Lairs = require("./Lairs")
local Progression = require("./Progression")
local Projectiles = require("./Projectiles")
local Shrines = require("./Shrines")
local State = require("./State")
local Types = require("./Types")

local Run = {}

function Run.new(config: Types.Config, seed: number): Types.Run
	return State.newRun(config, seed)
end

-- A hero of `class` joins at the start; an unknown class falls back to the
-- first class by id.
function Run.addPlayer(run: Types.Run, id: number, class: string?): Types.Player
	local chosen = class
	if chosen == nil or run.config.classes[chosen] == nil then
		local ids = {}
		for key in run.config.classes do
			table.insert(ids, key)
		end
		table.sort(ids)
		chosen = ids[1]
	end
	return State.newPlayer(run, id, chosen :: string)
end

-- A player who leaves the server leaves the run.
function Run.removePlayer(run: Types.Run, id: number)
	run.players[id] = nil
	run.paused = false
	for _, player in run.players do
		if #player.offers > 0 then
			run.paused = true
		end
	end
end

function Run.chooseCard(run: Types.Run, playerId: number, index: number): boolean
	if run.ended then
		return false
	end
	return Cards.choose(run, playerId, index)
end

function Run.useUtility(run: Types.Run, playerId: number, index: number): boolean
	if run.ended or run.paused then
		return false
	end
	return Hero.useUtility(run, playerId, index)
end

-- The interact button held or released: it opens the chest or activates a
-- shrine, whichever is in reach (the chest first).
function Run.setInteracting(run: Types.Run, playerId: number, held: boolean)
	if run.ended then
		return
	end
	Extraction.setOpening(run, playerId, held)
	Shrines.setHolding(run, playerId, held)
end

-- A dash in direction (dx, dz), normalised here; nothing while paused.
function Run.dash(run: Types.Run, playerId: number, dx: number, dz: number): boolean
	if run.ended or run.paused then
		return false
	end
	local player = run.players[playerId]
	if player == nil then
		return false
	end
	return Hero.dash(run, player, dx, dz)
end

function Run.castSpell(run: Types.Run, playerId: number): boolean
	if run.ended or run.paused then
		return false
	end
	return Extraction.castSpell(run, playerId)
end

function Run.enterPortal(run: Types.Run, playerId: number): boolean
	if run.ended or run.paused then
		return false
	end
	return Extraction.enterPortal(run, playerId)
end

-- How fast the player may walk now, after passives and the sprint.
function Run.walkSpeed(run: Types.Run, player: Types.Player): number
	return Hero.walkSpeed(run, player)
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Positions come from the client's character, so the run accepts only what
-- walking could reach (rule 1, ADR-0007): anything not finite is dropped, the
-- rest is held inside the arena, before the first obstacle on its way, and to
-- the player's movement budget. The budget refills at walking speed with a
-- tolerance and banks a short burst, which absorbs late updates but not a
-- teleport. A knocked player is carried by the knockback, not by the client.
local function move(run: Types.Run, player: Types.Player, input: Types.PlayerInput?, dt: number)
	local config = run.config.player
	local speed = Hero.walkSpeed(run, player) * config.moveTolerance
	local cap = speed * config.moveBurstSeconds
	if input == nil or not (isFinite(input.x) and isFinite(input.z)) then
		player.moveBudget = math.min(player.moveBudget + speed * dt, cap)
		return
	end
	player.moveBudget = math.min(player.moveBudget + speed * dt, cap)
	if run.time < player.knockUntil then
		return
	end

	local targetX, targetZ = Arena.clamp(run.arena, input.x, input.z, config.radius)
	local dx, dz = targetX - player.x, targetZ - player.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 1e-9 then
		return
	end
	local reach = Arena.reach(run.arena, player.x, player.z, targetX, targetZ, config.radius)
	local allowed = math.min(distance, reach, player.moveBudget)
	if allowed < distance then
		local scale = allowed / distance
		dx *= scale
		dz *= scale
		distance = allowed
	end
	if distance > 1e-9 then
		player.facing = math.atan2(dz, dx)
	end
	player.x += dx
	player.z += dz
	player.moveBudget -= distance
end

local function endRun(run: Types.Run, reason: "allDead" | "extracted" | "finalBossKilled")
	if run.ended then
		return
	end
	run.ended = true
	run.paused = false
	table.insert(run.events, { kind = "ended", reason = reason })
end

-- The run ends when nobody is alive, when every living player has left, or
-- when the final boss falls (everyone alive extracts). Doom (Lairs) ends it
-- through the first two.
local function checkEnded(run: Types.Run)
	local finalId = run.finalBossId
	if finalId ~= nil and State.enemyById(run, finalId) == nil then
		for _, player in State.sortedPlayers(run) do
			if player.state == "alive" then
				player.state = "extracted"
				table.insert(run.events, { kind = "extracted", player = player.id })
			end
		end
		endRun(run, "finalBossKilled")
		return
	end

	local any, alive, extracted = false, 0, 0
	for _, player in run.players do
		any = true
		if player.state == "alive" then
			alive += 1
		elseif player.state == "extracted" then
			extracted += 1
		end
	end
	if any and alive == 0 then
		endRun(run, if extracted > 0 then "extracted" else "allDead")
	end
end

-- Advances the run by `dt` seconds. `inputs` carries where each player's
-- character stands; only alive players move. The run stands still while a
-- solo player chooses a card.
function Run.step(run: Types.Run, dt: number, inputs: { [number]: Types.PlayerInput })
	if run.ended or run.paused then
		return
	end
	run.time += dt

	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" then
			move(run, player, inputs[player.id], dt)
		end
	end

	Casting.update(run, dt)
	Projectiles.step(run, dt)
	Lairs.update(run, dt)
	Flow.update(run)
	Enemies.step(run, dt)
	Damage.update(run, dt)
	Hero.update(run, dt)
	Progression.update(run, dt)
	Extraction.update(run, dt)
	Shrines.update(run, dt)
	checkEnded(run)
end

-- Returns the events produced since the last call and forgets them.
function Run.drainEvents(run: Types.Run): { Types.Event }
	local events = run.events
	run.events = {}
	return events
end

return Run
