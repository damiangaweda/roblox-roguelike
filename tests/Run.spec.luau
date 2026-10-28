--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Run = require("../src/shared/Core/Run")
local State = require("../src/shared/Core/State")

local DT = 1 / 30

local function stepFor(run, seconds: number, inputs)
	local steps = math.floor(seconds / DT + 0.5)
	for _ = 1, steps do
		Run.step(run, DT, inputs or {})
	end
end

-- Takes the first card whenever the run waits for one.
local function autoPick(run, seconds: number)
	local steps = math.floor(seconds / DT + 0.5)
	for _ = 1, steps do
		Run.step(run, DT, {})
		if run.paused then
			Run.chooseCard(run, 1, 1)
		end
	end
end

local function eventKinds(events): { string }
	local kinds = {}
	for _, event in events do
		table.insert(kinds, event.kind)
	end
	return kinds
end

return {
	["a run is repeatable for a seed"] = function()
		local a = Fixtures.run(1, nil, 21)
		local b = Fixtures.run(1, nil, 21)
		-- An unkillable hero, so both runs see the same long sequence.
		a.config.classes.mage.maxHealth = 1e6
		b.config.classes.mage.maxHealth = 1e6
		a.players[1].health = 1e6
		b.players[1].health = 1e6
		autoPick(a, 40)
		autoPick(b, 40)
		local ea, eb = Run.drainEvents(a), Run.drainEvents(b)
		Assert.equal(#ea, #eb, "event counts")
		Assert.equal(table.concat(eventKinds(ea), ","), table.concat(eventKinds(eb), ","))
		Assert.equal(#a.enemies, #b.enemies)
		Assert.equal(a.players[1].kills, b.players[1].kills)
		Assert.truthy(a.players[1].kills > 0, "the hero killed something")
	end,

	["the horde spawns, skills fire and crystals are collected on their own"] = function()
		local run = Fixtures.run(1, nil, 3)
		run.config.classes.mage.maxHealth = 1e6
		run.players[1].health = 1e6
		autoPick(run, 30)
		local events = Run.drainEvents(run)
		Assert.truthy(Fixtures.count(events, "cast") > 10, "skills cast themselves")
		Assert.truthy(Fixtures.count(events, "kill") > 0, "kills")
		Assert.truthy(Fixtures.count(events, "crystalCollected") > 0, "crystals collected")
		Assert.truthy(run.players[1].level > 1, "levelled up")
		Assert.truthy(#run.enemies >= 10, "the horde is up: " .. #run.enemies)
	end,

	["movement is held to the budget, the arena and the obstacles"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local player = run.players[1]
		-- A teleport across the map is cut to what walking allows.
		Run.step(run, DT, { [1] = { x = 300, z = 0 } })
		Assert.truthy(player.x < 30, "held back: " .. player.x)
		-- Walking speed passes.
		local before = player.x
		Run.step(run, DT, { [1] = { x = before + 16 * DT, z = 0 } })
		Assert.near(player.x, before + 16 * DT, 1e-6)
		-- The edge holds.
		player.x, player.z = run.arena.radius - 2, 0
		player.moveBudget = 100
		Run.step(run, DT, { [1] = { x = run.arena.radius + 50, z = 0 } })
		Assert.truthy(
			player.x <= run.arena.radius - run.config.player.radius + 1e-6,
			"inside the edge"
		)
		-- An obstacle stops the walk short of it.
		player.x, player.z = 0, 0
		player.moveBudget = 100
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 6, z = 0, radius = 3, rotation = 0 }
		)
		Run.step(run, DT, { [1] = { x = 10, z = 0 } })
		Assert.truthy(
			player.x <= 6 - 3 - run.config.player.radius + 1e-6,
			"stopped by the rock: " .. player.x
		)
		-- Non-finite input is dropped.
		local x = player.x
		Run.step(run, DT, { [1] = { x = 0 / 0, z = 0 } })
		Assert.equal(player.x, x)
	end,

	["a solo run pauses while a card is chosen and resumes after"] = function()
		local run = Fixtures.run(1, nil, 5)
		run.config.classes.mage.maxHealth = 1e6
		run.players[1].health = 1e6
		local paused = false
		for _ = 1, 30 * 60 do
			Run.step(run, DT, {})
			if run.paused then
				paused = true
				break
			end
		end
		Assert.truthy(paused, "the run paused for an offer")
		local time = run.time
		Run.step(run, DT, {})
		Assert.equal(run.time, time, "time stands still")
		Assert.falsy(Run.useUtility(run, 1, 1), "no utility while paused")
		Assert.truthy(Run.chooseCard(run, 1, 1))
		Assert.falsy(run.paused)
		Run.step(run, DT, {})
		Assert.truthy(run.time > time)
	end,

	["the run ends when the hero dies"] = function()
		local run = Fixtures.run(1, nil, 9)
		Fixtures.clearObstacles(run)
		autoPick(run, 15 * 60)
		Assert.truthy(run.ended, "ended")
		Assert.equal(run.players[1].state, "dead")
		local ended = Assert.findEvent(Run.drainEvents(run), "ended")
		Assert.truthy(ended ~= nil)
		Assert.equal(ended.reason, "allDead")
	end,

	["the final boss arrives at the duration and its death extracts the hero"] = function()
		local run = Fixtures.run(1, nil, 2)
		run.config.classes.mage.maxHealth = 1e6
		run.players[1].health = 1e6
		run.time = run.config.run.durationSeconds - DT / 2
		Run.step(run, DT, {})
		Assert.truthy(run.finalBossId ~= nil, "the final boss is up")
		Assert.truthy(run.finalBossDeadline ~= nil)
		local boss = State.enemyById(run, run.finalBossId :: number)
		Assert.truthy(boss ~= nil)
		Assert.equal((boss :: any).kind, run.map.finalBoss)
		-- Kill it by hand: the run extracts everyone alive.
		State.removeEnemy(run, boss :: any)
		Run.step(run, DT, {})
		Assert.truthy(run.ended)
		Assert.equal(run.players[1].state, "extracted")
		Assert.equal(Assert.findEvent(Run.drainEvents(run), "ended").reason, "finalBossKilled")
	end,

	["the map closes when the final boss outlives its time"] = function()
		local run = Fixtures.run(1, nil, 2)
		run.config.classes.mage.maxHealth = 1e6
		run.players[1].health = 1e6
		run.time = run.config.run.durationSeconds - DT / 2
		Run.step(run, DT, {})
		run.time = (run.finalBossDeadline :: number) - DT / 2
		Run.step(run, DT, {})
		Assert.truthy(run.ended)
		Assert.equal(run.players[1].state, "dead")
		Assert.equal(Assert.findEvent(Run.drainEvents(run), "ended").reason, "mapClosed")
	end,

	["extracting through the portal ends a solo run"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.hasSpell = true
		Assert.truthy(Run.castSpell(run, 1))
		stepFor(run, run.config.extraction.castSeconds + 0.1, { [1] = { x = 0, z = 0 } })
		Assert.truthy(run.portal ~= nil, "portal open")
		Assert.truthy(Run.enterPortal(run, 1))
		Run.step(run, DT, {})
		Assert.truthy(run.ended)
		Assert.equal(Assert.findEvent(Run.drainEvents(run), "ended").reason, "extracted")
	end,

	["an unknown class falls back to the first class"] = function()
		local run = Fixtures.run(0)
		local player = Run.addPlayer(run, 7, "nothing")
		Assert.equal(player.class, "archer")
	end,

	["a dash covers its distance over its time"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		run.nextSpawnAt = math.huge
		local player = run.players[1]
		local config = run.config.player
		Assert.truthy(Run.dash(run, 1, 0, 2))
		local event = Assert.findEvent(Run.drainEvents(run), "dash")
		Assert.equal(event.player, 1)
		Assert.near(event.dx, 0, 1e-9)
		Assert.near(event.dz, config.dashDistance, 1e-9)
		local dt = 0.05
		for _ = 1, math.round(config.dashSeconds / dt) - 1 do
			Run.step(run, dt, {})
			Assert.truthy(player.dashUntil > run.time, "untouchable during the dash")
		end
		Run.step(run, dt, {})
		Assert.near(player.z, config.dashDistance, 1e-6)
		Assert.near(player.x, 0, 1e-6)
		Assert.falsy(player.dashUntil > run.time, "over")
		for _ = 1, 10 do
			Run.step(run, dt, {})
		end
		Assert.near(player.z, config.dashDistance, 1e-6, "no drift after")
	end,

	["a dash is refused while the run waits for a card"] = function()
		local run = Fixtures.run()
		run.paused = true
		Assert.falsy(Run.dash(run, 1, 1, 0))
		Assert.equal(run.players[1].dashCharges, run.config.player.dashCharges)
		Assert.equal(Fixtures.count(Run.drainEvents(run), "dash"), 0)
		run.paused = false
		Assert.falsy(Run.dash(run, 99, 1, 0), "an unknown player")
		Assert.truthy(Run.dash(run, 1, 1, 0))
	end,
}
