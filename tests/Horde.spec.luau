--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Horde = require("../src/shared/Core/Horde")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- A run on open ground with the hero at the centre.
local function open(seed: number?): Types.Run
	local run = Fixtures.run(1, nil, seed)
	Fixtures.clearObstacles(run)
	return run
end

-- Runs the horde from now to `untilTime` in steps of `dt`.
local function advance(run: Types.Run, untilTime: number, dt: number)
	while run.time + dt <= untilTime + 1e-9 do
		run.time += dt
		Horde.update(run, dt)
	end
end

local function events(run: Types.Run, kind: string): { any }
	local found = {}
	for _, event in run.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

-- Only the clock under test: no spawner, no closing rings.
local function quiet(run: Types.Run)
	run.nextSpawnAt = math.huge
	run.ringsSpawned = #run.map.bosses
end

return {
	["the alive target rises from the start to the cap at the duration"] = function()
		local run = open()
		Assert.equal(Horde.aliveTarget(run), 14)
		run.time = run.config.run.durationSeconds / 2
		Assert.equal(Horde.aliveTarget(run), math.floor(14 + 225 * 0.5))
		run.time = run.config.run.durationSeconds
		Assert.equal(Horde.aliveTarget(run), 220)
		run.time = run.config.run.durationSeconds * 2
		Assert.equal(Horde.progress(run), 1)
		Assert.equal(Horde.aliveTarget(run), 220)
	end,

	["spawns land on the ring around the hero until the target is reached"] = function()
		local run = open()
		local horde = run.config.horde
		-- The target holds still, so reaching it is visible.
		horde.aliveGrowth = 0
		Horde.update(run, 0)
		-- The first batch: the shortfall of 14 divided by the share, at most the batch.
		Assert.equal(#run.enemies, math.min(horde.spawnBatchMax, math.ceil(14 / horde.spawnShare)))
		advance(run, 10, 0.05)
		Assert.equal(#run.enemies, 14)
		for _, enemy in run.enemies do
			local distance = Geometry.distance(enemy.x, enemy.z, 0, 0)
			Assert.truthy(
				distance >= horde.ringMin - 1e-6 and distance <= horde.ringMax + 1e-6,
				"off the ring: " .. distance
			)
		end
		-- Reached: nothing more spawns until one dies.
		advance(run, 12, 0.05)
		Assert.equal(#run.enemies, 14)
		State.removeEnemy(run, run.enemies[1])
		advance(run, 12.5, 0.05)
		Assert.equal(#run.enemies, 14)
	end,

	["the same seed spawns the same horde"] = function()
		local a, b = open(5), open(5)
		advance(a, 3, 0.1)
		advance(b, 3, 0.1)
		Assert.equal(#a.enemies, #b.enemies)
		for index, enemy in a.enemies do
			Assert.equal(enemy.kind, b.enemies[index].kind)
			Assert.equal(enemy.x, b.enemies[index].x)
			Assert.equal(enemy.z, b.enemies[index].z)
		end
	end,

	["nothing spawns while no hero is alive"] = function()
		local run = open()
		run.players[1].state = "dead"
		advance(run, 200, 0.5)
		Assert.equal(#run.enemies, 0)
	end,

	["the kind window starts at the bottom of the roster and slides to its top"] = function()
		local run = open()
		local roster = run.map.roster
		local window = Horde.windowKinds(run)
		Assert.equal(#window, 3)
		for index = 1, 3 do
			Assert.equal(window[index], roster[index])
		end
		run.time = run.config.run.durationSeconds
		window = Horde.windowKinds(run)
		for index = 1, 3 do
			Assert.equal(window[index], roster[#roster - 3 + index])
		end

		local lowest = 0
		for time = 0, run.config.run.durationSeconds, 5 do
			run.time = time
			window = Horde.windowKinds(run)
			Assert.equal(#window, 3)
			local lo = table.find(roster, window[1]) :: number
			Assert.truthy(lo >= lowest, "slid back at " .. time)
			for index = 2, 3 do
				Assert.equal(window[index], roster[lo + index - 1], "adjacent")
			end
			lowest = lo
		end
	end,

	["spawned health and damage grow with run time"] = function()
		local run = open()
		local horde = run.config.horde
		local kind = run.config.enemies.sproutImp
		local early = Horde.spawnKind(run, "sproutImp", 10, 0)
		Assert.near(early.maxHealth, kind.health)
		Assert.near(early.damageFactor, 1)
		run.time = run.config.run.durationSeconds / 2
		local middle = Horde.spawnKind(run, "sproutImp", 10, 0)
		Assert.near(middle.maxHealth, kind.health * (1 + horde.healthGrowth * 0.5))
		Assert.near(middle.damageFactor, 1 + horde.damageGrowth * 0.5)
		run.time = run.config.run.durationSeconds
		local late = Horde.spawnKind(run, "sproutImp", 10, 0)
		Assert.near(late.maxHealth, kind.health * (1 + horde.healthGrowth))
		Assert.truthy(late.damageFactor > middle.damageFactor)
	end,

	["elites come more often as the run goes on"] = function()
		local function elites(time: number): number
			local run = open(9)
			run.time = time
			run.config.horde.aliveAtStart = 2000
			run.config.horde.maxAlive = 2000
			run.config.horde.spawnBatchMax = 2000
			run.config.horde.spawnShare = 1
			Horde.update(run, 0)
			local count = 0
			for _, enemy in run.enemies do
				if State.kind(run, enemy).role == "elite" then
					count += 1
				end
			end
			return count
		end
		local early, late = elites(0), elites(Fixtures.config().run.durationSeconds)
		Assert.truthy(late > early * 2, string.format("early %d, late %d", early, late))
	end,

	["a closing ring spawns halfway before each boss on a circle around the hero"] = function()
		local run = open()
		run.nextSpawnAt = math.huge
		local horde = run.config.horde
		run.time = 67.4
		Horde.update(run, 0)
		Assert.equal(#run.enemies, 0)
		run.time = 67.5
		Horde.update(run, 0)
		local expected = horde.ringCountStart + math.floor(horde.ringCountGrowth * 67.5 / 900)
		Assert.equal(#run.enemies, expected)
		Assert.equal(run.ringsSpawned, 1)
		local ring = Assert.findEvent(run.events, "closingRing")
		Assert.equal(ring.count, expected)
		local kindId = Horde.windowKinds(run)[1]
		local sumX, sumZ = 0, 0
		for _, enemy in run.enemies do
			Assert.equal(enemy.kind, kindId)
			Assert.near(Geometry.distance(enemy.x, enemy.z, 0, 0), horde.ringRadius, 1e-6)
			sumX += enemy.x
			sumZ += enemy.z
		end
		-- Evenly spread: the ring's centre is the hero.
		Assert.near(sumX / expected, 0, 1e-6)
		Assert.near(sumZ / expected, 0, 1e-6)

		-- The next one halfway between the first two bosses; it ignores the cap.
		run.config.horde.maxAlive = 0
		run.time = 202.4
		Horde.update(run, 0)
		Assert.equal(run.ringsSpawned, 1)
		run.time = 202.5
		Horde.update(run, 0)
		Assert.equal(run.ringsSpawned, 2)
		Assert.equal(#events(run, "closingRing"), 2)
	end,

	["a boss arrives at each scheduled time with its kind"] = function()
		local run = open()
		quiet(run)
		local horde = run.config.horde
		for index, entry in run.map.bosses do
			run.time = entry.atSeconds - 0.1
			Horde.update(run, 0)
			Assert.equal(run.bossesSpawned, index - 1)
			run.time = entry.atSeconds
			Horde.update(run, 0)
			Assert.equal(run.bossesSpawned, index)
			local spawned = events(run, "bossSpawned")
			Assert.equal(#spawned, index)
			local event = spawned[index]
			Assert.equal(event.enemyKind, entry.kind)
			Assert.equal(event.final, false)
			local boss = State.enemyById(run, event.enemyId) :: Types.Enemy
			Assert.equal(boss.kind, entry.kind)
			Assert.near(Geometry.distance(boss.x, boss.z, 0, 0), horde.bossDistance, 1e-6)
			-- Stays close enough not to be moved back as a stray.
			boss.x, boss.z = 0, 0
		end
		Assert.equal(#run.enemies, #run.map.bosses)
		Assert.equal(run.finalBossId, nil)
	end,

	["bosses do not count toward the alive target"] = function()
		local run = open()
		run.ringsSpawned = #run.map.bosses
		Fixtures.enemy(run, "thornback", 5, 0)
		Fixtures.enemy(run, "forestHeart", -5, 0)
		Assert.equal(Horde.aliveCount(run), 0)
		advance(run, 10, 0.05)
		Assert.equal(Horde.aliveCount(run), Horde.aliveTarget(run))
		Assert.equal(#run.enemies, Horde.aliveTarget(run) + 2)
	end,

	["the final boss arrives at the duration with its deadline"] = function()
		local run = open()
		quiet(run)
		run.bossesSpawned = #run.map.bosses
		local duration = run.config.run.durationSeconds
		run.time = duration - 0.1
		Horde.update(run, 0)
		Assert.equal(run.finalBossId, nil)
		run.time = duration
		Horde.update(run, 0)
		local id = run.finalBossId :: number
		Assert.truthy(id ~= nil, "no final boss")
		local boss = State.enemyById(run, id) :: Types.Enemy
		Assert.equal(boss.kind, run.map.finalBoss)
		Assert.equal(run.finalBossDeadline, duration + run.config.horde.finalBossSeconds)
		local event = Assert.findEvent(run.events, "bossSpawned")
		Assert.equal(event.final, true)
		Assert.equal(event.enemyId, id)
		local timer = Assert.findEvent(run.events, "finalBossTimer")
		Assert.equal(timer.seconds, run.config.horde.finalBossSeconds)
		-- Once only.
		run.time = duration + 1
		Horde.update(run, 0)
		Assert.equal(#events(run, "bossSpawned"), 1)
	end,

	["a stray is moved back beyond the hero on the far side"] = function()
		local run = open()
		quiet(run)
		local horde = run.config.horde
		Fixtures.place(run, 1, 10, 0)
		local stray = Fixtures.enemy(run, "sproutImp", 10 + horde.strayDistance + 5, 0)
		local near = Fixtures.enemy(run, "sproutImp", 10 + horde.strayDistance - 5, 0)
		Horde.update(run, 0)
		Assert.near(stray.x, 10 - horde.strayReturnDistance, 1e-6)
		Assert.near(stray.z, 0, 1e-6)
		Assert.near(near.x, 10 + horde.strayDistance - 5, 1e-6)
	end,
}
