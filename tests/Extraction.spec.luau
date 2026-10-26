--!strict
local Assert = require("./Assert")
local Extraction = require("../src/shared/Core/Extraction")
local Fixtures = require("./Fixtures")
local Life = require("../src/shared/Core/Life")
local Types = require("../src/shared/Core/Types")

-- Advances the clock and extraction by `seconds` in steps of `dt`.
local function advance(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.round(seconds / dt) do
		run.time += dt
		Extraction.update(run, dt)
	end
end

-- Puts player `id` in the middle of zone `index`, holding the interact button.
local function enterZone(run: Types.Run, id: number, index: number?)
	local zone = run.zones[index or 1]
	Fixtures.place(run, run.players[id], zone.x, zone.z)
	run.players[id].interacting = true
end

local function count(events: { Types.Event }, kind: string): number
	local n = 0
	for _, event in events do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end

return {
	["zones exist from the start of the run, at the map's zone points"] = function()
		for _, players in { 1, 4, 8, 12 } do
			for seed = 1, 10 do
				local run = Fixtures.run(players, nil, seed)
				local label = "seed " .. seed .. ", " .. players .. " players"
				Assert.truthy(#run.zones > 0, "no zones, " .. label)
				Assert.equal(run.time, 0)
				Assert.equal(#run.zones, #run.map.zonePoints, label)
				for index, id in run.map.zonePoints do
					local point = run.map.points[id]
					local zone = run.zones[index]
					Assert.equal(zone.x, point.x, label)
					Assert.equal(zone.z, point.z, label)
					Assert.equal(zone.radius, run.config.map.zoneRadius, label)
				end
			end
		end
	end,

	["a player is extracted after five seconds in a zone"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		local extractSeconds = run.config.run.extractSeconds
		advance(run, extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
		Assert.near(run.players[1].extractProgress, extractSeconds - 1)
		Assert.falsy(Assert.findEvent(run.events, "extracted"))
		advance(run, 1, 1)
		Assert.equal(run.players[1].state, "extracted")
		local event = Assert.findEvent(run.events, "extracted")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["every zone extracts"] = function()
		local run = Fixtures.run(1)
		for index = 1, #run.zones do
			run.players[1].state = "alive"
			run.players[1].extractProgress = 0
			enterZone(run, 1, index)
			advance(run, run.config.run.extractSeconds, 1)
			Assert.equal(run.players[1].state, "extracted", "zone " .. index)
		end
	end,

	["the zone reaches as far as its radius"] = function()
		local run = Fixtures.run(1)
		local zone = run.zones[1]
		local radius = run.config.map.zoneRadius
		enterZone(run, 1)
		run.players[1].x = zone.x + radius
		advance(run, 1, 1)
		Assert.near(run.players[1].extractProgress, 1)
		run.players[1].x = zone.x + radius + 0.1
		advance(run, 1, 1)
		Assert.equal(run.players[1].extractProgress, 0)
	end,

	["outside a zone nothing happens"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		-- Entries hold no zone.
		Assert.falsy(run.map.points[run.map.zonePoints[1]].isEntry)
		player.interacting = true
		advance(run, run.config.run.extractSeconds * 2, 1)
		Assert.equal(player.state, "alive")
		Assert.equal(player.extractProgress, 0)
		Assert.falsy(Assert.findEvent(run.events, "extracted"))
	end,

	["standing in a zone without holding interact does not extract"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		run.players[1].interacting = false
		advance(run, run.config.run.extractSeconds * 2, 0.5)
		Assert.equal(run.players[1].state, "alive")
		Assert.equal(run.players[1].extractProgress, 0)
	end,

	["letting go of interact resets extraction progress"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		advance(run, 3, 1)
		Assert.near(run.players[1].extractProgress, 3)
		run.players[1].interacting = false
		advance(run, 1, 1)
		Assert.equal(run.players[1].extractProgress, 0)
		run.players[1].interacting = true
		advance(run, run.config.run.extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
	end,

	["leaving the zone resets extraction progress"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		advance(run, 3, 1)
		Assert.near(run.players[1].extractProgress, 3)
		run.players[1].x += run.config.map.zoneRadius + 1
		advance(run, 1, 1)
		Assert.equal(run.players[1].extractProgress, 0)
		enterZone(run, 1)
		advance(run, run.config.run.extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
	end,

	["a hit interrupts extraction"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		advance(run, 3, 1)
		Assert.near(run.players[1].extractProgress, 3)
		Life.damage(run, run.players[1], 1)
		Assert.equal(run.players[1].extractProgress, 0)
		advance(run, run.config.run.extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
		advance(run, 1, 1)
		Assert.equal(run.players[1].state, "extracted")
	end,

	["a downed player does not extract"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		Life.damage(run, run.players[1], run.players[1].maxHealth)
		advance(run, run.config.run.extractSeconds + 1, 1)
		Assert.equal(run.players[1].state, "downed")
		Assert.falsy(Assert.findEvent(run.events, "extracted"))
	end,

	["an extracted player is not extracted again"] = function()
		local run = Fixtures.run(1)
		enterZone(run, 1)
		advance(run, run.config.run.extractSeconds + 5, 1)
		Assert.equal(count(run.events, "extracted"), 1)
	end,

	["flood kills alive and downed players and keeps extracted ones"] = function()
		local run = Fixtures.run(4)
		run.players[2].state = "downed"
		run.players[3].state = "extracted"
		run.players[4].state = "dead"
		Extraction.flood(run)
		Assert.truthy(run.flooded)
		Assert.equal(count(run.events, "flood"), 1)
		Assert.equal(run.players[1].state, "dead")
		Assert.equal(run.players[2].state, "dead")
		Assert.equal(run.players[3].state, "extracted")
		Assert.equal(run.players[4].state, "dead")
		local died = {}
		for _, event in run.events do
			if event.kind == "died" then
				table.insert(died, event.player)
			end
		end
		Assert.equal(#died, 2)
		Assert.equal(died[1], 1)
		Assert.equal(died[2], 2)
	end,

	["the flood happens once"] = function()
		local run = Fixtures.run(1)
		Extraction.flood(run)
		run.events = {}
		run.players[1].state = "alive"
		Extraction.flood(run)
		Assert.equal(run.players[1].state, "alive")
		Assert.equal(#run.events, 0)
	end,
}
