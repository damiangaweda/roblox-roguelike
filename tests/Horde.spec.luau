--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Horde = require("../src/shared/Core/Horde")
local Types = require("../src/shared/Core/Types")

local function distance(a: { x: number, z: number }, b: { x: number, z: number }): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- Spawns for `seconds` of run time in steps of `dt`, advancing the clock.
local function spawnFor(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.floor(seconds / dt + 0.5) do
		run.time += dt
		Horde.spawn(run, dt)
	end
end

return {
	["spawn rate at the start matches the config"] = function()
		local run = Fixtures.run(1)
		Horde.spawn(run, 4)
		Assert.equal(#run.enemies, 6)
		Assert.near(run.spawnDebt, 0)
	end,

	["spawn rate grows with time"] = function()
		local early = Fixtures.run(1)
		Horde.spawn(early, 10)
		local late = Fixtures.run(1)
		late.time = 600
		Horde.spawn(late, 10)
		-- 1.5/s at the start, 1.5 + 0.6 * 10 = 7.5/s at minute 10.
		Assert.equal(#early.enemies, 15)
		Assert.equal(#late.enemies, 75)
	end,

	["spawn debt carries the fraction between steps"] = function()
		local run = Fixtures.run(1)
		for _ = 1, 10 do
			Horde.spawn(run, 0.1)
		end
		Assert.equal(#run.enemies, 1)
		Assert.near(run.spawnDebt, 0.5, 1e-9)
	end,

	["maxAlive caps the horde"] = function()
		local run = Fixtures.run(1)
		run.config.horde.maxAlive = 10
		Horde.spawn(run, 100)
		Assert.equal(#run.enemies, 10)
		Assert.truthy(run.spawnDebt < 1, "debt must be below 1")
	end,

	["a freed slot does not release a burst"] = function()
		local run = Fixtures.run(1)
		run.config.horde.maxAlive = 10
		Horde.spawn(run, 100)
		table.remove(run.enemies)
		Horde.spawn(run, 0)
		Assert.equal(#run.enemies, 9)
	end,

	["no spawn without an alive player"] = function()
		local run = Fixtures.run(2)
		run.players[1].state = "downed"
		run.players[2].state = "dead"
		run.spawnDebt = 0.5
		Horde.spawn(run, 10)
		Assert.equal(#run.enemies, 0)
		Assert.equal(run.spawnDebt, 0)
	end,

	["no spawn in an empty run"] = function()
		local run = Fixtures.run(0)
		Horde.spawn(run, 10)
		Assert.equal(#run.enemies, 0)
	end,

	["spawned enemies are fresh and numbered"] = function()
		local run = Fixtures.run(1)
		Horde.spawn(run, 3)
		Assert.equal(#run.enemies, 4)
		Assert.equal(run.nextEnemyId, 5)
		for index, enemy in run.enemies do
			Assert.equal(enemy.id, index)
			Assert.equal(enemy.health, run.config.horde.kinds[enemy.kind].health)
			Assert.equal(enemy.chilledUntil, 0)
			Assert.equal(enemy.burningUntil, 0)
			Assert.equal(enemy.burnSource, nil)
		end
	end,

	["spawns land in the ring around a player"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.x, player.z = 10, -20
		Horde.spawn(run, 100)
		Assert.truthy(#run.enemies > 100)
		local half = run.config.arena.halfSize
		for _, enemy in run.enemies do
			Assert.truthy(
				math.abs(enemy.x) <= half and math.abs(enemy.z) <= half,
				"outside the arena"
			)
			local d = distance(enemy, player)
			Assert.truthy(d >= run.config.horde.spawnRingMin - 1e-9, "inside the ring: " .. d)
			Assert.truthy(d <= run.config.horde.spawnRingMax + 1e-9, "beyond the ring: " .. d)
		end
	end,

	["spawns near the arena edge are clamped inside"] = function()
		local run = Fixtures.run(1)
		local half = run.config.arena.halfSize
		run.players[1].x, run.players[1].z = half, half
		run.config.horde.maxAlive = 1000
		Horde.spawn(run, 200)
		Assert.truthy(#run.enemies > 100)
		for _, enemy in run.enemies do
			Assert.truthy(
				math.abs(enemy.x) <= half and math.abs(enemy.z) <= half,
				"outside the arena"
			)
		end
	end,

	["spawns pick only alive players"] = function()
		local run = Fixtures.run(2)
		run.players[1].x, run.players[1].z = -100, 0
		run.players[2].x, run.players[2].z = 100, 0
		run.players[1].state = "downed"
		run.config.horde.maxAlive = 1000
		Horde.spawn(run, 100)
		for _, enemy in run.enemies do
			-- Ring minimum is 50, so anything near player 1 would be x < -50.
			Assert.truthy(enemy.x > 30, "spawned around a downed player")
		end
	end,

	["brute share is zero at the start"] = function()
		local run = Fixtures.run(1)
		run.config.horde.maxAlive = 1000
		Horde.spawn(run, 200)
		for _, enemy in run.enemies do
			Assert.equal(enemy.kind, "grunt")
		end
	end,

	["brutes appear later and stay under the share cap"] = function()
		local run = Fixtures.run(1)
		run.config.horde.maxAlive = 100000
		run.time = 20 * 60
		Horde.spawn(run, 200)
		local brutes = 0
		for _, enemy in run.enemies do
			if enemy.kind == "brute" then
				brutes += 1
				Assert.equal(enemy.health, run.config.horde.kinds.brute.health)
			end
		end
		local share = brutes / #run.enemies
		-- 20 minutes would give 0.6 uncapped; the cap is 0.3.
		Assert.truthy(share > 0.2 and share < 0.4, "brute share " .. share)
	end,

	["the same seed gives the same spawns"] = function()
		local a, b = Fixtures.run(3, nil, 99), Fixtures.run(3, nil, 99)
		spawnFor(a, 30, 0.1)
		spawnFor(b, 30, 0.1)
		Assert.equal(#a.enemies, #b.enemies)
		for index, enemy in a.enemies do
			local other = b.enemies[index]
			Assert.equal(enemy.kind, other.kind)
			Assert.equal(enemy.x, other.x)
			Assert.equal(enemy.z, other.z)
		end
	end,

	["different seeds give different spawns"] = function()
		local a, b = Fixtures.run(1, nil, 1), Fixtures.run(1, nil, 2)
		Horde.spawn(a, 5)
		Horde.spawn(b, 5)
		Assert.truthy(a.enemies[1].x ~= b.enemies[1].x)
	end,

	["an enemy moves toward the player at its speed"] = function()
		local run = Fixtures.run(1)
		local enemy = Fixtures.enemy(run, "grunt", 50, 0)
		Horde.move(run, 0.5)
		Assert.near(enemy.x, 45)
		Assert.near(enemy.z, 0)
	end,

	["an enemy heads for the nearest alive player"] = function()
		local run = Fixtures.run(3)
		run.players[1].x, run.players[1].z = -60, 0
		run.players[2].x, run.players[2].z = 30, 0
		run.players[3].x, run.players[3].z = 20, 0
		run.players[3].state = "downed"
		local enemy = Fixtures.enemy(run, "grunt", 50, 0)
		Horde.move(run, 1)
		Assert.near(enemy.x, 40)
	end,

	["an enemy stops at contact distance without overshooting"] = function()
		local run = Fixtures.run(1)
		local enemy = Fixtures.enemy(run, "grunt", 5, 0)
		Horde.move(run, 10)
		-- Grunt radius 1.5 plus player radius 1.5.
		Assert.near(enemy.x, 3)
		Assert.near(enemy.z, 0)
		Horde.move(run, 10)
		Assert.near(enemy.x, 3)
	end,

	["a brute stops further out than a grunt"] = function()
		local run = Fixtures.run(1)
		local brute = Fixtures.enemy(run, "brute", 0, 20)
		Horde.move(run, 10)
		Assert.near(brute.z, 4)
	end,

	["enemies stand still without an alive player"] = function()
		local run = Fixtures.run(1)
		run.players[1].state = "downed"
		local enemy = Fixtures.enemy(run, "grunt", 50, 0)
		Horde.move(run, 1)
		Assert.equal(enemy.x, 50)
		Assert.equal(enemy.z, 0)
	end,

	["chill slows movement while it lasts"] = function()
		local run = Fixtures.run(1)
		local chilled = Fixtures.enemy(run, "grunt", 50, 0)
		local plain = Fixtures.enemy(run, "grunt", 0, 50)
		run.time = 1
		chilled.chilledUntil = 2
		Horde.move(run, 1)
		Assert.near(chilled.x, 44)
		Assert.near(plain.z, 40)

		-- Once the chill has run out the enemy is back to full speed.
		run.time = 2
		Horde.move(run, 1)
		Assert.near(chilled.x, 34)
	end,

	["separation pushes two overlapping enemies apart"] = function()
		local run = Fixtures.run(1)
		local a = Fixtures.enemy(run, "grunt", 50, 50)
		local b = Fixtures.enemy(run, "grunt", 51, 50)
		Horde.move(run, 0)
		Assert.near(distance(a, b), run.config.horde.separationRadius, 1e-9)
		-- Half the overlap each, along the line between them.
		local half = (run.config.horde.separationRadius - 1) / 2
		Assert.near(a.x, 50 - half)
		Assert.near(b.x, 51 + half)
		Assert.near(a.z, 50)
	end,

	["enemies on the same spot are split"] = function()
		local run = Fixtures.run(1)
		local a = Fixtures.enemy(run, "grunt", 50, 50)
		local b = Fixtures.enemy(run, "grunt", 50, 50)
		Horde.move(run, 0)
		Assert.near(distance(a, b), run.config.horde.separationRadius, 1e-9)
	end,

	["enemies outside the separation radius are left alone"] = function()
		local run = Fixtures.run(1)
		local apart = run.config.horde.separationRadius + 0.1
		local a = Fixtures.enemy(run, "grunt", 50, 50)
		local b = Fixtures.enemy(run, "grunt", 50 + apart, 50)
		Horde.move(run, 0)
		Assert.equal(a.x, 50)
		Assert.equal(b.x, 50 + apart)
	end,

	["separation finds neighbours across grid cells"] = function()
		local run = Fixtures.run(1)
		-- The cell boundary falls at x = 50 for a 2.5 radius.
		local a = Fixtures.enemy(run, "grunt", 49.9, -7.6)
		local b = Fixtures.enemy(run, "grunt", 50.1, -7.4)
		Horde.move(run, 0)
		Assert.near(distance(a, b), run.config.horde.separationRadius, 1e-9)
	end,

	["a crowd keeps every enemy inside the arena"] = function()
		local run = Fixtures.run(1)
		local half = run.config.arena.halfSize
		run.players[1].x, run.players[1].z = half, half
		for _ = 1, 40 do
			Fixtures.enemy(run, "grunt", half, half)
		end
		for _ = 1, 20 do
			Horde.move(run, 0.1)
		end
		for _, enemy in run.enemies do
			Assert.truthy(
				math.abs(enemy.x) <= half and math.abs(enemy.z) <= half,
				"outside the arena"
			)
		end
	end,

	["a full horde moves deterministically"] = function()
		local function simulate(): { Types.Enemy }
			local run = Fixtures.run(2, nil, 5)
			run.players[2].x = 40
			run.config.horde.maxAlive = 150
			for _ = 1, 600 do
				run.time += 0.1
				Horde.spawn(run, 0.1)
				Horde.move(run, 0.1)
			end
			return run.enemies
		end
		local a, b = simulate(), simulate()
		Assert.equal(#a, #b)
		for index, enemy in a do
			Assert.equal(enemy.x, b[index].x)
			Assert.equal(enemy.z, b[index].z)
		end
	end,

	["contact deals dps times dt to a player in range"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "grunt", 2, 0)
		local damage = Horde.contact(run, 0.5)
		Assert.near(damage[1], run.config.horde.kinds.grunt.contactDps * 0.5)
	end,

	["contact is zero out of range"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "grunt", 3.5, 0)
		Assert.equal(Horde.contact(run, 1)[1], 0)
	end,

	["a brute reaches further than a grunt"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "brute", 3.9, 0)
		Assert.near(Horde.contact(run, 1)[1], run.config.horde.kinds.brute.contactDps)
	end,

	["contact sums over enemies"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "grunt", 2, 0)
		Fixtures.enemy(run, "brute", 0, 3)
		local kinds = run.config.horde.kinds
		Assert.near(
			Horde.contact(run, 0.5)[1],
			(kinds.grunt.contactDps + kinds.brute.contactDps) * 0.5
		)
	end,

	["an enemy that stopped at contact distance deals damage"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "brute", 37, 11)
		Horde.move(run, 10)
		Assert.near(Horde.contact(run, 1)[1], run.config.horde.kinds.brute.contactDps)
	end,

	["contact gives nothing to players who are not alive"] = function()
		local run = Fixtures.run(3)
		run.players[2].state = "downed"
		run.players[3].state = "extracted"
		Fixtures.enemy(run, "grunt", 1, 0)
		local damage = Horde.contact(run, 1)
		Assert.near(damage[1], run.config.horde.kinds.grunt.contactDps)
		Assert.equal(damage[2], nil)
		Assert.equal(damage[3], nil)
	end,

	["contact is counted per player"] = function()
		local run = Fixtures.run(2)
		run.players[2].x, run.players[2].z = 50, 0
		Fixtures.enemy(run, "grunt", 1, 0)
		local damage = Horde.contact(run, 1)
		Assert.near(damage[1], run.config.horde.kinds.grunt.contactDps)
		Assert.equal(damage[2], 0)
	end,

	["contact does not change health"] = function()
		local run = Fixtures.run(1)
		Fixtures.enemy(run, "grunt", 1, 0)
		Horde.contact(run, 1)
		Assert.equal(run.players[1].health, run.players[1].maxHealth)
	end,

	["a player in a corner is never spawned on"] = function()
		local run = Fixtures.run(1)
		local half = run.config.arena.halfSize
		local player = run.players[1]
		player.x, player.z = half - 1, half - 1
		run.config.horde.spawnPerSecondAtStart = 150
		Horde.spawn(run, 1)
		Assert.truthy(#run.enemies > 100)
		for _, enemy in run.enemies do
			local d = math.sqrt((enemy.x - player.x) ^ 2 + (enemy.z - player.z) ^ 2)
			Assert.truthy(
				d >= run.config.horde.spawnRingMin - 1e-6,
				"spawned " .. d .. " studs away"
			)
		end
	end,
}
