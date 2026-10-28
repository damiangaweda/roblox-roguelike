--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Hero = require("../src/shared/Core/Hero")
local Horde = require("../src/shared/Core/Horde")
local Run = require("../src/shared/Core/Run")
local Shrines = require("../src/shared/Core/Shrines")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

local DT = 0.05

-- Advances the clock and the shrines alone by `seconds`.
local function advance(run: Types.Run, seconds: number)
	for _ = 1, math.round(seconds / DT) do
		run.time += DT
		Shrines.update(run, DT)
	end
end

-- A run on open ground with only the spec's shrines, the hero at the start.
local function openRun(playerCount: number?, seed: number?): Types.Run
	local run = Fixtures.run(playerCount, nil, seed)
	Fixtures.clearObstacles(run)
	run.shrines = {}
	return run
end

-- Holds the interact button at the shrine until it activates.
local function activate(run: Types.Run, id: number, shrine: Types.Shrine)
	Fixtures.place(run, id, shrine.x + 2, shrine.z)
	Run.setInteracting(run, id, true)
	advance(run, run.config.shrines.holdSeconds)
end

return {
	["the nearest usable shrine in reach is found"] = function()
		local run = openRun()
		local player = run.players[1]
		local near = Fixtures.shrine(run, "boon", 50, 0)
		Fixtures.shrine(run, "pact", 50, 6)
		local reach = run.config.shrines.reach
		Fixtures.place(run, 1, 50, 1)
		Assert.equal(Shrines.inReach(run, player), near)
		Fixtures.place(run, 1, 50 - reach - 0.5, 0)
		Assert.equal(Shrines.inReach(run, player), nil, "out of reach")
		Fixtures.place(run, 1, 50, 1)
		near.used = true
		Assert.truthy(Shrines.inReach(run, player) ~= near, "a used shrine is passed over")
		near.used = false
		near.trialEnemies = { 999 }
		Assert.truthy(Shrines.inReach(run, player) ~= near, "a trial under way is passed over")
		near.trialEnemies = nil
		near.readyAt = run.time + 10
		Assert.truthy(Shrines.inReach(run, player) ~= near, "a recharging shrine is passed over")
	end,

	["the chest wins over a shrine beside it"] = function()
		local run = openRun()
		local player = run.players[1]
		local arena = run.arena
		local shrine = Fixtures.shrine(run, "boon", arena.chestX + 3, arena.chestZ)
		Fixtures.place(run, 1, arena.chestX + 1, arena.chestZ)
		Assert.equal(Shrines.inReach(run, player), nil)
		Run.setInteracting(run, 1, true)
		Assert.equal(player.shrineId, nil, "the hold goes to the chest")
		run.chestOpened = true
		Assert.equal(Shrines.inReach(run, player), shrine, "an opened chest no longer wins")
	end,

	["the hold takes its time and a hit resets it"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "boon", 60, 0)
		local hold = run.config.shrines.holdSeconds
		Fixtures.place(run, 1, 62, 0)
		Run.setInteracting(run, 1, true)
		Assert.equal(player.shrineId, shrine.id)
		advance(run, hold - 0.5)
		Assert.near(player.shrineProgress, hold - 0.5, 1e-6)
		Hero.damage(run, player, 1, nil)
		Assert.equal(player.shrineProgress, 0, "the hit reset the hold")
		Assert.equal(player.shrineId, shrine.id, "the hold goes on")
		advance(run, hold - DT)
		Assert.falsy(shrine.used, "not yet")
		advance(run, DT)
		Assert.truthy(shrine.used, "activated after the full hold")
		Assert.equal(player.shrineId, nil)
		Assert.equal(player.shrineProgress, 0)
	end,

	["stepping away or letting go drops the hold"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "boon", 60, 0)
		Fixtures.place(run, 1, 62, 0)
		Run.setInteracting(run, 1, true)
		advance(run, 0.5)
		Fixtures.place(run, 1, 80, 0)
		advance(run, DT)
		Assert.equal(player.shrineId, nil)
		Assert.equal(player.shrineProgress, 0)
		Fixtures.place(run, 1, 62, 0)
		advance(run, 2)
		Assert.falsy(shrine.used, "the button is pressed again")
		Run.setInteracting(run, 1, true)
		advance(run, 0.5)
		Run.setInteracting(run, 1, false)
		Assert.equal(player.shrineId, nil)
		advance(run, 2)
		Assert.falsy(shrine.used)
	end,

	["a boon raises its stat once"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "boon", 60, 0)
		shrine.boon = "might"
		local before = Hero.stats(run, player).damage
		activate(run, 1, shrine)
		Assert.near(Hero.stats(run, player).damage, before + 0.15, 1e-9)
		Assert.equal(player.gifts[1], "might")
		Assert.truthy(shrine.used)
		local event = Assert.findEvent(Run.drainEvents(run), "shrineActivated")
		Assert.equal(event.gift, "might")
		Assert.equal(event.shrineKind, "boon")
		Assert.equal(event.player, 1)
		Assert.equal(event.shrineId, shrine.id)
		-- Used: holding again gives nothing more.
		activate(run, 1, shrine)
		Assert.near(Hero.stats(run, player).damage, before + 0.15, 1e-9)
		Assert.equal(#player.gifts, 1)
	end,

	["a pact raises one stat and lowers another"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "pact", 60, 0)
		shrine.pact = "blood"
		local before = Hero.stats(run, player)
		activate(run, 1, shrine)
		local after = Hero.stats(run, player)
		Assert.near(after.damage, before.damage + 0.3, 1e-9)
		Assert.near(after.maxHealth, before.maxHealth * 0.85, 1e-9)
		Assert.truthy(player.health <= after.maxHealth, "health held to the new maximum")
		Assert.equal(player.gifts[1], "blood")
		Assert.truthy(shrine.used)
		Assert.equal(Assert.findEvent(Run.drainEvents(run), "shrineActivated").gift, "blood")
	end,

	["a pact never takes a scaled stat below a tenth"] = function()
		local run = openRun()
		local player = run.players[1]
		run.config.shrines.pacts[1].downAmount = 5
		local base = Hero.stats(run, player).maxHealth
		local shrine = Fixtures.shrine(run, "pact", 60, 0)
		shrine.pact = run.config.shrines.pacts[1].id
		activate(run, 1, shrine)
		Assert.near(Hero.stats(run, player).maxHealth, base * 0.1, 1e-9)
	end,

	["a trial spawns its ring of the window's grunts and an elite"] = function()
		local run = openRun()
		local config = run.config.shrines
		local shrine = Fixtures.shrine(run, "trial", 60, 0)
		activate(run, 1, shrine)
		local total = config.trialRingCount + config.trialEliteCount
		Assert.equal(#run.enemies, total)
		Assert.equal(#(shrine.trialEnemies :: { number }), total)
		Assert.equal(shrine.trialBy, 1)
		Assert.falsy(shrine.used, "used once the ring is dead")
		local window = Horde.windowKinds(run)
		local elites = 0
		for _, enemy in run.enemies do
			if table.find(run.map.elites, enemy.kind) then
				elites += 1
			else
				Assert.truthy(table.find(window, enemy.kind) ~= nil, "a window grunt")
			end
			Assert.near(
				Geometry.distance(enemy.x, enemy.z, shrine.x, shrine.z),
				config.trialRingRadius,
				1e-6
			)
		end
		Assert.equal(elites, config.trialEliteCount)
		local events = Run.drainEvents(run)
		Assert.equal(Assert.findEvent(events, "trialStarted").count, total)
		Assert.equal(Assert.findEvent(events, "shrineActivated").gift, nil)
		Assert.equal(Shrines.inReach(run, run.players[1]), nil, "no hold while it is fought")
	end,

	["a cleared trial deals a great offer"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "trial", 60, 0)
		activate(run, 1, shrine)
		local last = run.enemies[#run.enemies]
		for _, enemy in table.clone(run.enemies) do
			if enemy ~= last then
				State.removeEnemy(run, enemy)
			end
		end
		advance(run, DT)
		Assert.equal(#(shrine.trialEnemies :: { number }), 1, "one left")
		Assert.equal(#player.offers, 0)
		State.removeEnemy(run, last)
		Run.drainEvents(run)
		advance(run, DT)
		Assert.truthy(shrine.used)
		Assert.equal(shrine.trialEnemies, nil)
		local events = Run.drainEvents(run)
		Assert.equal(Assert.findEvent(events, "trialCompleted").player, 1)
		Assert.truthy(Assert.findEvent(events, "offer") ~= nil)
		Assert.truthy(run.paused, "the solo run waits for the choice")
		local ranks = run.config.shrines.greatOfferRanks
		local maxRank = run.config.ranks.maxRank
		for _, card in player.offers[1] do
			if card.kind == "newSkill" then
				Assert.equal(card.rank, ranks)
			elseif card.kind == "skillRank" then
				Assert.equal(card.rank, math.min(player.skills[1].rank + ranks, maxRank))
			elseif card.kind == "newPassive" then
				Assert.equal(card.rank, math.min(ranks, run.config.passives[card.passive].maxRank))
			end
		end
	end,

	["a trial's offer goes to a living hero when its starter is dead"] = function()
		local run = openRun(2)
		local shrine = Fixtures.shrine(run, "trial", 60, 0)
		activate(run, 1, shrine)
		run.players[1].state = "dead"
		for _, enemy in table.clone(run.enemies) do
			State.removeEnemy(run, enemy)
		end
		advance(run, DT)
		Assert.equal(#run.players[1].offers, 0)
		Assert.equal(#run.players[2].offers, 1)
		Assert.equal(Assert.findEvent(Run.drainEvents(run), "trialCompleted").player, 2)
	end,

	["a spring heals, readies everything and comes back"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "spring", 60, 0)
		player.health = 1
		for index in player.utilityReadyAt do
			player.utilityReadyAt[index] = 999
		end
		player.dashCharges = 0
		player.dashReadyAt = 999
		activate(run, 1, shrine)
		Assert.near(player.health, Hero.stats(run, player).maxHealth, 1e-9)
		for index, readyAt in player.utilityReadyAt do
			Assert.truthy(readyAt <= run.time, "utility " .. index .. " ready")
		end
		Assert.equal(player.dashCharges, run.config.player.dashCharges)
		Assert.falsy(shrine.used, "a spring is never spent")
		local recharge = run.config.shrines.springRechargeSeconds
		Assert.near(shrine.readyAt, run.time + recharge, 1e-9)
		Assert.equal(Shrines.inReach(run, player), nil, "recharging")
		Run.drainEvents(run)
		advance(run, recharge - 1)
		Assert.equal(Fixtures.count(Run.drainEvents(run), "shrineReady"), 0)
		advance(run, 2)
		local ready = Assert.findEvent(Run.drainEvents(run), "shrineReady")
		Assert.equal(ready.shrineId, shrine.id)
		advance(run, 5)
		Assert.equal(Fixtures.count(Run.drainEvents(run), "shrineReady"), 0, "once")
		Assert.equal(Shrines.inReach(run, player), shrine, "back")
	end,

	["a paused run holds no shrine"] = function()
		local run = openRun()
		local player = run.players[1]
		local shrine = Fixtures.shrine(run, "boon", 60, 0)
		Fixtures.place(run, 1, 62, 0)
		Run.setInteracting(run, 1, true)
		run.paused = true
		for _ = 1, 100 do
			Run.step(run, DT, {})
		end
		Assert.equal(player.shrineProgress, 0)
		Assert.falsy(shrine.used)
	end,

	["shrines are dealt and activated the same for a seed"] = function()
		local function play(seed: number): string
			local run = openRun(1, seed)
			local trial = Fixtures.shrine(run, "trial", 60, 0)
			local boon = Fixtures.shrine(run, "boon", -60, 0)
			activate(run, 1, trial)
			local parts = { boon.boon :: string }
			for _, enemy in run.enemies do
				table.insert(parts, string.format("%s@%.4f,%.4f", enemy.kind, enemy.x, enemy.z))
			end
			for _, enemy in table.clone(run.enemies) do
				State.removeEnemy(run, enemy)
			end
			advance(run, DT)
			for _, card in run.players[1].offers[1] do
				table.insert(parts, card.kind .. ":" .. tostring((card :: any).rank))
			end
			return table.concat(parts, ";")
		end
		Assert.equal(play(4), play(4))
		Assert.truthy(play(4) ~= play(5), "another seed, another ring")
	end,

	["gifts are listed in the order taken"] = function()
		local run = openRun()
		local boon = Fixtures.shrine(run, "boon", 60, 0)
		local pact = Fixtures.shrine(run, "pact", -60, 0)
		boon.boon = "wind"
		pact.pact = "haste"
		activate(run, 1, boon)
		activate(run, 1, pact)
		local gifts = run.players[1].gifts
		Assert.equal(#gifts, 2)
		Assert.equal(gifts[1], "wind")
		Assert.equal(gifts[2], "haste")
	end,
}
