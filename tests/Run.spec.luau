--!strict
-- Whole runs through Run.step, the way the server adapter drives them.
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Run = require("../src/shared/Core/Run")

local STEP = 1 / 30

local function advance(run: any, seconds: number, inputs: any?): { any }
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

return {
	["a player who fights the horde kills, levels up and is offered perks"] = function()
		local config = Fixtures.config()
		config.player.maxHealth = 1e9
		local run = Fixtures.run(1, config)
		local events = advance(run, 60)
		Assert.truthy(count(events, "kill") > 0, "no kills in a minute")
		Assert.truthy(count(events, "levelUp") > 0, "no level-up in a minute")
		Assert.truthy(Assert.findEvent(events, "offer"), "no perk offer")
		Assert.truthy(Run.choosePerk(run, 1, 1))
	end,

	["a player standing still is eventually downed and dies alone"] = function()
		local config = Fixtures.config()
		config.basicAttack.damage = 0
		local run = Fixtures.run(1, config)
		local events = advance(run, 120)
		Assert.truthy(Assert.findEvent(events, "downed"), "never downed")
		Assert.truthy(Assert.findEvent(events, "died"), "never died")
		Assert.truthy(Assert.findEvent(events, "ended"), "the run did not end")
		Assert.truthy(run.ended)
	end,

	["a player who reaches a zone extracts and the run ends"] = function()
		local config = Fixtures.config()
		config.horde.spawnPerSecondAtStart = 0
		config.horde.spawnPerSecondGrowthPerMinute = 0
		local run = Fixtures.run(1, config)
		local events = advance(run, config.run.zonesOpenAtSeconds + 1)
		Assert.truthy(Assert.findEvent(events, "zonesOpened"))
		local zone = run.zones[1]
		events = advance(run, config.run.extractSeconds + 1, { [1] = { x = zone.x, z = zone.z } })
		Assert.truthy(Assert.findEvent(events, "extracted"))
		Assert.truthy(Assert.findEvent(events, "ended"))
		Assert.equal(run.players[1].state, "extracted")
	end,

	["the flood ends the run at its duration"] = function()
		local config = Fixtures.config()
		config.horde.spawnPerSecondAtStart = 0
		config.horde.spawnPerSecondGrowthPerMinute = 0
		local run = Fixtures.run(2, config)
		local events = advance(run, config.run.durationSeconds + 1)
		Assert.truthy(Assert.findEvent(events, "flood"))
		Assert.equal(count(events, "died"), 2)
		Assert.truthy(run.ended)
	end,

	["the same seed replays the same run"] = function()
		local a, b = Fixtures.run(2, nil, 99), Fixtures.run(2, nil, 99)
		advance(a, 90)
		advance(b, 90)
		Assert.equal(#a.enemies, #b.enemies)
		for i, enemy in a.enemies do
			Assert.equal(enemy.x, b.enemies[i].x)
			Assert.equal(enemy.health, b.enemies[i].health)
		end
		Assert.equal(a.players[1].xp, b.players[1].xp)
	end,

	["the horde never exceeds its cap"] = function()
		local config = Fixtures.config()
		config.basicAttack.damage = 0
		config.player.maxHealth = 1e9
		local run = Fixtures.run(1, config)
		advance(run, 8 * 60)
		Assert.equal(#run.enemies, config.horde.maxAlive)
	end,

	["nothing happens after the run ended"] = function()
		local run = Fixtures.run(1)
		run.ended = true
		Run.step(run, STEP, {})
		Assert.equal(run.time, 0)
		Assert.falsy(Run.useActiveSkill(run, 1, nil))
	end,

	["positions that are not finite are ignored"] = function()
		local run = Fixtures.run(1)
		run.players[1].x, run.players[1].z = 5, 6
		Run.step(run, STEP, { [1] = { x = 0 / 0, z = 1 } })
		Run.step(run, STEP, { [1] = { x = math.huge, z = 1 } })
		Assert.equal(run.players[1].x, 5)
		Assert.equal(run.players[1].z, 6)
		advance(run, 30)
	end,

	["positions are held inside the arena"] = function()
		local run = Fixtures.run(1)
		local half = run.config.arena.halfSize
		Run.step(run, STEP, { [1] = { x = half + 500, z = -half - 500 } })
		Assert.equal(run.players[1].x, half)
		Assert.equal(run.players[1].z, -half)
	end,
}
