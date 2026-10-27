--!strict
-- Builds the open map of a run (ADR-0012) in Roblox: terrain from the core's
-- heights, painted with grass, dirt paths, cobbled points, sandy shores, rock
-- on steep slopes and water, then the props, the cover bushes and the zone and
-- entry markers in one folder, and invisible barriers over the water and
-- around the edge that hold characters where the rules let them stand. Pure
-- presentation of the core's data; nothing here is read back by the rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(ReplicatedStorage.Shared.Core.Map)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local MapBuilder = {}

-- Presentation constants, not gameplay numbers.
-- The side of a terrain voxel; WriteVoxels takes no other resolution.
local VOXEL = 4
-- The terrain is written in squares of this many studs, one square a frame,
-- so the server never stalls on the build.
local CHUNK = 64
-- How far below the lowest ground the terrain's bottom lies.
local BOTTOM_DEPTH = 8
local GRASS_MATERIAL = Enum.Material.Grass
local LAKEBED_MATERIAL = Enum.Material.Mud
local PATH_MATERIAL = Enum.Material.Ground
local POINT_MATERIAL = Enum.Material.Cobblestone
local SHORE_MATERIAL = Enum.Material.Sand
local SLOPE_MATERIAL = Enum.Material.Rock
local WATER_MATERIAL = Enum.Material.Water
local AIR_MATERIAL = Enum.Material.Air
-- Ground at most this far above the water's surface is a sandy shore.
local SHORE_HEIGHT = 1.5
-- Ground rising more than this many studs per stud is bare rock.
local ROCK_SLOPE = 0.55
-- The terrain's colour per material, set once per build.
local MATERIAL_COLORS: { [Enum.Material]: Color3 } = {
	[GRASS_MATERIAL] = Color3.fromRGB(98, 128, 64),
	[LAKEBED_MATERIAL] = Color3.fromRGB(76, 66, 52),
	[PATH_MATERIAL] = Color3.fromRGB(122, 98, 68),
	[POINT_MATERIAL] = Color3.fromRGB(140, 134, 122),
	[SHORE_MATERIAL] = Color3.fromRGB(192, 174, 130),
	[SLOPE_MATERIAL] = Color3.fromRGB(112, 110, 104),
}
-- The water's look, set once per build.
local WATER_COLOR = Color3.fromRGB(40, 88, 98)
-- 0 is opaque, 1 clear; enough to see the shallows' bed.
local WATER_TRANSPARENCY = 0.4
local WATER_WAVE_SIZE = 0.08
local WATER_WAVE_SPEED = 6
local WATER_REFLECTANCE = 0.5
local PROP_HEIGHT = 14
-- How far a prop reaches below the lowest ground under it, so a slope never
-- shows a gap.
local PROP_SINK = 2
-- A square prop up to this half side is a pillar, a larger one a well; any
-- other prop is a ruin wall. The core only knows rects, so the look follows
-- the shape.
local PILLAR_MAX_HALF = 1.5
-- Two sides equal within this are a square.
local SQUARE_TOLERANCE = 0.01
-- Every stone prop takes a colour between these two, so no two walls match.
local STONE_COLOR_DARK = Color3.fromRGB(92, 90, 86)
local STONE_COLOR_LIGHT = Color3.fromRGB(124, 118, 106)
local STONE_MATERIAL = Enum.Material.Slate
local STONE_BASE_MATERIAL = Enum.Material.Cobblestone
-- A wall's base is this much darker, its cap this much lighter (0 to 1).
local BASE_DARKEN = 0.3
local CAP_LIGHTEN = 0.2
-- A wall's base reaches this high above the floor and juts this far out.
local WALL_BASE_HEIGHT = 1.2
local WALL_BASE_OUTSET = 0.3
-- A wall's cap is this thick and juts this far out.
local WALL_CAP_HEIGHT = 0.6
local WALL_CAP_OUTSET = 0.2
-- A pillar's plinth and capital: their height and how far they jut out.
local PILLAR_PLINTH_HEIGHT = 1.2
local PILLAR_CAPITAL_HEIGHT = 0.8
local PILLAR_RIM_OUTSET = 0.3
-- A well's rim stands this high, low enough to see into from above but above
-- a character's middle, so a dash still stops at it.
local WELL_HEIGHT = 4.5
-- The well's capstone ring: its thickness and how far it juts out.
local WELL_CAP_HEIGHT = 0.4
local WELL_CAP_OUTSET = 0.25
-- The water inside a well: a disc this far in from the rim, this thick on
-- the rim's top.
local WELL_WATER_INSET = 0.5
local WELL_WATER_LIFT = 0.05
local WELL_WATER_COLOR = Color3.fromRGB(28, 52, 60)
local WELL_WATER_REFLECTANCE = 0.25
-- A bush is a big leafy sphere and one or two smaller ones around it, in
-- two greens; sizes are fractions of the cover radius.
local BUSH_MAIN_DIAMETER = 1.5
local BUSH_SIDE_MIN_DIAMETER = 1
local BUSH_SIDE_MAX_DIAMETER = 1.2
local BUSH_SIDE_OFFSET = 0.4
local BUSH_MAX_SIDES = 2
-- How much of a sphere's diameter lies under the ground's level.
local BUSH_SINK = 0.2
local BUSH_COLOR_DARK = Color3.fromRGB(52, 96, 46)
local BUSH_COLOR_LIGHT = Color3.fromRGB(84, 128, 58)
local BUSH_MATERIAL = Enum.Material.LeafyGrass
-- Enough to show the player hiding inside.
local BUSH_TRANSPARENCY = 0.2
-- The invisible barriers over the water and around the edge reach this far
-- above the highest ground, so no character walks or dashes over them, and
-- this far below the lowest.
local BARRIER_CLEARANCE = 10
local BARRIER_SINK = 2
-- The water is sampled in square cells of this side, one cell water when its
-- centre is.
local BARRIER_CELL = 4
local EDGE_WALL_THICKNESS = 4
-- The barriers are parented in batches of about this many parts, a frame
-- apart, so the build never creates them all in one frame.
local BARRIER_BATCH = 64
-- How far a marker floats above the ground, so the terrain does not hide it.
local MARKER_LIFT = 0.2
-- A zone's marker: a glowing ring on its edge of this many segments, this
-- wide and tall, and a beam of light from its centre.
local ZONE_COLOR = Color3.fromRGB(90, 255, 150)
local ZONE_RING_SEGMENTS = 32
local ZONE_RING_WIDTH = 0.5
local ZONE_RING_HEIGHT = 0.3
-- Each segment is this much longer than its share of the circle, so the ring
-- shows no gaps.
local ZONE_RING_OVERLAP = 1.1
local ZONE_BEAM_RADIUS = 0.8
local ZONE_BEAM_HEIGHT = 30
-- Faint enough that the beam never hides a fight under it.
local ZONE_BEAM_TRANSPARENCY = 0.8
-- An entry's marker: a circle of low standing stones.
local ENTRY_MARKER_RADIUS = 6
local ENTRY_STONES = 10
local ENTRY_STONE_SIZE = Vector3.new(1.2, 0.8, 1.6)
-- How far each stone is sunk into the ground.
local ENTRY_STONE_SINK = 0.2
local ENTRY_STONE_COLOR = Color3.fromRGB(118, 118, 110)

local folder: Folder? = nil

local function distanceToSegment(
	x: number,
	z: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local dx, dz = bx - ax, bz - az
	local lengthSquared = dx * dx + dz * dz
	local t = 0
	if lengthSquared > 1e-12 then
		t = math.clamp(((x - ax) * dx + (z - az) * dz) / lengthSquared, 0, 1)
	end
	local px, pz = ax + dx * t - x, az + dz * t - z
	return math.sqrt(px * px + pz * pz)
end

-- The ground's height at (x, z), bilinear over the grid as the core reads it,
-- before water.
local function groundAt(map: Types.Map, x: number, z: number): number
	local heights = map.heights
	local size = #heights
	local u = (math.clamp(x, -map.half, map.half) + map.half) / map.heightCell
	local v = (math.clamp(z, -map.half, map.half) + map.half) / map.heightCell
	local col = math.clamp(math.floor(u) + 1, 1, size - 1)
	local row = math.clamp(math.floor(v) + 1, 1, size - 1)
	local fx = math.clamp(u - (col - 1), 0, 1)
	local fz = math.clamp(v - (row - 1), 0, 1)
	local low = heights[row][col] * (1 - fx) + heights[row][col + 1] * fx
	local high = heights[row + 1][col] * (1 - fx) + heights[row + 1][col + 1] * fx
	return low * (1 - fz) + high * fz
end

-- The material on top of the ground at (x, z): a point's footprint, a path's
-- band, the bed of the water, rock on a steep slope, sand on a shore or grass.
-- `slope` is how many studs the ground rises per stud there.
local function surfaceAt(
	map: Types.Map,
	points: { Types.MapPoint },
	paths: { Types.Path },
	x: number,
	z: number,
	ground: number,
	slope: number
): Enum.Material
	for _, point in points do
		if (point.x - x) ^ 2 + (point.z - z) ^ 2 <= point.radius * point.radius then
			return POINT_MATERIAL
		end
	end
	for _, path in paths do
		local a, b = map.points[path.a], map.points[path.b]
		if distanceToSegment(x, z, a.x, a.z, b.x, b.z) <= path.halfWidth then
			return PATH_MATERIAL
		end
	end
	if ground < map.waterLevel then
		return LAKEBED_MATERIAL
	end
	if slope > ROCK_SLOPE then
		return SLOPE_MATERIAL
	end
	if ground <= map.waterLevel + SHORE_HEIGHT then
		return SHORE_MATERIAL
	end
	return GRASS_MATERIAL
end

-- Writes the terrain of the square [x0, x1] x [z0, z1], from `bottom` up
-- `layers` voxels. Every bound is a multiple of VOXEL.
local function writeChunk(
	map: Types.Map,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	bottom: number,
	layers: number
)
	-- Only the points and paths that can reach into the square are tested.
	local points: { Types.MapPoint } = {}
	for _, point in map.points do
		local r = point.radius
		if point.x + r >= x0 and point.x - r <= x1 and point.z + r >= z0 and point.z - r <= z1 then
			table.insert(points, point)
		end
	end
	local paths: { Types.Path } = {}
	for _, path in map.paths do
		local a, b = map.points[path.a], map.points[path.b]
		local w = path.halfWidth
		if
			math.max(a.x, b.x) + w >= x0
			and math.min(a.x, b.x) - w <= x1
			and math.max(a.z, b.z) + w >= z0
			and math.min(a.z, b.z) - w <= z1
		then
			table.insert(paths, path)
		end
	end

	local columnsX = (x1 - x0) / VOXEL
	local columnsZ = (z1 - z0) / VOXEL
	-- The ground of every column and of a ring of columns around the square,
	-- for the slopes: grounds[ix + 1][iz + 1] for ix, iz from 0 to columns + 1.
	local grounds: { { number } } = {}
	for ix = 0, columnsX + 1 do
		local x = x0 + (ix - 0.5) * VOXEL
		local line = table.create(columnsZ + 2, 0)
		for iz = 0, columnsZ + 1 do
			line[iz + 1] = groundAt(map, x, z0 + (iz - 0.5) * VOXEL)
		end
		grounds[ix + 1] = line
	end

	-- WriteVoxels reads both arrays as [x][y][z].
	local materials: { { { Enum.Material } } } = {}
	local occupancy: { { { number } } } = {}
	for ix = 1, columnsX do
		local materialPlane: { { Enum.Material } } = {}
		local occupancyPlane: { { number } } = {}
		for iy = 1, layers do
			materialPlane[iy] = table.create(columnsZ, AIR_MATERIAL)
			occupancyPlane[iy] = table.create(columnsZ, 0)
		end
		materials[ix] = materialPlane
		occupancy[ix] = occupancyPlane

		local x = x0 + (ix - 0.5) * VOXEL
		local west, here, east = grounds[ix], grounds[ix + 1], grounds[ix + 2]
		for iz = 1, columnsZ do
			local z = z0 + (iz - 0.5) * VOXEL
			local ground = here[iz + 1]
			local slopeX = (east[iz + 1] - west[iz + 1]) / (2 * VOXEL)
			local slopeZ = (here[iz + 2] - here[iz]) / (2 * VOXEL)
			local slope = math.sqrt(slopeX * slopeX + slopeZ * slopeZ)
			local surface = surfaceAt(map, points, paths, x, z, ground, slope)
			for iy = 1, layers do
				local y = bottom + (iy - 1) * VOXEL
				local solid = math.clamp((ground - y) / VOXEL, 0, 1)
				if solid > 0 then
					materialPlane[iy][iz] = surface
					occupancyPlane[iy][iz] = solid
				elseif y < map.waterLevel then
					materialPlane[iy][iz] = WATER_MATERIAL
					occupancyPlane[iy][iz] = math.clamp((map.waterLevel - y) / VOXEL, 0, 1)
				end
			end
		end
	end

	local region =
		Region3.new(Vector3.new(x0, bottom, z0), Vector3.new(x1, bottom + layers * VOXEL, z1))
	workspace.Terrain:WriteVoxels(region, VOXEL, materials, occupancy)
end

-- The water's look and the colour of every material, the same each run.
local function styleTerrain()
	local terrain = workspace.Terrain
	terrain.WaterColor = WATER_COLOR
	terrain.WaterTransparency = WATER_TRANSPARENCY
	terrain.WaterWaveSize = WATER_WAVE_SIZE
	terrain.WaterWaveSpeed = WATER_WAVE_SPEED
	terrain.WaterReflectance = WATER_REFLECTANCE
	for material, color in MATERIAL_COLORS do
		terrain:SetMaterialColor(material, color)
	end
end

-- The lowest and highest ground of the map, the water's surface counted.
local function heightRange(map: Types.Map): (number, number)
	local lowest, highest = math.huge, map.waterLevel
	for _, line in map.heights do
		for _, height in line do
			lowest = math.min(lowest, height)
			highest = math.max(highest, height)
		end
	end
	return lowest, highest
end

-- Writes the whole terrain, one chunk a frame. Yields.
local function writeTerrain(map: Types.Map)
	local lowest, highest = heightRange(map)
	local bottom = math.floor((lowest - BOTTOM_DEPTH) / VOXEL) * VOXEL
	local layers = math.max(1, math.ceil((highest - bottom) / VOXEL))
	local edge = math.ceil(map.half / VOXEL) * VOXEL
	for z0 = -edge, edge - 1, CHUNK do
		for x0 = -edge, edge - 1, CHUNK do
			writeChunk(
				map,
				x0,
				z0,
				math.min(x0 + CHUNK, edge),
				math.min(z0 + CHUNK, edge),
				bottom,
				layers
			)
			task.wait()
		end
	end
end

local function newPart(name: string, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Dressing that nothing collides with, hits or aims at.
local function decor(name: string, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = newPart(name, color, parent)
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- An upright cylinder of dressing from `bottom` to `top`.
local function column(
	name: string,
	x: number,
	z: number,
	bottom: number,
	top: number,
	radius: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = decor(name, color, material, parent)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(top - bottom, radius * 2, radius * 2)
	-- A cylinder's axis is its X; turned upright.
	part.CFrame = CFrame.new(x, (bottom + top) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

-- A box of dressing over the rect grown by `outset` on every side, from
-- `bottom` to `top`.
local function slab(
	name: string,
	prop: Types.Rect,
	outset: number,
	bottom: number,
	top: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = decor(name, color, material, parent)
	part.Size =
		Vector3.new((prop.halfWidth + outset) * 2, top - bottom, (prop.halfDepth + outset) * 2)
	part.Position = Vector3.new(prop.x, (bottom + top) / 2, prop.z)
	return part
end

-- `count` blocks of `size` on a circle of `radius` around (x, z), standing on
-- `y`, each laid along the circle (its length on Z).
local function ring(
	prefix: string,
	x: number,
	y: number,
	z: number,
	radius: number,
	count: number,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
)
	for index = 1, count do
		local angle = (index - 1) * 2 * math.pi / count
		local position =
			Vector3.new(x + math.cos(angle) * radius, y + size.Y / 2, z + math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local part = decor(prefix .. index, color, material, parent)
		part.Size = size
		part.CFrame = CFrame.lookAt(position, position + tangent)
	end
end

-- A stone prop standing on the point's flat ground, reaching below the lowest
-- ground under any of its corners. Its body is exactly the core's rect, so
-- what stops characters, dashes and the mouse's aim is what the rules use; a
-- ruin wall shows the body with a darker base and a lighter cap, a pillar or
-- a well hides it behind round stone drawn inside it.
local function buildProp(
	map: Types.Map,
	name: string,
	prop: Types.Rect,
	floor: number,
	parent: Instance,
	random: Random
)
	local lowest = floor
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x = prop.x + corner[1] * prop.halfWidth
		local z = prop.z + corner[2] * prop.halfDepth
		lowest = math.min(lowest, Map.heightAt(map, x, z))
	end
	local square = math.abs(prop.halfWidth - prop.halfDepth) <= SQUARE_TOLERANCE
	local well = square and prop.halfWidth > PILLAR_MAX_HALF
	local base = lowest - PROP_SINK
	local top = floor + (if well then WELL_HEIGHT else PROP_HEIGHT)
	local color = STONE_COLOR_DARK:Lerp(STONE_COLOR_LIGHT, random:NextNumber())
	local dark = color:Lerp(Color3.new(0, 0, 0), BASE_DARKEN)
	local light = color:Lerp(Color3.new(1, 1, 1), CAP_LIGHTEN)

	local model = Instance.new("Model")
	model.Name = name
	local body = newPart("Body", color, model)
	body.Material = STONE_MATERIAL
	body.Size = Vector3.new(prop.halfWidth * 2, top - base, prop.halfDepth * 2)
	body.Position = Vector3.new(prop.x, (base + top) / 2, prop.z)

	local x, z = prop.x, prop.z
	if not square then
		slab(
			"Base",
			prop,
			WALL_BASE_OUTSET,
			base,
			floor + WALL_BASE_HEIGHT,
			dark,
			STONE_BASE_MATERIAL,
			model
		)
		slab("Cap", prop, WALL_CAP_OUTSET, top, top + WALL_CAP_HEIGHT, light, STONE_MATERIAL, model)
	else
		body.Transparency = 1
		body.CastShadow = false
		local radius = prop.halfWidth
		if well then
			column("Rim", x, z, base, top, radius, color, STONE_BASE_MATERIAL, model)
			column(
				"Capstone",
				x,
				z,
				top - WELL_CAP_HEIGHT,
				top,
				radius + WELL_CAP_OUTSET,
				light,
				STONE_MATERIAL,
				model
			)
			local water = column(
				"Water",
				x,
				z,
				top,
				top + WELL_WATER_LIFT,
				radius - WELL_WATER_INSET,
				WELL_WATER_COLOR,
				Enum.Material.SmoothPlastic,
				model
			)
			water.Reflectance = WELL_WATER_REFLECTANCE
			water.CastShadow = false
		else
			column("Shaft", x, z, base, top, radius, color, STONE_MATERIAL, model)
			column(
				"Plinth",
				x,
				z,
				base,
				floor + PILLAR_PLINTH_HEIGHT,
				radius + PILLAR_RIM_OUTSET,
				dark,
				STONE_BASE_MATERIAL,
				model
			)
			column(
				"Capital",
				x,
				z,
				top - PILLAR_CAPITAL_HEIGHT,
				top,
				radius + PILLAR_RIM_OUTSET,
				light,
				STONE_MATERIAL,
				model
			)
		end
	end
	model.Parent = parent
end

-- A cover bush: a big leafy sphere with one or two smaller ones around it,
-- which nothing collides with or hits.
local function buildBush(
	map: Types.Map,
	config: Types.Config,
	name: string,
	spot: Types.Point,
	parent: Instance,
	random: Random
)
	local radius = config.map.coverRadius
	local ground = Map.heightAt(map, spot.x, spot.z)
	local model = Instance.new("Model")
	model.Name = name
	local function sphere(leaves: string, x: number, z: number, diameter: number, color: Color3)
		local part = decor(leaves, color, BUSH_MATERIAL, model)
		part.Shape = Enum.PartType.Ball
		part.Transparency = BUSH_TRANSPARENCY
		part.Size = Vector3.one * diameter
		part.Position = Vector3.new(x, ground + diameter * (0.5 - BUSH_SINK), z)
	end
	sphere("Leaves1", spot.x, spot.z, radius * BUSH_MAIN_DIAMETER, BUSH_COLOR_DARK)
	local start = random:NextNumber(0, 2 * math.pi)
	for index = 1, random:NextInteger(1, BUSH_MAX_SIDES) do
		-- The side spheres a third of a turn apart.
		local angle = start + (index - 1) * 2 * math.pi / 3
		sphere(
			"Leaves" .. index + 1,
			spot.x + math.cos(angle) * radius * BUSH_SIDE_OFFSET,
			spot.z + math.sin(angle) * radius * BUSH_SIDE_OFFSET,
			radius * random:NextNumber(BUSH_SIDE_MIN_DIAMETER, BUSH_SIDE_MAX_DIAMETER),
			if index % 2 == 1 then BUSH_COLOR_LIGHT else BUSH_COLOR_DARK
		)
	end
	model.Parent = parent
end

-- A zone's marker: a glowing ring on the zone's edge and a faint beam of
-- light from its centre, seen from across the map.
local function buildZoneMarker(
	map: Types.Map,
	name: string,
	point: Types.MapPoint,
	radius: number,
	parent: Instance
)
	local y = Map.heightAt(map, point.x, point.z) + MARKER_LIFT
	local model = Instance.new("Model")
	model.Name = name
	local length = 2 * math.pi * radius / ZONE_RING_SEGMENTS * ZONE_RING_OVERLAP
	ring(
		"Ring",
		point.x,
		y,
		point.z,
		radius,
		ZONE_RING_SEGMENTS,
		Vector3.new(ZONE_RING_WIDTH, ZONE_RING_HEIGHT, length),
		ZONE_COLOR,
		Enum.Material.Neon,
		model
	)
	local beam = column(
		"Beam",
		point.x,
		point.z,
		y,
		y + ZONE_BEAM_HEIGHT,
		ZONE_BEAM_RADIUS,
		ZONE_COLOR,
		Enum.Material.Neon,
		model
	)
	beam.Transparency = ZONE_BEAM_TRANSPARENCY
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CastShadow = false
		end
	end
	model.Parent = parent
end

-- An entry's marker: a circle of low standing stones.
local function buildEntryMarker(
	map: Types.Map,
	name: string,
	point: Types.MapPoint,
	parent: Instance
)
	local y = Map.heightAt(map, point.x, point.z) - ENTRY_STONE_SINK
	local model = Instance.new("Model")
	model.Name = name
	ring(
		"Stone",
		point.x,
		y,
		point.z,
		ENTRY_MARKER_RADIUS,
		ENTRY_STONES,
		ENTRY_STONE_SIZE,
		ENTRY_STONE_COLOR,
		STONE_MATERIAL,
		model
	)
	model.Parent = parent
end

-- An invisible, anchored box that stops characters, and the client's dash
-- and knockback rays, but nothing else.
local function barrier(
	name: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	bottom: number,
	top: number
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Transparency = 1
	part.CastShadow = false
	part.CanQuery = true
	part.CanTouch = false
	part.Size = Vector3.new(x1 - x0, top - bottom, z1 - z0)
	part.CFrame = CFrame.new((x0 + x1) / 2, (bottom + top) / 2, (z0 + z1) / 2)
	return part
end

-- The core does not let anyone walk on water, but a character would swim
-- across it and be pulled back every second. The water is sampled on a grid
-- of BARRIER_CELL squares, and each run of water cells along x in one row
-- becomes one barrier, so the barriers follow the core's water closely and
-- stay few. Yields between batches.
local function buildWaterBarriers(map: Types.Map, bottom: number, top: number, parent: Instance)
	local cells = math.ceil(2 * map.half / BARRIER_CELL)
	local origin = -map.half
	local count, batch = 0, 0
	for row = 1, cells do
		local z0 = origin + (row - 1) * BARRIER_CELL
		local z1 = z0 + BARRIER_CELL
		local cz = z0 + BARRIER_CELL / 2
		local start: number? = nil
		for col = 1, cells + 1 do
			local water = false
			if col <= cells then
				local cx = origin + (col - 0.5) * BARRIER_CELL
				water = Map.heightAt(map, cx, cz) <= map.waterLevel
			end
			if water and start == nil then
				start = col
			elseif not water and start ~= nil then
				count += 1
				batch += 1
				local x0 = origin + (start - 1) * BARRIER_CELL
				local x1 = origin + (col - 1) * BARRIER_CELL
				barrier("Water" .. count, x0, z0, x1, z1, bottom, top).Parent = parent
				start = nil
			end
		end
		if batch >= BARRIER_BATCH then
			batch = 0
			task.wait()
		end
	end
end

-- Four walls just outside the core's square, so nothing leaves the map.
local function buildEdgeWalls(map: Types.Map, bottom: number, top: number, parent: Instance)
	local inner = map.half
	local outer = map.half + EDGE_WALL_THICKNESS
	barrier("EdgeWest", -outer, -outer, -inner, outer, bottom, top).Parent = parent
	barrier("EdgeEast", inner, -outer, outer, outer, bottom, top).Parent = parent
	barrier("EdgeNorth", -inner, -outer, inner, -inner, bottom, top).Parent = parent
	barrier("EdgeSouth", -inner, inner, inner, outer, bottom, top).Parent = parent
end

-- Replaces the previous run's map with this one. Yields while the terrain and
-- the barriers are built.
function MapBuilder.build(map: Types.Map, config: Types.Config)
	MapBuilder.clear()
	styleTerrain()
	writeTerrain(map)

	local root = Instance.new("Folder")
	root.Name = "World"
	folder = root
	-- The props are the only solid parts the client's mouse aim lands on, so
	-- they get a folder of their own, as the barriers do.
	local propFolder = Instance.new("Folder")
	propFolder.Name = "Props"
	propFolder.Parent = root
	local barrierFolder = Instance.new("Folder")
	barrierFolder.Name = "Barriers"
	barrierFolder.Parent = root
	-- Only the look varies with it: the stone's colour, the bushes' shape.
	local random = Random.new()
	local props, covers = 0, 0
	for _, point in map.points do
		local floor = Map.heightAt(map, point.x, point.z)
		for _, prop in point.props do
			props += 1
			buildProp(map, "Prop" .. props, prop, floor, propFolder, random)
		end
		for _, spot in point.cover do
			covers += 1
			buildBush(map, config, "Cover" .. covers, spot, root, random)
		end
	end
	for _, spot in map.fieldCover do
		covers += 1
		buildBush(map, config, "Cover" .. covers, spot, root, random)
	end
	for index, id in map.zonePoints do
		buildZoneMarker(map, "Zone" .. index, map.points[id], config.map.zoneRadius, root)
	end
	for index, id in map.entries do
		buildEntryMarker(map, "Entry" .. index, map.points[id], root)
	end
	root.Parent = workspace

	-- The barriers go in after the rest, a batch a frame, into the folder
	-- already in the workspace.
	local lowest, highest = heightRange(map)
	local bottom = lowest - BARRIER_SINK
	local top = math.max(highest, config.map.maxHeight) + BARRIER_CLEARANCE
	buildEdgeWalls(map, bottom, top, barrierFolder)
	buildWaterBarriers(map, bottom, top, barrierFolder)
end

-- Removes the terrain and the parts of the current map, the barriers among
-- them, and what a default place brings: the baseplate and any spawn
-- location. Characters reach the map through the run's teleport.
function MapBuilder.clear()
	workspace.Terrain:Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant:Destroy()
		end
	end
end

return MapBuilder
