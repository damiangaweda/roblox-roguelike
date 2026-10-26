--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Rng = require("../src/shared/Core/Rng")
local Types = require("../src/shared/Core/Types")
local World = require("../src/shared/Core/World")

local PLAYER_COUNTS = { 1, 4, 8, 12 }
local SEEDS = 20

local function generate(config: Types.Config, seed: number, players: number): Types.World
	return World.generate(config, Rng.new(seed), players)
end

-- Calls `check` with a world for every seed and player count, and a label for
-- failure messages.
local function eachWorld(check: (
	world: Types.World,
	config: Types.Config,
	label: string,
	players: number
) -> ())
	local config = Fixtures.config()
	for _, players in PLAYER_COUNTS do
		for seed = 1, SEEDS do
			check(
				generate(config, seed, players),
				config,
				"seed " .. seed .. ", " .. players .. " players",
				players
			)
		end
	end
end

local function deepestDistance(world: Types.World): number
	local deepest = 0
	for _, room in world.rooms do
		deepest = math.max(deepest, room.distance)
	end
	return deepest
end

-- A string that is equal for two worlds exactly when their rooms and
-- corridors are.
local function signature(world: Types.World): string
	local parts = {}
	for _, room in world.rooms do
		table.insert(
			parts,
			string.format(
				"R%d:%d,%d:%s:%s:%s",
				room.id,
				room.x,
				room.z,
				room.template,
				table.concat(room.neighbours, "/"),
				table.concat(room.corridors, "/")
			)
		)
	end
	for _, corridor in world.corridors do
		table.insert(
			parts,
			string.format(
				"C%d:%d-%d:%g,%g,%g,%g",
				corridor.id,
				corridor.roomA,
				corridor.roomB,
				corridor.x,
				corridor.z,
				corridor.halfWidth,
				corridor.halfDepth
			)
		)
	end
	return table.concat(parts, ";")
end

-- The distance from (x, z) to the nearest room or corridor, by brute force.
local function distanceToWalkable(world: Types.World, x: number, z: number): number
	local best = math.huge
	local function consider(rect: Types.Rect)
		local cx, cz = Geometry.clampToRect(rect, x, z)
		best = math.min(best, Geometry.distance(x, z, cx, cz))
	end
	for _, room in world.rooms do
		consider(room)
	end
	for _, corridor in world.corridors do
		consider(corridor)
	end
	return best
end

local function templateById(config: Types.Config, id: string): Types.RoomTemplate?
	for _, template in config.world.templates do
		if template.id == id then
			return template
		end
	end
	return nil
end

return {

	["reach stops at the first wall and clearPath says whether there is one"] = function()
		local world = World.generate(Fixtures.config(), Rng.new(3), 4)
		local room = world.rooms[world.startRooms[1]]
		local x, z = room.x + 3, room.z - room.halfDepth + 2
		-- North through the wall: the reach ends inside the room.
		local reach = World.reach(world, x, z, x, z - 20)
		Assert.truthy(reach >= 1 and reach <= 2 + 1e-9, "reach " .. reach)
		Assert.falsy(World.clearPath(world, x, z, x, z - 20))
		-- Across the room: clear.
		Assert.truthy(World.clearPath(world, x, z, room.x - 3, room.z + room.halfDepth - 2))
		Assert.near(World.reach(world, x, z, x, z + 10), 10)
	end,
	["every room is reachable from every other"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				Assert.truthy(
					room.distance < math.huge,
					"unreachable room " .. room.id .. ", " .. label
				)
				for _, other in world.rooms do
					local hops = world.hops[room.id][other.id]
					Assert.truthy(hops < math.huge, "no path, " .. label)
					Assert.equal(hops, world.hops[other.id][room.id], "hops symmetric, " .. label)
				end
				Assert.equal(world.hops[room.id][room.id], 0)
			end
		end)
	end,

	["hops and next hops agree with the corridors"] = function()
		eachWorld(function(world, _, label)
			for _, from in world.rooms do
				for _, neighbour in from.neighbours do
					Assert.equal(world.hops[from.id][neighbour], 1, label)
				end
				for _, to in world.rooms do
					if from.id ~= to.id then
						local next = world.nextHop[from.id][to.id]
						Assert.truthy(
							table.find(from.neighbours, next),
							"not a neighbour, " .. label
						)
						Assert.equal(
							world.hops[next][to.id],
							world.hops[from.id][to.id] - 1,
							"next hop does not approach, " .. label
						)
					end
				end
				Assert.equal(world.nextHop[from.id][from.id], from.id)
			end
		end)
	end,

	["the room count follows the player count within its limits"] = function()
		local config = Fixtures.config()
		local settings = config.world
		local counts = { 1, 2, 3, 4, 5, 8, 12, 20, 100 }
		for _, players in counts do
			local expected =
				math.clamp(settings.roomsPerPlayer * players, settings.minRooms, settings.maxRooms)
			for seed = 1, 5 do
				Assert.equal(
					#generate(config, seed, players).rooms,
					expected,
					players .. " players"
				)
			end
		end
		Assert.equal(#generate(config, 1, 1).rooms, settings.minRooms)
		Assert.equal(#generate(config, 1, 100).rooms, settings.maxRooms)
	end,

	["start rooms are leaves, as many as the players need"] = function()
		eachWorld(function(world, config, label, players)
			local expected = math.clamp(
				math.ceil(players / config.world.playersPerStart),
				1,
				config.world.maxStarts
			)
			Assert.equal(#world.startRooms, expected, label)
			for _, id in world.startRooms do
				local room = world.rooms[id]
				Assert.equal(#room.neighbours, 1, "start room " .. id .. " is no leaf, " .. label)
				Assert.truthy(room.isStart)
				Assert.equal(room.distance, 0)
			end
			local flagged = 0
			for _, room in world.rooms do
				if room.isStart then
					flagged += 1
				end
			end
			Assert.equal(flagged, #world.startRooms, label)
		end)
	end,

	["start rooms are at least the minimum distance apart"] = function()
		eachWorld(function(world, config, label)
			for i, a in world.startRooms do
				for j = i + 1, #world.startRooms do
					local hops = world.hops[a][world.startRooms[j]]
					Assert.truthy(
						hops >= config.world.minStartDistance,
						"starts " .. hops .. " apart, " .. label
					)
				end
			end
		end)
	end,

	["room distance is the hops to the nearest start room"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				local nearest = math.huge
				for _, start in world.startRooms do
					nearest = math.min(nearest, world.hops[room.id][start])
				end
				Assert.equal(room.distance, nearest, "room " .. room.id .. ", " .. label)
			end
		end)
	end,

	["room levels follow the distance from the starts"] = function()
		eachWorld(function(world, config, label)
			local maxLevel = config.world.maxLevel
			local deepest = deepestDistance(world)
			local deepestLevel = 0
			for _, room in world.rooms do
				Assert.truthy(room.level >= 1 and room.level <= maxLevel, label)
				deepestLevel = math.max(deepestLevel, room.level)
				if room.isStart then
					Assert.equal(room.level, 1, "start room level, " .. label)
				else
					local expected =
						math.clamp(math.ceil(room.distance / deepest * maxLevel), 1, maxLevel)
					Assert.equal(room.level, expected, "room " .. room.id .. ", " .. label)
					if room.distance == deepest then
						Assert.equal(room.level, maxLevel, "deepest room, " .. label)
					end
					if room.distance == 1 and deepest >= maxLevel then
						Assert.equal(room.level, 1, "room next to a start, " .. label)
					end
				end
			end
			Assert.equal(deepestLevel, maxLevel, "no room of the top level, " .. label)
		end)
	end,

	["extraction zones sit in deep rooms outside the start rooms"] = function()
		eachWorld(function(world, config, label, players)
			local settings = config.world
			local expected = math.clamp(
				math.ceil(players / settings.playersPerZone),
				settings.minZones,
				settings.maxZones
			)
			Assert.equal(#world.zoneRooms, expected, label)
			local half = math.floor(deepestDistance(world) / 2)
			local seen = {}
			for _, id in world.zoneRooms do
				local room = world.rooms[id]
				Assert.falsy(seen[id], "zone room repeated, " .. label)
				seen[id] = true
				Assert.falsy(room.isStart, "zone in a start room, " .. label)
				Assert.truthy(room.hasZone, label)
				Assert.truthy(room.distance >= 1, label)
				Assert.truthy(
					room.distance >= half,
					"zone room " .. id .. " too shallow, " .. label
				)
			end
			local flagged = 0
			for _, room in world.rooms do
				if room.hasZone then
					flagged += 1
				end
			end
			Assert.equal(flagged, #world.zoneRooms, label)
		end)
	end,

	["the same seed makes the same world"] = function()
		local config = Fixtures.config()
		for _, players in PLAYER_COUNTS do
			for seed = 1, 10 do
				Assert.equal(
					signature(generate(config, seed, players)),
					signature(generate(config, seed, players)),
					"seed " .. seed .. ", " .. players .. " players"
				)
			end
		end
	end,

	["different seeds make different worlds"] = function()
		local config = Fixtures.config()
		local first = signature(generate(config, 1, 4))
		local differs = false
		for seed = 2, 10 do
			if signature(generate(config, seed, 4)) ~= first then
				differs = true
			end
		end
		Assert.truthy(differs, "every seed gave the same world")
	end,

	["no room has more corridors than the limit"] = function()
		eachWorld(function(world, config, label)
			for _, room in world.rooms do
				Assert.truthy(#room.corridors <= config.world.maxExits, label)
				Assert.equal(#room.corridors, #room.neighbours, label)
				Assert.truthy(#room.corridors >= 1, "isolated room, " .. label)
			end
		end)
	end,

	["every corridor touches both its rooms on the line between their centres"] = function()
		eachWorld(function(world, config, label)
			for _, corridor in world.corridors do
				local a, b = world.rooms[corridor.roomA], world.rooms[corridor.roomB]
				Assert.truthy(table.find(a.neighbours, b.id), label)
				Assert.truthy(table.find(b.neighbours, a.id), label)
				if a.cellZ == b.cellZ then
					local left, right = a, b
					if b.x < a.x then
						left, right = b, a
					end
					Assert.equal(corridor.x - corridor.halfWidth, left.x + left.halfWidth, label)
					Assert.equal(corridor.x + corridor.halfWidth, right.x - right.halfWidth, label)
					Assert.equal(corridor.z, a.z, label)
					Assert.equal(corridor.z, b.z, label)
					Assert.equal(corridor.halfDepth, config.world.corridorHalfWidth, label)
				else
					Assert.equal(a.cellX, b.cellX, label)
					local near, far = a, b
					if b.z < a.z then
						near, far = b, a
					end
					Assert.equal(corridor.z - corridor.halfDepth, near.z + near.halfDepth, label)
					Assert.equal(corridor.z + corridor.halfDepth, far.z - far.halfDepth, label)
					Assert.equal(corridor.x, a.x, label)
					Assert.equal(corridor.x, b.x, label)
					Assert.equal(corridor.halfWidth, config.world.corridorHalfWidth, label)
				end
			end
		end)
	end,

	["rooms come from the templates with their camp and cover inside"] = function()
		eachWorld(function(world, config, label)
			for _, room in world.rooms do
				local template = templateById(config, room.template)
				Assert.truthy(template, "unknown template " .. room.template .. ", " .. label)
				if template then
					Assert.equal(room.halfWidth, template.halfWidth, label)
					Assert.equal(room.halfDepth, template.halfDepth, label)
					Assert.equal(#room.cover, #template.cover, label)
				end
				Assert.truthy(Geometry.insideRect(room, room.campX, room.campZ), label)
				for _, spot in room.cover do
					Assert.truthy(Geometry.insideRect(room, spot.x, spot.z), label)
				end
			end
		end)
	end,

	["a template given in the configuration is the only one used"] = function()
		local config = Fixtures.config()
		local only = config.world.templates[3]
		config.world.templates = { only }
		for _, room in generate(config, 7, 4).rooms do
			Assert.equal(room.template, only.id)
			Assert.equal(room.halfWidth, only.halfWidth)
		end
	end,

	["locate finds rooms, corridors and the outside"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				local found = World.locate(world, room.x, room.z)
				Assert.equal(found.kind, "room", label)
				Assert.equal(found.id, room.id, label)
				Assert.equal(World.roomAt(world, room.x, room.z), room)
			end
			for _, corridor in world.corridors do
				local found = World.locate(world, corridor.x, corridor.z)
				Assert.equal(found.kind, "corridor", label)
				Assert.equal(found.id, corridor.id, label)
				Assert.equal(World.roomAt(world, corridor.x, corridor.z), nil)
			end
			local far = world.bounds.x + world.bounds.halfWidth + 1000
			Assert.equal(World.locate(world, far, world.bounds.z).kind, "outside", label)
			Assert.equal(World.locate(world, world.bounds.x, -far).kind, "outside", label)
		end)
	end,

	["a point in a room's wall belongs to the room, not the corridor"] = function()
		local world = generate(Fixtures.config(), 3, 4)
		local corridor = world.corridors[1]
		local a, b = world.rooms[corridor.roomA], world.rooms[corridor.roomB]
		-- The shared boundary of room and corridor.
		local x, z = corridor.x, corridor.z
		if a.cellZ == b.cellZ then
			x = math.min(a.x, b.x) == a.x and a.x + a.halfWidth or b.x + b.halfWidth
		else
			z = math.min(a.z, b.z) == a.z and a.z + a.halfDepth or b.z + b.halfDepth
		end
		Assert.equal(World.locate(world, x, z).kind, "room")
	end,

	["clamp keeps a point that is inside"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				local x, z = World.clamp(world, room.x + 3, room.z - 2)
				Assert.equal(x, room.x + 3, label)
				Assert.equal(z, room.z - 2, label)
			end
			for _, corridor in world.corridors do
				local x, z = World.clamp(world, corridor.x, corridor.z)
				Assert.equal(x, corridor.x, label)
				Assert.equal(z, corridor.z, label)
			end
		end)
	end,

	["clamp returns the nearest walkable point for one outside"] = function()
		eachWorld(function(world, _, label)
			local bounds = world.bounds
			local spots = {
				{ bounds.x + bounds.halfWidth + 30, bounds.z },
				{ bounds.x - bounds.halfWidth - 17, bounds.z + 9 },
				{ bounds.x + 5, bounds.z + bounds.halfDepth + 40 },
				{ bounds.x - 2, bounds.z - bounds.halfDepth - 8 },
				{ bounds.x + 11, bounds.z + 3 },
			}
			for _, spot in spots do
				local x, z = World.clamp(world, spot[1], spot[2])
				Assert.truthy(
					World.locate(world, x, z).kind ~= "outside",
					"clamped outside, " .. label
				)
				Assert.near(
					Geometry.distance(spot[1], spot[2], x, z),
					distanceToWalkable(world, spot[1], spot[2]),
					1e-9,
					"not the nearest point, " .. label
				)
			end
		end)
	end,

	["clamp puts a point past the outermost wall on that wall"] = function()
		local world = generate(Fixtures.config(), 5, 4)
		local rightmost = world.rooms[1]
		for _, room in world.rooms do
			if room.x + room.halfWidth > rightmost.x + rightmost.halfWidth then
				rightmost = room
			end
		end
		local edge = rightmost.x + rightmost.halfWidth
		local x, z = World.clamp(world, edge + 10, rightmost.z + 1)
		Assert.near(x, edge)
		Assert.near(z, rightmost.z + 1)
	end,

	["cover is the neighbourhood of a cover spot in a room"] = function()
		local tested = 0
		eachWorld(function(world, config, label)
			local radius = config.world.coverRadius
			for _, room in world.rooms do
				for _, spot in room.cover do
					Assert.truthy(World.inCover(world, config, spot.x, spot.z), label)
					Assert.truthy(
						World.inCover(world, config, spot.x + radius - 0.5, spot.z),
						label
					)
					-- A point just out of reach, toward the room's centre, unless it
					-- falls within another spot's reach.
					local dx, dz = Geometry.normalize(room.x - spot.x, room.z - spot.z)
					local x, z = spot.x + dx * (radius + 1), spot.z + dz * (radius + 1)
					local nearOther = false
					for _, other in room.cover do
						if Geometry.distance(x, z, other.x, other.z) <= radius then
							nearOther = true
						end
					end
					if not nearOther then
						tested += 1
						Assert.falsy(World.inCover(world, config, x, z), label)
					end
				end
			end
		end)
		Assert.truthy(tested > 0, "no point was tested")
	end,

	["a corridor point or a point outside is never cover"] = function()
		eachWorld(function(world, config, label)
			for _, corridor in world.corridors do
				Assert.falsy(World.inCover(world, config, corridor.x, corridor.z), label)
			end
			Assert.falsy(
				World.inCover(world, config, world.bounds.x + world.bounds.halfWidth + 1000, 0),
				label
			)
		end)
	end,

	["a waypoint within the same room is the target itself"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				local x, z =
					World.waypointToward(world, room.x - 4, room.z + 3, room.x + 5, room.z - 6)
				Assert.equal(x, room.x + 5, label)
				Assert.equal(z, room.z - 6, label)
			end
		end)
	end,

	["stepping toward the waypoints walks from a start room to a zone room"] = function()
		eachWorld(function(world, _, label)
			for _, startId in world.startRooms do
				for _, zoneId in world.zoneRooms do
					local start, zone = world.rooms[startId], world.rooms[zoneId]
					local x, z = start.x, start.z
					local limit = world.hops[startId][zoneId] * 200
					local steps = 0
					while Geometry.distance(x, z, zone.x, zone.z) > 1e-6 do
						steps += 1
						Assert.truthy(
							steps <= limit,
							"no arrival in " .. limit .. " steps, " .. label
						)
						local wx, wz = World.waypointToward(world, x, z, zone.x, zone.z)
						x, z = Geometry.stepToward(x, z, wx, wz, 3)
						Assert.truthy(
							World.locate(world, x, z).kind ~= "outside",
							string.format("left the world at %.1f, %.1f, %s", x, z, label)
						)
					end
				end
			end
		end)
	end,

	["from a corridor the waypoint is in the room at the end nearer the target"] = function()
		eachWorld(function(world, _, label)
			for _, corridor in world.corridors do
				for _, target in world.rooms do
					local x, z =
						World.waypointToward(world, corridor.x, corridor.z, target.x, target.z)
					local found = World.locate(world, x, z)
					Assert.equal(found.kind, "room", label)
					local hopsA = world.hops[corridor.roomA][target.id]
					local hopsB = world.hops[corridor.roomB][target.id]
					if hopsA < hopsB then
						Assert.equal(found.id, corridor.roomA, label)
					elseif hopsB < hopsA then
						Assert.equal(found.id, corridor.roomB, label)
					else
						Assert.truthy(
							found.id == corridor.roomA or found.id == corridor.roomB,
							label
						)
					end
				end
			end
		end)
	end,

	["from a room the waypoint toward another room enters the corridor on the way"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				for _, target in world.rooms do
					if room.id ~= target.id then
						local x, z = World.waypointToward(world, room.x, room.z, target.x, target.z)
						local found = World.locate(world, x, z)
						Assert.equal(found.kind, "corridor", label)
						local next = world.nextHop[room.id][target.id]
						Assert.equal(
							found.id,
							(World.corridorBetween(world, room.id, next) :: any).id,
							label
						)
					end
				end
			end
		end)
	end,

	["corridorBetween returns the corridor of neighbours and nil otherwise"] = function()
		eachWorld(function(world, _, label)
			for _, room in world.rooms do
				for _, other in world.rooms do
					local corridor = World.corridorBetween(world, room.id, other.id)
					if table.find(room.neighbours, other.id) then
						Assert.truthy(corridor, "missing corridor, " .. label)
						if corridor then
							Assert.truthy(
								(corridor.roomA == room.id and corridor.roomB == other.id)
									or (corridor.roomA == other.id and corridor.roomB == room.id),
								label
							)
						end
					else
						Assert.equal(corridor, nil, label)
					end
				end
			end
		end)
	end,
}
