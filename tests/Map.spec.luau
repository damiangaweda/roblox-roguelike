--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Map = require("../src/shared/Core/Map")
local Rng = require("../src/shared/Core/Rng")
local Types = require("../src/shared/Core/Types")

local PLAYER_COUNTS = { 1, 4, 8, 12 }
local SEEDS = 20

local function generate(config: Types.Config, seed: number, players: number): Types.Map
	return Map.generate(config, Rng.new(seed), players)
end

-- Calls `check` with a map for every seed and player count, and a label for
-- failure messages.
local function eachMap(check: (
	map: Types.Map,
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

local function farthestDistance(map: Types.Map): number
	local farthest = 0
	for _, point in map.points do
		farthest = math.max(farthest, point.distance)
	end
	return farthest
end

local function distanceToSegment(
	x: number,
	z: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1)
	return Geometry.distance(x, z, ax + dx * t, az + dz * t)
end

-- The map position of a height grid node.
local function nodePosition(map: Types.Map, row: number, col: number): (number, number)
	return -map.half + (col - 1) * map.heightCell, -map.half + (row - 1) * map.heightCell
end

-- A string that is equal for two maps exactly when their points, paths,
-- terrain and cover are.
local function signature(map: Types.Map): string
	local parts = { tostring(map.half) }
	for _, point in map.points do
		table.insert(
			parts,
			string.format(
				"P%d:%.4f,%.4f:%s:%s:%d",
				point.id,
				point.x,
				point.z,
				point.template,
				table.concat(point.neighbours, "/"),
				#point.props
			)
		)
	end
	for _, path in map.paths do
		table.insert(parts, string.format("L%d:%d-%d", path.id, path.a, path.b))
	end
	local total = 0
	for _, line in map.heights do
		for _, height in line do
			total += height
		end
	end
	table.insert(parts, string.format("H%.6f", total))
	for _, spot in map.fieldCover do
		table.insert(parts, string.format("C%.4f,%.4f", spot.x, spot.z))
	end
	return table.concat(parts, ";")
end

return {
	["the map grows with the players within its limits"] = function()
		local config = Fixtures.config()
		local settings = config.map
		Assert.equal(generate(config, 1, 1).half, settings.minHalf, "solo")
		Assert.equal(generate(config, 1, 12).half, settings.maxHalf, "twelve")
		Assert.equal(generate(config, 1, 100).half, settings.maxHalf, "a hundred")
		Assert.equal(generate(config, 1, 5).half, settings.studsPerPlayer * 5, "five")
		for _, players in { 1, 2, 3, 4, 5, 6, 8, 12 } do
			Assert.equal(
				generate(config, 2, players).half,
				math.clamp(settings.studsPerPlayer * players, settings.minHalf, settings.maxHalf),
				players .. " players"
			)
		end
	end,

	["the point count follows the player count within its limits"] = function()
		local config = Fixtures.config()
		local settings = config.map
		for _, players in { 1, 2, 3, 4, 5, 8, 12, 20, 100 } do
			local expected = math.clamp(
				settings.pointsPerPlayer * players,
				settings.minPoints,
				settings.maxPoints
			)
			for seed = 1, 10 do
				Assert.equal(
					#generate(config, seed, players).points,
					expected,
					players .. " players"
				)
			end
		end
		Assert.equal(#generate(config, 1, 1).points, settings.minPoints)
		Assert.equal(#generate(config, 1, 100).points, settings.maxPoints)
	end,

	["point centres keep the spacing and the edge margin"] = function()
		eachMap(function(map, config, label)
			for _, point in map.points do
				local edge = map.half - math.max(math.abs(point.x), math.abs(point.z))
				Assert.truthy(edge >= config.map.edgeMargin - 1e-9, "near the edge, " .. label)
				for _, other in map.points do
					if other.id ~= point.id then
						Assert.truthy(
							Geometry.distance(point.x, point.z, other.x, other.z)
								>= config.map.pointSpacing,
							"points " .. point.id .. " and " .. other.id .. " too close, " .. label
						)
					end
				end
			end
		end)
	end,

	["entries sit on the edge band, apart, as many as the players need"] = function()
		eachMap(function(map, config, label, players)
			local settings = config.map
			local expected =
				math.clamp(math.ceil(players / settings.playersPerEntry), 1, settings.maxEntries)
			Assert.equal(#map.entries, expected, label)
			for index, id in map.entries do
				local point = map.points[id]
				local edge = map.half - math.max(math.abs(point.x), math.abs(point.z))
				Assert.truthy(
					edge >= settings.edgeMargin - 1e-9 and edge <= settings.edgeMargin + 5,
					"entry " .. id .. " " .. edge .. " from the edge, " .. label
				)
				Assert.truthy(point.isEntry, label)
				Assert.equal(point.template, settings.entryTemplate.id, label)
				Assert.equal(point.campX, nil, "entry with a camp, " .. label)
				Assert.equal(point.campZ, nil, label)
				Assert.equal(point.distance, 0, label)
				Assert.equal(point.level, 1, label)
				for j = index + 1, #map.entries do
					local other = map.points[map.entries[j]]
					Assert.truthy(
						Geometry.distance(point.x, point.z, other.x, other.z)
							>= settings.minEntrySpacing,
						"entries too close, " .. label
					)
				end
			end
			local flagged = 0
			for _, point in map.points do
				if point.isEntry then
					flagged += 1
				else
					Assert.truthy(point.campX ~= nil and point.campZ ~= nil, "no camp, " .. label)
				end
			end
			Assert.equal(flagged, #map.entries, label)
		end)
	end,

	["every point is reachable from every other, and next hops approach"] = function()
		eachMap(function(map, _, label)
			for _, from in map.points do
				Assert.truthy(from.distance < math.huge, "unreachable point, " .. label)
				Assert.equal(#from.paths, #from.neighbours, label)
				Assert.truthy(#from.paths >= 1, "isolated point, " .. label)
				for _, neighbour in from.neighbours do
					Assert.equal(map.hops[from.id][neighbour], 1, label)
					local path = Map.pathBetween(map, from.id, neighbour)
					Assert.truthy(path, label)
				end
				for _, to in map.points do
					local hops = map.hops[from.id][to.id]
					Assert.truthy(hops < math.huge, "no path, " .. label)
					Assert.equal(hops, map.hops[to.id][from.id], "hops symmetric, " .. label)
					if from.id ~= to.id then
						local next = map.nextHop[from.id][to.id]
						Assert.truthy(
							table.find(from.neighbours, next),
							"not a neighbour, " .. label
						)
						Assert.equal(
							map.hops[next][to.id],
							hops - 1,
							"does not approach, " .. label
						)
					end
				end
				Assert.equal(map.nextHop[from.id][from.id], from.id)
			end
			Assert.equal(Map.pathBetween(map, 1, 1), nil)
		end)
	end,

	["every point is reached on foot from every entry along the paths"] = function()
		eachMap(function(map, _, label)
			for _, entry in map.entries do
				for _, target in map.points do
					local current = entry
					while current ~= target.id do
						local next = map.nextHop[current][target.id]
						local a, b = map.points[current], map.points[next]
						local full = Geometry.distance(a.x, a.z, b.x, b.z)
						Assert.near(
							Map.reach(map, a.x, a.z, b.x, b.z),
							full,
							1e-6,
							"leg " .. current .. " to " .. next .. " blocked, " .. label
						)
						current = next
					end
				end
			end
		end)
	end,

	["no path crosses a third point's footprint or its ends' props"] = function()
		eachMap(function(map, _, label)
			for _, path in map.paths do
				local a, b = map.points[path.a], map.points[path.b]
				for _, point in map.points do
					if point.id ~= a.id and point.id ~= b.id then
						Assert.truthy(
							distanceToSegment(point.x, point.z, a.x, a.z, b.x, b.z)
								> point.radius + path.halfWidth,
							"path " .. path.id .. " crosses point " .. point.id .. ", " .. label
						)
					end
				end
				for _, point in { a, b } do
					for _, prop in point.props do
						for t = 0, 1, 0.01 do
							local x, z = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
							Assert.falsy(
								Geometry.insideRect(prop, x, z),
								"prop on a path, " .. label
							)
						end
					end
				end
			end
		end)
	end,

	["point levels follow the distance from the entries"] = function()
		eachMap(function(map, config, label)
			local maxLevel = config.map.maxLevel
			local farthest = farthestDistance(map)
			local farthestLevel = 0
			for _, point in map.points do
				local nearest = math.huge
				for _, entry in map.entries do
					nearest = math.min(nearest, map.hops[point.id][entry])
				end
				Assert.equal(point.distance, nearest, label)
				Assert.truthy(point.level >= 1 and point.level <= maxLevel, label)
				farthestLevel = math.max(farthestLevel, point.level)
				if not point.isEntry then
					local expected =
						math.clamp(math.ceil(point.distance / farthest * maxLevel), 1, maxLevel)
					Assert.equal(point.level, expected, "point " .. point.id .. ", " .. label)
					if point.distance == 1 and farthest >= maxLevel then
						Assert.equal(point.level, 1, "next to an entry, " .. label)
					end
				end
			end
			Assert.equal(farthestLevel, maxLevel, "no point of the top level, " .. label)
			for _, id in Map.farthestPoints(map, 1) do
				Assert.equal(map.points[id].level, maxLevel, "farthest point, " .. label)
			end
		end)
	end,

	["farthest points come by distance from the entries, ties by id"] = function()
		local distances = { 0, 2, 3, 1, 3, 2 }
		local points = {}
		for id, distance in distances do
			points[id] = { id = id, distance = distance }
		end
		local map = ({ points = points } :: any) :: Types.Map
		local farthest = Map.farthestPoints(map, 4)
		Assert.equal(table.concat(farthest, ","), "3,5,2,6")
		Assert.equal(table.concat(Map.farthestPoints(map, 10), ","), "3,5,2,6,4,1")
		Assert.equal(#Map.farthestPoints(map, 0), 0)
	end,

	["heights stay within the hills, and footprints and paths stay dry"] = function()
		local sawWater = false
		eachMap(function(map, config, label)
			local settings = config.map
			local dry = settings.waterLevel + settings.dryMargin
			local size = math.ceil(2 * map.half / settings.heightCell) + 1
			Assert.equal(#map.heights, size, label)
			for _, line in map.heights do
				Assert.equal(#line, size, label)
				for _, height in line do
					Assert.truthy(height >= 0 and height <= settings.maxHeight, label)
					if height < settings.waterLevel then
						sawWater = true
					end
				end
			end
			for row = 1, size do
				for col = 1, size do
					local x, z = nodePosition(map, row, col)
					local height = map.heights[row][col]
					for _, point in map.points do
						if Geometry.distance(x, z, point.x, point.z) <= point.radius then
							Assert.truthy(height >= dry, "footprint under water, " .. label)
							local centre = Map.heightAt(map, point.x, point.z)
							Assert.near(height, centre, 1e-9, "footprint not flat, " .. label)
						end
					end
					for _, path in map.paths do
						local a, b = map.points[path.a], map.points[path.b]
						if distanceToSegment(x, z, a.x, a.z, b.x, b.z) <= path.halfWidth then
							Assert.truthy(height >= dry, "path under water, " .. label)
						end
					end
				end
			end
		end)
		Assert.truthy(sawWater, "no map has water")
	end,

	["walkable ground excludes water, props and the outside"] = function()
		local sawWater, sawProp = false, false
		eachMap(function(map, config, label)
			for row, line in map.heights do
				for col, height in line do
					local x, z = nodePosition(map, row, col)
					if
						height < config.map.waterLevel
						and math.abs(x) <= map.half
						and math.abs(z) <= map.half
					then
						sawWater = true
						Assert.falsy(Map.walkable(map, x, z), "water walkable, " .. label)
						Assert.equal(Map.heightAt(map, x, z), config.map.waterLevel, label)
					end
				end
			end
			for _, point in map.points do
				Assert.truthy(Map.walkable(map, point.x, point.z), "centre, " .. label)
				for _, prop in point.props do
					sawProp = true
					Assert.falsy(Map.walkable(map, prop.x, prop.z), "prop walkable, " .. label)
				end
			end
			Assert.falsy(Map.walkable(map, map.half + 1, 0), label)
			Assert.falsy(Map.walkable(map, 0, -map.half - 1), label)
		end)
		Assert.truthy(sawWater, "no map has water")
		Assert.truthy(sawProp, "no map has a prop")
	end,

	["clamp returns walkable ground"] = function()
		local config = Fixtures.config()
		for _, players in PLAYER_COUNTS do
			for seed = 1, 5 do
				local map = generate(config, seed, players)
				local probe = Rng.new(seed * 7)
				local span = map.half + 20
				for _ = 1, 200 do
					local x, z = -span + probe:next() * 2 * span, -span + probe:next() * 2 * span
					local cx, cz = Map.clamp(map, x, z)
					Assert.truthy(Map.walkable(map, cx, cz), "clamp " .. x .. ", " .. z)
					if Map.walkable(map, x, z) then
						Assert.equal(cx, x)
						Assert.equal(cz, z)
					end
				end
				for _, point in map.points do
					for _, prop in point.props do
						local cx, cz = Map.clamp(map, prop.x, prop.z)
						Assert.truthy(Map.walkable(map, cx, cz), "out of a prop")
					end
				end
				local ex, ez = Map.clamp(map, map.half + 50, 0)
				Assert.truthy(Map.walkable(map, ex, ez), "off the map")
				Assert.truthy(ex <= map.half, "off the map")
			end
		end
	end,

	["heightAt is bilinear over the grid"] = function()
		local config = Fixtures.config()
		local map = generate(config, 4, 4)
		local checked = 0
		for row = 1, #map.heights - 1 do
			for col = 1, #map.heights - 1 do
				local h00, h01 = map.heights[row][col], map.heights[row][col + 1]
				local h10, h11 = map.heights[row + 1][col], map.heights[row + 1][col + 1]
				if math.min(h00, h01, h10, h11) >= config.map.waterLevel then
					local x, z = nodePosition(map, row, col)
					local cell = map.heightCell
					Assert.near(Map.heightAt(map, x, z), h00)
					Assert.near(Map.heightAt(map, x + cell / 2, z), (h00 + h01) / 2)
					Assert.near(
						Map.heightAt(map, x + cell / 2, z + cell / 2),
						(h00 + h01 + h10 + h11) / 4
					)
					Assert.near(
						Map.heightAt(map, x + cell / 4, z + cell * 3 / 4),
						(h00 * 0.75 + h01 * 0.25) * 0.25 + (h10 * 0.75 + h11 * 0.25) * 0.75
					)
					checked += 1
				end
			end
		end
		Assert.truthy(checked > 0)
	end,

	["pointAt finds footprints and nearestPoint the nearest centre"] = function()
		eachMap(function(map, _, label)
			for _, point in map.points do
				Assert.equal(Map.pointAt(map, point.x, point.z), point, label)
				Assert.equal(Map.pointAt(map, point.x + point.radius - 0.01, point.z), point, label)
				Assert.equal(Map.pointAt(map, point.x, point.z - point.radius + 0.01), point, label)
				Assert.equal(Map.pointAt(map, point.x + point.radius + 0.5, point.z), nil, label)
				Assert.equal(Map.nearestPoint(map, point.x + 1, point.z - 1), point, label)
			end
			Assert.equal(Map.pointAt(map, map.half + 1, 0), nil, label)
		end)
	end,

	["cover hides within its radius, at points and between them"] = function()
		local config = Fixtures.config()
		local radius = config.map.coverRadius
		local sawField = false
		for seed = 1, 5 do
			local map = generate(config, seed, 4)
			local spots: { Types.Point } = {}
			for _, point in map.points do
				for _, spot in point.cover do
					table.insert(spots, spot)
				end
			end
			for _, spot in map.fieldCover do
				sawField = true
				table.insert(spots, spot)
				Assert.truthy(Map.walkable(map, spot.x, spot.z), "bush in water")
				Assert.equal(Map.pointAt(map, spot.x, spot.z), nil, "bush in a footprint")
			end
			for _, spot in spots do
				Assert.truthy(Map.inCover(map, config, spot.x, spot.z))
				Assert.truthy(Map.inCover(map, config, spot.x + radius - 0.1, spot.z))
			end
			-- Positions with no spot within the radius.
			local probe = Rng.new(seed)
			local outside = 0
			for _ = 1, 200 do
				local x = -map.half + probe:next() * 2 * map.half
				local z = -map.half + probe:next() * 2 * map.half
				local nearest = math.huge
				for _, spot in spots do
					nearest = math.min(nearest, Geometry.distance(x, z, spot.x, spot.z))
				end
				Assert.equal(Map.inCover(map, config, x, z), nearest <= radius)
				if nearest > radius then
					outside += 1
				end
			end
			Assert.truthy(outside > 0)
		end
		Assert.truthy(sawField, "no bushes between points")
	end,

	["clearPath stops at a prop and runs along a path"] = function()
		local sawProp = false
		eachMap(function(map, config, label)
			for _, path in map.paths do
				local a, b = map.points[path.a], map.points[path.b]
				Assert.truthy(Map.clearPath(map, a.x, a.z, b.x, b.z), label)
				Assert.truthy(Map.clearPath(map, b.x, b.z, a.x, a.z), label)
			end
			for _, point in map.points do
				for _, prop in point.props do
					local fromX, toX = prop.x - prop.halfWidth - 2, prop.x + prop.halfWidth + 2
					if
						Map.walkable(map, fromX, prop.z)
						and Map.pointAt(map, fromX, prop.z) == point
						and Map.pointAt(map, toX, prop.z) == point
					then
						sawProp = true
						Assert.falsy(Map.clearPath(map, fromX, prop.z, toX, prop.z), label)
						-- Two studs to the prop: the walk stops within a sample of it.
						local reach = Map.reach(map, fromX, prop.z, toX, prop.z)
						Assert.truthy(reach <= 2 + 1e-9, "reach " .. reach .. ", " .. label)
						Assert.truthy(
							reach >= 2 - config.map.sampleStep - 1e-9,
							"reach " .. reach .. ", " .. label
						)
					end
				end
			end
		end)
		Assert.truthy(sawProp, "no prop checked")
	end,

	["shots fly over water but stop at props and the map's edge"] = function()
		local sawWater, sawProp = false, false
		eachMap(function(map, config, label)
			-- Water stops a walk, never a shot. Props stand on footprints, which
			-- keep more than a cell from the water, so a short line to a water
			-- node meets none.
			for row, line in map.heights do
				for col, height in line do
					local x, z = nodePosition(map, row, col)
					if
						height < config.map.waterLevel
						and math.abs(x) <= map.half - 3
						and math.abs(z) <= map.half
					then
						sawWater = true
						Assert.falsy(Map.walkable(map, x, z), label)
						Assert.falsy(Map.blocksShots(map, x, z), label)
						Assert.falsy(Map.clearPath(map, x - 3, z, x, z), label)
						Assert.truthy(Map.clearShot(map, x - 3, z, x, z), label)
					end
				end
			end
			for _, point in map.points do
				for _, prop in point.props do
					Assert.truthy(Map.blocksShots(map, prop.x, prop.z), label)
					local fromX, toX = prop.x - prop.halfWidth - 2, prop.x + prop.halfWidth + 2
					if
						Map.pointAt(map, fromX, prop.z) == point
						and Map.pointAt(map, toX, prop.z) == point
					then
						sawProp = true
						Assert.falsy(Map.clearShot(map, fromX, prop.z, toX, prop.z), label)
						local reach = Map.shotReach(map, fromX, prop.z, toX, prop.z)
						Assert.truthy(reach <= 2 + 1e-9, "reach " .. reach .. ", " .. label)
						Assert.truthy(
							reach >= 2 - config.map.sampleStep - 1e-9,
							"reach " .. reach .. ", " .. label
						)
					end
				end
				Assert.falsy(Map.blocksShots(map, point.x, point.z), label)
			end
			Assert.truthy(Map.blocksShots(map, map.half + 1, 0), label)
			local reach = Map.shotReach(map, map.half - 10, 0, map.half + 10, 0)
			Assert.truthy(
				reach >= 10 - config.map.sampleStep - 1e-9 and reach <= 10 + 1e-9,
				"edge " .. reach
			)
			Assert.equal(Map.shotReach(map, 0, 0, 0, 0), 0)
		end)
		Assert.truthy(sawWater, "no water checked")
		Assert.truthy(sawProp, "no prop checked")
	end,

	["waypointToward returns the target when clear and the next point otherwise"] = function()
		local sawBlocked = false
		eachMap(function(map, _, label)
			for _, path in map.paths do
				local a, b = map.points[path.a], map.points[path.b]
				local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
				local wx, wz = Map.waypointToward(map, a.x, a.z, mx, mz)
				Assert.equal(wx, mx, label)
				Assert.equal(wz, mz, label)
			end
			for _, from in map.points do
				for _, to in map.points do
					if from.id ~= to.id and not Map.clearPath(map, from.x, from.z, to.x, to.z) then
						sawBlocked = true
						local next = map.points[map.nextHop[from.id][to.id]]
						local wx, wz = Map.waypointToward(map, from.x, from.z, to.x, to.z)
						Assert.equal(wx, next.x, label)
						Assert.equal(wz, next.z, label)
						Assert.truthy(Map.clearPath(map, from.x, from.z, wx, wz), label)
					end
				end
			end
		end)
		Assert.truthy(sawBlocked, "no blocked line checked")
	end,

	["templates keep props clear of the centre, the camp and the marked places"] = function()
		local config = Fixtures.config()
		local templates = table.clone(config.map.templates)
		table.insert(templates, config.map.entryTemplate)
		for _, template in templates do
			local marked: { Types.Point } = { template.chest, template.clue }
			for _, spot in template.cover do
				table.insert(marked, spot)
			end
			if template.camp then
				table.insert(marked, template.camp)
			end
			for _, spot in marked do
				Assert.truthy(
					Geometry.distance(spot.x, spot.z, 0, 0) <= template.radius,
					template.id .. " place outside the footprint"
				)
			end
			for _, prop in template.props do
				local corner = Geometry.distance(
					math.abs(prop.x) + prop.halfWidth,
					math.abs(prop.z) + prop.halfDepth,
					0,
					0
				)
				Assert.truthy(corner <= template.radius, template.id .. " prop outside")
				for _, spot in { { x = 0, z = 0 }, template.camp or { x = 0, z = 0 } } do
					local cx, cz = Geometry.clampToRect(prop, spot.x, spot.z)
					Assert.truthy(
						Geometry.distance(cx, cz, spot.x, spot.z) >= 6,
						template.id .. " prop near the centre or the camp"
					)
				end
				for _, spot in marked do
					Assert.falsy(
						Geometry.insideRect(prop, spot.x, spot.z),
						template.id .. " place in a prop"
					)
				end
			end
		end
		Assert.equal(config.map.entryTemplate.camp, nil)
	end,

	["templates put the clue beyond an open zone's reach and clear of the props"] = function()
		local config = Fixtures.config()
		local templates = table.clone(config.map.templates)
		table.insert(templates, config.map.entryTemplate)
		-- A reader within readRadius of the clue stands outside a zone at the
		-- centre.
		local reach = config.map.zoneRadius + config.run.arc.clues.readRadius
		for _, template in templates do
			local clue = template.clue
			Assert.truthy(
				Geometry.distance(clue.x, clue.z, 0, 0) > reach,
				template.id .. " clue within reach of the zone"
			)
			for _, prop in template.props do
				local cx, cz = Geometry.clampToRect(prop, clue.x, clue.z)
				Assert.truthy(
					Geometry.distance(cx, cz, clue.x, clue.z) >= 6,
					template.id .. " clue near a prop"
				)
			end
		end
	end,

	["the same seed makes the same map"] = function()
		local config = Fixtures.config()
		for _, players in PLAYER_COUNTS do
			for seed = 1, 5 do
				Assert.equal(
					signature(generate(config, seed, players)),
					signature(generate(config, seed, players)),
					"seed " .. seed .. ", " .. players .. " players"
				)
			end
		end
	end,

	["different seeds make different maps"] = function()
		local config = Fixtures.config()
		local first = signature(generate(config, 1, 4))
		for seed = 2, 10 do
			Assert.truthy(signature(generate(config, seed, 4)) ~= first, "seed " .. seed)
		end
	end,

	["a full map generates well within its time budget"] = function()
		local config = Fixtures.config()
		for seed = 1, 5 do
			local started = os.clock()
			local map = generate(config, seed, 12)
			local elapsed = os.clock() - started
			Assert.equal(#map.points, config.map.maxPoints)
			Assert.truthy(elapsed < 0.1, string.format("%.1f ms", elapsed * 1000))
		end
	end,

	["clamp puts a half-stud step into water back within a stud and a half"] = function()
		local config = Fixtures.config()
		local checked = 0
		for seed = 1, 20 do
			local map = generate(config, seed, 4)
			local probe = Rng.new(seed * 13)
			-- Shores lie within a cell of a node under water.
			local wet: { { number } } = {}
			for row, line in map.heights do
				for col, height in line do
					if height < config.map.waterLevel then
						table.insert(wet, { nodePosition(map, row, col) })
					end
				end
			end
			local found = 0
			for _ = 1, 100000 do
				if found >= 25 or #wet == 0 then
					break
				end
				local node = wet[probe:integer(1, #wet)]
				local x = node[1] + (probe:next() * 2 - 1) * map.heightCell
				local z = node[2] + (probe:next() * 2 - 1) * map.heightCell
				local angle = probe:next() * 2 * math.pi
				local sx, sz = x + math.cos(angle) * 0.5, z + math.sin(angle) * 0.5
				-- A shore: walkable ground half a stud from water, not a prop.
				if
					Map.walkable(map, x, z)
					and not Map.walkable(map, sx, sz)
					and not Map.blocksShots(map, sx, sz)
				then
					found += 1
					local cx, cz = Map.clamp(map, sx, sz)
					Assert.truthy(Map.walkable(map, cx, cz), "seed " .. seed)
					local moved = Geometry.distance(cx, cz, x, z)
					Assert.truthy(
						moved <= 1.5,
						string.format("seed %d: (%.2f, %.2f) put back %.2f away", seed, x, z, moved)
					)
				end
			end
			checked += found
		end
		Assert.equal(checked, 500)
	end,

	["waypointToward leads round a prop to a target behind it"] = function()
		local config = Fixtures.config()
		local checked = 0
		for _, players in { 1, 4 } do
			for seed = 1, 5 do
				local map = generate(config, seed, players)
				for _, point in map.points do
					local startX, startZ = point.campX or point.x, point.campZ or point.z
					for _, prop in point.props do
						for k = 0, 7 do
							-- Two studs out from the prop's face, all round it.
							local dx, dz = math.cos(k * math.pi / 4), math.sin(k * math.pi / 4)
							local out = math.min(
								prop.halfWidth / math.max(math.abs(dx), 1e-9),
								prop.halfDepth / math.max(math.abs(dz), 1e-9)
							) + 2
							local tx, tz = prop.x + dx * out, prop.z + dz * out
							if
								not Map.walkable(map, tx, tz)
								or Map.nearestPoint(map, tx, tz) ~= point
								or Map.clearPath(map, startX, startZ, tx, tz)
							then
								continue
							end
							checked += 1
							local x, z = startX, startZ
							local steps = 0
							while Geometry.distance(x, z, tx, tz) > 0.5 and steps < 200 do
								steps += 1
								local wx, wz = Map.waypointToward(map, x, z, tx, tz)
								Assert.truthy(wx ~= x or wz ~= z, "no way on, seed " .. seed)
								x, z = Map.clamp(map, Geometry.stepToward(x, z, wx, wz, 0.5))
								Assert.truthy(Map.walkable(map, x, z))
							end
							Assert.truthy(
								steps < 200,
								string.format(
									"seed %d, %d players: stuck at point %d short of (%.1f, %.1f)",
									seed,
									players,
									point.id,
									tx,
									tz
								)
							)
						end
					end
				end
			end
		end
		Assert.truthy(checked > 50, "only " .. checked .. " targets behind props")
	end,

	["waypointToward stays put when water leaves no way to the target"] = function()
		local run = Fixtures.run(1)
		local map = run.map
		local entry = Fixtures.entryOf(run)
		Fixtures.dry(run, entry.x, entry.z, 40)
		-- An island: one height node above a pond.
		local col = math.round((entry.x + 12 + map.half) / map.heightCell) + 1
		local row = math.round((entry.z + map.half) / map.heightCell) + 1
		local islandX = -map.half + (col - 1) * map.heightCell
		local islandZ = -map.half + (row - 1) * map.heightCell
		Fixtures.water(run, islandX, islandZ, 14)
		map.heights[row][col] = map.waterLevel + 1
		Assert.truthy(Map.walkable(map, islandX, islandZ))
		Assert.equal(Map.nearestPoint(map, islandX, islandZ), entry)

		local x, z = islandX - 22, islandZ
		Assert.truthy(Map.walkable(map, x, z))
		local stuck = false
		for _ = 1, 200 do
			local wx, wz = Map.waypointToward(map, x, z, islandX, islandZ)
			if wx == x and wz == z then
				stuck = true
				break
			end
			x, z = Map.clamp(map, Geometry.stepToward(x, z, wx, wz, 0.5))
			Assert.truthy(Map.walkable(map, x, z), "walked into the water")
		end
		Assert.truthy(stuck, "kept walking toward an island")
		Assert.truthy(Geometry.distance(x, z, islandX, islandZ) > 4)
	end,

	["generate fails loudly when the entries cannot keep their spacing"] = function()
		local config = Fixtures.config()
		config.map.minEntrySpacing = 10000
		local ok, message = pcall(Map.generate, config, Rng.new(1), 12)
		Assert.falsy(ok)
		Assert.truthy(string.find(tostring(message), "minEntrySpacing", 1, true), tostring(message))
	end,

	["generate fails loudly when too few points fit"] = function()
		local config = Fixtures.config()
		config.map.pointSpacing = 200
		local ok, message = pcall(Map.generate, config, Rng.new(1), 1)
		Assert.falsy(ok)
		Assert.truthy(string.find(tostring(message), "pointSpacing", 1, true), tostring(message))
	end,
}
