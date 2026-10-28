--!strict
-- The lairs (ADR-0021): the draw and placement, the batches, the sleeping
-- boss and its guard, silencing, the final boss's rise and doom.
local Assert = require("./Assert")
local Damage = require("../src/shared/Core/Damage")
local Enemies = require("../src/shared/Core/Enemies")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Lairs = require("../src/shared/Core/Lairs")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- A run on open ground with the hero at the centre and no lairs of its own.
local function open(playerCount: number?): Types.Run
	local run = Fixtures.run(playerCount or 1)
	Fixtures.clearObstacles(run)
	Fixtures.clearLairs(run)
	return run
end

-- Runs the lairs from now to `untilTime` in steps of `dt`.
local function advance(run: Types.Run, untilTime: number, dt: number)
	while run.time < untilTime - 1e-9 do
		-- The last step lands on `untilTime` exactly, whatever the rounding.
		local step = if untilTime - run.time <= dt + 1e-9 then untilTime - run.time else dt
		run.time = if step == dt then run.time + dt else untilTime
		Lairs.update(run, step)
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

-- The lair's released grunts alive.
local function released(run: Types.Run, lair: Types.Lair): { Types.Enemy }
	local found = {}
	for _, enemy in run.enemies do
		if enemy.lairId == lair.id and State.kind(run, enemy).role == "grunt" then
			table.insert(found, enemy)
		end
	end
	return found
end

local function boss(run: Types.Run, lair: Types.Lair): Types.Enemy
	return State.enemyById(run, lair.bossId :: number) :: Types.Enemy
end

local function guards(run: Types.Run, lair: Types.Lair): { Types.Enemy }
	local found = {}
	for _, id in lair.guardIds do
		local guard = State.enemyById(run, id)
		if guard then
			table.insert(found, guard)
		end
	end
	return found
end

-- A hit from player 1 at (fromX, fromZ).
local function hitBy(amount: number, fromX: number, fromZ: number): Damage.Hit
	return {
		source = 1,
		skill = "test",
		amount = amount,
		tags = {},
		effect = nil,
		critChance = 0,
		knockback = 0,
		fromX = fromX,
		fromZ = fromZ,
	}
end

-- Kills the lair's boss as player 1 would; the hit is far past its health,
-- which grows when the hit wakes it.
local function killBoss(run: Types.Run, lair: Types.Lair)
	local target = boss(run, lair)
	Damage.hit(run, target, hitBy(1e12, target.x - 1, target.z))
end

local spec: { [string]: () -> () } = {}

spec["a run draws its lairs' kinds without repeats and places them by the rules"] = function()
	local config = Fixtures.config()
	local lairs = config.lairs
	local map = config.maps[config.map]
	for seed = 1, 20 do
		local run = State.newRun(Fixtures.config(), seed)
		local arena = run.arena
		Assert.equal(#arena.lairSpots, lairs.count, "seed " .. seed .. " count")
		Assert.equal(#run.lairs, lairs.count)
		local seen = {}
		for index, spot in arena.lairSpots do
			Assert.falsy(seen[spot.kind], "a repeated kind")
			seen[spot.kind] = true
			local kind = State.lairKind(run, run.lairs[index])
			Assert.equal(run.lairs[index].kind, spot.kind)
			Assert.equal(run.lairs[index].radius, kind.radius)
			Assert.truthy(
				Geometry.distance(spot.x, spot.z, 0, 0) >= lairs.startMinDistance,
				"start"
			)
			Assert.truthy(
				Geometry.distance(spot.x, spot.z, arena.chestX, arena.chestZ)
					>= lairs.chestMinDistance,
				"chest"
			)
			Assert.truthy(
				Geometry.distance(spot.x, spot.z, 0, 0) + kind.clearRadius
					<= map.radius - map.edgeMargin + 1e-6,
				"edge"
			)
			for other = index + 1, #arena.lairSpots do
				local next = arena.lairSpots[other]
				Assert.truthy(
					Geometry.distance(spot.x, spot.z, next.x, next.z) >= lairs.spacing,
					"spacing"
				)
			end
		end
	end
end

spec["the same seed draws the same lairs and staggers them the same way"] = function()
	local a = State.newRun(Fixtures.config(), 17)
	local b = State.newRun(Fixtures.config(), 17)
	for index, lair in a.lairs do
		local other = b.lairs[index]
		Assert.equal(lair.kind, other.kind)
		Assert.equal(lair.x, other.x)
		Assert.equal(lair.z, other.z)
		Assert.equal(lair.rotation, other.rotation)
		Assert.equal(lair.nextBatchAt, other.nextBatchAt)
	end
end

spec["the first releases are offset within the lair's interval so they differ"] = function()
	local run = State.newRun(Fixtures.config(), 4)
	local first: { [number]: boolean } = {}
	local distinct = 0
	for _, lair in run.lairs do
		local interval = State.lairKind(run, lair).intervalSeconds
		Assert.truthy(lair.nextBatchAt >= 0)
		Assert.truthy(lair.nextBatchAt < interval * run.config.lairs.offsetShare + 1e-9)
		if not first[lair.nextBatchAt] then
			first[lair.nextBatchAt] = true
			distinct += 1
		end
	end
	Assert.equal(distinct, #run.lairs)
end

spec["each lair's boss sleeps at its centre with its guard on a ring"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	local kind = State.lairKind(run, lair)
	Lairs.update(run, 0)
	local sleeper = boss(run, lair)
	Assert.equal(sleeper.kind, kind.boss)
	Assert.truthy(sleeper.asleep)
	Assert.equal(sleeper.lairId, lair.id)
	Assert.near(sleeper.x, 200, 1e-6)
	Assert.near(sleeper.z, 0, 1e-6)
	local guard = guards(run, lair)
	Assert.equal(#guard, kind.guardCount)
	for index, enemy in guard do
		Assert.equal(enemy.kind, kind.guards[(index - 1) % #kind.guards + 1], "in turn")
		Assert.truthy(enemy.asleep)
		Assert.equal(enemy.lairId, lair.id)
		Assert.near(
			Geometry.distance(enemy.x, enemy.z, 200, 0),
			lair.radius * run.config.lairs.guardRingShare,
			1e-6
		)
	end
	Assert.truthy(lair.asleep)
	Assert.equal(Lairs.aliveCount(run), 0, "bosses and guards do not count")
	Assert.equal(#events(run, "lairWoke"), 0)
	-- Once only.
	Lairs.update(run, 0)
	Assert.equal(#run.enemies, 1 + kind.guardCount)
end

spec["a lair releases its batch at its interval, its kinds in turn, one batch a step"] = function()
	local run = open()
	local lairs = run.config.lairs
	local lair = Fixtures.lair(run, "brambleNest", 200, 0, 0)
	local kind = State.lairKind(run, lair)
	Lairs.update(run, 0)
	local batch = released(run, lair)
	Assert.equal(#batch, lairs.batchStart)
	for _, grunt in batch do
		Assert.equal(grunt.kind, kind.grunts[1], "only the weakest kind at the start")
		local distance = Geometry.distance(grunt.x, grunt.z, lair.x, lair.z)
		Assert.truthy(
			distance >= lair.radius * lairs.releaseRingMin - 1e-6
				and distance <= lair.radius * lairs.releaseRingMax + 1e-6
		)
		Assert.falsy(grunt.asleep)
	end
	Assert.equal(lair.nextBatchAt, kind.intervalSeconds)
	advance(run, kind.intervalSeconds - 0.05, 0.05)
	Assert.equal(#released(run, lair), lairs.batchStart, "nothing before the interval")
	advance(run, kind.intervalSeconds, 0.05)
	Assert.equal(#released(run, lair), 2 * lairs.batchStart)
	-- A long step releases one batch, not a backlog.
	run.time = kind.intervalSeconds * 3
	Lairs.update(run, 0)
	Assert.equal(#released(run, lair), 3 * lairs.batchStart)
	Assert.near(lair.nextBatchAt, run.time + kind.intervalSeconds)
end

spec["trials and summons take only a lair's unlocked grunts"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	local kind = State.lairKind(run, lair)
	local early = Lairs.gruntKinds(run, 190, 0)
	Assert.equal(#early, 1)
	Assert.equal(early[1], kind.grunts[1])
	run.time = run.config.run.durationSeconds / 2
	local middle = Lairs.gruntKinds(run, 190, 0)
	Assert.equal(#middle, 2)
	Assert.equal(middle[2], kind.grunts[2])
	Assert.equal(#kind.grunts, 3, "the kind's list is untouched")
end

spec["owed strays the cap holds back stay owed"] = function()
	local run = open()
	local lairs = run.config.lairs
	local lair = Fixtures.lair(run, "brambleNest", 200, 0, 0)
	Lairs.update(run, 0)
	-- Room for 2 under the cap; the batch is batchStart + 3 owed.
	run.config.horde.maxAlive = 2
	lair.owed = 3
	lair.nextBatchAt = run.time
	Lairs.update(run, 0)
	Assert.equal(#released(run, lair), 2)
	Assert.equal(lair.owed, math.min(3, lairs.batchStart + 3 - 2))
	-- With room for all but one, only that one stays owed.
	run.config.horde.maxAlive = 2 + lairs.batchStart + 3 - 1
	lair.owed = 3
	lair.nextBatchAt = run.time
	Lairs.update(run, 0)
	Assert.equal(lair.owed, 1)
	-- With room for the whole batch nothing stays owed.
	run.config.horde.maxAlive = 1000
	lair.nextBatchAt = run.time
	Lairs.update(run, 0)
	Assert.equal(lair.owed, 0)
end

spec["every lair kind lists its grunts weakest first"] = function()
	local config = Fixtures.config()
	local roster = config.maps[config.map].roster
	for _, kind in config.lairs.kinds do
		for index = 2, #kind.grunts do
			local before = table.find(roster, kind.grunts[index - 1]) :: number
			local after = table.find(roster, kind.grunts[index]) :: number
			Assert.truthy(before < after, kind.id .. ": " .. kind.grunts[index] .. " out of order")
		end
	end
end

spec["a lair's grunt kinds unlock with the run's progress, drawn in turn"] = function()
	local duration = Fixtures.config().run.durationSeconds
	for _, case in
		{
			{ share = 0, unlocked = 1 },
			{ share = 0.5, unlocked = 2 },
			{ share = 0.99, unlocked = 2 },
		}
	do
		local run = open()
		local lair = Fixtures.lair(run, "brambleNest", 200, 0, 0)
		local kind = State.lairKind(run, lair)
		run.time = duration * case.share
		lair.nextBatchAt = run.time
		Assert.equal(Lairs.unlockedGrunts(run, kind), case.unlocked)
		Lairs.update(run, 0)
		local batch = released(run, lair)
		Assert.truthy(#batch >= case.unlocked)
		local first = table.find(kind.grunts, batch[1].kind) :: number
		Assert.truthy(first <= case.unlocked)
		for index, grunt in batch do
			Assert.equal(
				grunt.kind,
				kind.grunts[(first + index - 2) % case.unlocked + 1],
				"in turn"
			)
		end
	end
	-- Every kind is unlocked at the end time.
	local run = open()
	run.time = duration
	Assert.equal(
		Lairs.unlockedGrunts(run, run.config.lairs.kinds[1]),
		#run.config.lairs.kinds[1].grunts
	)
end

spec["the batch and its grunts grow with run time"] = function()
	local run = open()
	local lairs = run.config.lairs
	local horde = run.config.horde
	local duration = run.config.run.durationSeconds
	local lair = Fixtures.lair(run, "bog", 200, 0, duration / 2)
	run.time = duration / 2
	Lairs.update(run, 0)
	local batch = released(run, lair)
	Assert.equal(
		#batch,
		math.floor(lairs.batchStart + (lairs.batchEnd - lairs.batchStart) * 0.5 + 0.5)
	)
	local grunt = batch[1]
	local kind = run.config.enemies[grunt.kind]
	Assert.near(grunt.maxHealth, kind.health * (1 + horde.healthGrowth * 0.5))
	Assert.near(grunt.damageFactor, 1 + horde.damageGrowth * 0.5)
	-- Just before the end time the batch has reached batchEnd.
	local late = open()
	local other = Fixtures.lair(late, "bog", 200, 0, duration - 1)
	late.time = duration - 0.5
	Lairs.update(late, 0)
	Assert.equal(#released(late, other), lairs.batchEnd)
end

spec["batches are held to the cap; bosses, guards and wraiths do not count"] = function()
	local run = open()
	run.config.horde.maxAlive = 5
	local lair = Fixtures.lair(run, "brambleNest", 200, 0, 0)
	Fixtures.enemy(run, "wraith", -50, 0)
	for index = 1, 4 do
		Fixtures.enemy(run, "sproutImp", -20, index * 4)
	end
	Assert.equal(Lairs.aliveCount(run), 4)
	Lairs.update(run, 0)
	Assert.equal(#released(run, lair), 1)
	Assert.equal(Lairs.aliveCount(run), 5)
	Assert.equal(#run.enemies, 5 + 1 + 1 + #lair.guardIds)
end

spec["a stray despawns and is owed to its lair's next batch"] = function()
	local run = open()
	local lairs = run.config.lairs
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	local far = Fixtures.enemy(run, "sproutImp", 0, lairs.strayDespawnDistance + 5)
	far.lairId = lair.id
	local near = Fixtures.enemy(run, "sproutImp", 0, lairs.strayDespawnDistance - 5)
	near.lairId = lair.id
	local free = Fixtures.enemy(run, "sproutImp", 0, -lairs.strayDespawnDistance - 50)
	Lairs.update(run, 0)
	Assert.equal(State.enemyById(run, far.id), nil, "the stray is gone")
	Assert.truthy(State.enemyById(run, near.id) ~= nil)
	Assert.truthy(State.enemyById(run, free.id) ~= nil, "a grunt of no lair stays")
	Assert.equal(lair.owed, 1)
	-- Its next batch carries it, and the debt is paid.
	lair.nextBatchAt = run.time
	Lairs.update(run, 0)
	Assert.equal(#released(run, lair), lairs.batchStart + 1 + 1, "the batch, the owed and `near`")
	Assert.equal(lair.owed, 0)
	-- The debt never passes batchEnd.
	for _ = 1, lairs.batchEnd + 5 do
		local stray = Fixtures.enemy(run, "sproutImp", 0, lairs.strayDespawnDistance + 5)
		stray.lairId = lair.id
		Lairs.update(run, 0)
	end
	Assert.equal(lair.owed, lairs.batchEnd)
end

spec["a hero entering the lair wakes its boss and guard together"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	Fixtures.place(run, 1, 200 - lair.radius - 1, 0)
	Lairs.update(run, 0)
	Assert.truthy(lair.asleep, "outside the radius")
	Fixtures.place(run, 1, 200 - lair.radius + 1, 0)
	Lairs.update(run, 0)
	Assert.falsy(lair.asleep)
	Assert.equal(#events(run, "lairWoke"), 1)
	Assert.equal(events(run, "lairWoke")[1].lairId, lair.id)
	Assert.falsy(boss(run, lair).asleep)
	for _, guard in guards(run, lair) do
		Assert.falsy(guard.asleep)
	end
end

spec["damage to any of a lair's sleepers wakes the whole lair"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	local guard = guards(run, lair)[1]
	-- From far outside the lair: a skill fired from afar wakes it too.
	Damage.hit(run, guard, hitBy(1, 0, 0))
	Assert.falsy(lair.asleep)
	Assert.falsy(boss(run, lair).asleep)
	Assert.equal(#events(run, "lairWoke"), 1)
end

spec["a boss wakes grown with run time, keeping its share of health"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "bog", 200, 0)
	Lairs.update(run, 0)
	local sleeper = boss(run, lair)
	local kind = State.kind(run, sleeper)
	sleeper.health = sleeper.maxHealth / 2
	run.time = 300
	Fixtures.wake(run, lair)
	local growth = 1 + run.config.lairs.bossGrowthPerMinute * 5
	Assert.near(sleeper.maxHealth, kind.health * growth, 1e-6)
	Assert.near(sleeper.health, kind.health * growth / 2, 1e-6)
	Assert.near(sleeper.damageFactor, growth, 1e-9)
	-- A guard grows with the horde instead.
	local guard = guards(run, lair)[1]
	local p = 300 / run.config.run.durationSeconds
	Assert.near(guard.damageFactor, 1 + run.config.horde.damageGrowth * p, 1e-9)
end

spec["the boss and guard stay in the lair and fight only heroes within its reach"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "burntGlade", 200, 0)
	run.config.classes.mage.maxHealth = 1e6
	run.players[1].health = 1e6
	Lairs.update(run, 0)
	Fixtures.wake(run, lair)
	-- Outside the radius but within the reach: they come at the hero, up to the edge.
	Fixtures.place(run, 1, 200 - lair.radius * 1.8, 0)
	for _ = 1, 200 do
		run.time += 0.05
		Lairs.update(run, 0.05)
		Enemies.step(run, 0.05)
		for _, enemy in run.enemies do
			if Lairs.leashOf(run, enemy) == lair then
				Assert.truthy(
					Geometry.distance(enemy.x, enemy.z, lair.x, lair.z) <= lair.radius + 1e-6,
					"inside the lair"
				)
			end
		end
	end
	Assert.falsy(lair.asleep, "the hero is within reach")
	Assert.equal(boss(run, lair).target, 1)
	local edge = Geometry.distance(boss(run, lair).x, boss(run, lair).z, lair.x, lair.z)
	Assert.truthy(edge > lair.radius * 0.5, "it walked toward the hero: " .. edge)
end

spec["a boss with no hero in reach walks home, out of a skill's range from outside"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	run.config.classes.mage.maxHealth = 1e6
	run.players[1].health = 1e6
	Lairs.update(run, 0)
	Fixtures.wake(run, lair)
	local sleeper = boss(run, lair)
	-- Pulled to the lair's edge toward the hero, who then stands 91 studs from
	-- the centre: beyond the reach (90), within 72 of the boss at the edge.
	sleeper.x, sleeper.z = 200 - lair.radius, 0
	Assert.equal(Lairs.reach(run, lair), 90)
	local heroX = 200 - 91
	Fixtures.place(run, 1, heroX, 0)
	Assert.truthy(Geometry.distance(sleeper.x, sleeper.z, heroX, 0) < 72)
	-- The hero keeps shooting it every two seconds, which keeps the lair awake.
	local nextShot = 0
	for _ = 1, 400 do
		run.time += 0.05
		if run.time >= nextShot then
			Damage.hit(run, sleeper, hitBy(1, heroX, 0))
			nextShot += 2
		end
		Lairs.update(run, 0.05)
		Enemies.step(run, 0.05)
	end
	Assert.falsy(lair.asleep, "the shots keep it awake")
	Assert.equal(sleeper.target, nil, "no hero in reach")
	local home = Geometry.distance(sleeper.x, sleeper.z, lair.x, lair.z)
	-- Its guard crowds the centre too, so it stands near it, not on it.
	Assert.truthy(home < lair.radius * 0.25, "home at the centre: " .. home)
	local away = Geometry.distance(sleeper.x, sleeper.z, heroX, 0)
	Assert.truthy(away > 72, "out of a 72-stud skill's reach: " .. away)
end

spec["the lair sleeps when every hero has left, the boss regaining its share"] = function()
	local run = open()
	local lairs = run.config.lairs
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	Fixtures.place(run, 1, 200, 10)
	Lairs.update(run, 0)
	Assert.falsy(lair.asleep)
	local sleeper = boss(run, lair)
	sleeper.health = sleeper.maxHealth * 0.4
	Fixtures.place(run, 1, 200 - Lairs.reach(run, lair) - 1, 0)
	advance(run, lairs.sleepGraceSeconds - 0.05, 0.05)
	Assert.falsy(lair.asleep, "within the grace")
	advance(run, lairs.sleepGraceSeconds, 0.05)
	Assert.truthy(lair.asleep)
	Assert.equal(#events(run, "lairSlept"), 1)
	Assert.truthy(sleeper.asleep)
	for _, guard in guards(run, lair) do
		Assert.truthy(guard.asleep)
	end
	Assert.near(sleeper.health, sleeper.maxHealth * (0.4 + 0.6 * lairs.sleepRecoverShare), 1e-6)
end

spec["a shot every two seconds from outside keeps the lair awake"] = function()
	local run = open()
	local lairs = run.config.lairs
	Assert.truthy(lairs.sleepGraceSeconds > 2)
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	-- Far outside the reach the whole time.
	Fixtures.place(run, 1, 0, 0)
	local sleeper = boss(run, lair)
	Damage.hit(run, sleeper, hitBy(1, 0, 0))
	Assert.falsy(lair.asleep)
	local nextShot = 2
	advance(run, 0, 0.05)
	while run.time < 12 - 1e-9 do
		advance(run, math.min(nextShot, 12), 0.05)
		if run.time >= nextShot - 1e-9 then
			Damage.hit(run, sleeper, hitBy(1, 0, 0))
			nextShot += 2
		end
		Assert.falsy(lair.asleep, "awake at " .. run.time)
	end
	Assert.equal(#events(run, "lairWoke"), 1)
	Assert.equal(#events(run, "lairSlept"), 0)
	-- The shooting stops: the lair sleeps once the grace has passed.
	local last = run.time
	advance(run, last + lairs.sleepGraceSeconds - 0.05, 0.05)
	Assert.falsy(lair.asleep)
	advance(run, last + lairs.sleepGraceSeconds, 0.05)
	Assert.truthy(lair.asleep)
	Assert.equal(#events(run, "lairSlept"), 1)
end

spec["the boss's death silences the lair with a great offer and food"] = function()
	local run = open()
	local lair = Fixtures.lair(run, "brambleNest", 200, 0, 0)
	local second = Fixtures.lair(run, "bog", -200, 0)
	Lairs.update(run, 0)
	local dead = boss(run, lair)
	local x, z = dead.x, dead.z
	killBoss(run, lair)
	Assert.truthy(lair.silenced)
	Assert.equal(lair.bossId, nil)
	local event = Assert.findEvent(run.events, "lairSilenced")
	Assert.equal(event.lairId, lair.id)
	Assert.equal(event.player, 1)
	local player = run.players[1]
	Assert.equal(#player.offers, 1)
	Assert.equal(player.offers[1].ranks, run.config.shrines.greatOfferRanks)
	local food = run.foods[#run.foods]
	Assert.equal(food.heal, math.huge)
	Assert.near(food.x, x)
	Assert.near(food.z, z)
	Assert.equal(#guards(run, lair), 0, "the guard is gone")
	Assert.equal(#lair.guardIds, 0)
	Assert.equal(#events(run, "kill"), 1, "the boss's kill only")
	Assert.equal(#run.crystals, 1, "the boss's crystal only")
	Assert.equal(run.players[1].kills, 1)
	Assert.falsy(Assert.findEvent(run.events, "finalRising"), "a lair still lives")
	Assert.falsy(second.silenced)
	-- No more batches.
	local before = #released(run, lair)
	lair.nextBatchAt = 0
	run.time = 100
	Lairs.update(run, 0)
	Assert.equal(#released(run, lair), before)
end

spec["the last lair's fall raises the final boss there after its rise"] = function()
	local run = open()
	local lairs = run.config.lairs
	local first = Fixtures.lair(run, "brambleNest", 200, 0)
	local last = Fixtures.lair(run, "bog", -150, 50)
	Lairs.update(run, 0)
	killBoss(run, first)
	run.time = 30
	killBoss(run, last)
	local rising = Assert.findEvent(run.events, "finalRising")
	Assert.truthy(rising, "the rise begins")
	Assert.equal(rising.lairId, last.id)
	Assert.equal(rising.x, -150)
	Assert.equal(rising.z, 50)
	Assert.equal(rising.seconds, lairs.finalRiseSeconds)
	Assert.equal(run.finalRiseAt, 30 + lairs.finalRiseSeconds)
	advance(run, 30 + lairs.finalRiseSeconds - 0.1, 0.05)
	Assert.equal(run.finalBossId, nil, "still rising")
	advance(run, 30 + lairs.finalRiseSeconds, 0.05)
	local id = run.finalBossId :: number
	Assert.truthy(id ~= nil, "risen")
	local final = State.enemyById(run, id) :: Types.Enemy
	Assert.equal(final.kind, run.map.finalBoss)
	Assert.near(final.x, -150, 1e-6)
	Assert.near(final.z, 50, 1e-6)
	Assert.equal(final.lairId, nil, "the final boss is not leashed")
	local spawned = Assert.findEvent(run.events, "bossSpawned")
	Assert.equal(spawned.final, true)
	Assert.equal(spawned.enemyId, id)
	Assert.equal(run.finalRiseAt, nil)
	advance(run, 60, 0.5)
	Assert.equal(#events(run, "bossSpawned"), 1, "once")
end

spec["doom cancels a rise under way and no final boss comes after it"] = function()
	local run = open()
	local duration = run.config.run.durationSeconds
	local lair = Fixtures.lair(run, "brambleNest", 200, 0)
	Lairs.update(run, 0)
	run.time = duration - 1
	killBoss(run, lair)
	Assert.truthy(run.finalRiseAt ~= nil)
	advance(run, duration + run.config.lairs.finalRiseSeconds + 1, 0.05)
	Assert.truthy(run.doom)
	Assert.equal(run.finalRiseAt, nil)
	Assert.equal(run.finalBossId, nil)
	Assert.equal(#events(run, "bossSpawned"), 0)

	-- The last lair falling in doom raises nothing.
	local late = open()
	local other = Fixtures.lair(late, "bog", 200, 0)
	Lairs.update(late, 0)
	late.time = duration
	Lairs.update(late, 0)
	killBoss(late, other)
	Assert.truthy(other.silenced)
	Assert.equal(late.finalRiseAt, nil)
	Assert.falsy(Assert.findEvent(late.events, "finalRising"))
end

spec["doom starts at the end time, stops the lairs and sends wraiths at every hero"] = function()
	local run = open(2)
	local wraith = run.config.lairs.wraith
	local duration = run.config.run.durationSeconds
	Fixtures.place(run, 2, 100, 100)
	local lair = Fixtures.lair(run, "brambleNest", -200, 0)
	Lairs.update(run, 0)
	lair.nextBatchAt = duration
	run.time = duration - 0.05
	Lairs.update(run, 0)
	Assert.falsy(run.doom)
	run.time = duration
	Lairs.update(run, 0)
	Assert.truthy(run.doom)
	Assert.equal(#events(run, "doomStarted"), 1)
	Assert.equal(#released(run, lair), 0, "the lairs no longer release")
	local function wraiths(): { Types.Enemy }
		local found = {}
		for _, enemy in run.enemies do
			if enemy.kind == wraith.kind then
				table.insert(found, enemy)
			end
		end
		return found
	end
	Assert.equal(#wraiths(), 2 * wraith.count)
	for _, enemy in wraiths() do
		local d1 = Geometry.distance(enemy.x, enemy.z, 0, 0)
		local d2 = Geometry.distance(enemy.x, enemy.z, 100, 100)
		Assert.truthy(
			math.abs(d1 - wraith.ringRadius) < 1e-6 or math.abs(d2 - wraith.ringRadius) < 1e-6,
			"on a ring around a hero"
		)
	end
	advance(run, duration + wraith.intervalSeconds - 0.05, 0.05)
	Assert.equal(#wraiths(), 2 * wraith.count)
	advance(run, duration + wraith.intervalSeconds, 0.05)
	Assert.equal(#wraiths(), 4 * wraith.count)
	Assert.equal(Lairs.aliveCount(run), 0, "wraiths do not count")
	Assert.equal(#events(run, "doomStarted"), 1, "once")
end

spec["a wraith takes damage over time but no control or knockback, and leaves nothing"] = function()
	local run = open()
	local wraith = Fixtures.enemy(run, "wraith", 10, 0)
	Damage.applyStatus(run, wraith, "stunned", 5)
	Damage.applyStatus(run, wraith, "slowed", 5, 0.5)
	Damage.applyStatus(run, wraith, "feared", 5)
	Damage.applyEffect(
		run,
		wraith,
		{ kind = "dot", dps = 10, seconds = 3, status = "burning" },
		1,
		{}
	)
	Assert.equal(wraith.stunnedUntil, 0)
	Assert.equal(wraith.slowFactor, 1)
	Assert.equal(wraith.fearedUntil, 0)
	Assert.equal(#wraith.dots, 1, "damage over time still burns")
	local push = hitBy(1, 0, 0)
	push.knockback = 10
	Damage.hit(run, wraith, push)
	Assert.equal(wraith.knockUntil, 0)
	local execute = hitBy(1, 0, 0)
	execute.effect = { kind = "execute", factor = 0.99 }
	Damage.hit(run, wraith, execute)
	Assert.truthy(State.enemyById(run, wraith.id) ~= nil, "no execute")
	Damage.hit(run, wraith, hitBy(wraith.health + 1, 0, 0))
	Assert.equal(State.enemyById(run, wraith.id), nil)
	Assert.equal(#run.crystals, 0, "no experience")
	Assert.equal(#run.foods, 0)
	Assert.equal(#events(run, "kill"), 1)
end

spec["the lairs replay the same for a seed"] = function()
	local function play(): Types.Run
		local run = Fixtures.run(1, nil, 33)
		for _ = 1, 600 do
			run.time += 0.1
			Lairs.update(run, 0.1)
			Enemies.step(run, 0.1)
		end
		return run
	end
	local a, b = play(), play()
	Assert.equal(#a.enemies, #b.enemies)
	Assert.truthy(#a.enemies > #a.lairs * 3, "the lairs released: " .. #a.enemies)
	for index, enemy in a.enemies do
		local other = b.enemies[index]
		Assert.equal(enemy.kind, other.kind)
		Assert.equal(enemy.x, other.x)
		Assert.equal(enemy.z, other.z)
		Assert.equal(enemy.lairId, other.lairId)
	end
end

return spec
