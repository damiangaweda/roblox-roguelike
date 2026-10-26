--!strict
-- Where enemies come from (ADR-0008, ADR-0004): a camp in every room, camps
-- that grow with the players in their room, patrols that grow with run time,
-- and wanderers. The kinds of enemy and their counts are configuration.

local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")
local World = require("./World")

local Camps = {}

-- Studs from the room centre that a new patrol's members stand at.
local PATROL_RING_RADIUS = 2

local function full(run: Types.Run): boolean
	return #run.enemies >= run.config.enemies.maxAlive
end

-- A spot on the ring around the camp, kept inside the walkable world.
local function ringSpot(run: Types.Run, camp: Types.Camp, angle: number): (number, number)
	local radius = run.config.enemies.campSpreadRadius
	return World.clamp(
		run.world,
		camp.x + math.cos(angle) * radius,
		camp.z + math.sin(angle) * radius
	)
end

-- Adds one member to `camp` at (x, z), facing the room's centre.
local function addMember(
	run: Types.Run,
	camp: Types.Camp,
	archetype: string,
	x: number,
	z: number,
	healthFactor: number?
): Types.Enemy
	local room = run.world.rooms[camp.roomId]
	local enemy = State.newEnemy(run, archetype, camp.level, x, z, healthFactor)
	enemy.campId = camp.id
	enemy.facing = Geometry.angle(room.x - x, room.z - z)
	table.insert(camp.members, enemy.id)
	return enemy
end

local function populateCamp(run: Types.Run, room: Types.Room)
	local enemies = run.config.enemies
	local level = enemies.camps[room.level]
	local camp: Types.Camp = {
		id = run.nextCampId,
		roomId = room.id,
		x = room.campX,
		z = room.campZ,
		level = room.level,
		members = {},
		alerted = false,
		scaledFor = 0,
		leaderId = nil,
	}
	run.nextCampId += 1
	table.insert(run.camps, camp)

	local archetypes: { string } = {}
	for _, group in level.groups do
		for _ = 1, group.count do
			table.insert(archetypes, group.archetype)
		end
	end
	-- Drawn even when the cap leaves no room, so the rng stream does not depend on it.
	local hasLeader = run.rng:next() < level.leaderChance

	for index, archetype in archetypes do
		if full(run) then
			return
		end
		local x, z = ringSpot(run, camp, (index - 1) / #archetypes * 2 * math.pi)
		addMember(run, camp, archetype, x, z)
	end
	if hasLeader and not full(run) then
		local x, z = World.clamp(run.world, camp.x, camp.z)
		camp.leaderId = addMember(run, camp, enemies.campLeader, x, z).id
	end
end

function Camps.populate(run: Types.Run)
	local config = run.config
	for _, room in run.world.rooms do
		if room.isStart or (room.hasZone and not config.world.campsInZoneRooms) then
			continue
		end
		populateCamp(run, room)
	end

	local patrols = config.enemies.patrols
	for _ = 1, patrols.groupsAtStart do
		Camps.spawnPatrol(run, patrols.sizeAtStart, patrols.pool, 1)
	end
	-- A wanderer is a patrol of one.
	for _ = 1, patrols.wanderersAtStart do
		Camps.spawnPatrol(run, 1, patrols.wandererPool, 1)
	end
end

-- Non-start rooms at least minHopsFromPlayers corridors from every alive player.
local function eligibleRooms(run: Types.Run): { Types.Room }
	local minHops = run.config.enemies.patrols.minHopsFromPlayers
	local playerRooms: { number } = {}
	for _, player in State.sortedPlayers(run) do
		if player.state ~= "alive" then
			continue
		end
		local room = World.roomAt(run.world, player.x, player.z)
		if room then
			table.insert(playerRooms, room.id)
		end
	end

	local far: { Types.Room } = {}
	local any: { Types.Room } = {}
	for _, room in run.world.rooms do
		if room.isStart then
			continue
		end
		table.insert(any, room)
		local ok = true
		for _, playerRoom in playerRooms do
			if run.world.hops[room.id][playerRoom] < minHops then
				ok = false
				break
			end
		end
		if ok then
			table.insert(far, room)
		end
	end
	-- A world too small for the distance still gets its patrols.
	return if #far > 0 then far else any
end

function Camps.spawnPatrol(
	run: Types.Run,
	size: number,
	pool: { string },
	strength: number
): Types.Patrol?
	local candidates = eligibleRooms(run)
	if #candidates == 0 then
		return nil
	end
	local room = candidates[run.rng:integer(1, #candidates)]
	local routeRoom = room.id
	if #room.neighbours > 0 then
		routeRoom = room.neighbours[run.rng:integer(1, #room.neighbours)]
	end

	local patrol: Types.Patrol = {
		id = run.nextPatrolId,
		members = {},
		routeRoom = routeRoom,
		previousRoom = room.id,
		strength = strength,
	}
	run.nextPatrolId += 1
	table.insert(run.patrols, patrol)

	local destination = run.world.rooms[routeRoom]
	for index = 1, size do
		if full(run) then
			break
		end
		local archetype = pool[run.rng:integer(1, #pool)]
		local angle = (index - 1) / size * 2 * math.pi
		local x = room.x + math.cos(angle) * PATROL_RING_RADIUS
		local z = room.z + math.sin(angle) * PATROL_RING_RADIUS
		local enemy = State.newEnemy(run, archetype, room.level, x, z, strength)
		enemy.patrolId = patrol.id
		enemy.state = "patrol"
		enemy.routeRoom = routeRoom
		enemy.facing = Geometry.angle(destination.x - x, destination.z - z)
		table.insert(patrol.members, enemy.id)
	end

	if #patrol.members == 0 then
		table.remove(run.patrols, #run.patrols)
		return nil
	end
	table.insert(run.events, { kind = "patrolSpawned", patrolId = patrol.id, roomId = room.id })
	return patrol
end

local function growPatrols(run: Types.Run, dt: number)
	local patrols = run.config.enemies.patrols
	local minutes = run.time / 60
	run.patrolDebt += patrols.groupsPerMinute / 60 * dt
	while run.patrolDebt >= 1 do
		-- At the cap only the fraction stays, so a freed slot does not release a burst.
		if full(run) then
			run.patrolDebt %= 1
			return
		end
		run.patrolDebt -= 1
		local size = math.min(
			patrols.maxSize,
			math.floor(patrols.sizeAtStart + patrols.sizeGrowthPerMinute * minutes)
		)
		local strength = 1 + patrols.healthGrowthPerMinute * minutes
		local pool = if minutes >= patrols.lateMinutes then patrols.latePool else patrols.pool
		Camps.spawnPatrol(run, size, pool, strength)
	end
end

-- The camp grows for the players in its room, never shrinks, and so grows when
-- its first player arrives: the configured groups are the size for nobody there.
local function scaleCamp(run: Types.Run, camp: Types.Camp)
	local level = run.config.enemies.camps[camp.level]
	local present: { number } = {}
	for _, id in State.aliveIds(run) do
		if run.players[id].roomId == camp.roomId then
			table.insert(present, id)
		end
	end
	local count = #present
	if count <= camp.scaledFor then
		return
	end
	local delta = count - camp.scaledFor

	-- Before the newcomers are added, so they are not scaled twice.
	local growth = (1 + level.healthPerExtraPlayer) ^ delta
	for _, id in camp.members do
		local enemy = State.enemyById(run, id)
		if enemy then
			enemy.health *= growth
			enemy.maxHealth *= growth
		end
	end

	local newcomerFactor = (1 + level.healthPerExtraPlayer) ^ count
	local total = level.extraPerPlayer * delta
	for index = 1, total do
		if full(run) then
			break
		end
		local group = level.groups[run.rng:integer(1, #level.groups)]
		local x, z = ringSpot(run, camp, (index - 1) / total * 2 * math.pi)
		local enemy = addMember(run, camp, group.archetype, x, z, newcomerFactor)
		if camp.alerted then
			enemy.state = "chase"
			enemy.target = present[1]
		end
	end

	camp.scaledFor = count
	table.insert(run.events, { kind = "campScaled", campId = camp.id, players = count })
end

function Camps.update(run: Types.Run, dt: number)
	growPatrols(run, dt)
	for _, camp in run.camps do
		if #camp.members > 0 then
			scaleCamp(run, camp)
		end
	end
end

return Camps
