--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Life = require("../src/shared/Core/Life")
local Run = require("../src/shared/Core/Run")
local Types = require("../src/shared/Core/Types")

-- Advances the clock and the life rules by `seconds` in steps of `dt`.
local function advance(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.round(seconds / dt) do
		run.time += dt
		Life.update(run, dt)
	end
end

-- Two players: player 1 downed at the origin, player 2 alive beside them and
-- holding the interact button.
local function downedPair(): (Types.Run, Types.Player, Types.Player)
	local run = Fixtures.run(2)
	local downed, helper = run.players[1], run.players[2]
	helper.x = 3
	helper.interacting = true
	Life.damage(run, downed, downed.maxHealth)
	run.events = {}
	return run, downed, helper
end

return {
	["damage reduces health and emits playerHurt"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		Life.damage(run, player, 30)
		Assert.equal(player.health, player.maxHealth - 30)
		Assert.equal(player.state, "alive")
		local event = Assert.findEvent(run.events, "playerHurt")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
		Assert.equal(event.amount, 30)
		Assert.falsy(Assert.findEvent(run.events, "downed"))
	end,

	["zero health downs the player"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		run.time = 12
		Life.damage(run, player, player.maxHealth + 50)
		Assert.equal(player.health, 0)
		Assert.equal(player.state, "downed")
		Assert.equal(player.downedAt, 12)
		Assert.equal(player.reviveProgress, 0)
		local event = Assert.findEvent(run.events, "downed")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["damage to a downed player does nothing"] = function()
		local run, downed = downedPair()
		Life.damage(run, downed, 10)
		Assert.equal(downed.health, 0)
		Assert.equal(downed.state, "downed")
		Assert.equal(#run.events, 0)
	end,

	["damage to a dead player does nothing"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.state = "dead"
		player.health = 0
		Life.damage(run, player, 10)
		Assert.equal(player.health, 0)
		Assert.equal(#run.events, 0)
	end,

	["damage that is not positive does nothing"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		Life.damage(run, player, 0)
		Life.damage(run, player, -5)
		Assert.equal(player.health, player.maxHealth)
		Assert.equal(#run.events, 0)
	end,

	["damage resets extraction progress"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.extractProgress = 3
		Life.damage(run, player, 5)
		Assert.equal(player.extractProgress, 0)
	end,

	["a downed player is revived after three seconds near an alive one"] = function()
		local run, downed, helper = downedPair()
		local config = run.config.player
		advance(run, config.reviveSeconds - 0.5, 0.5)
		Assert.equal(downed.state, "downed")
		advance(run, 0.5, 0.5)
		Assert.equal(downed.state, "alive")
		Assert.equal(downed.health, downed.maxHealth * config.reviveHealthFraction)
		Assert.equal(downed.downedAt, nil)
		Assert.equal(downed.reviveProgress, 0)
		local event = Assert.findEvent(run.events, "revived")
		Assert.truthy(event)
		Assert.equal(event.player, downed.id)
		Assert.equal(event.by, helper.id)
	end,

	["the nearest alive player is credited with the revive"] = function()
		local run, downed = downedPair()
		run.players[2].x = 6
		Run.addPlayer(run, 3, 1, 0).interacting = true
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "alive")
		Assert.equal(Assert.findEvent(run.events, "revived").by, 3)
	end,

	["a player out of revive range does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.x = run.config.player.reviveRadius + 1
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "downed")
		Assert.equal(downed.reviveProgress, 0)
	end,

	["a downed or dead player does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.state = "downed"
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "downed")
		helper.state = "dead"
		advance(run, 1, 0.5)
		Assert.equal(downed.state, "downed")
	end,

	["moving away resets revive progress"] = function()
		local run, downed, helper = downedPair()
		advance(run, 2, 0.5)
		Assert.near(downed.reviveProgress, 2)
		helper.x = 100
		advance(run, 0.5, 0.5)
		Assert.equal(downed.reviveProgress, 0)
		helper.x = 3
		advance(run, 2, 0.5)
		Assert.equal(downed.state, "downed")
	end,

	["bleeding out pauses while being revived"] = function()
		local run, downed, helper = downedPair()
		local config = run.config.player
		-- Bleed for 10 s alone, revive for 2 s, then be left alone again.
		helper.x = 100
		advance(run, 10, 0.5)
		helper.x = 3
		advance(run, 2, 0.5)
		helper.x = 100
		-- 10 s bled; 5 s remain, not the 3 s that a running clock would leave.
		advance(run, config.downedSeconds - 10 - 0.5, 0.5)
		Assert.equal(downed.state, "downed")
		advance(run, 0.5, 0.5)
		Assert.equal(downed.state, "dead")
	end,

	["a player alone dies after fifteen seconds"] = function()
		local run, downed = downedPair()
		run.players[2] = nil
		local downedSeconds = run.config.player.downedSeconds
		advance(run, downedSeconds - 1, 1)
		Assert.equal(downed.state, "downed")
		Assert.falsy(Assert.findEvent(run.events, "died"))
		advance(run, 1, 1)
		Assert.equal(downed.state, "dead")
		local event = Assert.findEvent(run.events, "died")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["standing beside a downed player without holding interact does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.interacting = false
		advance(run, run.config.player.reviveSeconds + 1, 0.5)
		Assert.equal(downed.state, "downed")
		Assert.equal(downed.reviveProgress, 0)
	end,

	["letting go of interact resets revive progress"] = function()
		local run, downed, helper = downedPair()
		advance(run, run.config.player.reviveSeconds / 2, 0.5)
		Assert.truthy(downed.reviveProgress > 0)
		helper.interacting = false
		advance(run, 0.5, 0.5)
		Assert.equal(downed.reviveProgress, 0)
	end,
}
