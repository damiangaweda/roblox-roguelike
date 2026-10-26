--!strict
local Assert = require("./Assert")
local Enemies = require("../src/shared/Core/Enemies")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")
local World = require("../src/shared/Core/World")

local DT = 0.1

-- Advances the clock by `dt`, then the enemies.
local function tick(run: Types.Run, dt: number?)
	local step = dt or DT
	run.time += step
	Enemies.step(run, step)
end

-- A run with `playerCount` players. Player 1 stands in the centre of its start
-- room, and `room` is that room; every room is at least 28 studs across, so
-- offsets of up to 12 studs from the centre stay inside it.
local function arena(playerCount: number?): (Types.Run, Types.Room, Types.Player)
	local run = Fixtures.run(playerCount or 1)
	local player = run.players[1]
	local room = Fixtures.roomOf(run, player)
	Fixtures.place(run, player, room.x, room.z)
	return run, room, player
end

-- An enemy chasing player 1.
local function chaser(run: Types.Run, archetype: string, x: number, z: number): Types.Enemy
	local enemy = Fixtures.enemy(run, archetype, x, z)
	enemy.state = "chase"
	enemy.target = 1
	return enemy
end

local function addCamp(run: Types.Run, room: Types.Room, members: { Types.Enemy }): Types.Camp
	local ids = {}
	for _, member in members do
		table.insert(ids, member.id)
	end
	local camp: Types.Camp = {
		id = #run.camps + 1,
		roomId = room.id,
		x = room.x,
		z = room.z,
		level = 1,
		members = ids,
		alerted = false,
		scaledFor = 1,
	}
	for _, member in members do
		member.campId = camp.id
	end
	table.insert(run.camps, camp)
	return camp
end

local function countEvents(run: Types.Run, kind: string): number
	local count = 0
	for _, event in run.events do
		if event.kind == kind then
			count += 1
		end
	end
	return count
end

-- Starts a telegraph for an enemy that already has `target` in range, checks
-- that the attack lands exactly when its time comes, and returns the time.
local function windUp(run: Types.Run, enemy: Types.Enemy, landed: () -> boolean): number
	local archetype = State.archetype(run, enemy)
	local attack = archetype.attacks[enemy.attack]
	local start = run.time
	tick(run, 0)
	Assert.equal(enemy.state, "telegraph")
	Assert.near(enemy.stateUntil, start + attack.telegraphSeconds)
	local event = Assert.findEvent(run.events, "telegraph")
	Assert.truthy(event, "no telegraph event")
	Assert.equal(event.enemyId, enemy.id)
	Assert.near(event.seconds, attack.telegraphSeconds)
	Assert.falsy(landed(), "landed during the wind-up")

	run.time = enemy.stateUntil - 0.01
	Enemies.step(run, 0)
	Assert.equal(enemy.state, "telegraph")
	Assert.falsy(landed(), "landed early")

	run.time = enemy.stateUntil
	Enemies.step(run, 0)
	Assert.truthy(landed(), "did not land on time")
	return run.time
end

local function expectRecovery(run: Types.Run, enemy: Types.Enemy, landedAt: number)
	local attack = State.archetype(run, enemy).attacks[1]
	Assert.near(enemy.attackReadyAt, landedAt + attack.cooldownSeconds)
	Assert.equal(enemy.state, "recover")
	Assert.near(enemy.stateUntil, landedAt + attack.recoverSeconds)
end

return {
	["a grunt notices a player only within its detection range"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.detectionRange = 10
		local grunt = Fixtures.enemy(run, "grunt", room.x - 8, room.z)
		Fixtures.place(run, player, room.x + 3, room.z)
		Assert.falsy(Enemies.detects(run, grunt, player), "11 studs away")
		tick(run)
		Assert.equal(grunt.state, "idle")
		Assert.equal(grunt.target, nil)

		Fixtures.place(run, player, room.x + 1, room.z)
		Assert.truthy(Enemies.detects(run, grunt, player), "9 studs away")
		tick(run)
		Assert.equal(grunt.state, "chase")
		Assert.equal(grunt.target, 1)
	end,

	["a player in cover is noticed only at half the range"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.detectionRange = 10
		local grunt = Fixtures.enemy(run, "grunt", room.x - 8, room.z)
		Fixtures.place(run, player, room.x - 1, room.z)
		Assert.truthy(Enemies.detects(run, grunt, player))
		player.inCover = true
		Assert.falsy(Enemies.detects(run, grunt, player), "7 studs, range 5")
		Fixtures.place(run, player, room.x - 4, room.z)
		Assert.truthy(Enemies.detects(run, grunt, player), "4 studs, range 5")
	end,

	["a player in another room is not noticed, nor a downed one"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.detectionRange = 500
		local grunt = Fixtures.enemy(run, "grunt", room.x - 8, room.z)
		local other = run.world.rooms[room.neighbours[1]]
		Fixtures.place(run, player, other.x, other.z)
		Assert.falsy(Enemies.detects(run, grunt, player))
		Fixtures.place(run, player, room.x, room.z)
		Assert.truthy(Enemies.detects(run, grunt, player))
		player.state = "downed"
		Assert.falsy(Enemies.detects(run, grunt, player))
	end,

	["one camp member noticing wakes the idle others once"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.detectionRange = 10
		Fixtures.place(run, player, room.x - 8, room.z)
		local near = Fixtures.enemy(run, "grunt", room.x - 3, room.z)
		local farA = Fixtures.enemy(run, "grunt", room.x + 8, room.z + 8)
		local farB = Fixtures.enemy(run, "grunt", room.x + 8, room.z - 8)
		local camp = addCamp(run, room, { near, farA, farB })

		tick(run)
		Assert.equal(near.state, "chase")
		Assert.equal(farA.state, "chase")
		Assert.equal(farB.state, "chase")
		Assert.equal(farA.target, 1)
		Assert.equal(farB.target, 1)
		Assert.truthy(camp.alerted)
		Assert.equal(countEvents(run, "campAlerted"), 1)

		tick(run)
		Assert.equal(countEvents(run, "campAlerted"), 1)
	end,

	["without campAlerts the others stay idle"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.detectionRange = 10
		run.config.enemies.campAlerts = false
		Fixtures.place(run, player, room.x - 8, room.z)
		local near = Fixtures.enemy(run, "grunt", room.x - 3, room.z)
		local far = Fixtures.enemy(run, "grunt", room.x + 8, room.z + 8)
		addCamp(run, room, { near, far })
		tick(run)
		Assert.equal(near.state, "chase")
		Assert.equal(far.state, "idle")
		Assert.equal(countEvents(run, "campAlerted"), 0)
	end,

	["a chase past the leash ends in a walk home and a full heal"] = function()
		local run, room, player = arena()
		local config = run.config.enemies
		config.archetypes.grunt.leash = 6
		config.archetypes.grunt.detectionRange = 10
		config.returnHealFraction = 1
		Fixtures.place(run, player, room.x + 10, room.z)
		local grunt = chaser(run, "grunt", room.x - 10, room.z)
		grunt.health = 10

		local steps = 0
		while grunt.state == "chase" and steps < 50 do
			tick(run)
			steps += 1
		end
		Assert.equal(grunt.state, "return")
		Assert.equal(grunt.target, nil)
		Assert.truthy(Geometry.distance(grunt.x, grunt.z, grunt.homeX, grunt.homeZ) > 6)

		-- A player right beside it is ignored on the way home.
		Fixtures.place(run, player, grunt.x + 2, grunt.z)
		tick(run)
		Assert.equal(grunt.state, "return")
		Fixtures.place(run, player, room.x + 10, room.z)

		steps = 0
		while grunt.state == "return" and steps < 100 do
			tick(run)
			steps += 1
		end
		Assert.equal(grunt.state, "idle")
		Assert.truthy(
			Geometry.distance(grunt.x, grunt.z, grunt.homeX, grunt.homeZ) <= config.arriveDistance
		)
		Assert.equal(grunt.health, grunt.maxHealth)
	end,

	["a chase through a corridor follows the world's graph"] = function()
		local run, room, player = arena()
		run.config.enemies.archetypes.grunt.leash = 1000
		run.config.enemies.archetypes.grunt.detectionRange = 1000
		local other = run.world.rooms[room.neighbours[1]]
		local grunt = chaser(run, "grunt", room.x, room.z)
		Fixtures.place(run, player, other.x, other.z)
		local before = Geometry.distance(grunt.x, grunt.z, player.x, player.z)
		for _ = 1, 100 do
			tick(run)
			local location = World.locate(run.world, grunt.x, grunt.z)
			Assert.truthy(location.kind ~= "outside", "walked out of the world")
		end
		Assert.truthy(Geometry.distance(grunt.x, grunt.z, player.x, player.z) < before - 50)
	end,

	["a grunt's swing lands when its telegraph ends"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2.8, room.z)
		local grunt = chaser(run, "grunt", room.x - 6, room.z)
		local landedAt = windUp(run, grunt, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		Assert.equal(player.health, player.maxHealth - 8)
		expectRecovery(run, grunt, landedAt)
		Assert.equal(grunt.attack, 1)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.near(event.x, grunt.x)
		Assert.near(event.radius, 4)
	end,

	["a recovering enemy goes back to chasing"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2.8, room.z)
		local grunt = chaser(run, "grunt", room.x - 6, room.z)
		windUp(run, grunt, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		run.time = grunt.stateUntil - 0.01
		Enemies.step(run, 0)
		Assert.equal(grunt.state, "recover")
		run.time = grunt.stateUntil
		Enemies.step(run, 0)
		Assert.equal(grunt.state, "chase")
		Assert.equal(grunt.target, 1)
	end,

	["a brute hits in front, not behind, and knocks back"] = function()
		local run, room, front = arena(2)
		local behind = run.players[2]
		Fixtures.place(run, front, room.x - 2, room.z)
		Fixtures.place(run, behind, room.x - 10, room.z)
		local brute = chaser(run, "brute", room.x - 6, room.z)
		windUp(run, brute, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		Assert.equal(brute.facing, 0)
		Assert.equal(front.health, front.maxHealth - 25)
		Assert.equal(behind.health, behind.maxHealth)
		Assert.truthy(front.knockX > 0)
		Assert.near(front.knockZ, 0)
		local knocked = Assert.findEvent(run.events, "knocked")
		Assert.truthy(knocked)
		Assert.equal(knocked.player, front.id)
		Assert.near(knocked.dx, 12)
	end,

	["a shieldbearer swings with its own telegraph"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2.5, room.z)
		local shield = chaser(run, "shieldbearer", room.x - 6, room.z)
		local landedAt = windUp(run, shield, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		Assert.equal(player.health, player.maxHealth - 12)
		expectRecovery(run, shield, landedAt)
	end,

	["a buffed enemy hits harder"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2.8, room.z)
		local grunt = chaser(run, "grunt", room.x - 6, room.z)
		grunt.buffedUntil = 100
		windUp(run, grunt, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		Assert.near(player.health, player.maxHealth - 8 * run.config.enemies.buffDamageFactor)
	end,

	["a spitter backs away when the player is too close"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x + 2, room.z)
		local spitter = chaser(run, "spitter", room.x - 6, room.z)
		spitter.attackReadyAt = 1e9
		tick(run)
		Assert.near(spitter.x, room.x - 6 - 11 * DT)
		Assert.near(spitter.facing, 0)
		Assert.equal(spitter.state, "chase")
	end,

	["a spitter fires at the locked aim"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x + 4, room.z)
		local spitter = chaser(run, "spitter", room.x - 8, room.z)
		local landedAt = windUp(run, spitter, function()
			return #run.projectiles > 0
		end)
		expectRecovery(run, spitter, landedAt)
		Assert.equal(#run.projectiles, 1)
		local shot = run.projectiles[1]
		Assert.equal(shot.owner, "enemy")
		Assert.equal(shot.source, spitter.id)
		Assert.equal(shot.kind, "spitter")
		Assert.near(shot.dirX, 1)
		Assert.near(shot.dirZ, 0)
		Assert.equal(shot.speed, 32)
		Assert.equal(shot.damage, 12)
		Assert.near(shot.remaining, 28 * 1.5)
		Assert.equal(run.nextProjectileId, 2)
		Assert.truthy(Assert.findEvent(run.events, "enemyAttack"))
		-- Hurts nobody on its own: the projectile module moves and lands it.
		Assert.equal(player.health, player.maxHealth)
	end,

	["a telegraphed projectile is aimed where the player was"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x + 4, room.z)
		local spitter = chaser(run, "spitter", room.x - 8, room.z)
		tick(run, 0)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.near(event.x, room.x + 4)
		Assert.near(event.z, room.z)
		Assert.equal(event.radius, 1)
		Fixtures.place(run, player, room.x - 8, room.z + 8)
		run.time = spitter.stateUntil
		Enemies.step(run, 0)
		Assert.near(run.projectiles[1].dirX, 1)
		Assert.near(run.projectiles[1].dirZ, 0)
	end,

	["an exploder runs in, telegraphs and bursts"] = function()
		local run, room, player = arena(2)
		local bystander = run.players[2]
		Fixtures.place(run, player, room.x + 2, room.z)
		Fixtures.place(run, bystander, room.x + 11, room.z)
		local exploder = chaser(run, "exploder", room.x - 8, room.z)
		tick(run)
		Assert.near(exploder.x, room.x - 8 + 16 * DT)
		Assert.equal(exploder.state, "chase")

		exploder.x = room.x - 1.5
		windUp(run, exploder, function()
			return Assert.findEvent(run.events, "exploded") ~= nil
		end)
		Assert.equal(State.enemyById(run, exploder.id), nil)
		Assert.equal(#run.enemies, 0)
		Assert.equal(player.health, player.maxHealth - 35)
		Assert.equal(bystander.health, bystander.maxHealth)
		Assert.falsy(Assert.findEvent(run.events, "kill"))
		local exploded = Assert.findEvent(run.events, "exploded")
		Assert.equal(exploded.radius, 7)
		Assert.near(exploded.x, room.x - 1.5)
	end,

	["a shaman heals and buffs a hurt member in radius only"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x, room.z + 8)
		local shaman = chaser(run, "shaman", room.x - 10, room.z - 10)
		local near = Fixtures.enemy(run, "grunt", room.x, room.z)
		local far = Fixtures.enemy(run, "grunt", room.x + 10, room.z + 10)
		addCamp(run, room, { shaman, near, far })
		near.health = 5
		far.health = 5
		local landedAt = windUp(run, shaman, function()
			return Assert.findEvent(run.events, "healed") ~= nil
		end)
		expectRecovery(run, shaman, landedAt)
		Assert.equal(near.health, 25)
		Assert.near(near.buffedUntil, landedAt + 4)
		Assert.equal(far.health, 5)
		Assert.equal(far.buffedUntil, 0)
		-- The shaman is one of its camp's members.
		Assert.near(shaman.buffedUntil, landedAt + 4)
		local telegraph = Assert.findEvent(run.events, "telegraph")
		Assert.equal(telegraph.radius, 18)
		for _, event in run.events do
			if event.kind == "healed" then
				Assert.equal(event.by, shaman.id)
			end
		end
	end,

	["a shaman with nothing to heal keeps its distance and does not attack"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x, room.z + 8)
		local shaman = chaser(run, "shaman", room.x - 4, room.z - 4)
		local friend = Fixtures.enemy(run, "grunt", room.x, room.z)
		addCamp(run, room, { shaman, friend })
		local distance = Geometry.distance(shaman.x, shaman.z, player.x, player.z)
		Assert.truthy(distance < 16)
		tick(run)
		Assert.equal(shaman.state, "chase")
		Assert.falsy(Assert.findEvent(run.events, "telegraph"))
		Assert.truthy(Geometry.distance(shaman.x, shaman.z, player.x, player.z) > distance)
	end,

	["a buffed enemy moves faster"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x + 10, room.z)
		local plain = chaser(run, "grunt", room.x - 10, room.z - 8)
		local buffed = chaser(run, "grunt", room.x - 10, room.z + 8)
		buffed.buffedUntil = 100
		tick(run)
		local speed = run.config.enemies.archetypes.grunt.speed
		Assert.near(Geometry.distance(plain.x, plain.z, room.x - 10, room.z - 8), speed * DT, 1e-3)
		Assert.near(
			Geometry.distance(buffed.x, buffed.z, room.x - 10, room.z + 8),
			speed * DT * run.config.enemies.buffSpeedFactor,
			1e-3
		)
	end,

	["chill slows movement"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x + 10, room.z)
		local plain = chaser(run, "grunt", room.x - 10, room.z - 8)
		local chilled = chaser(run, "grunt", room.x - 10, room.z + 8)
		chilled.chilledUntil = 100
		tick(run)
		local plainMoved = plain.x - (room.x - 10)
		local chilledMoved = chilled.x - (room.x - 10)
		Assert.near(chilledMoved, plainMoved * (1 - run.config.statuses.chillSlow), 1e-3)
	end,

	["a camp leader alternates its two attacks"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2, room.z)
		local leader = chaser(run, "campLeader", room.x - 8, room.z)
		Assert.equal(leader.attack, 1)

		local landedAt = windUp(run, leader, function()
			return Assert.findEvent(run.events, "enemyAttack") ~= nil
		end)
		Assert.equal(player.health, player.maxHealth - 30)
		Assert.equal(leader.attack, 2)
		Assert.equal(#run.projectiles, 0)
		Assert.near(leader.attackReadyAt, landedAt + 3)

		run.time = leader.stateUntil
		Enemies.step(run, 0)
		Assert.equal(leader.state, "chase")
		run.time = leader.attackReadyAt
		run.events = {}
		local second = windUp(run, leader, function()
			return #run.projectiles > 0
		end)
		Assert.equal(#run.projectiles, 3)
		Assert.equal(leader.attack, 1)
		Assert.near(leader.attackReadyAt, second + 3)
		-- A fan: the middle shot flies straight, the outer two 20 degrees off.
		Assert.near(run.projectiles[2].dirZ, 0)
		Assert.near(run.projectiles[1].dirZ, -math.sin(math.rad(20)), 1e-6)
		Assert.near(run.projectiles[3].dirZ, math.sin(math.rad(20)), 1e-6)
		Assert.equal(run.projectiles[1].id + 2, run.projectiles[3].id)
	end,

	["knockback moves an enemy and suspends its behaviour"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 10, room.z)
		local grunt = chaser(run, "grunt", room.x, room.z)
		grunt.knockX, grunt.knockZ = 20, 0
		grunt.knockUntil = run.time + 0.25
		tick(run)
		Assert.near(grunt.x, room.x + 2)
		Assert.equal(grunt.state, "chase")
		tick(run)
		Assert.near(grunt.x, room.x + 4)

		-- The last step covers what is left of the push; then it chases again,
		-- toward the player.
		tick(run)
		Assert.near(grunt.x, room.x + 5)
		tick(run)
		Assert.truthy(grunt.x < room.x + 5)
	end,

	["a knocked enemy's telegraph still lands"] = function()
		local run, room, player = arena()
		Fixtures.place(run, player, room.x - 2.8, room.z)
		local grunt = chaser(run, "grunt", room.x - 6, room.z)
		tick(run, 0)
		Assert.equal(grunt.state, "telegraph")
		grunt.knockX, grunt.knockZ = 1, 0
		grunt.knockUntil = run.time + 10
		run.time = grunt.stateUntil
		Enemies.step(run, 0)
		Assert.truthy(Assert.findEvent(run.events, "enemyAttack"))
		Assert.equal(grunt.state, "recover")
	end,

	["knockback stops at a wall"] = function()
		local run, room = arena()
		local grunt = chaser(run, "grunt", room.x + room.halfWidth - 1, room.z + room.halfDepth - 2)
		grunt.knockX, grunt.knockZ = 100, 100
		grunt.knockUntil = run.time + 1
		tick(run)
		Assert.near(grunt.x, room.x + room.halfWidth)
		Assert.near(grunt.z, room.z + room.halfDepth)
	end,

	["enemies on one spot are pushed apart and kept in the world"] = function()
		local run, room = arena()
		local a = Fixtures.enemy(run, "grunt", room.x - room.halfWidth, room.z - room.halfDepth)
		local b = Fixtures.enemy(run, "grunt", a.x, a.z)
		tick(run)
		Assert.truthy(Geometry.distance(a.x, a.z, b.x, b.z) > 0)
		Assert.truthy(a.x >= room.x - room.halfWidth)
		Assert.truthy(b.z >= room.z - room.halfDepth)
		Assert.truthy(Geometry.distance(a.x, a.z, b.x, b.z) <= run.config.enemies.separationRadius)
	end,

	["a patrol walks its route, notices a player, and returns to patrolling"] = function()
		local run, _, player = arena()
		local start = Fixtures.roomOf(run, player)
		local room = run.world.rooms[start.neighbours[1]]
		local lead = Fixtures.enemy(run, "grunt", room.x - 12, room.z)
		local follower = Fixtures.enemy(run, "grunt", room.x - 12, room.z + 6)
		local patrol: Types.Patrol = {
			id = 1,
			members = { lead.id, follower.id },
			routeRoom = room.id,
			previousRoom = start.id,
			strength = 1,
		}
		table.insert(run.patrols, patrol)
		for _, member in { lead, follower } do
			member.patrolId = patrol.id
			member.state = "patrol"
			member.routeRoom = room.id
		end

		tick(run)
		Assert.equal(patrol.routeRoom, room.id)
		Assert.near(lead.x, room.x - 12 + 13 * DT, 1e-3)
		Assert.near(lead.facing, 0)

		local steps = 0
		while patrol.routeRoom == room.id and steps < 200 do
			tick(run)
			steps += 1
		end
		Assert.equal(patrol.previousRoom, room.id)
		Assert.truthy(table.find(room.neighbours, patrol.routeRoom), "not a neighbour")
		if #room.neighbours > 1 then
			Assert.truthy(patrol.routeRoom ~= start.id, "went back where it came from")
		end
		Assert.equal(lead.state, "patrol")

		-- Back to a known spot, then a player walks in.
		lead.x, lead.z = room.x - 12, room.z
		follower.x, follower.z = room.x - 12, room.z + 6
		patrol.routeRoom = room.id
		Fixtures.place(run, player, room.x + 10, room.z)
		tick(run)
		Assert.equal(lead.state, "chase")
		Assert.equal(lead.target, 1)
		Assert.near(lead.homeX, room.x - 12)
		Assert.near(lead.homeZ, room.z)

		for _ = 1, 3 do
			tick(run)
		end
		lead.health = 1
		player.state = "dead"
		steps = 0
		while lead.state ~= "patrol" and steps < 200 do
			tick(run)
			steps += 1
		end
		Assert.equal(lead.state, "patrol")
		Assert.equal(lead.target, nil)
		Assert.equal(lead.health, lead.maxHealth)
	end,
}
