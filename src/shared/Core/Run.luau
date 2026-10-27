--!strict
-- One run, advanced by the server adapter in fixed steps (ADR-0002). The core
-- never reads time, randomness or the engine itself: the adapter passes them in.

local Arc = require("./Arc")
local Camps = require("./Camps")
local Combat = require("./Combat")
local Enemies = require("./Enemies")
local Extraction = require("./Extraction")
local Life = require("./Life")
local Map = require("./Map")
local Perks = require("./Perks")
local Projectiles = require("./Projectiles")
local State = require("./State")
local Types = require("./Types")

local Run = {}

-- A run for `playerCount` players: the map is generated for that many,
-- populated with camps and patrols, and given the clues to its leaders.
function Run.new(config: Types.Config, seed: number, playerCount: number): Types.Run
	local run = State.newRun(config, seed, playerCount)
	Camps.populate(run)
	Arc.placeClues(run)
	return run
end

function Run.addPlayer(run: Types.Run, id: number, class: string?): Types.Player
	return State.newPlayer(run, id, class)
end

-- A player who leaves the server leaves the run.
function Run.removePlayer(run: Types.Run, id: number)
	run.players[id] = nil
end

local function alivePlayer(run: Types.Run, playerId: number): Types.Player?
	if run.ended then
		return nil
	end
	local player = run.players[playerId]
	if player == nil or player.state ~= "alive" then
		return nil
	end
	return player
end

-- The player's class.
function Run.class(run: Types.Run, player: Types.Player): Types.ClassConfig
	return run.config.classes[player.class]
end

-- How fast the player may walk, after perks.
function Run.walkSpeed(run: Types.Run, player: Types.Player): number
	return Perks.playerValue(run.config, player, "moveSpeed", run.config.player.walkSpeed)
end

function Run.dashMaxCharges(run: Types.Run, player: Types.Player): number
	return math.floor(
		Perks.playerValue(run.config, player, "dashCharges", Run.class(run, player).dash.charges)
	)
end

-- The player pressed (`held`) or released the basic attack.
function Run.setFiring(run: Types.Run, playerId: number, held: boolean)
	local player = run.players[playerId]
	if player then
		player.firing = held
	end
end

-- Whether the player's aim snaps to enemies in the assist cone (touch, gamepad).
function Run.setAssist(run: Types.Run, playerId: number, enabled: boolean)
	local player = run.players[playerId]
	if player then
		player.assist = enabled
	end
end

-- The aim: the direction the player's skills fire in (ADR-0009).
function Run.setAim(run: Types.Run, playerId: number, angle: number)
	local player = run.players[playerId]
	if player and angle == angle and angle ~= math.huge and angle ~= -math.huge then
		player.facing = angle
	end
end

-- Uses active skill `index` along `aim` (the player's current aim when nil).
function Run.useSkill(
	run: Types.Run,
	playerId: number,
	index: number,
	aim: number?,
	aimDistance: number?
): boolean
	if run.ended then
		return false
	end
	if aim then
		Run.setAim(run, playerId, aim)
	end
	return Combat.useActive(run, playerId, index, aimDistance)
end

-- The dash: the client moves the character; the run only spends a charge and
-- grants the dash distance as a boost to the movement budget (ADR-0007),
-- usable for the dash's duration plus a grace for lag. A dash not taken lapses,
-- so boosts cannot be banked into a teleport.
function Run.dash(run: Types.Run, playerId: number): boolean
	local player = alivePlayer(run, playerId)
	if player == nil or player.dashCharges <= 0 then
		return false
	end
	local dash = Run.class(run, player).dash
	if player.dashCharges >= Run.dashMaxCharges(run, player) then
		player.dashRechargeAt = run.time + dash.rechargeSeconds
	end
	player.dashCharges -= 1
	if run.time >= player.boostUntil then
		player.boost = 0
	end
	player.boost += Run.dashDistance(run, player)
	player.boostUntil = run.time + dash.seconds + run.config.player.moveBurstSeconds
	table.insert(run.events, { kind = "dashed", player = player.id })
	return true
end

-- How far the player's dash carries, after perks.
function Run.dashDistance(run: Types.Run, player: Types.Player): number
	return Perks.playerValue(
		run.config,
		player,
		"dashDistance",
		Run.class(run, player).dash.distance
	)
end

function Run.drink(run: Types.Run, playerId: number): boolean
	if run.ended then
		return false
	end
	return Life.drink(run, playerId)
end

-- The player pressed (`held`) or released the interact button.
function Run.setInteracting(run: Types.Run, playerId: number, held: boolean)
	local player = run.players[playerId]
	if player then
		player.interacting = held
	end
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
-- walking could reach: anything not finite is dropped, the rest is held on
-- walkable ground, before the first water or prop on its way, and to the player's
-- movement budget (rule 1). The budget refills at walking speed with a
-- tolerance (slower while firing backwards) and banks a short burst, which
-- absorbs late updates but not a teleport; a dash adds a boost that lapses.
-- A knocked player is carried by the knockback, not by the client.
local function move(run: Types.Run, player: Types.Player, input: Types.PlayerInput?, dt: number)
	local config = run.config.player
	if input == nil or not (isFinite(input.x) and isFinite(input.z)) then
		player.moveBudget = math.min(
			player.moveBudget + Run.walkSpeed(run, player) * config.moveTolerance * dt,
			Run.walkSpeed(run, player) * config.moveTolerance * config.moveBurstSeconds
		)
		return
	end
	if run.time < player.knockUntil then
		return
	end

	local targetX, targetZ = Map.clamp(run.map, input.x, input.z)
	local dx, dz = targetX - player.x, targetZ - player.z
	local distance = math.sqrt(dx * dx + dz * dz)

	-- Walking away from the aim while firing is slower.
	local speed = Run.walkSpeed(run, player) * config.moveTolerance
	if player.firing and distance > 1e-6 then
		local dot = (dx * math.cos(player.facing) + dz * math.sin(player.facing)) / distance
		if dot < config.backpedalDot then
			speed *= config.backpedalFactor
		end
	end
	player.moveBudget = math.min(player.moveBudget + speed * dt, speed * config.moveBurstSeconds)
	if run.time >= player.boostUntil then
		player.boost = 0
	end

	-- Water or a prop on the way stops the move there.
	local reach = Map.reach(run.map, player.x, player.z, targetX, targetZ)
	local allowed = math.min(distance, reach, player.moveBudget + player.boost)
	if distance > 1e-9 and allowed < distance then
		local scale = allowed / distance
		dx *= scale
		dz *= scale
		distance = allowed
	end
	player.x += dx
	player.z += dz
	-- The boost is spent first; it is the part that lapses.
	local fromBoost = math.min(distance, player.boost)
	player.boost -= fromBoost
	player.moveBudget -= distance - fromBoost
end

-- Refreshes where the player stands and gives dash charges back.
local function refresh(run: Types.Run, player: Types.Player)
	player.pointId = State.pointIdAt(run, player.x, player.z)
	player.inCover = Map.inCover(run.map, run.config, player.x, player.z)

	local max = Run.dashMaxCharges(run, player)
	while player.dashCharges < max and run.time >= player.dashRechargeAt do
		player.dashCharges += 1
		player.dashRechargeAt += Run.class(run, player).dash.rechargeSeconds
	end
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

-- Advances the run by `dt` seconds. `inputs` carries the positions and
-- facings of players the adapter reports; only alive players move. The arc
-- (zones, the flood and its damage, run events) follows the moves, so the
-- flood hurts where players stand and its deaths go through Life.update.
-- The run ends when the flood meets at the centre, or at its duration.
function Run.step(run: Types.Run, dt: number, inputs: { [number]: Types.PlayerInput })
	if run.ended then
		return
	end
	run.time += dt

	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" then
			move(run, player, inputs[player.id], dt)
			refresh(run, player)
			Combat.fireBasic(run, player)
		end
	end

	Arc.update(run, dt)
	Camps.update(run, dt)
	Enemies.step(run, dt)
	Projectiles.step(run, dt)
	Combat.burn(run, dt)
	Life.update(run, dt)
	Extraction.update(run, dt)
	if run.floodHalf <= 0 or run.time >= run.config.run.durationSeconds then
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
