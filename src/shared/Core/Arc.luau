--!strict
-- The run's arc (stage 2d, ADR-0012): extraction zones that open on a clock,
-- the flood that closes the map from its edges to its centre, clues that
-- narrow where a camp leader is for everyone, chests, and the run events (a
-- chest drop, the wandering boss, the incursion wave). Reading a clue and
-- opening a chest are held interactions, advanced by Extraction; the flood's
-- end, when it meets at the centre, is Extraction.flood.

local Camps = require("./Camps")
local Geometry = require("./Geometry")
local Life = require("./Life")
local Perks = require("./Perks")
local State = require("./State")
local Types = require("./Types")

local Arc = {}

local function announce(
	run: Types.Run,
	what: Types.Announcement,
	x: number?,
	z: number?,
	id: number?
)
	table.insert(run.events, { kind = "announcement", what = what, x = x, z = z, id = id })
end

-- Whether the flood covers any of the disc of `radius` around (x, z): the
-- flood is everything outside the square of half side floodHalf.
function Arc.flooded(run: Types.Run, x: number, z: number, radius: number?): boolean
	return math.max(math.abs(x), math.abs(z)) + (radius or 0) > run.floodHalf
end

-- The half side of the square the flood has not reached at run time `time`:
-- the map's half until startMinute, shrinking evenly to 0 at endMinute.
function Arc.floodHalfAt(run: Types.Run, time: number): number
	local flood = run.config.run.arc.flood
	local start, finish = flood.startMinute * 60, flood.endMinute * 60
	if time <= start then
		return run.map.half
	end
	if time >= finish then
		return 0
	end
	return run.map.half * (1 - (time - start) / (finish - start))
end

-- The template a point was built from; nil when the configuration lost it.
local function templateOf(run: Types.Run, point: Types.MapPoint): Types.PointTemplate?
	if point.isEntry then
		return run.config.map.entryTemplate
	end
	for _, template in run.config.map.templates do
		if template.id == point.template then
			return template
		end
	end
	return nil
end

-- Where the point's template marks the chest, or the clue, absolute; the
-- centre without a template.
local function spotOf(run: Types.Run, point: Types.MapPoint, chest: boolean): (number, number)
	local template = templateOf(run, point)
	if template == nil then
		return point.x, point.z
	end
	local offset = if chest then template.chest else template.clue
	return point.x + offset.x, point.z + offset.z
end

-- Whether a camp at the point still has its leader.
local function leaderAlive(run: Types.Run, pointId: number): boolean
	for _, camp in run.camps do
		if camp.pointId == pointId and camp.leaderId ~= nil then
			return true
		end
	end
	return false
end

-- Opens a zone at the point's centre and announces it.
function Arc.openZone(run: Types.Run, pointId: number): Types.Zone
	local point = run.map.points[pointId]
	local zone: Types.Zone = {
		id = run.nextZoneId,
		pointId = pointId,
		x = point.x,
		z = point.z,
		radius = run.config.map.zoneRadius,
		open = true,
		openedAt = run.time,
	}
	run.nextZoneId += 1
	table.insert(run.zones, zone)
	announce(run, "zoneOpened", zone.x, zone.z, zone.id)
	return zone
end

-- The ids of the points a zone may open at now, ascending: not an entry, not
-- a point with a living camp leader, none that had a zone, out of the flood,
-- and minZoneDistance from every open zone.
function Arc.zoneCandidates(run: Types.Run): { number }
	local apart = run.config.run.arc.zones.minZoneDistance
	local radius = run.config.map.zoneRadius
	local candidates: { number } = {}
	for _, point in run.map.points do
		if
			point.isEntry
			or leaderAlive(run, point.id)
			or Arc.flooded(run, point.x, point.z, radius)
		then
			continue
		end
		local ok = true
		for _, zone in run.zones do
			if
				zone.pointId == point.id
				or (zone.open and Geometry.distance(point.x, point.z, zone.x, zone.z) < apart)
			then
				ok = false
				break
			end
		end
		if ok then
			table.insert(candidates, point.id)
		end
	end
	return candidates
end

-- A zone is due from firstOpenMinute and every intervalMinutes after; one
-- that finds no point waits for a step where one qualifies, and the clock
-- keeps its slots.
local function openZones(run: Types.Run)
	if run.time < run.nextZoneAt then
		return
	end
	local candidates = Arc.zoneCandidates(run)
	if #candidates == 0 then
		return
	end
	Arc.openZone(run, candidates[run.rng:integer(1, #candidates)])
	run.nextZoneAt += run.config.run.arc.zones.intervalMinutes * 60
end

-- Moves the flood's edge, closes the zones it touches and hurts the players
-- inside it. Its damage goes through Life.damage, so a flood death is any
-- death; the run's end at the centre is Extraction.flood.
local function advanceFlood(run: Types.Run, dt: number)
	local flood = run.config.run.arc.flood
	run.floodHalf = Arc.floodHalfAt(run, run.time)
	if not run.floodStarted and run.time >= flood.startMinute * 60 then
		run.floodStarted = true
		announce(run, "floodStarted")
	end
	for _, zone in run.zones do
		if zone.open and Arc.flooded(run, zone.x, zone.z, zone.radius) then
			zone.open = false
			announce(run, "zoneClosed", zone.x, zone.z, zone.id)
		end
	end
	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" and Arc.flooded(run, player.x, player.z) then
			Life.damage(run, player, flood.damagePerSecond * dt, nil, "flood")
		end
	end
end

-- Drops a chest at the point's chest spot with a patrol that stays by it,
-- and announces it.
function Arc.dropChest(run: Types.Run, pointId: number): Types.Chest
	local drop = run.config.run.arc.events.chestDrop
	local point = run.map.points[pointId]
	local x, z = spotOf(run, point, true)
	local guard =
		Camps.spawnPatrol(run, drop.guardSize, drop.guardPool, Camps.strengthNow(run), false, point)
	if guard then
		guard.stays = true
		guard.routePoint = point.id
		guard.previousPoint = point.id
		for _, id in guard.members do
			local member = State.enemyById(run, id)
			if member then
				member.routePoint = point.id
			end
		end
	end
	local chest: Types.Chest = {
		id = run.nextChestId,
		x = x,
		z = z,
		pointId = pointId,
		opened = false,
		patrolId = if guard then guard.id else nil,
	}
	run.nextChestId += 1
	table.insert(run.chests, chest)
	announce(run, "chestDrop", x, z, chest.id)
	return chest
end

-- A chest drop is due from firstMinute and every intervalMinutes after, at a
-- random point other than an entry with no closed chest, its chest spot out
-- of the flood; with none, it waits like a zone.
local function dropChests(run: Types.Run)
	if run.time < run.nextChestDropAt then
		return
	end
	local candidates: { number } = {}
	for _, point in run.map.points do
		if point.isEntry then
			continue
		end
		local x, z = spotOf(run, point, true)
		if Arc.flooded(run, x, z) then
			continue
		end
		local taken = false
		for _, chest in run.chests do
			if chest.pointId == point.id and not chest.opened then
				taken = true
				break
			end
		end
		if not taken then
			table.insert(candidates, point.id)
		end
	end
	if #candidates == 0 then
		return
	end
	Arc.dropChest(run, candidates[run.rng:integer(1, #candidates)])
	run.nextChestDropAt += run.config.run.arc.events.chestDrop.intervalMinutes * 60
end

-- The point other than an entry, out of the flood, whose nearest alive player
-- is farthest; ties go to the lower id. With nobody alive the entries count
-- as the players.
local function farthestFromPlayers(run: Types.Run): Types.MapPoint?
	local players: { Types.Point } = {}
	for _, id in State.aliveIds(run) do
		local player = run.players[id]
		table.insert(players, { x = player.x, z = player.z })
	end
	if #players == 0 then
		for _, id in run.map.entries do
			local entry = run.map.points[id]
			table.insert(players, { x = entry.x, z = entry.z })
		end
	end
	local best: Types.MapPoint? = nil
	local bestDistance = -1
	for _, point in run.map.points do
		if point.isEntry or Arc.flooded(run, point.x, point.z) then
			continue
		end
		local nearest = math.huge
		for _, player in players do
			nearest = math.min(nearest, Geometry.distance(point.x, point.z, player.x, player.z))
		end
		if nearest > bestDistance then
			best, bestDistance = point, nearest
		end
	end
	return best
end

-- The wandering boss: once, at its minute, a wanderer of the configured
-- archetype at the point farthest from the players, with its health and
-- damage multiplied. At the enemy cap it waits for room.
local function spawnBoss(run: Types.Run)
	local settings = run.config.run.arc.events.wanderingBoss
	if run.bossSpawned or run.time < settings.minute * 60 then
		return
	end
	local point = farthestFromPlayers(run)
	if point == nil then
		return
	end
	local patrol =
		Camps.spawnPatrol(run, 1, { settings.archetype }, settings.healthMultiplier, true, point)
	local enemy = if patrol then State.enemyById(run, patrol.members[1]) else nil
	if enemy == nil then
		return
	end
	enemy.boss = true
	run.bossSpawned = true
	announce(run, "wanderingBoss", enemy.x, enemy.z, enemy.id)
end

-- The incursion wave is announced when it begins; Camps grows the patrols
-- faster while it lasts.
local function startWave(run: Types.Run)
	local wave = run.config.run.arc.events.incursionWave
	if run.waveStarted or run.time < wave.minute * 60 then
		return
	end
	run.waveStarted = true
	announce(run, "incursionWave")
end

-- One step of the arc: zones, the flood, then the run events.
function Arc.update(run: Types.Run, dt: number)
	openZones(run)
	advanceFlood(run, dt)
	dropChests(run)
	spawnBoss(run)
	startWave(run)
end

-- Places perLeader clues for every camp that has a leader at the start, at
-- the clue spots of random points other than entries and the leader's own,
-- one clue to a point while points are left.
function Arc.placeClues(run: Types.Run)
	local perLeader = run.config.run.arc.clues.perLeader
	local used: { [number]: boolean } = {}
	for _, camp in run.camps do
		if camp.leaderId == nil then
			continue
		end
		for _ = 1, perLeader do
			local fresh: { number } = {}
			local any: { number } = {}
			for _, point in run.map.points do
				if point.isEntry or point.id == camp.pointId then
					continue
				end
				table.insert(any, point.id)
				if not used[point.id] then
					table.insert(fresh, point.id)
				end
			end
			local pool = if #fresh > 0 then fresh else any
			if #pool == 0 then
				break
			end
			local pointId = pool[run.rng:integer(1, #pool)]
			used[pointId] = true
			local x, z = spotOf(run, run.map.points[pointId], false)
			table.insert(run.clues, {
				id = run.nextClueId,
				x = x,
				z = z,
				pointId = pointId,
				campId = camp.id,
				read = false,
			})
			run.nextClueId += 1
		end
	end
end

-- The camp's area after `read` of its clues, `remaining` still unread: the
-- first is a circle drawn around the leader's point, each next one that
-- circle shrunk toward the point, so it lies inside the last and still holds
-- the point; the last clue marks the point.
local function narrow(run: Types.Run, camp: Types.Camp, read: number, remaining: number)
	local settings = run.config.run.arc.clues
	local point = run.map.points[camp.pointId]
	local radii = settings.areaRadii
	if remaining == 0 or #radii == 0 then
		run.leaderAreas[camp.id] = { x = point.x, z = point.z, radius = 0 }
		return
	end
	local radius = radii[math.min(read, #radii)]
	local previous = run.leaderAreas[camp.id]
	if previous and previous.radius > 0 then
		radius = math.min(radius, previous.radius)
		local shrink = radius / previous.radius
		run.leaderAreas[camp.id] = {
			x = point.x + (previous.x - point.x) * shrink,
			z = point.z + (previous.z - point.z) * shrink,
			radius = radius,
		}
		return
	end
	local angle = run.rng:next() * 2 * math.pi
	-- Uniform over the disc, not bunched at the point.
	local offset = radius * settings.areaOffsetFraction * math.sqrt(run.rng:next())
	run.leaderAreas[camp.id] = {
		x = point.x + math.cos(angle) * offset,
		z = point.z + math.sin(angle) * offset,
		radius = radius,
	}
end

-- The player has read the clue: the leader's area narrows for everyone.
function Arc.readClue(run: Types.Run, clue: Types.Clue, player: Types.Player)
	clue.read = true
	local read, remaining = 0, 0
	for _, other in run.clues do
		if other.campId == clue.campId then
			if other.read then
				read += 1
			else
				remaining += 1
			end
		end
	end
	local camp = State.campById(run, clue.campId)
	if camp then
		narrow(run, camp, read, remaining)
	end
	table.insert(run.events, {
		kind = "clueRead",
		clueId = clue.id,
		campId = clue.campId,
		playerId = player.id,
		remaining = remaining,
	})
end

-- The player has opened the chest: a perk choice by perkChance, else (or
-- when no perk is left to offer) potions up to the capacity. Its guard is
-- free to walk on.
function Arc.openChest(run: Types.Run, chest: Types.Chest, player: Types.Player)
	local settings = run.config.run.arc.events.chest
	chest.opened = true
	local reward: "perk" | "potions" = "potions"
	if run.rng:next() < settings.perkChance then
		local before = #player.offers
		Perks.offer(run, player)
		if #player.offers > before then
			reward = "perk"
		end
	end
	if reward == "potions" then
		player.potions = math.max(
			player.potions,
			math.min(Life.potionCapacity(run, player), player.potions + settings.potions)
		)
	end
	local guard = if chest.patrolId then State.patrolById(run, chest.patrolId) else nil
	if guard then
		guard.stays = false
	end
	table.insert(
		run.events,
		{ kind = "chestOpened", chestId = chest.id, playerId = player.id, reward = reward }
	)
end

-- The nearest unread clue within readRadius of the player; a tie goes to
-- the first placed.
function Arc.clueNear(run: Types.Run, player: Types.Player): Types.Clue?
	local best: Types.Clue? = nil
	local bestDistance = math.huge
	local radius = run.config.run.arc.clues.readRadius
	for _, clue in run.clues do
		local distance = Geometry.distance(player.x, player.z, clue.x, clue.z)
		if not clue.read and distance <= radius and distance < bestDistance then
			best, bestDistance = clue, distance
		end
	end
	return best
end

-- The nearest closed chest within openRadius of the player; a tie goes to
-- the first dropped.
function Arc.chestNear(run: Types.Run, player: Types.Player): Types.Chest?
	local best: Types.Chest? = nil
	local bestDistance = math.huge
	local radius = run.config.run.arc.events.chest.openRadius
	for _, chest in run.chests do
		local distance = Geometry.distance(player.x, player.z, chest.x, chest.z)
		if not chest.opened and distance <= radius and distance < bestDistance then
			best, bestDistance = chest, distance
		end
	end
	return best
end

return Arc
