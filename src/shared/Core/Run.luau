--!strict
-- One run, advanced by the server adapter in fixed steps (ADR-0002). The core
-- never reads time, randomness or the world itself: the adapter passes them in.

local Camps = require("./Camps")
local Combat = require("./Combat")
local Enemies = require("./Enemies")
local Extraction = require("./Extraction")
local Geometry = require("./Geometry")
local Life = require("./Life")
local Perks = require("./Perks")
local Projectiles = require("./Projectiles")
local State = require("./State")
local Types = require("./Types")
local World = require("./World")

local Run = {}

-- A run for `playerCount` players: the world is generated for that many and
-- populated with camps and patrols.
function Run.new(config: Types.Config, seed: number, playerCount: number): Types.Run
	local run = State.newRun(config, seed, playerCount)
	Camps.populate(run)
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

function Run.useSkill(
	run: Types.Run,
	playerId: number,
	index: number,
	aimDistance: number?
): boolean
	if run.ended then
		return false
	end
	return Combat.useActive(run, playerId, index, aimDistance)
end

-- The dash: the client moves the character; the run only spends a charge and
-- raises the movement budget by the dash distance (ADR-0007), so the next
-- position report is accepted and a dash on cooldown is pulled back.
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
	player.moveBudget += Perks.playerValue(run.config, player, "dashDistance", dash.distance)
	table.insert(run.events, { kind = "dashed", player = player.id })
	return true
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
-- walking could reach: anything not finite is dropped, the rest is held inside
-- the walkable world and to the player's movement budget (rule 1). The budget
-- refills at walking speed with a tolerance and banks a short burst, which
-- absorbs late updates but not a teleport; a dash raises it.
local function move(run: Types.Run, player: Types.Player, input: Types.PlayerInput?, dt: number)
	local config = run.config.player
	local speed = Run.walkSpeed(run, player) * config.moveTolerance
	player.moveBudget = math.min(
		math.max(player.moveBudget, 0) + speed * dt,
		math.max(player.moveBudget, speed * config.moveBurstSeconds)
	)
	if input == nil then
		return
	end
	if input.facing and isFinite(input.facing) then
		player.facing = input.facing
	end
	if not (isFinite(input.x) and isFinite(input.z)) then
		return
	end

	local targetX, targetZ = World.clamp(run.world, input.x, input.z)
	local dx, dz = targetX - player.x, targetZ - player.z
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

-- Refreshes where the player stands and gives dash charges back.
local function refresh(run: Types.Run, player: Types.Player)
	local room = World.roomAt(run.world, player.x, player.z)
	player.roomId = if room then room.id else nil
	player.inCover = World.inCover(run.world, run.config, player.x, player.z)

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
-- facings of players the adapter reports; only alive players move.
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

	Camps.update(run, dt)
	Enemies.step(run, dt)
	Projectiles.step(run, dt)
	Combat.burn(run, dt)
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

-- Where (x, z) is relative to the player: the distance along the aim. Used by
-- the adapter for nothing yet; kept for the HUD's aim marker.
function Run.distanceAlongAim(player: Types.Player, x: number, z: number): number
	return Geometry.distance(player.x, player.z, x, z)
end

return Run
