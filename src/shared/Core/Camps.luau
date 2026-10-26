--!strict
-- Where enemies come from (ADR-0012, ADR-0004): a camp at every point but the
-- entries, camps that grow with the players at their point and return after
-- they are cleared, patrols that grow with run time, and wanderers. The kinds
-- of enemy and their counts are configuration.

local Geometry = require("./Geometry")
local Map = require("./Map")
local State = require("./State")
local Types = require("./Types")

local Camps = {}

-- Studs from the point centre that a new patrol's members stand at.
local PATROL_RING_RADIUS = 2

local function full(run: Types.Run): boolean
	return #run.enemies >= run.config.enemies.maxAlive
end

-- The strength patrols spawn with at the current run time; a returning camp
-- comes back at it too.
local function strengthNow(run: Types.Run): number
	return 1 + run.config.enemies.patrols.healthGrowthPerMinute * run.time / 60
end

-- A spot on the ring around the camp, kept on walkable ground.
local function ringSpot(run: Types.Run, camp: Types.Camp, angle: number): (number, number)
	local radius = run.config.enemies.campSpreadRadius
	return Map.clamp(run.map, camp.x + math.cos(angle) * radius, camp.z + math.sin(angle) * radius)
end

-- Adds one member to `camp` at (x, z), facing the point's centre.
local function addMember(
	run: Types.Run,
	camp: Types.Camp,
	archetype: string,
	x: number,
	z: number,
	healthFactor: number?
): Types.Enemy
	local point = run.map.points[camp.pointId]
	local enemy = State.newEnemy(run, archetype, camp.level, x, z, healthFactor)
	enemy.campId = camp.id
	enemy.facing = Geometry.angle(point.x - x, point.z - z)
	table.insert(camp.members, enemy.id)
	return enemy
end

-- Stands the level's groups on the ring around the camp at its strength.
local function fillCamp(run: Types.Run, camp: Types.Camp)
	local level = run.config.enemies.camps[camp.level]
	local archetypes: { string } = {}
	for _, group in level.groups do
		for _ = 1, group.count do
			table.insert(archetypes, group.archetype)
		end
	end
	for index, archetype in archetypes do
		if full(run) then
			return
		end
		local x, z = ringSpot(run, camp, (index - 1) / #archetypes * 2 * math.pi)
		addMember(run, camp, archetype, x, z, camp.strength)
	end
end

local function populateCamp(run: Types.Run, point: Types.MapPoint, x: number, z: number)
	local enemies = run.config.enemies
	local level = enemies.camps[point.level]
	local camp: Types.Camp = {
		id = run.nextCampId,
		pointId = point.id,
		x = x,
		z = z,
		level = point.level,
		members = {},
		alerted = false,
		scaledFor = 0,
		leaderId = nil,
		clearedAt = nil,
		returns = true,
		strength = 1,
	}
	run.nextCampId += 1
	table.insert(run.camps, camp)

	-- Drawn even when the cap leaves no room, so the rng stream does not depend on it.
	local hasLeader = run.rng:next() < level.leaderChance
	fillCamp(run, camp)
	if hasLeader and not full(run) then
		local lx, lz = Map.clamp(run.map, camp.x, camp.z)
		camp.leaderId = addMember(run, camp, enemies.campLeader, lx, lz).id
	end
end

function Camps.populate(run: Types.Run)
	local config = run.config
	for _, point in run.map.points do
		local campX, campZ = point.campX, point.campZ
		if point.isEntry or campX == nil or campZ == nil then
			continue
		end
		populateCamp(run, point, campX, campZ)
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

-- Points other than entries at least minHopsFromPlayers paths from every
-- alive player's point.
local function eligiblePoints(run: Types.Run): { Types.MapPoint }
	local minHops = run.config.enemies.patrols.minHopsFromPlayers
	local playerPoints: { number } = {}
	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" then
			table.insert(playerPoints, player.pointId)
		end
	end

	local far: { Types.MapPoint } = {}
	local any: { Types.MapPoint } = {}
	for _, point in run.map.points do
		if point.isEntry then
			continue
		end
		table.insert(any, point)
		local ok = true
		for _, playerPoint in playerPoints do
			if run.map.hops[point.id][playerPoint] < minHops then
				ok = false
				break
			end
		end
		if ok then
			table.insert(far, point)
		end
	end
	-- A map too small for the distance still gets its patrols.
	return if #far > 0 then far else any
end

function Camps.spawnPatrol(
	run: Types.Run,
	size: number,
	pool: { string },
	strength: number
): Types.Patrol?
	local candidates = eligiblePoints(run)
	if #candidates == 0 then
		return nil
	end
	local point = candidates[run.rng:integer(1, #candidates)]
	local routePoint = point.id
	if #point.neighbours > 0 then
		routePoint = point.neighbours[run.rng:integer(1, #point.neighbours)]
	end

	local patrol: Types.Patrol = {
		id = run.nextPatrolId,
		members = {},
		routePoint = routePoint,
		previousPoint = point.id,
		strength = strength,
	}
	run.nextPatrolId += 1
	table.insert(run.patrols, patrol)

	local destination = run.map.points[routePoint]
	for index = 1, size do
		if full(run) then
			break
		end
		local archetype = pool[run.rng:integer(1, #pool)]
		local angle = (index - 1) / size * 2 * math.pi
		local x = point.x + math.cos(angle) * PATROL_RING_RADIUS
		local z = point.z + math.sin(angle) * PATROL_RING_RADIUS
		local enemy = State.newEnemy(run, archetype, point.level, x, z, strength)
		enemy.patrolId = patrol.id
		enemy.state = "patrol"
		enemy.routePoint = routePoint
		enemy.facing = Geometry.angle(destination.x - x, destination.z - z)
		table.insert(patrol.members, enemy.id)
	end

	if #patrol.members == 0 then
		table.remove(run.patrols, #run.patrols)
		return nil
	end
	table.insert(run.events, { kind = "patrolSpawned", patrolId = patrol.id, pointId = point.id })
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
		local strength = strengthNow(run)
		local pool = if minutes >= patrols.lateMinutes then patrols.latePool else patrols.pool
		Camps.spawnPatrol(run, size, pool, strength)
	end
end

-- The camp grows for the players on its point's footprint, never shrinks, and
-- so grows when its first player arrives: the configured groups are the size
-- for nobody there.
local function scaleCamp(run: Types.Run, camp: Types.Camp)
	local level = run.config.enemies.camps[camp.level]
	local point = run.map.points[camp.pointId]
	local present: { number } = {}
	for _, id in State.aliveIds(run) do
		local player = run.players[id]
		if
			player.pointId == camp.pointId
			and Geometry.distance(player.x, player.z, point.x, point.z) <= point.radius
		then
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

	local newcomerFactor = camp.strength * (1 + level.healthPerExtraPlayer) ^ count
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

-- A cleared camp comes back campReturnMinutes after its last member died,
-- with the level's groups at the patrols' strength for the run time and
-- without a leader, and grows anew for the players there. At the cap it waits
-- for a free slot.
local function returnCamp(run: Types.Run, camp: Types.Camp)
	local clearedAt = camp.clearedAt
	if
		not camp.returns
		or clearedAt == nil
		or #camp.members > 0
		or run.time < clearedAt + run.config.map.campReturnMinutes * 60
		or full(run)
	then
		return
	end
	camp.clearedAt = nil
	camp.alerted = false
	camp.scaledFor = 0
	camp.strength = strengthNow(run)
	fillCamp(run, camp)
	table.insert(run.events, { kind = "campReturned", campId = camp.id, pointId = camp.pointId })
end

function Camps.update(run: Types.Run, dt: number)
	growPatrols(run, dt)
	for _, camp in run.camps do
		returnCamp(run, camp)
		if #camp.members > 0 then
			scaleCamp(run, camp)
		end
	end
end

return Camps
