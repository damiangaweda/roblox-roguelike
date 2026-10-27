--!strict
local Assert = require("./Assert")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Map = require("../src/shared/Core/Map")
local Protocol = require("../src/shared/Protocol")
local Rng = require("../src/shared/Core/Rng")
local Types = require("../src/shared/Core/Types")

-- A 3 x 2 map with one point, one path and one bush; mapView reads only its ground.
local function smallMap(): Types.Map
	return {
		half = 8,
		points = {
			{
				id = 1,
				x = 1,
				z = -2,
				template = "entry",
				radius = 6,
				paths = { 1 },
				neighbours = { 2 },
				distance = 0,
				level = 1,
				isEntry = true,
				hasZone = false,
				campX = nil,
				campZ = nil,
				cover = { { x = 2, z = 2 } },
				props = {},
			},
		},
		paths = { { id = 1, a = 1, b = 2, halfWidth = 4 } },
		entries = { 1 },
		zonePoints = {},
		nextHop = {},
		hops = {},
		heights = { { 0, 1.25, 23.96 }, { 4, 4.04, 12.3 } },
		heightCell = 8,
		waterLevel = 4,
		fieldCover = { { x = -3.5, z = 7 } },
		pointCells = {},
	}
end

return {
	["fire intent takes a boolean"] = function()
		local intent = Protocol.parseIntent("fire", true) :: any
		Assert.equal(intent.kind, "fire")
		Assert.equal(intent.held, true)
		Assert.equal(Protocol.parseIntent("fire", 1), nil)
		Assert.equal(Protocol.parseIntent("fire", true, 1), nil)
	end,

	["aim intent takes an angle"] = function()
		local intent = Protocol.parseIntent("aim", -1.25) :: any
		Assert.equal(intent.kind, "aim")
		Assert.equal(intent.angle, -1.25)
		Assert.equal(Protocol.parseIntent("aim", 7), nil)
		Assert.equal(Protocol.parseIntent("aim", 0 / 0), nil)
		Assert.equal(Protocol.parseIntent("aim", "1"), nil)
		Assert.equal(Protocol.parseIntent("aim", 1, 2), nil)
	end,

	["skill intent takes a small index, an optional aim and an optional distance"] = function()
		local plain = Protocol.parseIntent("skill", 2) :: any
		Assert.equal(plain.kind, "skill")
		Assert.equal(plain.index, 2)
		Assert.equal(plain.aim, nil)
		Assert.equal(plain.aimDistance, nil)
		local aimed = Protocol.parseIntent("skill", 1, 0.5, 17.5) :: any
		Assert.equal(aimed.aim, 0.5)
		Assert.equal(aimed.aimDistance, 17.5)
		local angled = Protocol.parseIntent("skill", 1, 3) :: any
		Assert.equal(angled.aim, 3)
		Assert.equal(angled.aimDistance, nil)
		Assert.equal(Protocol.parseIntent("skill", 0), nil)
		Assert.equal(Protocol.parseIntent("skill", 1.5), nil)
		Assert.equal(Protocol.parseIntent("skill", 9), nil)
		Assert.equal(Protocol.parseIntent("skill", "1"), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 7), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0 / 0), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0, 0), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0, -5), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0, math.huge), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0, 5000), nil)
		Assert.equal(Protocol.parseIntent("skill", 1, 0, "5"), nil)
		Assert.equal(Protocol.parseIntent("fire", true, nil, 1), nil)
	end,

	["dash and drink take no arguments"] = function()
		Assert.equal((Protocol.parseIntent("dash") :: any).kind, "dash")
		Assert.equal((Protocol.parseIntent("drink") :: any).kind, "drink")
		Assert.equal(Protocol.parseIntent("dash", 1), nil)
		Assert.equal(Protocol.parseIntent("drink", true), nil)
	end,

	["interact and assist take a boolean"] = function()
		Assert.equal((Protocol.parseIntent("interact", false) :: any).held, false)
		Assert.equal((Protocol.parseIntent("assist", true) :: any).enabled, true)
		Assert.equal(Protocol.parseIntent("interact", "yes"), nil)
		Assert.equal(Protocol.parseIntent("assist", nil), nil)
	end,

	["perk intent takes a small whole index"] = function()
		local intent = Protocol.parseIntent("perk", 2) :: any
		Assert.equal(intent.kind, "perk")
		Assert.equal(intent.index, 2)
		Assert.equal(Protocol.parseIntent("perk", 0), nil)
		Assert.equal(Protocol.parseIntent("perk", 1.5), nil)
		Assert.equal(Protocol.parseIntent("perk", 17), nil)
		Assert.equal(Protocol.parseIntent("perk", "1"), nil)
		Assert.equal(Protocol.parseIntent("perk", 1, 2), nil)
	end,

	["unknown intents are rejected"] = function()
		Assert.equal(Protocol.parseIntent("damage", 100), nil)
		Assert.equal(Protocol.parseIntent("activeSkill", 1, 2), nil)
		Assert.equal(Protocol.parseIntent(nil), nil)
	end,

	["enemies survive encoding"] = function()
		local run = Fixtures.run(1)
		local names = Protocol.archetypeNames(run.config)
		local grunt = Fixtures.enemy(run, "grunt", 12.34, -56.78)
		local leader = Fixtures.enemy(run, "campLeader", -1199.9, 1199.9)
		run.time = 5
		grunt.chilledUntil = 6
		grunt.brittleUntil = 7
		grunt.facing = math.pi / 2
		grunt.state = "telegraph"
		grunt.health = grunt.maxHealth / 2
		leader.burningUntil = 6
		leader.buffedUntil = 6
		leader.level = 3
		leader.state = "chase"

		local decoded = Protocol.decodeEnemies(Protocol.encodeEnemies(run, names), names)
		Assert.truthy(decoded)
		assert(decoded, "decoding failed")
		Assert.equal(#decoded, 2)
		Assert.equal(decoded[1].id, grunt.id)
		Assert.equal(decoded[1].archetype, "grunt")
		Assert.near(decoded[1].x, 12.3, 0.05)
		Assert.near(decoded[1].z, -56.8, 0.05)
		Assert.near(decoded[1].facing, math.pi / 2, 0.03)
		Assert.equal(decoded[1].state, "telegraph")
		Assert.near(decoded[1].health, 0.5, 0.01)
		Assert.equal(decoded[1].chilled, true)
		Assert.equal(decoded[1].burning, false)
		Assert.equal(decoded[1].brittle, true)
		Assert.equal(decoded[1].buffed, false)
		Assert.equal(decoded[2].archetype, "campLeader")
		Assert.equal(decoded[2].level, 3)
		Assert.near(decoded[2].x, -1199.9, 0.05)
		Assert.near(decoded[2].z, 1199.9, 0.05)
		Assert.equal(decoded[2].state, "chase")
		Assert.equal(decoded[2].burning, true)
		Assert.equal(decoded[2].buffed, true)
		Assert.equal(decoded[2].chilled, false)
	end,

	["a malformed enemy buffer is rejected"] = function()
		local names = Protocol.archetypeNames(Fixtures.config())
		Assert.equal(Protocol.decodeEnemies("not a buffer", names), nil)
		Assert.equal(Protocol.decodeEnemies(buffer.create(1), names), nil)
		local short = buffer.create(2)
		buffer.writeu16(short, 0, 3)
		Assert.equal(Protocol.decodeEnemies(short, names), nil)
		local empty = buffer.create(2)
		Assert.equal(#(Protocol.decodeEnemies(empty, names) :: any), 0)
	end,

	["projectiles survive encoding"] = function()
		local run = Fixtures.run(1)
		local kinds = Protocol.projectileKinds(run.config)
		Assert.truthy(table.find(kinds, "fireball"))
		Assert.truthy(table.find(kinds, "spitter"))
		table.insert(run.projectiles, {
			id = 7,
			owner = "player",
			source = 1,
			kind = "fireball",
			x = 10.26,
			z = -3.14,
			dirX = 0,
			dirZ = 1,
			speed = 50,
			remaining = 20,
			damage = 30,
			radius = 7,
			knockback = 4,
			tags = { "fire" },
			statusFactor = 1,
		})
		table.insert(run.projectiles, {
			id = 8,
			owner = "enemy",
			source = 3,
			kind = "spitter",
			x = 0,
			z = 0,
			dirX = -1,
			dirZ = 0,
			speed = 32,
			remaining = 20,
			damage = 12,
			radius = 0,
			knockback = 0,
			tags = {},
			statusFactor = 1,
		})
		local decoded = Protocol.decodeProjectiles(Protocol.encodeProjectiles(run, kinds), kinds)
		assert(decoded, "decoding failed")
		Assert.equal(#decoded, 2)
		Assert.equal(decoded[1].id, 7)
		Assert.equal(decoded[1].owner, "player")
		Assert.equal(decoded[1].kind, "fireball")
		Assert.near(decoded[1].x, 10.3, 0.05)
		Assert.near(decoded[1].z, -3.1, 0.05)
		Assert.near(decoded[1].facing, math.pi / 2, 0.03)
		Assert.equal(decoded[2].owner, "enemy")
		Assert.equal(decoded[2].kind, "spitter")
		Assert.near(decoded[2].facing, math.pi, 0.03)
		Assert.equal(Protocol.decodeProjectiles(buffer.create(5), kinds), nil)
	end,

	["the world view lists players in id order with potions and drinks"] = function()
		local run = Fixtures.run(3)
		run.players[3].potions = 2
		run.players[2].drinkingUntil = 1.5
		run.time = 1
		local view = Protocol.worldView(run)
		Assert.equal(#view.players, 3)
		Assert.equal(view.players[1].id, 1)
		Assert.equal(view.players[3].potions, 2)
		Assert.near(view.players[2].drinkingFor, 0.5)
		Assert.equal(view.players[1].drinkingFor, 0)
		Assert.equal(#view.zones, #run.zones)
	end,

	["the map view carries only the ground, its heights to the tenth"] = function()
		local view = Protocol.mapView(smallMap())
		Assert.equal(view.rows, 2)
		Assert.equal(view.cols, 3)
		Assert.equal(view.half, 8)
		Assert.equal(view.heightCell, 8)
		Assert.equal(view.waterLevel, 4)
		local heights = Protocol.decodeHeights(view)
		assert(heights, "decoding failed")
		Assert.equal(#heights, 2)
		Assert.equal(#heights[1], 3)
		Assert.near(heights[1][1], 0, 1e-9)
		Assert.near(heights[1][2], 1.3, 1e-9)
		Assert.near(heights[1][3], 24, 1e-9)
		Assert.near(heights[2][2], 4, 1e-9)
		Assert.near(heights[2][3], 12.3, 1e-9)
		-- Nothing about the points travels: a zone not yet open stays hidden.
		local fields = {}
		for key in view :: any do
			table.insert(fields, key)
		end
		table.sort(fields)
		Assert.equal(table.concat(fields, ","), "cols,half,heightCell,heights,rows,waterLevel")
	end,

	["a map view whose heights do not match its grid is rejected"] = function()
		local view = Protocol.mapView(smallMap())
		view.heights = buffer.create(10)
		Assert.equal(Protocol.decodeHeights(view), nil)
		local other = Protocol.mapView(smallMap())
		other.rows = 3
		Assert.equal(Protocol.decodeHeights(other), nil)
		local missing = Protocol.mapView(smallMap());
		(missing :: any).heights = "not a buffer"
		Assert.equal(Protocol.decodeHeights(missing), nil)
	end,

	["the client's heights match the core's at nodes and midpoints"] = function()
		local map = Map.generate(Config, Rng.new(7), 2)
		local view = Protocol.mapView(map)
		local heights = Protocol.decodeHeights(view)
		assert(heights, "decoding failed")
		local function check(x: number, z: number)
			local drawn =
				Protocol.heightAt(heights, view.heightCell, view.half, view.waterLevel, x, z)
			-- Heights travel rounded to a tenth of a stud.
			Assert.near(drawn, Map.heightAt(map, x, z), 0.051)
		end
		local cell = map.heightCell
		for row = 1, #map.heights do
			for col = 1, #map.heights[1] do
				local x = -map.half + (col - 1) * cell
				local z = -map.half + (row - 1) * cell
				check(x, z)
				check(x + cell / 2, z + cell / 2)
				check(x + cell / 3, z)
			end
		end
	end,

	["private events name their player"] = function()
		Assert.truthy(Protocol.isPrivate({ kind = "offer", player = 4, perks = {} }))
		Assert.truthy(Protocol.isPrivate({ kind = "pickedUp", player = 4, pickup = "potion" }))
		Assert.truthy(Protocol.isPrivate({ kind = "knockback", player = 4, dx = 1, dz = 0 }))
		Assert.falsy(Protocol.isPrivate({ kind = "died", player = 4 }))
		Assert.falsy(Protocol.isPrivate({ kind = "flood" }))
		Assert.equal(Protocol.eventPlayer({ kind = "levelUp", player = 9, level = 2 }), 9)
		Assert.equal(Protocol.eventPlayer({ kind = "ended" }), nil)
	end,
}
