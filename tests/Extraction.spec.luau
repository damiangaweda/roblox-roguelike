--!strict
local Assert = require("./Assert")
local Extraction = require("../src/shared/Core/Extraction")
local Fixtures = require("./Fixtures")
local Types = require("../src/shared/Core/Types")

local DT = 0.1

-- Advances the clock and extraction by `seconds` in steps of DT.
local function advance(run: Types.Run, seconds: number)
	for _ = 1, math.round(seconds / DT) do
		run.time += DT
		Extraction.update(run, DT)
	end
end

local function atChest(run: Types.Run, id: number, offset: number?)
	Fixtures.place(run, id, run.arena.chestX + (offset or 0), run.arena.chestZ)
end

-- Player `id` holds the spell, as if it had opened the chest.
local function withSpell(run: Types.Run, id: number): Types.Player
	local player = run.players[id]
	player.hasSpell = true
	run.chestOpened = true
	return player
end

return {
	["the compass turns on at its minute, once"] = function()
		local run = Fixtures.run(1, nil, 5)
		local at = run.config.extraction.compassMinute * 60
		advance(run, at - 1)
		Assert.falsy(run.compassOn, "before the minute")
		Assert.equal(Fixtures.count(run.events, "compass"), 0)
		advance(run, 2)
		Assert.truthy(run.compassOn, "at the minute")
		local event = Assert.findEvent(run.events, "compass")
		Assert.near(event.x, run.arena.chestX)
		Assert.near(event.z, run.arena.chestZ)
		advance(run, 5)
		Assert.equal(Fixtures.count(run.events, "compass"), 1)
	end,

	["opening takes the hold within reach for its seconds"] = function()
		local run = Fixtures.run(1, nil, 5)
		local config = run.config.extraction
		atChest(run, 1, config.openRadius - 0.5)
		Extraction.setOpening(run, 1, true)
		advance(run, config.openSeconds - 2 * DT)
		Assert.falsy(run.chestOpened, "not yet")
		Assert.truthy(run.players[1].openProgress > 0)
		advance(run, 3 * DT)
		Assert.truthy(run.chestOpened)
		Assert.truthy(run.players[1].hasSpell)
		Assert.equal(Fixtures.count(run.events, "chestOpened"), 1)
		Assert.equal(Assert.findEvent(run.events, "chestOpened").player, 1)
	end,

	["releasing or stepping away resets the hold"] = function()
		local run = Fixtures.run(1, nil, 5)
		local config = run.config.extraction
		local player = run.players[1]
		atChest(run, 1)
		Extraction.setOpening(run, 1, true)
		advance(run, config.openSeconds / 2)
		Extraction.setOpening(run, 1, false)
		advance(run, DT)
		Assert.equal(player.openProgress, 0, "released")
		Extraction.setOpening(run, 1, true)
		advance(run, config.openSeconds / 2)
		atChest(run, 1, config.openRadius + 1)
		advance(run, DT)
		Assert.equal(player.openProgress, 0, "stepped away")
		atChest(run, 1)
		advance(run, config.openSeconds - 2 * DT)
		Assert.falsy(run.chestOpened, "the hold started over")
	end,

	["the chest gives the spell to its opener only, once"] = function()
		local run = Fixtures.run(2, nil, 5)
		local config = run.config.extraction
		atChest(run, 1)
		atChest(run, 2, config.openRadius + 5)
		Extraction.setOpening(run, 1, true)
		Extraction.setOpening(run, 2, true)
		advance(run, config.openSeconds + DT)
		Assert.truthy(run.players[1].hasSpell)
		Assert.falsy(run.players[2].hasSpell)
		atChest(run, 2)
		advance(run, config.openSeconds * 2)
		Assert.falsy(run.players[2].hasSpell, "the chest is open")
		Assert.equal(run.players[2].openProgress, 0)
		Assert.equal(Fixtures.count(run.events, "chestOpened"), 1)
	end,

	["a dead player does not open the chest"] = function()
		local run = Fixtures.run(1, nil, 5)
		atChest(run, 1)
		run.players[1].state = "dead"
		Extraction.setOpening(run, 1, true)
		advance(run, run.config.extraction.openSeconds * 2)
		Assert.falsy(run.chestOpened)
	end,

	["the cast opens a portal at the caster after its seconds"] = function()
		local run = Fixtures.run(1, nil, 5)
		local config = run.config.extraction
		withSpell(run, 1)
		Fixtures.place(run, 1, 30, -20)
		Assert.truthy(Extraction.castSpell(run, 1))
		Assert.equal(Assert.findEvent(run.events, "castStarted").seconds, config.castSeconds)
		advance(run, config.castSeconds - 2 * DT)
		Assert.equal(run.portal, nil, "still casting")
		advance(run, 3 * DT)
		local portal = run.portal
		assert(portal, "the portal opened")
		Assert.near(portal.x, 30)
		Assert.near(portal.z, -20)
		Assert.equal(run.players[1].castingUntil, nil)
		local event = Assert.findEvent(run.events, "portalOpened")
		Assert.near(event.x, 30)
		Assert.equal(event.seconds, config.portalSeconds)
	end,

	["the cast needs the spell and starts once while no portal stands"] = function()
		local run = Fixtures.run(2, nil, 5)
		local config = run.config.extraction
		Assert.falsy(Extraction.castSpell(run, 1), "no spell")
		withSpell(run, 1)
		Assert.falsy(Extraction.castSpell(run, 2), "the other player has none")
		Assert.truthy(Extraction.castSpell(run, 1))
		Assert.falsy(Extraction.castSpell(run, 1), "already casting")
		advance(run, config.castSeconds + DT)
		Assert.truthy(run.portal)
		Assert.falsy(Extraction.castSpell(run, 1), "a portal stands")
		Assert.equal(Fixtures.count(run.events, "castStarted"), 1)
		run.players[1].state = "dead"
		run.portal = nil
		Assert.falsy(Extraction.castSpell(run, 1), "dead")
	end,

	["the portal closes after its seconds and the spell can be cast again"] = function()
		local run = Fixtures.run(1, nil, 5)
		local config = run.config.extraction
		withSpell(run, 1)
		Extraction.castSpell(run, 1)
		advance(run, config.castSeconds + DT)
		Assert.truthy(run.portal)
		advance(run, config.portalSeconds - 2 * DT)
		Assert.truthy(run.portal, "still standing")
		advance(run, 3 * DT)
		Assert.equal(run.portal, nil)
		Assert.equal(Fixtures.count(run.events, "portalClosed"), 1)
		Assert.truthy(run.players[1].hasSpell, "the spell stays")
		Assert.truthy(Extraction.castSpell(run, 1))
	end,

	["entering needs an open portal within reach and extracts"] = function()
		local run = Fixtures.run(2, nil, 5)
		local config = run.config.extraction
		Assert.falsy(Extraction.enterPortal(run, 1), "no portal")
		withSpell(run, 1)
		Fixtures.place(run, 1, 10, 10)
		Extraction.castSpell(run, 1)
		advance(run, config.castSeconds + DT)
		Fixtures.place(run, 2, 10 + config.portalRadius + 1, 10)
		Assert.falsy(Extraction.enterPortal(run, 2), "too far")
		Assert.equal(run.players[2].state, "alive")
		Fixtures.place(run, 2, 10 + config.portalRadius - 0.5, 10)
		Assert.truthy(Extraction.enterPortal(run, 2))
		Assert.equal(run.players[2].state, "extracted")
		Assert.equal(Assert.findEvent(run.events, "extracted").player, 2)
		Assert.falsy(Extraction.enterPortal(run, 2), "already gone")
		Assert.truthy(Extraction.enterPortal(run, 1))
		Assert.equal(Fixtures.count(run.events, "extracted"), 2)
	end,
}
