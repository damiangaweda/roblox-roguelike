--!strict
-- Whole runs through Run.step, the way the server adapter drives them.
local Arc = require("../src/shared/Core/Arc")
local Assert = require("./Assert")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Life = require("../src/shared/Core/Life")
local Map = require("../src/shared/Core/Map")
local Run = require("../src/shared/Core/Run")
local Types = require("../src/shared/Core/Types")

local STEP = 1 / 30

-- A run built like the server's: the map populated with camps and patrols.
local function populated(playerCount: number, config: Types.Config?, seed: number?): Types.Run
	local run = Run.new(config or Fixtures.config(), seed or 1, playerCount)
	for id = 1, playerCount do
		Run.addPlayer(run, id)
	end
	return run
end

-- Config for a map with nothing on it but the players: no camp members,
-- leaders, patrols, chest guards or wandering boss.
local function quietConfig(config: Types.Config?): Types.Config
	local settings = config or Fixtures.config()
	for _, level in settings.enemies.camps do
		level.groups = {}
		level.leaderChance = 0
		level.extraPerPlayer = 0
	end
	settings.enemies.patrols.groupsAtStart = 0
	settings.enemies.patrols.groupsPerMinute = 0
	settings.enemies.patrols.wanderersAtStart = 0
	settings.run.arc.events.chestDrop.guardSize = 0
	settings.run.arc.events.wanderingBoss.minute = math.huge
	return settings
end

-- A quiet map, with dry ground within 30 studs of the first entry.
local function quiet(playerCount: number, config: Types.Config?, seed: number?): Types.Run
	local run = populated(playerCount, quietConfig(config), seed)
	local entry = Fixtures.entryOf(run)
	Fixtures.dry(run, entry.x, entry.z, 30)
	return run
end

local function advance(run: Types.Run, seconds: number, inputs: any?): { any }
	local events = {}
	for _ = 1, math.round(seconds / STEP) do
		Run.step(run, STEP, inputs or {})
		for _, event in Run.drainEvents(run) do
			table.insert(events, event)
		end
	end
	return events
end

local function count(events: { any }, kind: string): number
	local n = 0
	for _, event in events do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end

-- Walks the player to (x, z) at walking speed along the map's paths,
-- reporting positions each step, for at most ten minutes of run time.
local function walkTo(run: Types.Run, player: Types.Player, x: number, z: number): { any }
	local events = {}
	local speed = run.config.player.walkSpeed
	local steps = 0
	while steps < 600 * 30 do
		steps += 1
		local wx, wz = Map.waypointToward(run.map, player.x, player.z, x, z)
		local dx, dz = wx - player.x, wz - player.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < 0.01 then
			if wx == x and wz == z then
				break
			end
			-- At a waypoint: the next loop asks for the next one.
			continue
		end
		local step = math.min(distance, speed * STEP)
		Run.setAim(run, player.id, math.atan2(dz, dx))
		local input = {
			[player.id] = {
				x = player.x + dx / distance * step,
				z = player.z + dz / distance * step,
			},
		}
		Run.step(run, STEP, input)
		for _, event in Run.drainEvents(run) do
			table.insert(events, event)
		end
		if run.ended then
			break
		end
	end
	return events
end

return {
	["a new run has a populated map: camps at every point but the entries, patrols, zones"] = function()
		local run = populated(4)
		local campPoints = 0
		for _, point in run.map.points do
			if not point.isEntry then
				campPoints += 1
			end
		end
		Assert.equal(#run.camps, campPoints)
		Assert.truthy(#run.patrols >= run.config.enemies.patrols.groupsAtStart)
		Assert.truthy(#run.enemies > 0)
		-- No zone yet; the clues to every leader are placed.
		Assert.equal(#run.zones, 0)
		local leaders = 0
		for _, camp in run.camps do
			if camp.leaderId then
				leaders += 1
			end
		end
		Assert.equal(#run.clues, leaders * run.config.run.arc.clues.perLeader)
		for id = 1, 4 do
			local point = Fixtures.pointOf(run, id)
			Assert.truthy(point.isEntry, "player " .. id .. " does not start at an entry")
			Assert.equal(run.players[id].pointId, point.id)
		end
	end,

	["players spread over the entries as they join"] = function()
		local run = populated(12)
		Assert.truthy(#run.map.entries > 1)
		local perEntry: { [number]: number } = {}
		for id = 1, 12 do
			local point = Fixtures.pointOf(run, id)
			Assert.truthy(point.isEntry)
			perEntry[point.id] = (perEntry[point.id] or 0) + 1
		end
		for _, id in run.map.entries do
			Assert.equal(perEntry[id], 12 / #run.map.entries, "entry " .. id)
		end
	end,

	["a player who fires at a camp kills, levels up and is offered perks"] = function()
		local config = Fixtures.config()
		config.player.maxHealth = 1e9
		-- Two grunts of the camp pay for the level, whatever else walks by.
		config.progression.xpToSecondLevel = 2
		local run = populated(1, config)
		local player = run.players[1]
		-- Walk to the nearest camp's point and shoot toward its camp.
		local start = Fixtures.pointOf(run, 1)
		local target = run.map.points[start.neighbours[1]]
		local campX, campZ = target.campX :: number, target.campZ :: number
		local events = walkTo(run, player, target.x, target.z)
		player.facing = math.atan2(campZ - player.z, campX - player.x)
		Run.setFiring(run, 1, true)
		for _, event in advance(run, 60) do
			table.insert(events, event)
		end
		Assert.truthy(count(events, "hit") > 0, "no hits in a minute")
		Assert.truthy(count(events, "kill") > 0, "no kills in a minute")
		Assert.truthy(count(events, "levelUp") > 0, "no level-up in a minute")
		Assert.truthy(Assert.findEvent(events, "offer"), "no perk offer")
		Assert.truthy(Run.choosePerk(run, 1, 1))
	end,

	["a player who walks into a camp and stands still is downed and dies alone"] = function()
		local run = populated(1)
		local player = run.players[1]
		local start = Fixtures.pointOf(run, 1)
		local target = run.map.points[start.neighbours[1]]
		local events = walkTo(run, player, target.campX :: number, target.campZ :: number)
		for _, event in advance(run, 120) do
			table.insert(events, event)
		end
		Assert.truthy(Assert.findEvent(events, "campAlerted"), "the camp never noticed")
		Assert.truthy(Assert.findEvent(events, "telegraph"), "no telegraph")
		Assert.truthy(Assert.findEvent(events, "playerHurt"), "never hurt")
		Assert.truthy(Assert.findEvent(events, "downed"), "never downed")
		Assert.truthy(Assert.findEvent(events, "died"), "never died")
		Assert.truthy(Assert.findEvent(events, "ended"), "the run did not end")
		Assert.truthy(run.ended)
	end,

	["a zone opens at the configured minute and a player who reaches it extracts"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local opensAt = run.config.run.arc.zones.firstOpenMinute * 60
		advance(run, opensAt - 1)
		Assert.equal(#run.zones, 0)
		local events = advance(run, 1)
		Assert.equal(#run.zones, 1)
		local zone = run.zones[1]
		Assert.near(zone.openedAt, opensAt, STEP + 1e-6)
		local announced = Assert.findEvent(events, "announcement")
		Assert.truthy(announced)
		Assert.equal(announced.what, "zoneOpened")
		Assert.equal(announced.id, zone.id)
		walkTo(run, player, zone.x, zone.z)
		Assert.truthy(zone.open)
		Run.setInteracting(run, 1, true)
		events =
			advance(run, run.config.run.extractSeconds + 1, { [1] = { x = zone.x, z = zone.z } })
		Assert.truthy(Assert.findEvent(events, "extracted"))
		Assert.truthy(Assert.findEvent(events, "ended"))
		Assert.equal(player.state, "extracted")
	end,

	["the flood meets at the centre at the run's end and kills everyone left"] = function()
		local run = quiet(2)
		-- At the very centre the flood reaches them only as it meets.
		for id = 1, 2 do
			Fixtures.place(run, run.players[id], 0, 0)
		end
		local events = advance(run, run.config.run.durationSeconds - 1)
		Assert.falsy(Assert.findEvent(events, "flood"))
		Assert.falsy(Assert.findEvent(events, "playerHurt"))
		events = advance(run, 2)
		Assert.truthy(Assert.findEvent(events, "flood"))
		Assert.equal(count(events, "died"), 2)
		Assert.truthy(run.ended)
		Assert.equal(run.floodHalf, 0)
	end,

	["the flood hurts a player at the edge every second, then closes their zone"] = function()
		local config = Fixtures.config()
		config.player.maxHealth = 1e9
		local run = quiet(1, config)
		local player = run.players[1]
		-- The zone at the point nearest the edge, the player standing in it
		-- without extracting.
		local edgeMost: Types.MapPoint? = nil
		for _, point in run.map.points do
			local reach = math.max(math.abs(point.x), math.abs(point.z))
			if
				not point.isEntry
				and (
					edgeMost == nil
					or reach > math.max(math.abs(edgeMost.x), math.abs(edgeMost.z))
				)
			then
				edgeMost = point
			end
		end
		assert(edgeMost, "no point")
		local zone = Arc.openZone(run, edgeMost.id)
		-- Sitting at the zone's edge nearest the map's edge.
		local reach = math.max(math.abs(zone.x), math.abs(zone.z))
		local sx = if math.abs(zone.x) >= math.abs(zone.z) then math.sign(zone.x) else 0
		local sz = if sx == 0 then math.sign(zone.z) else 0
		local x, z = zone.x + sx * (zone.radius - 1), zone.z + sz * (zone.radius - 1)
		Fixtures.place(run, player, x, z)
		local flood = config.run.arc.flood
		advance(run, flood.startMinute * 60 - 1)
		Assert.equal(player.health, player.maxHealth)

		local events: { any } = {}
		local hurt = false
		while not hurt and run.time < config.run.durationSeconds do
			for _, event in advance(run, 1) do
				table.insert(events, event)
				if event.kind == "playerHurt" then
					Assert.equal(event.cause, "flood")
					hurt = true
				end
			end
		end
		Assert.truthy(hurt, "the flood never reached the player")
		Assert.truthy(run.floodHalf < reach + zone.radius)
		local before = player.health
		advance(run, 1)
		Assert.near(before - player.health, flood.damagePerSecond, 1e-6)
		-- The flood touched the zone before it reached the player inside it.
		Assert.falsy(zone.open)
		local closed = nil
		for _, event in events do
			if event.kind == "announcement" and event.what == "zoneClosed" then
				closed = event
			end
		end
		Assert.truthy(closed, "no zoneClosed announcement")
		Assert.equal(closed.id, zone.id)
		-- A closed zone does not extract.
		Run.setInteracting(run, 1, true)
		advance(run, run.config.run.extractSeconds + 1, { [1] = { x = x, z = z } })
		Assert.equal(player.state, "alive")
	end,

	["three clues read mark the leader's point for every player"] = function()
		local config = quietConfig()
		config.player.maxHealth = 1e9
		-- Leaders at the farthest camps, who notice nobody.
		config.enemies.camps[config.map.maxLevel].leaderChance = 1
		config.enemies.archetypes.campLeader.detectionRange = 0
		local run = populated(2, config)
		local camp: Types.Camp? = nil
		for _, candidate in run.camps do
			if candidate.leaderId then
				camp = candidate
				break
			end
		end
		assert(camp, "no leader")
		local clues = {}
		for _, clue in run.clues do
			if clue.campId == camp.id then
				table.insert(clues, clue)
			end
		end
		Assert.equal(#clues, config.run.arc.clues.perLeader)
		Assert.equal(run.leaderAreas[camp.id], nil)

		local function read(id: number, clue: Types.Clue): { any }
			local player = run.players[id]
			Fixtures.place(run, player, clue.x, clue.z)
			Run.setInteracting(run, id, true)
			local events = advance(
				run,
				config.run.arc.clues.readSeconds + 0.5,
				{ [id] = { x = clue.x, z = clue.z } }
			)
			Run.setInteracting(run, id, false)
			return events
		end

		-- Player 1 reads two; the area narrows and still holds the point.
		local point = run.map.points[camp.pointId]
		read(1, clues[1])
		local first = run.leaderAreas[camp.id]
		Assert.equal(first.radius, config.run.arc.clues.areaRadii[1])
		Assert.truthy(Geometry.distance(first.x, first.z, point.x, point.z) <= first.radius)
		read(1, clues[2])
		local second = run.leaderAreas[camp.id]
		Assert.equal(second.radius, config.run.arc.clues.areaRadii[2])
		Assert.truthy(Geometry.distance(second.x, second.z, point.x, point.z) <= second.radius)
		-- Player 2 reads the last one: the point is marked, for everyone.
		local events = read(2, clues[3])
		local event = Assert.findEvent(events, "clueRead")
		Assert.truthy(event)
		Assert.equal(event.playerId, 2)
		Assert.equal(event.remaining, 0)
		local area = run.leaderAreas[camp.id]
		Assert.equal(area.radius, 0)
		Assert.equal(area.x, point.x)
		Assert.equal(area.z, point.z)
		-- A clue read is read for everyone: reading it again does nothing.
		events = read(2, clues[1])
		Assert.falsy(Assert.findEvent(events, "clueRead"))
	end,

	["a chest from a chest drop gives a perk choice or potions"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local drop = run.config.run.arc.events.chestDrop
		local events = advance(run, drop.firstMinute * 60 + 1)
		Assert.equal(#run.chests, 1)
		local chest = run.chests[1]
		local announced = nil
		for _, event in events do
			if event.kind == "announcement" and event.what == "chestDrop" then
				announced = event
			end
		end
		Assert.truthy(announced)
		Assert.equal(announced.id, chest.id)
		Assert.equal(announced.x, chest.x)
		Fixtures.place(run, player, chest.x, chest.z)
		Run.setInteracting(run, 1, true)
		events = advance(
			run,
			run.config.run.arc.events.chest.openSeconds + 0.5,
			{ [1] = { x = chest.x, z = chest.z } }
		)
		local opened = Assert.findEvent(events, "chestOpened")
		Assert.truthy(opened)
		Assert.truthy(chest.opened)
		if opened.reward == "perk" then
			Assert.equal(#player.offers, 1)
			Assert.truthy(Assert.findEvent(events, "offer"))
		else
			Assert.equal(opened.reward, "potions")
			Assert.equal(player.potions, run.config.run.arc.events.chest.potions)
		end
	end,

	["the wandering boss comes at its minute far from the players, multiplied"] = function()
		local run = quiet(2)
		local settings = run.config.run.arc.events.wanderingBoss
		settings.minute = Config.run.arc.events.wanderingBoss.minute
		local events = advance(run, settings.minute * 60 - 1)
		Assert.equal(#run.enemies, 0)
		for _, event in advance(run, 1) do
			table.insert(events, event)
		end
		Assert.equal(#run.enemies, 1)
		local boss = run.enemies[1]
		Assert.truthy(boss.boss)
		Assert.equal(boss.archetype, settings.archetype)
		local base = run.config.enemies.archetypes[settings.archetype].health
		Assert.near(boss.maxHealth, base * settings.healthMultiplier)
		local announced = nil
		for _, event in events do
			if event.kind == "announcement" and event.what == "wanderingBoss" then
				announced = event
			end
		end
		Assert.truthy(announced)
		Assert.equal(announced.id, boss.id)
		-- Its point is the one whose nearest player is farthest away.
		local function nearestPlayer(x: number, z: number): number
			local best = math.huge
			for _, player in run.players do
				best = math.min(best, Geometry.distance(x, z, player.x, player.z))
			end
			return best
		end
		local patrol = run.patrols[1]
		Assert.falsy(patrol.wanders)
		local start = run.map.points[patrol.previousPoint]
		for _, point in run.map.points do
			if not point.isEntry then
				Assert.truthy(
					nearestPlayer(point.x, point.z) <= nearestPlayer(start.x, start.z),
					"point " .. point.id .. " is farther from the players"
				)
			end
		end
	end,

	["the incursion wave doubles the patrols' growth for its seconds"] = function()
		local config = Fixtures.config()
		config.player.maxHealth = 1e9
		local run = quiet(1, config)
		config.enemies.patrols.groupsPerMinute = 0.6
		local wave = config.run.arc.events.incursionWave
		-- Groups owed over a stretch: those spawned and the change in the debt.
		local events: { any } = {}
		local function owedOver(seconds: number): number
			local debt = run.patrolDebt
			local spawned = 0
			for _, event in advance(run, seconds) do
				table.insert(events, event)
				if event.kind == "patrolSpawned" then
					spawned += 1
				end
			end
			return spawned + run.patrolDebt - debt
		end
		owedOver(wave.minute * 60 - 60)
		local normal = owedOver(60)
		local during = owedOver(wave.seconds)
		local after = owedOver(60)
		-- The window's edges fall within a step.
		local slack = 0.6 / 60 * STEP * wave.factor
		Assert.near(normal, 0.6, slack)
		Assert.near(during, 0.6 * wave.seconds / 60 * wave.factor, slack)
		Assert.near(after, 0.6, slack)
		local announced = 0
		for _, event in events do
			if event.kind == "announcement" and event.what == "incursionWave" then
				announced += 1
			end
		end
		Assert.equal(announced, 1)
	end,

	["the same seed replays the same run"] = function()
		local a, b = populated(2, nil, 99), populated(2, nil, 99)
		advance(a, 30)
		advance(b, 30)
		Assert.equal(#a.enemies, #b.enemies)
		for i, enemy in a.enemies do
			Assert.equal(enemy.x, b.enemies[i].x)
			Assert.equal(enemy.state, b.enemies[i].state)
		end
		Assert.equal(#a.patrols, #b.patrols)
	end,

	["enemies never exceed the alive cap"] = function()
		local config = Fixtures.config()
		config.enemies.maxAlive = 40
		config.player.maxHealth = 1e9
		local run = populated(12, config)
		Assert.truthy(#run.enemies <= 40)
		advance(run, 3 * 60)
		Assert.truthy(#run.enemies <= 40, "alive: " .. #run.enemies)
	end,

	["nothing happens after the run ended"] = function()
		local run = quiet(1)
		run.ended = true
		Run.step(run, STEP, {})
		Assert.equal(run.time, 0)
		Assert.falsy(Run.useSkill(run, 1, 1, nil, nil))
		Assert.falsy(Run.dash(run, 1))
		Assert.falsy(Run.drink(run, 1))
	end,

	["positions that are not finite are ignored"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local x, z = player.x, player.z
		Run.step(run, STEP, { [1] = { x = 0 / 0, z = z } })
		Run.step(run, STEP, { [1] = { x = math.huge, z = z } })
		Assert.equal(player.x, x)
		Assert.equal(player.z, z)
	end,

	["positions are held on walkable ground"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		-- Far off the map.
		local farX, farZ = point.x + 1000, point.z + 1000
		for _ = 1, 60 * 30 do
			Run.step(run, STEP, { [1] = { x = farX, z = farZ } })
			Assert.truthy(Map.walkable(run.map, player.x, player.z), "off walkable ground")
		end
		Assert.truthy(player.x <= run.map.half and player.z <= run.map.half)
	end,

	["the aim is an intent and a skill may carry its own"] = function()
		local run = quiet(1)
		Run.setAim(run, 1, 1.5)
		Assert.equal(run.players[1].facing, 1.5)
		Run.setAim(run, 1, 0 / 0)
		Assert.equal(run.players[1].facing, 1.5)
		Run.useSkill(run, 1, 1, 2.5, 20)
		Assert.equal(run.players[1].facing, 2.5)
	end,

	["walking at walking speed is accepted"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x - 10, point.z)
		local speed = run.config.player.walkSpeed
		for step = 1, 30 do
			Run.step(run, STEP, { [1] = { x = point.x - 10 + speed * STEP * step, z = point.z } })
		end
		Assert.near(player.x, point.x - 10 + speed * STEP * 30, 1e-6)
	end,

	["late updates catch up within the burst"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x - 10, point.z)
		local speed = run.config.player.walkSpeed
		-- Ten steps without news, then the whole walk arrives at once.
		for _ = 1, 10 do
			Run.step(run, STEP, {})
		end
		Run.step(run, STEP, { [1] = { x = point.x - 10 + speed * STEP * 11, z = point.z } })
		Assert.near(player.x, point.x - 10 + speed * STEP * 11, 1e-6)
	end,

	["a teleport is held to the movement budget"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local settings = run.config.player
		local x = player.x
		advance(run, 2)
		Run.step(run, STEP, { [1] = { x = x + 100, z = player.z } })
		local most = settings.walkSpeed * settings.moveTolerance * settings.moveBurstSeconds
		Assert.truthy(player.x - x <= most + 1e-6, "moved " .. player.x - x .. " studs")
	end,

	["a dash spends a charge and grants its distance as a boost"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x - 15, point.z)
		local dash = run.config.classes.elementalist.dash
		advance(run, 1)
		Assert.truthy(Run.dash(run, 1))
		Assert.equal(player.dashCharges, dash.charges - 1)
		Assert.near(player.boost, dash.distance, 1e-9)
		Assert.truthy(Assert.findEvent(Run.drainEvents(run), "dashed"))
		-- The dashed-to position is accepted in one step.
		Run.step(run, STEP, { [1] = { x = point.x - 15 + dash.distance, z = point.z } })
		Assert.near(player.x, point.x - 15 + dash.distance, 1e-6)
		-- The second charge goes too; the third request is refused.
		Assert.truthy(Run.dash(run, 1))
		Assert.falsy(Run.dash(run, 1))
	end,

	["dash charges come back one at a time"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local dash = run.config.classes.elementalist.dash
		Run.dash(run, 1)
		Run.dash(run, 1)
		Assert.equal(player.dashCharges, 0)
		advance(run, dash.rechargeSeconds + STEP)
		Assert.equal(player.dashCharges, 1)
		advance(run, dash.rechargeSeconds)
		Assert.equal(player.dashCharges, 2)
	end,

	["Long Blink raises the boost a dash grants"] = function()
		local run = quiet(1)
		local player = run.players[1]
		player.perks.longBlink = 1
		local dash = run.config.classes.elementalist.dash
		Run.dash(run, 1)
		Assert.near(player.boost, dash.distance * 1.3, 1e-9)
		Assert.near(Run.dashDistance(run, player), dash.distance * 1.3, 1e-9)
	end,

	["a dash not taken lapses: boosts cannot be banked into a teleport"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x - 15, point.z)
		local dash = run.config.classes.elementalist.dash
		-- Two dashes while standing still, then a long wait.
		Run.dash(run, 1)
		Run.dash(run, 1)
		advance(run, dash.seconds + run.config.player.moveBurstSeconds + 1)
		local settings = run.config.player
		Run.step(run, STEP, { [1] = { x = point.x - 15 + 100, z = point.z } })
		local most = settings.walkSpeed * settings.moveTolerance * settings.moveBurstSeconds
		Assert.truthy(
			player.x - (point.x - 15) <= most + 1e-6,
			"moved " .. player.x - (point.x - 15)
		)
	end,

	["a move stops at the first prop on its way"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		local wall = Fixtures.prop(point, point.x, point.z - 6, 6, 1)
		-- Beside the wall; the report is beyond it.
		Fixtures.place(run, player, point.x + 3, wall.z + wall.halfDepth + 1)
		advance(run, 1)
		Run.step(run, STEP, { [1] = { x = point.x + 3, z = wall.z - wall.halfDepth - 3 } })
		Assert.truthy(player.z > wall.z + wall.halfDepth, "through the prop")
		Assert.truthy(Map.walkable(run.map, player.x, player.z))
	end,

	["a move stops at the water's edge"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		-- Water whose middle is 20 studs from the centre along +x.
		Fixtures.water(run, point.x + 20, point.z, 12)
		Fixtures.place(run, player, point.x + 4, point.z)
		advance(run, 1)
		Assert.truthy(player.moveBudget > 6, "budget " .. player.moveBudget)
		-- The report is in the middle of the water.
		Run.step(run, STEP, { [1] = { x = point.x + 20, z = point.z } })
		Assert.truthy(Map.walkable(run.map, player.x, player.z), "walked into the water")
		Assert.truthy(player.x < point.x + 20, "crossed the water")
		-- Walking on toward the water gets no farther than its edge.
		for _ = 1, 30 do
			Run.step(run, STEP, { [1] = { x = player.x + 0.5, z = point.z } })
			Assert.truthy(Map.walkable(run.map, player.x, player.z), "walked into the water")
		end
		Assert.truthy(player.x < point.x + 20, "crossed the water")
	end,

	["a knocked player is carried by the knockback, not by the client"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x, point.z)
		Life.knockPlayer(run, player, point.x - 5, point.z, 10)
		-- The client keeps reporting the old spot.
		advance(run, run.config.player.knockbackSeconds, { [1] = { x = point.x, z = point.z } })
		Assert.truthy(player.x > point.x + 8, "carried " .. player.x - point.x)
	end,

	["firing backwards is slower"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x, point.z)
		player.moveBudget = 0
		Run.setAim(run, 1, 0)
		Run.setFiring(run, 1, true)
		local speed = run.config.player.walkSpeed * run.config.player.moveTolerance
		-- Away from the aim (+x): only the backpedal share of a step is accepted.
		Run.step(run, STEP, { [1] = { x = point.x - 10, z = point.z } })
		Assert.near(point.x - player.x, speed * run.config.player.backpedalFactor * STEP, 1e-6)
		-- Along the aim: a full step.
		Fixtures.place(run, player, point.x, point.z)
		player.moveBudget = 0
		Run.step(run, STEP, { [1] = { x = point.x + 10, z = point.z } })
		Assert.near(player.x - point.x, speed * STEP, 1e-6)
	end,

	["Fleet Footed adds a dash charge"] = function()
		local run = quiet(1)
		local player = run.players[1]
		player.perks.fleetFooted = 1
		Assert.equal(Run.dashMaxCharges(run, player), 3)
	end,

	["Swift raises the walking speed the run accepts"] = function()
		local run = quiet(1)
		local player = run.players[1]
		player.perks.swift = 1
		Assert.near(Run.walkSpeed(run, player), run.config.player.walkSpeed * 1.1, 1e-9)
	end,

	["a downed player does not move and cannot fire or dash"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local x = player.x
		player.state = "downed"
		player.downedAt = 0
		Run.setFiring(run, 1, true)
		Run.step(run, STEP, { [1] = { x = x + 1, z = player.z + 1 } })
		Assert.equal(player.x, x)
		Assert.falsy(Run.dash(run, 1))
		Assert.falsy(Run.useSkill(run, 1, 2, nil, nil))
	end,

	["the player's point and cover are refreshed each step"] = function()
		local run = quiet(1)
		local player = run.players[1]
		local start = Fixtures.pointOf(run, 1)
		Assert.equal(player.pointId, start.id)
		local target = run.map.points[start.neighbours[1]]
		walkTo(run, player, target.x, target.z)
		Assert.equal(player.pointId, target.id)
		local spot = target.cover[1]
		if spot then
			walkTo(run, player, spot.x, spot.z)
			Assert.truthy(player.inCover)
		end
	end,

	["a camp leader's potion is picked up and drunk"] = function()
		local config = Fixtures.config()
		local run = quiet(1, config)
		local player = run.players[1]
		local point = Fixtures.pointOf(run, 1)
		Fixtures.place(run, player, point.x - 10, point.z)
		local leader = Fixtures.enemy(run, "campLeader", point.x + 5, point.z)
		leader.health = 1
		player.facing = 0
		Run.setFiring(run, 1, true)
		local events = advance(run, 1)
		Assert.truthy(Assert.findEvent(events, "kill"))
		Assert.truthy(Assert.findEvent(events, "dropped"))
		Run.setFiring(run, 1, false)
		for _, event in walkTo(run, player, point.x + 5, point.z) do
			table.insert(events, event)
		end
		Assert.truthy(Assert.findEvent(events, "pickedUp"), "potion not picked up")
		Assert.equal(player.potions, 1)
		player.health = 10
		Assert.truthy(Run.drink(run, 1))
		for _, event in advance(run, config.player.drinkSeconds + STEP) do
			table.insert(events, event)
		end
		Assert.truthy(Assert.findEvent(events, "drank"))
		Assert.equal(player.potions, 0)
		Assert.near(player.health, 10 + config.player.potionHeal)
	end,
}
