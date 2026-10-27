--!strict
-- The run's arc (stage 2d): zones on a clock, the flood, clues, chests and the
-- run events.
local Arc = require("../src/shared/Core/Arc")
local Assert = require("./Assert")
local Camps = require("../src/shared/Core/Camps")
local Combat = require("../src/shared/Core/Combat")
local Enemies = require("../src/shared/Core/Enemies")
local Extraction = require("../src/shared/Core/Extraction")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Life = require("../src/shared/Core/Life")
local Run = require("../src/shared/Core/Run")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- A config whose flood never comes, chest drops and boss never come, and
-- whose cap never interferes; a spec turns on what it tests.
local function calm(): Types.Config
	local config = Fixtures.config()
	config.enemies.maxAlive = 10000
	config.run.arc.flood.startMinute = 1000
	config.run.arc.events.chestDrop.firstMinute = math.huge
	config.run.arc.events.wanderingBoss.minute = math.huge
	return config
end

-- Advances the clock and the arc by `seconds` in steps of `dt`.
local function tick(run: Types.Run, seconds: number, dt: number?)
	local step = dt or 0.5
	for _ = 1, math.round(seconds / step) do
		run.time += step
		Arc.update(run, step)
	end
end

-- Advances the clock and the interactions by `seconds` in steps of `dt`;
-- the clues the players come near are found first, as in Run.step.
local function hold(run: Types.Run, seconds: number, dt: number?)
	local step = dt or 0.5
	for _ = 1, math.round(seconds / step) do
		run.time += step
		Arc.findClues(run)
		Extraction.update(run, step)
	end
end

local function announcements(run: Types.Run, what: string): { any }
	local found = {}
	for _, event in run.events do
		local any = event :: any
		if any.kind == "announcement" and any.what == what then
			table.insert(found, any)
		end
	end
	return found
end

local function eventsOf(run: Types.Run, kind: string): { any }
	local found = {}
	for _, event in run.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

-- A run whose farthest camps have leaders, or with `everywhere` every camp,
-- and the clues to them placed.
local function withLeaders(players: number, seed: number?, everywhere: boolean?): Types.Run
	local settings = calm()
	for index, level in settings.enemies.camps do
		level.leaderChance = if everywhere or index == settings.map.maxLevel then 1 else 0
	end
	local run = Fixtures.run(players, settings, seed)
	Camps.populate(run)
	Arc.placeClues(run)
	return run
end

-- The first camp with a leader, and its clues in placement order.
local function leaderCamp(run: Types.Run): (Types.Camp, { Types.Clue })
	for _, camp in run.camps do
		if camp.leaderId then
			local clues = {}
			for _, clue in run.clues do
				if clue.campId == camp.id then
					table.insert(clues, clue)
				end
			end
			return camp, clues
		end
	end
	error("no leader")
end

-- Puts player `id` on (x, z), holding the interact button.
local function standAt(run: Types.Run, id: number, x: number, z: number)
	Fixtures.place(run, run.players[id], x, z)
	run.players[id].interacting = true
end

local function readClue(run: Types.Run, id: number, clue: Types.Clue)
	standAt(run, id, clue.x, clue.z)
	hold(run, run.config.run.arc.clues.readSeconds)
	run.players[id].interacting = false
end

-- A chest at the first point that is not an entry.
local function someChest(run: Types.Run): Types.Chest
	for _, point in run.map.points do
		if not point.isEntry then
			return Arc.dropChest(run, point.id)
		end
	end
	error("no point")
end

return {
	-- Zones.

	["no zone opens before the first minute, then one every interval"] = function()
		for seed = 1, 5 do
			local run = Fixtures.run(12, calm(), seed)
			local zones = run.config.run.arc.zones
			local label = "seed " .. seed
			tick(run, zones.firstOpenMinute * 60 - 0.5)
			Assert.equal(#run.zones, 0, label)
			tick(run, 0.5)
			Assert.equal(#run.zones, 1, label)
			Assert.equal(run.zones[1].openedAt, zones.firstOpenMinute * 60, label)
			tick(run, zones.intervalMinutes * 60 - 0.5)
			Assert.equal(#run.zones, 1, label)
			tick(run, 0.5)
			Assert.equal(#run.zones, 2, label)
			Assert.equal(
				run.zones[2].openedAt,
				(zones.firstOpenMinute + zones.intervalMinutes) * 60,
				label
			)
			local opened = announcements(run, "zoneOpened")
			Assert.equal(#opened, 2, label)
			for index, event in opened do
				local zone = run.zones[index]
				Assert.equal(event.id, zone.id, label)
				Assert.equal(event.x, zone.x, label)
				Assert.equal(event.z, zone.z, label)
			end
		end
	end,

	["zones open at points apart, never at an entry or twice at one point"] = function()
		for _, players in { 1, 4, 12 } do
			for seed = 1, 8 do
				local run = Fixtures.run(players, calm(), seed)
				local apart = run.config.run.arc.zones.minZoneDistance
				local label = "seed " .. seed .. ", " .. players .. " players"
				tick(run, 30 * 60, 1)
				Assert.truthy(#run.zones >= 1, label)
				local seen: { [number]: boolean } = {}
				for index, zone in run.zones do
					local point = run.map.points[zone.pointId]
					Assert.falsy(point.isEntry, label)
					Assert.falsy(seen[zone.pointId], label)
					seen[zone.pointId] = true
					Assert.equal(zone.x, point.x, label)
					Assert.equal(zone.z, point.z, label)
					Assert.equal(zone.id, index, label)
					-- No flood here: every zone is still open.
					Assert.truthy(zone.open, label)
					for other = 1, index - 1 do
						local before = run.zones[other]
						Assert.truthy(
							Geometry.distance(zone.x, zone.z, before.x, before.z) >= apart,
							label
						)
					end
				end
			end
		end
	end,

	["a zone never opens at a point whose camp leader is alive"] = function()
		local run = withLeaders(4, 3, true)
		local zones = run.config.run.arc.zones
		-- Every point but the entries holds a leader: nothing qualifies.
		Assert.equal(#Arc.zoneCandidates(run), 0)
		tick(run, zones.firstOpenMinute * 60 + 30)
		Assert.equal(#run.zones, 0)
		-- The zone waits for a step where a point qualifies: one whose leader died.
		local camp = run.camps[1]
		local leader = State.enemyById(run, camp.leaderId :: number)
		assert(leader, "no leader")
		State.removeEnemy(run, leader)
		tick(run, 0.5)
		Assert.equal(#run.zones, 1)
		Assert.equal(run.zones[1].pointId, camp.pointId)
		-- The next one is due an interval after it opened, not after its slot.
		Assert.equal(run.nextZoneAt, run.time + zones.intervalMinutes * 60)
	end,

	["a late zone does not bring the next one early"] = function()
		local run = withLeaders(4, 3, true)
		local zones = run.config.run.arc.zones
		-- Every point holds a leader until they all die, 100 seconds late.
		tick(run, zones.firstOpenMinute * 60 + 100)
		Assert.equal(#run.zones, 0)
		for _, camp in run.camps do
			local leader = State.enemyById(run, camp.leaderId :: number)
			if leader then
				State.removeEnemy(run, leader)
			end
		end
		tick(run, 0.5)
		Assert.equal(#run.zones, 1)
		local openedAt = run.zones[1].openedAt
		-- Not at the slot an interval after the first minute.
		tick(run, zones.intervalMinutes * 60 - 0.5)
		Assert.equal(#run.zones, 1)
		tick(run, 0.5)
		Assert.equal(#run.zones, 2)
		Assert.equal(run.zones[2].openedAt, openedAt + zones.intervalMinutes * 60)
	end,

	["a zone never opens where the flood arrives in the same step"] = function()
		local config = calm()
		config.run.arc.flood.startMinute = 0
		config.run.arc.zones.minZoneDistance = 0
		local run = Fixtures.run(1, config, 2)
		local radius = config.map.zoneRadius
		-- One point left without a zone: the one the flood reaches last.
		local last: Types.MapPoint? = nil
		for _, point in run.map.points do
			if
				not point.isEntry
				and (
					last == nil
					or math.max(math.abs(point.x), math.abs(point.z))
						< math.max(math.abs(last.x), math.abs(last.z))
				)
			then
				last = point
			end
		end
		assert(last, "no point")
		for _, id in Arc.zoneCandidates(run) do
			if id ~= last.id then
				Arc.openZone(run, id)
			end
		end
		local opened = #run.zones
		-- The step at which the flood's edge passes the zone it would open.
		local reach = math.max(math.abs(last.x), math.abs(last.z)) + radius
		local at = config.run.durationSeconds * (1 - (reach - 0.05) / run.map.half)
		Assert.truthy(Arc.floodHalfAt(run, at - 1) > reach)
		Assert.truthy(Arc.floodHalfAt(run, at) < reach)
		run.time = at - 1
		run.nextZoneAt = at
		Arc.update(run, 1)
		Assert.equal(#run.zones, opened)
		run.events = {}
		run.time = at
		Arc.update(run, 1)
		Assert.equal(#run.zones, opened)
		Assert.equal(#announcements(run, "zoneOpened"), 0)
	end,

	-- The flood.

	["the flood holds at the edges until its start, then reaches the centre at the run's end"] = function()
		local run = Fixtures.run(1)
		local flood = run.config.run.arc.flood
		local half = run.map.half
		Assert.equal(run.floodHalf, half)
		tick(run, flood.startMinute * 60, 1)
		Assert.equal(run.floodHalf, half)
		Assert.equal(#announcements(run, "floodStarted"), 1)
		local span = run.config.run.durationSeconds - flood.startMinute * 60
		tick(run, span / 2, 1)
		Assert.near(run.floodHalf, half / 2)
		tick(run, span / 4, 1)
		Assert.near(run.floodHalf, half / 4)
		tick(run, span / 4, 1)
		Assert.equal(run.floodHalf, 0)
		Assert.equal(run.time, run.config.run.durationSeconds)
		Assert.equal(#announcements(run, "floodStarted"), 1)
	end,

	["a player inside the flood is hurt once a tick, one inside the square is not"] = function()
		local config = Fixtures.config()
		config.player.maxHealth = 1e6
		local run = Fixtures.run(2, config)
		local flood = config.run.arc.flood
		local span = config.run.durationSeconds - flood.startMinute * 60
		-- Halfway: the safe square is half the map's.
		run.time = flood.startMinute * 60 + span / 2
		local edge = run.map.half / 2
		Fixtures.place(run, run.players[1], edge + 5, 0)
		Fixtures.place(run, run.players[2], 0, -(edge - 5))
		-- Steps at the server's rate, over three ticks.
		local dt = 1 / config.net.stepHz
		for _ = 1, math.round(3 * flood.tickSeconds / dt) do
			run.time += dt
			Arc.update(run, dt)
		end
		local perTick = flood.damagePerSecond * flood.tickSeconds
		Assert.near(run.players[1].health, config.player.maxHealth - 3 * perTick, 1e-6)
		Assert.equal(run.players[2].health, config.player.maxHealth)
		local hurts = eventsOf(run, "playerHurt")
		Assert.equal(#hurts, 3)
		for _, event in hurts do
			Assert.equal(event.player, 1)
			Assert.equal(event.cause, "flood")
			Assert.equal(event.enemyId, nil)
			Assert.near(event.amount, perTick)
		end
	end,

	["the flood closes the zones it touches, and no zone opens inside it"] = function()
		local config = calm()
		config.run.arc.flood.startMinute = 11
		config.run.arc.zones.minZoneDistance = 0
		local run = Fixtures.run(12, config, 4)
		-- Every point but the entries has a zone before the flood.
		for _, id in Arc.zoneCandidates(run) do
			Arc.openZone(run, id)
		end
		local opened = #run.zones
		Assert.truthy(opened > 3)
		run.events = {}
		for _ = 1, 15 * 60 do
			run.time += 1
			Arc.update(run, 1)
			for _, zone in run.zones do
				Assert.equal(zone.open, not Arc.flooded(run, zone.x, zone.z, zone.radius))
			end
		end
		Assert.equal(#run.zones, opened)
		local closed = announcements(run, "zoneClosed")
		Assert.equal(#closed, opened)
		for _, event in closed do
			Assert.truthy(event.id >= 1 and event.id <= opened)
		end
	end,

	["the flood downs a player like any hit and the run ends when it meets"] = function()
		local config = calm()
		config.enemies.patrols.groupsPerMinute = 0
		config.run.arc.flood.startMinute = 11
		local run = Fixtures.run(2, config)
		local flood = config.run.arc.flood
		-- Player 1 at the very edge, nearly dead; player 2 at the centre.
		local player, survivor = run.players[1], run.players[2]
		Fixtures.place(run, player, run.map.half, 0)
		Fixtures.place(run, survivor, 0, 0)
		player.health = flood.damagePerSecond / 2
		run.time = flood.startMinute * 60
		local events = {}
		local function step(seconds: number)
			for _ = 1, seconds * 10 do
				Run.step(run, 0.1, {})
				for _, event in Run.drainEvents(run) do
					table.insert(events, event)
				end
			end
		end
		step(2 * flood.tickSeconds)
		Assert.equal(player.state, "downed")
		step(config.player.downedSeconds + 1)
		Assert.equal(player.state, "dead")
		Assert.equal(survivor.state, "alive")
		Assert.falsy(Assert.findEvent(events, "flood"))
		step(config.run.durationSeconds - flood.startMinute * 60)
		Assert.truthy(Assert.findEvent(events, "flood"))
		Assert.equal(survivor.state, "dead")
		Assert.truthy(run.ended)
	end,

	["flood damage interrupts nothing, and still names the flood"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.extractProgress, player.clueProgress, player.chestProgress = 1, 1, 1
		player.drinkingUntil = run.time + 1
		Life.damage(run, player, 5, nil, "flood", { interrupts = false })
		Assert.equal(player.health, player.maxHealth - 5)
		Assert.equal(player.extractProgress, 1)
		Assert.equal(player.clueProgress, 1)
		Assert.equal(player.chestProgress, 1)
		Assert.equal(player.drinkingUntil, run.time + 1)
		Assert.equal(player.hurtAt, -math.huge)
		Assert.falsy(Assert.findEvent(run.events, "drinkInterrupted"))
		local hurt = Assert.findEvent(run.events, "playerHurt")
		Assert.equal(hurt.cause, "flood")
		Assert.equal(hurt.amount, 5)
	end,

	["a drink finishes inside the flood"] = function()
		local config = Fixtures.config()
		local run = Fixtures.run(1, config)
		local player = run.players[1]
		local flood = config.run.arc.flood
		run.time = flood.startMinute * 60
			+ (config.run.durationSeconds - flood.startMinute * 60) / 2
		Fixtures.place(run, player, run.map.half / 2 + 5, 0)
		player.health = player.maxHealth / 2
		player.potions = 1
		Assert.truthy(Life.drink(run, 1))
		local dt = 1 / config.net.stepHz
		for _ = 1, math.round((config.player.drinkSeconds + 0.5) / dt) do
			run.time += dt
			Arc.update(run, dt)
			Life.update(run, dt)
		end
		Assert.truthy(#eventsOf(run, "playerHurt") >= 1)
		Assert.falsy(Assert.findEvent(run.events, "drinkInterrupted"))
		Assert.truthy(Assert.findEvent(run.events, "drank"))
		Assert.equal(player.potions, 0)
	end,

	["a revive finishes inside the flood"] = function()
		local config = Fixtures.config()
		local run = Fixtures.run(2, config)
		local reviver, downed = run.players[1], run.players[2]
		local flood = config.run.arc.flood
		run.time = flood.startMinute * 60
			+ (config.run.durationSeconds - flood.startMinute * 60) / 2
		local x = run.map.half / 2 + 5
		Fixtures.place(run, reviver, x, 0)
		Fixtures.place(run, downed, x, 2)
		Life.damage(run, downed, downed.maxHealth)
		Assert.equal(downed.state, "downed")
		reviver.interacting = true
		local dt = 1 / config.net.stepHz
		for _ = 1, math.round((config.player.reviveSeconds + 0.5) / dt) do
			run.time += dt
			Arc.update(run, dt)
			Life.update(run, dt)
		end
		Assert.truthy(reviver.health < reviver.maxHealth)
		Assert.equal(reviver.state, "alive")
		Assert.equal(downed.state, "alive")
		Assert.truthy(Assert.findEvent(run.events, "revived"))
	end,

	-- Clues.

	["clues stand at other points' clue spots, perLeader for each leader"] = function()
		for seed = 1, 6 do
			local run = withLeaders(12, seed)
			local perLeader = run.config.run.arc.clues.perLeader
			local label = "seed " .. seed
			local leaders = 0
			local points = 0
			for _, point in run.map.points do
				if not point.isEntry then
					points += 1
				end
			end
			local used: { [number]: number } = {}
			for _, camp in run.camps do
				if camp.leaderId then
					leaders += 1
				end
			end
			Assert.equal(#run.clues, leaders * perLeader, label)
			for index, clue in run.clues do
				Assert.equal(clue.id, index, label)
				Assert.falsy(clue.read, label)
				local point = run.map.points[clue.pointId]
				local camp = State.campById(run, clue.campId)
				assert(camp, "no camp")
				Assert.falsy(point.isEntry, label)
				Assert.truthy(clue.pointId ~= camp.pointId, label)
				Assert.truthy(
					Geometry.distance(clue.x, clue.z, point.x, point.z) <= point.radius,
					label
				)
				used[clue.pointId] = (used[clue.pointId] or 0) + 1
			end
			-- One clue to a point while points last.
			local distinct = 0
			for _ in used do
				distinct += 1
			end
			Assert.truthy(distinct >= math.min(#run.clues, points - 1), label)
		end
	end,

	["each clue read narrows the leader's area for everyone and the last marks the point"] = function()
		for seed = 1, 6 do
			local run = withLeaders(2, seed)
			local radii = run.config.run.arc.clues.areaRadii
			local camp, clues = leaderCamp(run)
			local point = run.map.points[camp.pointId]
			local label = "seed " .. seed
			Assert.equal(run.leaderAreas[camp.id], nil, label)

			readClue(run, 1, clues[1])
			Assert.truthy(clues[1].read, label)
			local first = run.leaderAreas[camp.id]
			Assert.equal(first.radius, radii[1], label)
			Assert.truthy(
				Geometry.distance(first.x, first.z, point.x, point.z) <= first.radius,
				label
			)
			-- Not centred on the point, which would give it away.
			Assert.truthy(Geometry.distance(first.x, first.z, point.x, point.z) > 0, label)

			-- A second player reads the next one: the areas are the run's.
			readClue(run, 2, clues[2])
			local second = run.leaderAreas[camp.id]
			Assert.equal(second.radius, radii[2], label)
			Assert.truthy(
				Geometry.distance(second.x, second.z, point.x, point.z) <= second.radius,
				label
			)
			-- Inside the first area.
			Assert.truthy(
				Geometry.distance(second.x, second.z, first.x, first.z) + second.radius
					<= first.radius + 1e-6,
				label
			)

			readClue(run, 1, clues[3])
			local last = run.leaderAreas[camp.id]
			Assert.equal(last.radius, 0, label)
			Assert.equal(last.x, point.x, label)
			Assert.equal(last.z, point.z, label)

			local reads = eventsOf(run, "clueRead")
			Assert.equal(#reads, 3, label)
			for index, event in reads do
				Assert.equal(event.clueId, clues[index].id, label)
				Assert.equal(event.campId, camp.id, label)
				Assert.equal(event.remaining, 3 - index, label)
			end
			Assert.equal(reads[2].playerId, 2, label)
		end
	end,

	["reading takes its seconds held, within its radius, and a hit starts it over"] = function()
		local run = withLeaders(1)
		local settings = run.config.run.arc.clues
		local _, clues = leaderCamp(run)
		local clue = clues[1]
		local player = run.players[1]
		standAt(run, 1, clue.x + settings.readRadius + 0.5, clue.z)
		hold(run, settings.readSeconds * 2)
		Assert.equal(player.clueProgress, 0)
		Assert.falsy(clue.read)

		standAt(run, 1, clue.x + settings.readRadius - 0.5, clue.z)
		hold(run, settings.readSeconds - 0.5)
		Assert.near(player.clueProgress, settings.readSeconds - 0.5)
		Assert.falsy(clue.read)
		Life.damage(run, player, 1)
		Assert.equal(player.clueProgress, 0)
		hold(run, settings.readSeconds - 0.5)
		Assert.falsy(clue.read)
		player.interacting = false
		hold(run, 0.5)
		Assert.equal(player.clueProgress, 0)
		player.interacting = true
		hold(run, settings.readSeconds)
		Assert.truthy(clue.read)
		Assert.equal(player.clueProgress, 0)
		-- A read clue is not read again.
		hold(run, settings.readSeconds * 2)
		local reads = 0
		for _, event in eventsOf(run, "clueRead") do
			if event.clueId == clue.id then
				reads += 1
			end
		end
		Assert.equal(reads, 1)
	end,

	["a clue is found when an alive player comes within its find radius"] = function()
		local run = withLeaders(2)
		local findRadius = run.config.run.arc.clues.findRadius
		for _, clue in run.clues do
			Assert.falsy(clue.found)
		end
		local _, clues = leaderCamp(run)
		local clue = clues[1]
		-- Far enough from every other clue to find only this one.
		for _, other in run.clues do
			if other ~= clue then
				other.x, other.z = clue.x + 10 * findRadius, clue.z + 10 * findRadius
			end
		end
		-- Nobody near, and a downed player near, find nothing.
		Fixtures.place(run, run.players[1], clue.x + findRadius + 1, clue.z)
		Fixtures.place(run, run.players[2], clue.x, clue.z)
		run.players[2].state = "downed"
		tick(run, 1)
		Assert.falsy(clue.found)
		Assert.equal(#eventsOf(run, "clueFound"), 0)

		Fixtures.place(run, run.players[1], clue.x + findRadius - 1, clue.z)
		tick(run, 1)
		Assert.truthy(clue.found)
		local found = eventsOf(run, "clueFound")
		Assert.equal(#found, 1)
		Assert.equal(found[1].clueId, clue.id)
		Assert.falsy(clue.read)
		-- Found once.
		tick(run, 1)
		Assert.equal(#eventsOf(run, "clueFound"), 1)
	end,

	["a clue nobody has found is not read"] = function()
		local run = withLeaders(1)
		local _, clues = leaderCamp(run)
		local clue = clues[1]
		local player = run.players[1]
		standAt(run, 1, clue.x, clue.z)
		for _ = 1, 10 do
			run.time += 0.5
			Extraction.update(run, 0.5)
		end
		Assert.falsy(clue.read)
		Assert.equal(player.clueProgress, 0)
		Arc.findClues(run)
		Assert.truthy(clue.found)
		hold(run, run.config.run.arc.clues.readSeconds)
		Assert.truthy(clue.read)
	end,

	["a later area is drawn afresh, so two areas do not give the point away"] = function()
		local checked = 0
		for seed = 1, 40 do
			local run = withLeaders(2, seed, true)
			local label = "seed " .. seed
			for _, camp in run.camps do
				if camp.leaderId == nil then
					continue
				end
				local clues = {}
				for _, clue in run.clues do
					if clue.campId == camp.id then
						table.insert(clues, clue)
					end
				end
				local point = run.map.points[camp.pointId]
				Arc.readClue(run, clues[1], run.players[1])
				local first = run.leaderAreas[camp.id]
				Arc.readClue(run, clues[2], run.players[1])
				local second = run.leaderAreas[camp.id]
				Assert.truthy(
					Geometry.distance(second.x, second.z, point.x, point.z) <= second.radius,
					label
				)
				Assert.truthy(
					Geometry.distance(second.x, second.z, first.x, first.z) + second.radius
						<= first.radius + 1e-6,
					label
				)
				-- Shrinking the first toward the point would put the point
				-- exactly here.
				Assert.truthy(
					Geometry.distance(
						2 * second.x - first.x,
						2 * second.z - first.z,
						point.x,
						point.z
					) > 1,
					label
				)
				checked += 1
			end
		end
		Assert.truthy(checked > 100)
	end,

	-- Chests and the chest drop.

	["a chest drops at its first minute and every interval, guarded by a patrol that stays"] = function()
		local config = calm()
		config.run.arc.events.chestDrop.firstMinute = 4
		local run = Fixtures.run(4, config, 2)
		local drop = config.run.arc.events.chestDrop
		tick(run, drop.firstMinute * 60 - 0.5)
		Assert.equal(#run.chests, 0)
		tick(run, 0.5)
		Assert.equal(#run.chests, 1)
		tick(run, drop.intervalMinutes * 60 - 0.5)
		Assert.equal(#run.chests, 1)
		tick(run, 0.5)
		Assert.equal(#run.chests, 2)

		local dropped = announcements(run, "chestDrop")
		Assert.equal(#dropped, 2)
		for index, chest in run.chests do
			local point = run.map.points[chest.pointId]
			Assert.falsy(point.isEntry)
			Assert.falsy(chest.opened)
			Assert.equal(dropped[index].id, chest.id)
			Assert.equal(dropped[index].x, chest.x)
			Assert.equal(dropped[index].z, chest.z)
			Assert.truthy(Geometry.distance(chest.x, chest.z, point.x, point.z) <= point.radius)
			local guard = State.patrolById(run, chest.patrolId :: number)
			assert(guard, "no guard")
			Assert.truthy(guard.stays)
			Assert.equal(guard.routePoint, point.id)
			Assert.equal(#guard.members, drop.guardSize)
			for _, id in guard.members do
				local enemy = State.enemyById(run, id)
				assert(enemy, "no member")
				Assert.truthy(table.find(drop.guardPool, enemy.archetype) ~= nil)
			end
		end

		-- With nobody near, the guard walks to its point and stays there.
		local chest = run.chests[1]
		local point = run.map.points[chest.pointId]
		for _ = 1, 60 * 10 do
			run.time += 0.1
			Enemies.step(run, 0.1)
		end
		local guard = State.patrolById(run, chest.patrolId :: number)
		assert(guard, "no guard")
		Assert.equal(guard.routePoint, point.id)
		for _, id in guard.members do
			local enemy = State.enemyById(run, id)
			assert(enemy, "no member")
			Assert.truthy(Geometry.distance(enemy.x, enemy.z, point.x, point.z) <= point.radius)
		end
	end,

	["opening a chest takes its seconds held, and a hit starts it over"] = function()
		local run = Fixtures.run(1)
		local settings = run.config.run.arc.events.chest
		local chest = someChest(run)
		local player = run.players[1]
		standAt(run, 1, chest.x + settings.openRadius - 0.5, chest.z)
		hold(run, settings.openSeconds - 0.5)
		Assert.near(player.chestProgress, settings.openSeconds - 0.5)
		Assert.falsy(chest.opened)
		Life.damage(run, player, 1)
		Assert.equal(player.chestProgress, 0)
		hold(run, settings.openSeconds - 0.5)
		Assert.falsy(chest.opened)
		hold(run, 0.5)
		Assert.truthy(chest.opened)
		Assert.equal(#eventsOf(run, "chestOpened"), 1)
		-- An opened chest does not open again.
		hold(run, settings.openSeconds * 2)
		Assert.equal(#eventsOf(run, "chestOpened"), 1)
		-- Its guard walks on.
		local guard = State.patrolById(run, chest.patrolId :: number)
		assert(guard, "no guard")
		Assert.falsy(guard.stays)
	end,

	["a chest holds a perk choice or potions up to the capacity"] = function()
		local config = Fixtures.config()
		config.run.arc.events.chest.perkChance = 1
		local run = Fixtures.run(1, config)
		local chest = someChest(run)
		standAt(run, 1, chest.x, chest.z)
		hold(run, config.run.arc.events.chest.openSeconds)
		local opened = Assert.findEvent(run.events, "chestOpened")
		Assert.equal(opened.reward, "perk")
		Assert.equal(opened.playerId, 1)
		Assert.equal(opened.chestId, chest.id)
		Assert.equal(#run.players[1].offers, 1)
		Assert.truthy(Assert.findEvent(run.events, "offer"))

		config = Fixtures.config()
		config.run.arc.events.chest.perkChance = 0
		config.run.arc.events.chest.potions = 2
		run = Fixtures.run(1, config)
		local player = run.players[1]
		player.potions = config.player.potionCapacity - 1
		chest = someChest(run)
		standAt(run, 1, chest.x, chest.z)
		hold(run, config.run.arc.events.chest.openSeconds)
		opened = Assert.findEvent(run.events, "chestOpened")
		Assert.equal(opened.reward, "potions")
		Assert.equal(player.potions, config.player.potionCapacity)
		Assert.equal(#player.offers, 0)
	end,

	["a chest with no perk left to offer gives potions"] = function()
		local config = Fixtures.config()
		config.run.arc.events.chest.perkChance = 1
		local run = Fixtures.run(1, config)
		local player = run.players[1]
		for id, perk in config.perks.pool do
			player.perks[id] = perk.maxStacks
		end
		local chest = someChest(run)
		standAt(run, 1, chest.x, chest.z)
		hold(run, config.run.arc.events.chest.openSeconds)
		Assert.equal(Assert.findEvent(run.events, "chestOpened").reward, "potions")
		Assert.equal(player.potions, config.run.arc.events.chest.potions)
	end,

	["the interact button extracts before it reads, and reads before it opens"] = function()
		local run = withLeaders(1)
		local player = run.players[1]
		local _, clues = leaderCamp(run)
		local clue = clues[1]
		-- A zone, a clue and a chest on one spot at an entry, where no other
		-- clue stands.
		local entry = Fixtures.entryOf(run)
		clue.x, clue.z = entry.x, entry.z
		local zone = Arc.openZone(run, clue.pointId)
		zone.x, zone.z = entry.x, entry.z
		local chest = Arc.dropChest(run, clue.pointId)
		chest.x, chest.z = entry.x, entry.z
		standAt(run, 1, entry.x, entry.z)
		hold(run, 1)
		Assert.near(player.extractProgress, 1)
		Assert.equal(player.clueProgress, 0)
		Assert.equal(player.chestProgress, 0)
		zone.open = false
		hold(run, run.config.run.arc.clues.readSeconds)
		Assert.equal(player.extractProgress, 0)
		Assert.truthy(clue.read)
		Assert.falsy(chest.opened)
		hold(run, run.config.run.arc.events.chest.openSeconds)
		Assert.truthy(chest.opened)
	end,

	["a chest drop waits until its whole guard fits under the cap"] = function()
		local config = calm()
		config.run.arc.events.chestDrop.firstMinute = 4
		local drop = config.run.arc.events.chestDrop
		config.enemies.maxAlive = 10
		local run = Fixtures.run(1, config, 2)
		local entry = Fixtures.entryOf(run)
		for _ = 1, config.enemies.maxAlive - drop.guardSize + 1 do
			Fixtures.enemy(run, "grunt", entry.x, entry.z)
		end
		tick(run, drop.firstMinute * 60 + 100)
		Assert.equal(#run.chests, 0)
		Assert.equal(#announcements(run, "chestDrop"), 0)
		State.removeEnemy(run, run.enemies[1])
		tick(run, 0.5)
		Assert.equal(#run.chests, 1)
		local guard = State.patrolById(run, run.chests[1].patrolId :: number)
		assert(guard, "no guard")
		Assert.equal(#guard.members, drop.guardSize)
		-- The next one is due an interval after it came, not after its slot.
		Assert.equal(run.nextChestDropAt, run.time + drop.intervalMinutes * 60)
	end,

	["chests drop away from the players, and never twice at one point"] = function()
		for seed = 1, 4 do
			local config = calm()
			config.run.arc.events.chestDrop.firstMinute = 0.5
			config.run.arc.events.chestDrop.intervalMinutes = 0.5
			local run = Fixtures.run(3, config, seed)
			local apart = config.enemies.patrols.minDistanceFromPlayers
			local label = "seed " .. seed
			-- Two players stand at points of their own.
			local placed = 1
			for _, point in run.map.points do
				if not point.isEntry and placed < 3 then
					placed += 1
					Fixtures.place(run, run.players[placed], point.x, point.z)
				end
			end
			local seen: { [number]: boolean } = {}
			for _ = 1, 60 * 30 do
				local before = #run.chests
				tick(run, 1, 1)
				for index = before + 1, #run.chests do
					local chest = run.chests[index]
					local point = run.map.points[chest.pointId]
					Assert.falsy(seen[point.id], label)
					seen[point.id] = true
					for _, player in run.players do
						Assert.truthy(
							Geometry.distance(point.x, point.z, player.x, player.z) >= apart,
							label
						)
					end
					-- Opened at once: an opened chest's point still holds it.
					chest.opened = true
				end
			end
			Assert.truthy(#run.chests > 0, label)
		end
	end,

	-- The wandering boss and the incursion wave.

	["the wandering boss comes once at its minute, multiplied, walking the paths"] = function()
		local config = calm()
		config.run.arc.events.wanderingBoss.minute = 7
		local run = Fixtures.run(2, config, 5)
		local settings = config.run.arc.events.wanderingBoss
		tick(run, settings.minute * 60 - 0.5)
		Assert.equal(#run.enemies, 0)
		tick(run, 0.5)
		Assert.equal(#run.enemies, 1)
		tick(run, 60)
		Assert.equal(#run.enemies, 1)
		local boss = run.enemies[1]
		Assert.truthy(boss.boss)
		Assert.equal(boss.archetype, settings.archetype)
		Assert.near(
			boss.maxHealth,
			config.enemies.archetypes[settings.archetype].health * settings.healthMultiplier
		)
		local patrol = State.patrolById(run, boss.patrolId :: number)
		assert(patrol, "no patrol")
		Assert.falsy(patrol.wanders)
		Assert.equal(#patrol.members, 1)
		-- Bound for a neighbour of the point it came at, along a path.
		local start = run.map.points[patrol.previousPoint]
		Assert.truthy(table.find(start.neighbours, patrol.routePoint) ~= nil)
		local announced = announcements(run, "wanderingBoss")
		Assert.equal(#announced, 1)
		Assert.equal(announced[1].id, boss.id)
	end,

	["the boss lands its attacks multiplied and drops what a leader drops"] = function()
		local config = calm()
		local run = Fixtures.run(1, config)
		local player = run.players[1]
		local point = Fixtures.entryOf(run)
		Fixtures.dry(run, point.x, point.z, 20)
		Fixtures.place(run, player, point.x, point.z)
		local multiplier = config.run.arc.events.wanderingBoss.damageMultiplier
		local hits = {}
		for _, boss in { false, true } do
			run.enemies = {}
			local enemy = Fixtures.enemy(run, "grunt", point.x + 2, point.z)
			enemy.boss = boss
			enemy.state = "chase"
			enemy.target = 1
			player.health = player.maxHealth
			run.events = {}
			for _ = 1, 30 do
				run.time += 0.1
				Enemies.step(run, 0.1)
			end
			local hurt = Assert.findEvent(run.events, "playerHurt")
			Assert.truthy(hurt, "never hit")
			table.insert(hits, hurt.amount)
		end
		Assert.near(hits[2], hits[1] * multiplier)

		-- A boss that is no camp leader still drops a potion.
		local enemy = run.enemies[1]
		run.events = {}
		Combat.damageEnemy(run, enemy, 1, enemy.health, {}, "test")
		Assert.truthy(Assert.findEvent(run.events, "dropped"))
		Assert.equal(#run.pickups, 1)
	end,

	["the boss is hit as far from its centre as its radius multiplied"] = function()
		local config = calm()
		local run = Fixtures.run(1, config)
		local player = run.players[1]
		local point = Fixtures.entryOf(run)
		Fixtures.dry(run, point.x, point.z, 30)
		Fixtures.place(run, player, point.x, point.z)
		local settings = config.run.arc.events.wanderingBoss
		local archetype = config.enemies.archetypes[settings.archetype]
		local nova = config.classes.elementalist.actives[2]
		Assert.equal(nova.shape, "ring")
		-- Beyond the ring's reach for the archetype, within it for the boss.
		local distance = nova.radius + archetype.radius * (1 + settings.radiusMultiplier) / 2
		local boss = Fixtures.enemy(run, settings.archetype, point.x + distance, point.z)
		boss.boss = true
		local plain = Fixtures.enemy(run, settings.archetype, point.x - distance, point.z)
		Assert.near(State.enemyRadius(run, boss), archetype.radius * settings.radiusMultiplier)
		Assert.equal(State.enemyRadius(run, plain), archetype.radius)
		Assert.truthy(Combat.useActive(run, 1, 2))
		local hit: { [number]: boolean } = {}
		for _, event in eventsOf(run, "hit") do
			hit[event.enemyId] = true
		end
		Assert.truthy(hit[boss.id])
		Assert.falsy(hit[plain.id])
	end,

	["the incursion wave grows patrols factor times faster for its seconds"] = function()
		local config = calm()
		config.enemies.patrols.groupsPerMinute = 0.6
		config.enemies.patrols.groupsAtStart = 0
		config.enemies.patrols.wanderersAtStart = 0
		local wave = config.run.arc.events.incursionWave
		local run = Fixtures.run(1, config)
		local function owedOver(seconds: number): number
			local before = run.patrolDebt + #run.patrols
			for _ = 1, seconds do
				run.time += 1
				Arc.update(run, 1)
				Camps.update(run, 1)
			end
			return run.patrolDebt + #run.patrols - before
		end
		-- Steps land on whole seconds: the minute before the wave ends one
		-- step short of it.
		run.time = wave.minute * 60 - 61
		Assert.near(owedOver(60), 0.6)
		Assert.equal(#announcements(run, "incursionWave"), 0)
		Assert.near(owedOver(wave.seconds), 0.6 * wave.factor * wave.seconds / 60)
		Assert.near(owedOver(60), 0.6)
		Assert.equal(#announcements(run, "incursionWave"), 1)
	end,

	-- Determinism.

	["the same seed replays the same arc"] = function()
		local function play(): Types.Run
			local config = Fixtures.config()
			config.player.maxHealth = 1e9
			local run = Run.new(config, 77, 2)
			Run.addPlayer(run, 1)
			Run.addPlayer(run, 2)
			-- Player 1 reads every clue of the first leader as the run goes.
			local _, clues = leaderCamp(run)
			for minute = 1, 14 do
				local clue = clues[minute]
				if clue then
					standAt(run, 1, clue.x, clue.z)
				end
				for _ = 1, 60 * 5 do
					Run.step(run, 0.2, {})
				end
			end
			return run
		end
		local a, b = play(), play()
		Assert.equal(#a.zones, #b.zones)
		Assert.truthy(#a.zones > 0)
		for index, zone in a.zones do
			Assert.equal(zone.pointId, b.zones[index].pointId)
			Assert.equal(zone.open, b.zones[index].open)
			Assert.equal(zone.openedAt, b.zones[index].openedAt)
		end
		Assert.equal(#a.clues, #b.clues)
		for index, clue in a.clues do
			Assert.equal(clue.pointId, b.clues[index].pointId)
			Assert.equal(clue.read, b.clues[index].read)
		end
		for campId, area in a.leaderAreas do
			Assert.equal(area.x, b.leaderAreas[campId].x)
			Assert.equal(area.radius, b.leaderAreas[campId].radius)
		end
		Assert.equal(#a.chests, #b.chests)
		Assert.truthy(#a.chests > 0)
		for index, chest in a.chests do
			Assert.equal(chest.pointId, b.chests[index].pointId)
		end
		Assert.truthy(a.bossSpawned)
		Assert.equal(#a.enemies, #b.enemies)
		for index, enemy in a.enemies do
			Assert.equal(enemy.x, b.enemies[index].x)
			Assert.equal(enemy.boss, b.enemies[index].boss)
		end
		Assert.equal(a.floodHalf, b.floodHalf)
	end,
}
