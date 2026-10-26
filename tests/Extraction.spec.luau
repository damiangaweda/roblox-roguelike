--!strict
local Assert = require("./Assert")
local Extraction = require("../src/shared/Core/Extraction")
local Fixtures = require("./Fixtures")
local Life = require("../src/shared/Core/Life")
local Types = require("../src/shared/Core/Types")

-- Moves the clock to the moment the zones open and opens them.
local function openZones(run: Types.Run)
	run.time = run.config.run.zonesOpenAtSeconds
	Extraction.update(run, 0)
end

-- Advances the clock and extraction by `seconds` in steps of `dt`.
local function advance(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.round(seconds / dt) do
		run.time += dt
		Extraction.update(run, dt)
	end
end

-- Puts player `id` in the middle of the first zone.
local function enterZone(run: Types.Run, id: number)
	local zone = run.zones[1]
	run.players[id].x = zone.x
	run.players[id].z = zone.z
end

local function zoneKey(zone: Types.Zone): string
	return zone.x .. "," .. zone.z
end

return {
	["zones are closed before they open"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		run.time = run.config.run.zonesOpenAtSeconds - 1
		Extraction.update(run, 1)
		Assert.falsy(run.zonesOpen)
		Assert.equal(#run.zones, 0)
		Assert.falsy(Assert.findEvent(run.events, "zonesOpened"))
	end,

	["zones open with distinct points at their time"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		local config = run.config.run
		Assert.truthy(run.zonesOpen)
		Assert.equal(#run.zones, config.zoneCount)
		Assert.truthy(Assert.findEvent(run.events, "zonesOpened"))

		local allowed = {}
		for _, point in config.zonePoints do
			allowed[zoneKey({ x = point.x, z = point.z, radius = 0 })] = true
		end
		local seen = {}
		for _, zone in run.zones do
			Assert.truthy(allowed[zoneKey(zone)], "not a configured point")
			Assert.falsy(seen[zoneKey(zone)], "duplicate zone")
			seen[zoneKey(zone)] = true
			Assert.equal(zone.radius, config.zoneRadius)
		end
	end,

	["zones open only once"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		Extraction.update(run, 1)
		Assert.equal(#run.zones, run.config.run.zoneCount)
		local opened = 0
		for _, event in run.events do
			if event.kind == "zonesOpened" then
				opened += 1
			end
		end
		Assert.equal(opened, 1)
	end,

	["the same seed picks the same zones"] = function()
		local a, b = Fixtures.run(1, nil, 99), Fixtures.run(1, nil, 99)
		openZones(a)
		openZones(b)
		Assert.equal(#a.zones, #b.zones)
		for i, zone in a.zones do
			Assert.equal(zoneKey(zone), zoneKey(b.zones[i]))
		end
	end,

	["different seeds can pick different zones"] = function()
		local first = Fixtures.run(1, nil, 1)
		openZones(first)
		local differs = false
		for seed = 2, 40 do
			local other = Fixtures.run(1, nil, seed)
			openZones(other)
			for i, zone in first.zones do
				if zoneKey(zone) ~= zoneKey(other.zones[i]) then
					differs = true
				end
			end
		end
		Assert.truthy(differs)
	end,

	["fewer points than zoneCount opens one zone per point"] = function()
		local config = Fixtures.config()
		config.run.zonePoints = { { x = 5, z = 5 } }
		local run = Fixtures.run(1, config)
		openZones(run)
		Assert.equal(#run.zones, 1)
		Assert.equal(run.zones[1].x, 5)
	end,

	["a player is extracted after five seconds in a zone"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		enterZone(run, 1)
		local extractSeconds = run.config.run.extractSeconds
		advance(run, extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
		Assert.near(run.players[1].extractProgress, extractSeconds - 1)
		advance(run, 1, 1)
		Assert.equal(run.players[1].state, "extracted")
		local event = Assert.findEvent(run.events, "extracted")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["nobody extracts while the zones are closed"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		run.players[1].x = run.config.run.zonePoints[1].x
		run.players[1].z = run.config.run.zonePoints[1].z
		run.time = 1
		Extraction.update(run, 100)
		Assert.equal(run.players[1].state, "alive")
		Assert.equal(run.players[1].extractProgress, 0)
	end,

	["leaving the zone resets extraction progress"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		enterZone(run, 1)
		advance(run, 3, 1)
		Assert.near(run.players[1].extractProgress, 3)
		run.players[1].x += run.config.run.zoneRadius + 1
		advance(run, 1, 1)
		Assert.equal(run.players[1].extractProgress, 0)
		enterZone(run, 1)
		advance(run, run.config.run.extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
	end,

	["damage interrupts extraction"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		enterZone(run, 1)
		advance(run, 3, 1)
		Life.damage(run, run.players[1], 1)
		Assert.equal(run.players[1].extractProgress, 0)
		advance(run, run.config.run.extractSeconds - 1, 1)
		Assert.equal(run.players[1].state, "alive")
	end,

	["a downed player does not extract"] = function()
		local run = Fixtures.run(1)
		run.players[1].interacting = true
		openZones(run)
		enterZone(run, 1)
		Life.damage(run, run.players[1], run.players[1].maxHealth)
		advance(run, run.config.run.extractSeconds + 1, 1)
		Assert.equal(run.players[1].state, "downed")
		Assert.falsy(Assert.findEvent(run.events, "extracted"))
	end,

	["flood kills alive and downed players and keeps extracted ones"] = function()
		local run = Fixtures.run(4)
		run.players[2].state = "downed"
		run.players[3].state = "extracted"
		run.players[4].state = "dead"
		Extraction.flood(run)
		Assert.truthy(run.flooded)
		Assert.truthy(Assert.findEvent(run.events, "flood"))
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
		run.players[1].interacting = true
		Extraction.flood(run)
		run.events = {}
		run.players[1].state = "alive"
		Extraction.flood(run)
		Assert.equal(run.players[1].state, "alive")
		Assert.equal(#run.events, 0)
	end,

	["standing in a zone without holding interact does not extract"] = function()
		local run = Fixtures.run(1)
		run.time = run.config.run.zonesOpenAtSeconds
		Extraction.update(run, 0)
		local zone = run.zones[1]
		local player = run.players[1]
		player.x, player.z = zone.x, zone.z
		for _ = 1, 20 do
			Extraction.update(run, 0.5)
		end
		Assert.equal(player.state, "alive")
		Assert.equal(player.extractProgress, 0)
	end,
}
