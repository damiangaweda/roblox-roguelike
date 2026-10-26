--!strict
local Assert = require("./Assert")
local Camps = require("../src/shared/Core/Camps")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Map = require("../src/shared/Core/Map")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- A run of `players` players whose config `tweak` may change first. The alive
-- cap is high enough that it never interferes unless a test lowers it.
local function build(players: number, seed: number, tweak: ((Types.Config) -> ())?): Types.Run
	local config = Fixtures.config()
	config.enemies.maxAlive = 10000
	if tweak then
		tweak(config)
	end
	return Fixtures.run(players, config, seed)
end

local function enemyOf(run: Types.Run, id: number): Types.Enemy
	local enemy = State.enemyById(run, id)
	if enemy == nil then
		error("no enemy " .. id)
	end
	return enemy
end

local function countCamps(run: Types.Run, pointId: number): number
	local count = 0
	for _, camp in run.camps do
		if camp.pointId == pointId then
			count += 1
		end
	end
	return count
end

-- No patrols or wanderers at start and none arriving with time.
local function campsOnly(config: Types.Config)
	config.enemies.patrols.groupsAtStart = 0
	config.enemies.patrols.wanderersAtStart = 0
	config.enemies.patrols.groupsPerMinute = 0
end

local function setCamps(config: Types.Config, leaderChance: number, extra: number)
	for _, level in config.enemies.camps do
		level.leaderChance = leaderChance
		level.extraPerPlayer = extra
		level.healthPerExtraPlayer = 0.4
	end
end

local function spawn(run: Types.Run, size: number, pool: { string }, strength: number): Types.Patrol
	local patrol = Camps.spawnPatrol(run, size, pool, strength)
	if patrol == nil then
		error("no patrol spawned")
	end
	return patrol
end

local function groupTotal(level: Types.CampLevelConfig): number
	local total = 0
	for _, group in level.groups do
		total += group.count
	end
	return total
end

local function countArchetype(run: Types.Run, camp: Types.Camp, archetype: string): number
	local count = 0
	for _, id in camp.members do
		local enemy = enemyOf(run, id)
		if enemy and enemy.archetype == archetype then
			count += 1
		end
	end
	return count
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

local function signature(run: Types.Run): string
	local parts = {}
	for _, enemy in run.enemies do
		table.insert(parts, string.format("%s@%.3f,%.3f", enemy.archetype, enemy.x, enemy.z))
	end
	return table.concat(parts, ";")
end

-- A camp scaling test bed: one camp, nobody near it, no leader.
local function campBed(): (Types.Run, Types.Camp, Types.MapPoint)
	local run = build(4, 3, function(config)
		campsOnly(config)
		setCamps(config, 0, 2)
	end)
	Camps.populate(run)
	local camp = run.camps[1]
	return run, camp, run.map.points[camp.pointId]
end

local function enter(run: Types.Run, playerId: number, point: Types.MapPoint)
	Fixtures.place(run, run.players[playerId], point.x, point.z)
end

-- Removes every member of the camp, as their deaths would.
local function clear(run: Types.Run, camp: Types.Camp)
	for _, id in table.clone(camp.members) do
		State.removeEnemy(run, enemyOf(run, id))
	end
end

-- The run time at which a camp cleared at `clearedAt` returns.
local function returnTime(run: Types.Run, clearedAt: number): number
	return clearedAt + run.config.map.campReturnMinutes * 60
end

return {
	["populate gives every point but the entries one camp, zone points too"] = function()
		for _, seed in { 1, 2, 3 } do
			local run = build(8, seed)
			Camps.populate(run)
			local zonePoints = 0
			for _, point in run.map.points do
				local expected = if point.isEntry then 0 else 1
				Assert.equal(countCamps(run, point.id), expected, "point " .. point.id)
				if point.hasZone then
					zonePoints += 1
				end
			end
			Assert.truthy(zonePoints > 0)
		end
	end,

	["a camp takes its point's level and the level's groups"] = function()
		local run = build(8, 2, campsOnly)
		Camps.populate(run)
		Assert.truthy(#run.camps > 0)
		for _, camp in run.camps do
			local point = run.map.points[camp.pointId]
			local level = run.config.enemies.camps[point.level]
			Assert.equal(camp.level, point.level)
			Assert.equal(camp.x, point.campX :: number)
			Assert.equal(camp.z, point.campZ :: number)
			Assert.equal(camp.scaledFor, 0)
			Assert.falsy(camp.alerted)
			Assert.truthy(camp.returns)
			Assert.equal(camp.strength, 1)
			Assert.equal(camp.clearedAt, nil)
			local counted = #camp.members
			for _, group in level.groups do
				Assert.equal(countArchetype(run, camp, group.archetype) >= group.count, true)
			end
			local leaders = if camp.leaderId then 1 else 0
			Assert.equal(counted, groupTotal(level) + leaders)
		end
	end,

	["camp members are idle, in their camp and on its point's footprint"] = function()
		local run = build(8, 4, campsOnly)
		Camps.populate(run)
		for _, camp in run.camps do
			local point = run.map.points[camp.pointId]
			Assert.truthy(#camp.members > 0)
			for _, id in camp.members do
				local enemy = enemyOf(run, id)
				Assert.equal(enemy.campId, camp.id)
				Assert.equal(enemy.state, "idle")
				Assert.equal(enemy.level, camp.level)
				Assert.truthy(
					Geometry.distance(enemy.x, enemy.z, point.x, point.z) <= point.radius,
					"on the footprint"
				)
				Assert.truthy(Map.walkable(run.map, enemy.x, enemy.z), "on walkable ground")
			end
		end
	end,

	["a leaderChance of one gives every camp a leader, zero none"] = function()
		local sure = build(8, 5, function(config)
			campsOnly(config)
			setCamps(config, 1, 1)
		end)
		Camps.populate(sure)
		for _, camp in sure.camps do
			Assert.truthy(camp.leaderId, "camp " .. camp.id)
			local leader = enemyOf(sure, camp.leaderId :: number)
			Assert.equal(leader.archetype, sure.config.enemies.campLeader)
			Assert.truthy(table.find(camp.members, leader.id))
			Assert.equal(leader.x, camp.x)
		end

		local never = build(8, 5, function(config)
			campsOnly(config)
			setCamps(config, 0, 1)
		end)
		Camps.populate(never)
		for _, camp in never.camps do
			Assert.falsy(camp.leaderId)
			Assert.equal(countArchetype(never, camp, never.config.enemies.campLeader), 0)
		end
	end,

	["the same seed populates the same enemies, another seed differs"] = function()
		local first = build(8, 7)
		local second = build(8, 7)
		local other = build(8, 8)
		Camps.populate(first)
		Camps.populate(second)
		Camps.populate(other)
		Assert.equal(signature(first), signature(second))
		Assert.truthy(signature(first) ~= signature(other))
	end,

	["populate stops at maxAlive"] = function()
		local run = build(8, 1, function(config)
			config.enemies.maxAlive = 12
		end)
		Camps.populate(run)
		Assert.equal(#run.enemies, 12)
		-- Every point still has its camp record, however thin.
		for _, point in run.map.points do
			Assert.equal(countCamps(run, point.id), if point.isEntry then 0 else 1)
		end
	end,

	["before anyone joins, the start patrols keep away from the entries"] = function()
		local config = Fixtures.config()
		config.enemies.maxAlive = 10000
		local patrols = config.enemies.patrols
		patrols.groupsAtStart = 4
		patrols.wanderersAtStart = 4
		for seed = 1, 20 do
			local run = State.newRun(config, seed, 4)
			Assert.equal(#run.players, 0)
			Camps.populate(run)
			for _, patrol in run.patrols do
				local start = run.map.points[patrol.previousPoint]
				for _, id in run.map.entries do
					local entry = run.map.points[id]
					Assert.truthy(
						Geometry.distance(start.x, start.z, entry.x, entry.z)
							>= patrols.minDistanceFromPlayers,
						"seed " .. seed .. ": a start patrol near an entry"
					)
				end
			end
		end
	end,

	["populate spawns the start patrols and wanderers away from the players"] = function()
		local run = build(8, 6, function(config)
			local patrols = config.enemies.patrols
			patrols.groupsAtStart = 3
			patrols.sizeAtStart = 3
			patrols.wanderersAtStart = 2
			patrols.pool = { "spitter" }
			patrols.wandererPool = { "exploder" }
		end)
		local patrols = run.config.enemies.patrols
		Camps.populate(run)
		Assert.equal(#run.patrols, patrols.groupsAtStart + patrols.wanderersAtStart)
		Assert.equal(#eventsOf(run, "patrolSpawned"), #run.patrols)

		local groups, wanderers = 0, 0
		for _, patrol in run.patrols do
			local previous = run.map.points[patrol.previousPoint]
			Assert.truthy(
				table.find(previous.neighbours, patrol.routePoint),
				"route is a neighbour"
			)
			Assert.equal(patrol.strength, 1)
			Assert.falsy(previous.isEntry)
			for _, player in run.players do
				Assert.truthy(
					Geometry.distance(previous.x, previous.z, player.x, player.z)
						>= patrols.minDistanceFromPlayers,
					"near a player"
				)
			end
			local archetype = if #patrol.members == 1 then "exploder" else "spitter"
			Assert.equal(patrol.wanders, #patrol.members == 1)
			if #patrol.members == 1 then
				wanderers += 1
			else
				groups += 1
				Assert.equal(#patrol.members, patrols.sizeAtStart)
			end
			for _, id in patrol.members do
				local enemy = enemyOf(run, id)
				Assert.equal(enemy.state, "patrol")
				Assert.equal(enemy.patrolId, patrol.id)
				Assert.equal(enemy.routePoint, patrol.routePoint)
				Assert.equal(enemy.archetype, archetype)
			end
		end
		Assert.equal(groups, patrols.groupsAtStart)
		Assert.equal(wanderers, patrols.wanderersAtStart)
	end,

	["spawnPatrol scales health by strength and draws from the pool"] = function()
		local run = build(4, 2)
		local patrol = spawn(run, 4, { "brute" }, 1.5)
		Assert.equal(#patrol.members, 4)
		Assert.equal(patrol.strength, 1.5)
		for _, id in patrol.members do
			local enemy = enemyOf(run, id)
			Assert.equal(enemy.archetype, "brute")
			Assert.near(enemy.maxHealth, run.config.enemies.archetypes.brute.health * 1.5)
			Assert.near(enemy.health, enemy.maxHealth)
		end
	end,

	["spawnPatrol falls back to every point but the entries on a small map"] = function()
		local run = build(4, 2, function(config)
			config.enemies.patrols.minDistanceFromPlayers = 1e6
		end)
		local patrol = spawn(run, 2, { "grunt" }, 1)
		Assert.falsy(run.map.points[patrol.previousPoint].isEntry)
		local event = Assert.findEvent(run.events, "patrolSpawned")
		Assert.equal(event.pointId, patrol.previousPoint)
	end,

	["spawnPatrol returns nil at the cap and leaves no record"] = function()
		local run = build(4, 2, function(config)
			config.enemies.maxAlive = 2
		end)
		Fixtures.enemy(run, "grunt", 0, 0)
		Fixtures.enemy(run, "grunt", 0, 0)
		Assert.equal(Camps.spawnPatrol(run, 3, { "grunt" }, 1), nil)
		Assert.equal(#run.patrols, 0)
		Assert.equal(#eventsOf(run, "patrolSpawned"), 0)
	end,

	["patrols arrive at the configured rate over time"] = function()
		local run = build(8, 9, function(config)
			campsOnly(config)
			config.enemies.patrols.groupsPerMinute = 0.6
		end)
		for _ = 1, 600 do
			run.time += 1
			Camps.update(run, 1)
		end
		Assert.truthy(#run.patrols >= 5 and #run.patrols <= 6, "got " .. #run.patrols)
		Assert.near(#run.patrols + run.patrolDebt, 6, 1e-6)
		Assert.equal(#eventsOf(run, "patrolSpawned"), #run.patrols)
	end,

	["a patrol at minute eight is larger, stronger and from the late pool"] = function()
		local run = build(8, 9, function(config)
			campsOnly(config)
			local patrols = config.enemies.patrols
			patrols.pool = { "grunt" }
			patrols.latePool = { "brute" }
			patrols.sizeAtStart = 2
			patrols.sizeGrowthPerMinute = 0.5
			patrols.healthGrowthPerMinute = 0.08
			patrols.lateMinutes = 6
			patrols.maxSize = 8
		end)
		local patrols = run.config.enemies.patrols

		run.patrolDebt = 1
		Camps.update(run, 0)
		local early = run.patrols[1]
		Assert.equal(#early.members, 2)
		Assert.equal(enemyOf(run, early.members[1]).archetype, "grunt")

		run.time = 8 * 60
		run.patrolDebt = 1
		Camps.update(run, 0)
		local late = run.patrols[2]
		Assert.equal(#late.members, 6)
		Assert.near(late.strength, 1 + patrols.healthGrowthPerMinute * 8)
		for _, id in late.members do
			local enemy = enemyOf(run, id)
			Assert.equal(enemy.archetype, "brute")
			Assert.near(enemy.maxHealth, 120 * (1 + patrols.healthGrowthPerMinute * 8), 1e-6)
		end
	end,

	["patrol size stops growing at maxSize"] = function()
		local run = build(8, 9, function(config)
			campsOnly(config)
			config.enemies.patrols.maxSize = 4
		end)
		run.time = 20 * 60
		run.patrolDebt = 1
		Camps.update(run, 0)
		Assert.equal(#run.patrols[1].members, 4)
	end,

	["the patrol debt carries fractions between steps"] = function()
		local run = build(8, 9, function(config)
			campsOnly(config)
			config.enemies.patrols.groupsPerMinute = 60
		end)
		-- One group per second.
		Camps.update(run, 0.5)
		Assert.equal(#run.patrols, 0)
		Assert.near(run.patrolDebt, 0.5)
		Camps.update(run, 0.5)
		Assert.equal(#run.patrols, 1)
		Assert.near(run.patrolDebt, 0)
	end,

	["at the cap the patrol debt keeps only its fraction"] = function()
		local run = build(8, 9, function(config)
			campsOnly(config)
			config.enemies.maxAlive = 3
		end)
		for _ = 1, 3 do
			Fixtures.enemy(run, "grunt", 0, 0)
		end
		run.patrolDebt = 2.5
		Camps.update(run, 0)
		Assert.equal(#run.patrols, 0)
		Assert.near(run.patrolDebt, 0.5)
	end,

	["a camp grows once when its first player arrives and then stays"] = function()
		local run, camp, point = campBed()
		local level = run.config.enemies.camps[camp.level]
		local base = groupTotal(level)
		local archetypes = run.config.enemies.archetypes
		Assert.equal(#camp.members, base)

		Camps.update(run, 0.1)
		Assert.equal(#camp.members, base)
		Assert.equal(camp.scaledFor, 0)

		enter(run, 1, point)
		run.events = {}
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 1)
		Assert.equal(#camp.members, base + level.extraPerPlayer)
		local event = Assert.findEvent(run.events, "campScaled")
		Assert.truthy(event)
		Assert.equal(event.campId, camp.id)
		Assert.equal(event.players, 1)
		for _, id in camp.members do
			local enemy = enemyOf(run, id)
			Assert.equal(enemy.campId, camp.id)
			-- Newcomers match the scaled members.
			Assert.near(enemy.maxHealth, archetypes[enemy.archetype].health * 1.4, 1e-6)
			Assert.equal(enemy.state, "idle")
		end

		run.events = {}
		Camps.update(run, 0.1)
		Assert.equal(#camp.members, base + level.extraPerPlayer)
		Assert.equal(#eventsOf(run, "campScaled"), 0)
	end,

	["a second player adds members and scales the living ones"] = function()
		local run, camp, point = campBed()
		local level = run.config.enemies.camps[camp.level]
		local base = groupTotal(level)
		local archetypes = run.config.enemies.archetypes

		enter(run, 1, point)
		Camps.update(run, 0.1)
		local before: { [number]: number } = {}
		for _, id in camp.members do
			before[id] = enemyOf(run, id).maxHealth
		end
		local damaged = enemyOf(run, camp.members[1])
		damaged.health -= 5
		local healthBefore = damaged.health

		enter(run, 2, point)
		run.events = {}
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		Assert.equal(#camp.members, base + 2 * level.extraPerPlayer)
		for id, maxHealth in before do
			Assert.near(enemyOf(run, id).maxHealth, maxHealth * 1.4, 1e-6)
		end
		Assert.near(damaged.health, healthBefore * 1.4, 1e-6)
		for _, id in camp.members do
			if before[id] == nil then
				local enemy = enemyOf(run, id)
				Assert.near(enemy.maxHealth, archetypes[enemy.archetype].health * 1.4 ^ 2, 1e-6)
			end
		end
		local event = Assert.findEvent(run.events, "campScaled")
		Assert.truthy(event)
		Assert.equal(event.players, 2)
	end,

	["a player leaving does not shrink the camp, a return does not regrow it"] = function()
		local run, camp, point = campBed()
		enter(run, 1, point)
		enter(run, 2, point)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		local size = #camp.members

		local entry = Fixtures.entryOf(run)
		Fixtures.place(run, run.players[2], entry.x, entry.z)
		run.events = {}
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		Assert.equal(#camp.members, size)

		enter(run, 2, point)
		Camps.update(run, 0.1)
		Assert.equal(#camp.members, size)
		Assert.equal(#eventsOf(run, "campScaled"), 0)
	end,

	["downed players do not count toward a camp"] = function()
		local run, camp, point = campBed()
		enter(run, 1, point)
		run.players[1].state = "downed"
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 0)
	end,

	["a camp with no living members does not grow"] = function()
		local run, camp, point = campBed()
		camp.members = {}
		enter(run, 1, point)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 0)
		Assert.equal(#camp.members, 0)
		Assert.equal(#eventsOf(run, "campScaled"), 0)
	end,

	["members added to an alerted camp chase a player in the point"] = function()
		local run, camp, point = campBed()
		camp.alerted = true
		enter(run, 3, point)
		enter(run, 2, point)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		local chasers = 0
		for _, id in camp.members do
			local enemy = enemyOf(run, id)
			if enemy.state == "chase" then
				chasers += 1
				Assert.equal(enemy.target, 2)
			end
		end
		Assert.equal(chasers, 2 * run.config.enemies.camps[camp.level].extraPerPlayer)
	end,

	["camp scaling respects the cap but still strengthens the members"] = function()
		local run, camp, point = campBed()
		run.config.enemies.maxAlive = #run.enemies
		local first = enemyOf(run, camp.members[1])
		local maxHealth = first.maxHealth
		local size = #camp.members
		enter(run, 1, point)
		Camps.update(run, 0.1)
		Assert.equal(#camp.members, size)
		Assert.equal(camp.scaledFor, 1)
		Assert.near(first.maxHealth, maxHealth * 1.4, 1e-6)
	end,

	["a player beside the footprint does not count toward the camp"] = function()
		local run, camp, point = campBed()
		-- Nearest to the camp's point, but off its footprint.
		Fixtures.place(run, run.players[1], point.x + point.radius + 1, point.z)
		Assert.equal(run.players[1].pointId, point.id)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 0)
	end,

	-- Camp return

	["a camp's return clock starts when its last member dies"] = function()
		local run, camp = campBed()
		run.time = 30
		while #camp.members > 1 do
			State.removeEnemy(run, enemyOf(run, camp.members[1]))
		end
		Assert.equal(camp.clearedAt, nil)
		run.time = 40
		State.removeEnemy(run, enemyOf(run, camp.members[1]))
		Assert.equal(camp.clearedAt, 40)
	end,

	["a cleared camp returns after the configured minutes at the patrols' strength"] = function()
		local run, camp, point = campBed()
		local level = run.config.enemies.camps[camp.level]
		local archetypes = run.config.enemies.archetypes
		run.time = 90
		clear(run, camp)
		Assert.equal(camp.clearedAt, 90)

		run.time = returnTime(run, 90) - 0.1
		Camps.update(run, 0)
		Assert.equal(#camp.members, 0)
		Assert.equal(#eventsOf(run, "campReturned"), 0)

		run.time = returnTime(run, 90)
		Camps.update(run, 0)
		Assert.equal(#camp.members, groupTotal(level))
		Assert.equal(camp.clearedAt, nil)
		Assert.equal(camp.scaledFor, 0)
		Assert.falsy(camp.alerted)
		local strength = 1 + run.config.enemies.patrols.healthGrowthPerMinute * run.time / 60
		Assert.near(camp.strength, strength)
		for _, id in camp.members do
			local enemy = enemyOf(run, id)
			Assert.equal(enemy.campId, camp.id)
			Assert.equal(enemy.state, "idle")
			Assert.near(enemy.maxHealth, archetypes[enemy.archetype].health * strength, 1e-6)
			Assert.near(enemy.health, enemy.maxHealth)
			Assert.truthy(
				Geometry.distance(enemy.x, enemy.z, point.x, point.z) <= point.radius,
				"on the footprint"
			)
		end
		local events = eventsOf(run, "campReturned")
		Assert.equal(#events, 1)
		Assert.equal(events[1].campId, camp.id)
		Assert.equal(events[1].pointId, point.id)
	end,

	["a camp returns without its leader"] = function()
		local run = build(4, 3, function(config)
			campsOnly(config)
			setCamps(config, 1, 0)
		end)
		Camps.populate(run)
		local camp = run.camps[1]
		Assert.truthy(camp.leaderId)
		clear(run, camp)
		Assert.equal(camp.leaderId, nil)
		run.time = returnTime(run, 0)
		Camps.update(run, 0)
		Assert.equal(camp.leaderId, nil)
		Assert.equal(countArchetype(run, camp, run.config.enemies.campLeader), 0)
		Assert.equal(#camp.members, groupTotal(run.config.enemies.camps[camp.level]))
	end,

	["a returned camp does not return again until it is cleared again"] = function()
		local run, camp = campBed()
		clear(run, camp)
		run.time = returnTime(run, 0)
		Camps.update(run, 0)
		local size = #camp.members
		Assert.truthy(size > 0)

		-- Alive and long past the delay: nothing more comes.
		run.time = returnTime(run, run.time) * 2
		Camps.update(run, 0)
		Assert.equal(#camp.members, size)
		Assert.equal(#eventsOf(run, "campReturned"), 1)

		-- Cleared again, it returns again after a full delay from then.
		local clearedAt = run.time
		clear(run, camp)
		run.time = returnTime(run, clearedAt) - 0.1
		Camps.update(run, 0)
		Assert.equal(#camp.members, 0)
		run.time = returnTime(run, clearedAt)
		Camps.update(run, 0)
		Assert.equal(#camp.members, size)
		Assert.equal(#eventsOf(run, "campReturned"), 2)
	end,

	["a returned camp grows anew for the players at its point"] = function()
		local run, camp, point = campBed()
		local level = run.config.enemies.camps[camp.level]
		local archetypes = run.config.enemies.archetypes
		enter(run, 1, point)
		Camps.update(run, 0)
		Assert.equal(camp.scaledFor, 1)

		clear(run, camp)
		run.time = returnTime(run, 0)
		run.events = {}
		Camps.update(run, 0)
		Assert.equal(camp.scaledFor, 1)
		Assert.equal(#camp.members, groupTotal(level) + level.extraPerPlayer)
		local scaled = Assert.findEvent(run.events, "campScaled")
		Assert.truthy(scaled)
		Assert.equal(scaled.players, 1)
		-- Every member at the camp's strength, grown for the one player.
		local factor = camp.strength * (1 + level.healthPerExtraPlayer)
		for _, id in camp.members do
			local enemy = enemyOf(run, id)
			Assert.near(enemy.maxHealth, archetypes[enemy.archetype].health * factor, 1e-6)
		end
	end,

	["a camp that does not return stays cleared"] = function()
		local run, camp = campBed()
		camp.returns = false
		clear(run, camp)
		run.time = returnTime(run, 0) * 3
		Camps.update(run, 0)
		Assert.equal(#camp.members, 0)
		Assert.equal(#eventsOf(run, "campReturned"), 0)
	end,

	["near the cap a returning camp waits until all of it fits"] = function()
		local run, camp = campBed()
		local size = groupTotal(run.config.enemies.camps[camp.level])
		Assert.truthy(size > 1)
		clear(run, camp)
		-- Room for all but one of its members.
		run.config.enemies.maxAlive = #run.enemies + size - 1
		run.time = returnTime(run, 0)
		Camps.update(run, 0)
		Assert.equal(#camp.members, 0)
		Assert.equal(camp.clearedAt, 0)
		Assert.equal(#eventsOf(run, "campReturned"), 0)

		run.config.enemies.maxAlive = #run.enemies + size
		Camps.update(run, 0)
		Assert.equal(#camp.members, size)
		Assert.equal(camp.clearedAt, nil)
		Assert.equal(#eventsOf(run, "campReturned"), 1)
	end,

	["patrols spawn at points the configured distance from every alive player"] = function()
		local run = build(4, 5, function(config)
			config.enemies.patrols.minDistanceFromPlayers = 100
		end)
		local minDistance = run.config.enemies.patrols.minDistanceFromPlayers
		-- Spread the players over the map, one of them downed, which does not count.
		local ids = Map.farthestPoints(run.map, 3)
		for index, id in ids do
			local point = run.map.points[id]
			Fixtures.place(run, run.players[index], point.x, point.z)
		end
		local downed = run.players[4]
		downed.state = "downed"
		Fixtures.place(run, downed, run.map.points[ids[1]].x + 150, 0)
		local sawNearDowned = false
		for _ = 1, 200 do
			local patrol = spawn(run, 1, { "grunt" }, 1)
			local start = run.map.points[patrol.previousPoint]
			for index = 1, 3 do
				local player = run.players[index]
				Assert.truthy(
					Geometry.distance(start.x, start.z, player.x, player.z) >= minDistance,
					"patrol at point " .. start.id .. " near player " .. index
				)
			end
			if Geometry.distance(start.x, start.z, downed.x, downed.z) < minDistance then
				sawNearDowned = true
			end
			clear(run, ({ members = patrol.members } :: any) :: Types.Camp)
		end
		Assert.truthy(sawNearDowned, "no patrol near the downed player; the check proves nothing")
	end,
}
