--!strict
local Assert = require("./Assert")
local Camps = require("../src/shared/Core/Camps")
local Fixtures = require("./Fixtures")
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

local function countCamps(run: Types.Run, roomId: number): number
	local count = 0
	for _, camp in run.camps do
		if camp.roomId == roomId then
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
local function campBed(): (Types.Run, Types.Camp, Types.Room)
	local run = build(4, 3, function(config)
		campsOnly(config)
		setCamps(config, 0, 2)
	end)
	Camps.populate(run)
	local camp = run.camps[1]
	return run, camp, run.world.rooms[camp.roomId]
end

local function enter(run: Types.Run, playerId: number, room: Types.Room)
	Fixtures.place(run, run.players[playerId], room.x, room.z)
end

return {
	["populate gives every non-start room one camp and no zone room one"] = function()
		for _, seed in { 1, 2, 3 } do
			local run = build(8, seed)
			Camps.populate(run)
			for _, room in run.world.rooms do
				local expected = if room.isStart or room.hasZone then 0 else 1
				Assert.equal(countCamps(run, room.id), expected, "room " .. room.id)
			end
		end
	end,

	["campsInZoneRooms puts a camp in zone rooms too"] = function()
		local run = build(8, 1, function(config)
			config.world.campsInZoneRooms = true
		end)
		Camps.populate(run)
		local zoneRooms = 0
		for _, room in run.world.rooms do
			Assert.equal(countCamps(run, room.id), if room.isStart then 0 else 1)
			if room.hasZone then
				zoneRooms += 1
			end
		end
		Assert.truthy(zoneRooms > 0)
	end,

	["a camp takes its room's level and the level's groups"] = function()
		local run = build(8, 2, campsOnly)
		Camps.populate(run)
		Assert.truthy(#run.camps > 0)
		for _, camp in run.camps do
			local room = run.world.rooms[camp.roomId]
			local level = run.config.enemies.camps[room.level]
			Assert.equal(camp.level, room.level)
			Assert.equal(camp.x, room.campX)
			Assert.equal(camp.z, room.campZ)
			Assert.equal(camp.scaledFor, 0)
			Assert.falsy(camp.alerted)
			local counted = #camp.members
			for _, group in level.groups do
				Assert.equal(countArchetype(run, camp, group.archetype) >= group.count, true)
			end
			local leaders = if camp.leaderId then 1 else 0
			Assert.equal(counted, groupTotal(level) + leaders)
		end
	end,

	["camp members are idle, in their camp and inside the room"] = function()
		local run = build(8, 4, campsOnly)
		Camps.populate(run)
		for _, camp in run.camps do
			local room = run.world.rooms[camp.roomId]
			Assert.truthy(#camp.members > 0)
			for _, id in camp.members do
				local enemy = enemyOf(run, id)
				Assert.equal(enemy.campId, camp.id)
				Assert.equal(enemy.state, "idle")
				Assert.equal(enemy.level, camp.level)
				Assert.truthy(math.abs(enemy.x - room.x) <= room.halfWidth, "x in room")
				Assert.truthy(math.abs(enemy.z - room.z) <= room.halfDepth, "z in room")
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
		-- Every room still has its camp record, however thin.
		for _, room in run.world.rooms do
			Assert.equal(countCamps(run, room.id), if room.isStart or room.hasZone then 0 else 1)
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
			local previous = run.world.rooms[patrol.previousRoom]
			Assert.truthy(table.find(previous.neighbours, patrol.routeRoom), "route is a neighbour")
			Assert.equal(patrol.strength, 1)
			Assert.falsy(previous.isStart)
			for _, player in run.players do
				local playerRoom = Fixtures.roomOf(run, player)
				Assert.truthy(
					run.world.hops[previous.id][playerRoom.id] >= patrols.minHopsFromPlayers,
					"far from the players"
				)
			end
			local archetype = if #patrol.members == 1 then "exploder" else "spitter"
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
				Assert.equal(enemy.routeRoom, patrol.routeRoom)
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

	["spawnPatrol falls back to every non-start room in a small world"] = function()
		local run = build(4, 2, function(config)
			config.enemies.patrols.minHopsFromPlayers = 1000
		end)
		local patrol = spawn(run, 2, { "grunt" }, 1)
		Assert.falsy(run.world.rooms[patrol.previousRoom].isStart)
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
		local run, camp, room = campBed()
		local level = run.config.enemies.camps[camp.level]
		local base = groupTotal(level)
		local archetypes = run.config.enemies.archetypes
		Assert.equal(#camp.members, base)

		Camps.update(run, 0.1)
		Assert.equal(#camp.members, base)
		Assert.equal(camp.scaledFor, 0)

		enter(run, 1, room)
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
		local run, camp, room = campBed()
		local level = run.config.enemies.camps[camp.level]
		local base = groupTotal(level)
		local archetypes = run.config.enemies.archetypes

		enter(run, 1, room)
		Camps.update(run, 0.1)
		local before: { [number]: number } = {}
		for _, id in camp.members do
			before[id] = enemyOf(run, id).maxHealth
		end
		local damaged = enemyOf(run, camp.members[1])
		damaged.health -= 5
		local healthBefore = damaged.health

		enter(run, 2, room)
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
		local run, camp, room = campBed()
		enter(run, 1, room)
		enter(run, 2, room)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		local size = #camp.members

		Fixtures.place(run, run.players[2], run.world.rooms[run.world.startRooms[1]].x, 0)
		run.players[2].roomId = nil
		run.events = {}
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 2)
		Assert.equal(#camp.members, size)

		enter(run, 2, room)
		Camps.update(run, 0.1)
		Assert.equal(#camp.members, size)
		Assert.equal(#eventsOf(run, "campScaled"), 0)
	end,

	["downed players do not count toward a camp"] = function()
		local run, camp, room = campBed()
		enter(run, 1, room)
		run.players[1].state = "downed"
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 0)
	end,

	["a camp with no living members does not grow"] = function()
		local run, camp, room = campBed()
		camp.members = {}
		enter(run, 1, room)
		Camps.update(run, 0.1)
		Assert.equal(camp.scaledFor, 0)
		Assert.equal(#camp.members, 0)
		Assert.equal(#eventsOf(run, "campScaled"), 0)
	end,

	["members added to an alerted camp chase a player in the room"] = function()
		local run, camp, room = campBed()
		camp.alerted = true
		enter(run, 3, room)
		enter(run, 2, room)
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
		local run, camp, room = campBed()
		run.config.enemies.maxAlive = #run.enemies
		local first = enemyOf(run, camp.members[1])
		local maxHealth = first.maxHealth
		local size = #camp.members
		enter(run, 1, room)
		Camps.update(run, 0.1)
		Assert.equal(#camp.members, size)
		Assert.equal(camp.scaledFor, 1)
		Assert.near(first.maxHealth, maxHealth * 1.4, 1e-6)
	end,
}
