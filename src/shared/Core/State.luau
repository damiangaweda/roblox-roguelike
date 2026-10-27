--!strict
-- Constructors and lookups for the run's state, shared by the rules modules
-- and the specs. Nothing here decides a rule.

local Geometry = require("./Geometry")
local Map = require("./Map")
local Rng = require("./Rng")
local Types = require("./Types")

local State = {}

-- Studs from an entry's centre that players stand at when they join.
local START_RING_RADIUS = 3

function State.newRun(config: Types.Config, seed: number, playerCount: number): Types.Run
	local rng = Rng.new(seed)
	local map = Map.generate(config, rng, playerCount)
	local arc = config.run.arc
	return {
		config = config,
		rng = rng,
		time = 0,
		map = map,
		nextEnemyId = 1,
		nextCampId = 1,
		nextPatrolId = 1,
		nextProjectileId = 1,
		nextPickupId = 1,
		nextZoneId = 1,
		nextClueId = 1,
		nextChestId = 1,
		patrolDebt = 0,
		enemies = {},
		camps = {},
		patrols = {},
		projectiles = {},
		pickups = {},
		players = {},
		-- No zone is open at the start (stage 2d): they open on the arc's clock.
		zones = {},
		nextZoneAt = arc.zones.firstOpenMinute * 60,
		nextChestDropAt = arc.events.chestDrop.firstMinute * 60,
		floodHalf = map.half,
		floodStarted = false,
		clues = {},
		leaderAreas = {},
		chests = {},
		bossSpawned = false,
		waveStarted = false,
		flooded = false,
		ended = false,
		events = {},
	}
end

-- Players by ascending id: `pairs` order over the map is not stable between runs.
function State.sortedPlayers(run: Types.Run): { Types.Player }
	local list = {}
	for _, player in run.players do
		table.insert(list, player)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Ids of the alive players, ascending, so every pass visits them in one order.
function State.aliveIds(run: Types.Run): { number }
	local ids = {}
	for id, player in run.players do
		if player.state == "alive" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- The point an actor at (x, z) is at: the one whose footprint contains it,
-- else the nearest one.
function State.pointIdAt(run: Types.Run, x: number, z: number): number
	local point = Map.pointAt(run.map, x, z) or Map.nearestPoint(run.map, x, z)
	return point.id
end

-- The entry with the fewest players on its footprint; ties go to the first.
local function emptiestEntry(run: Types.Run): Types.MapPoint
	local best, bestCount = run.map.entries[1], math.huge
	for _, id in run.map.entries do
		local point = run.map.points[id]
		local count = 0
		for _, player in run.players do
			if Geometry.distance(player.x, player.z, point.x, point.z) <= point.radius then
				count += 1
			end
		end
		if count < bestCount then
			best, bestCount = id, count
		end
	end
	return run.map.points[best]
end

-- Adds a player of `class` at an entry and returns them.
function State.newPlayer(run: Types.Run, id: number, class: string?): Types.Player
	local config = run.config
	local className = class or "elementalist"
	local classConfig = config.classes[className]
	local entry = emptiestEntry(run)
	local occupants = 0
	for _ in run.players do
		occupants += 1
	end
	local angle = occupants * 2 * math.pi / 6
	local player: Types.Player = {
		id = id,
		class = className,
		x = entry.x + math.cos(angle) * START_RING_RADIUS,
		z = entry.z + math.sin(angle) * START_RING_RADIUS,
		facing = 0,
		assist = false,
		firing = false,
		state = "alive",
		health = config.player.maxHealth,
		maxHealth = config.player.maxHealth,
		downedAt = nil,
		reviveProgress = 0,
		extractProgress = 0,
		clueProgress = 0,
		chestProgress = 0,
		level = 1,
		xp = 0,
		perks = {},
		offers = {},
		basicReadyAt = 0,
		skillReadyAt = table.create(#classConfig.actives, 0),
		dashCharges = classConfig.dash.charges,
		dashRechargeAt = 0,
		potions = 0,
		drinkingUntil = nil,
		kills = 0,
		moveBudget = 0,
		boost = 0,
		boostUntil = 0,
		interacting = false,
		hurtAt = -math.huge,
		knockX = 0,
		knockZ = 0,
		knockUntil = 0,
		pointId = entry.id,
		inCover = false,
	}
	run.players[id] = player
	return player
end

function State.archetype(run: Types.Run, enemy: Types.Enemy): Types.ArchetypeConfig
	return run.config.enemies.archetypes[enemy.archetype]
end

-- Adds a fresh enemy at (x, z), at home there, and returns it. `healthFactor`
-- scales its health (camp scaling, patrol strength).
function State.newEnemy(
	run: Types.Run,
	archetype: string,
	level: number,
	x: number,
	z: number,
	healthFactor: number?
): Types.Enemy
	local config = run.config.enemies.archetypes[archetype]
	local health = config.health * (healthFactor or 1)
	local enemy: Types.Enemy = {
		id = run.nextEnemyId,
		archetype = archetype,
		level = level,
		x = x,
		z = z,
		facing = 0,
		health = health,
		maxHealth = health,
		campId = nil,
		patrolId = nil,
		homeX = x,
		homeZ = z,
		state = "idle",
		stateUntil = 0,
		target = nil,
		stuckSince = nil,
		attack = 1,
		aimX = x,
		aimZ = z,
		attackReadyAt = 0,
		routePoint = nil,
		chilledUntil = 0,
		burningUntil = 0,
		burnSource = nil,
		brittleUntil = 0,
		buffedUntil = 0,
		knockX = 0,
		knockZ = 0,
		knockUntil = 0,
		boss = false,
	}
	run.nextEnemyId += 1
	table.insert(run.enemies, enemy)
	return enemy
end

function State.enemyById(run: Types.Run, id: number): Types.Enemy?
	for _, enemy in run.enemies do
		if enemy.id == id then
			return enemy
		end
	end
	return nil
end

function State.campById(run: Types.Run, id: number): Types.Camp?
	for _, camp in run.camps do
		if camp.id == id then
			return camp
		end
	end
	return nil
end

function State.patrolById(run: Types.Run, id: number): Types.Patrol?
	for _, patrol in run.patrols do
		if patrol.id == id then
			return patrol
		end
	end
	return nil
end

-- Takes a dead enemy out of the run and out of its camp or patrol.
function State.removeEnemy(run: Types.Run, enemy: Types.Enemy)
	local index = table.find(run.enemies, enemy)
	if index then
		table.remove(run.enemies, index)
	end
	if enemy.campId then
		local camp = State.campById(run, enemy.campId)
		if camp then
			local at = table.find(camp.members, enemy.id)
			if at then
				table.remove(camp.members, at)
			end
			if camp.leaderId == enemy.id then
				camp.leaderId = nil
			end
			-- The last member gone: the camp is cleared and its return clock starts.
			if at and #camp.members == 0 then
				camp.clearedAt = run.time
			end
		end
	end
	if enemy.patrolId then
		local patrol = State.patrolById(run, enemy.patrolId)
		if patrol then
			local at = table.find(patrol.members, enemy.id)
			if at then
				table.remove(patrol.members, at)
			end
		end
	end
end

function State.newPickup(run: Types.Run, kind: "potion", x: number, z: number): Types.Pickup
	local pickup: Types.Pickup = { id = run.nextPickupId, kind = kind, x = x, z = z }
	run.nextPickupId += 1
	table.insert(run.pickups, pickup)
	return pickup
end

return State
