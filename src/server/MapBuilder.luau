--!strict
-- Builds the open map of a run (ADR-0012) in Roblox: terrain from the core's
-- heights, with the paths and the points' footprints painted on it, then the
-- props, the cover bushes and the zone and entry markers as plain parts in one
-- folder, and invisible barriers over the water and around the edge that hold
-- characters where the rules let them stand. Pure presentation of the core's
-- data; nothing here is read back by the rules.

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
local WATER_MATERIAL = Enum.Material.Water
local AIR_MATERIAL = Enum.Material.Air
local PROP_HEIGHT = 14
-- How far a prop reaches below the lowest ground under it, so a slope never
-- shows a gap.
local PROP_SINK = 2
local PROP_COLOR = Color3.fromRGB(58, 60, 68)
local COVER_HEIGHT = 4
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
local COVER_COLOR = Color3.fromRGB(70, 120, 60)
local MARKER_THICKNESS = 0.4
-- How far a marker floats above the ground, so the terrain does not hide it.
local MARKER_LIFT = 0.2
local ZONE_MARKER_COLOR = Color3.fromRGB(70, 110, 140)
local ENTRY_MARKER_RADIUS = 6
local ENTRY_MARKER_COLOR = Color3.fromRGB(104, 124, 108)

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
-- band, the bed of the water or grass.
local function surfaceAt(
	map: Types.Map,
	points: { Types.MapPoint },
	paths: { Types.Path },
	x: number,
	z: number,
	ground: number
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
		for iz = 1, columnsZ do
			local z = z0 + (iz - 0.5) * VOXEL
			local ground = groundAt(map, x, z)
			local surface = surfaceAt(map, points, paths, x, z, ground)
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

-- A solid prop standing on the point's flat ground, reaching below the lowest
-- ground under any of its corners.
local function buildProp(
	map: Types.Map,
	name: string,
	prop: Types.Rect,
	floor: number,
	parent: Instance
)
	local lowest = floor
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x = prop.x + corner[1] * prop.halfWidth
		local z = prop.z + corner[2] * prop.halfDepth
		lowest = math.min(lowest, Map.heightAt(map, x, z))
	end
	local base = lowest - PROP_SINK
	local top = floor + PROP_HEIGHT
	local part = newPart(name, PROP_COLOR, parent)
	part.Size = Vector3.new(prop.halfWidth * 2, top - base, prop.halfDepth * 2)
	part.Position = Vector3.new(prop.x, (base + top) / 2, prop.z)
end

-- An upright cylinder standing on `y` that nothing collides with or hits.
local function disc(
	name: string,
	x: number,
	y: number,
	z: number,
	radius: number,
	height: number,
	color: Color3,
	parent: Instance
): Part
	local part = newPart(name, color, parent)
	part.Shape = Enum.PartType.Cylinder
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

local function buildBush(
	map: Types.Map,
	config: Types.Config,
	name: string,
	spot: Types.Point,
	parent: Instance
)
	local bush = disc(
		name,
		spot.x,
		Map.heightAt(map, spot.x, spot.z),
		spot.z,
		config.map.coverRadius,
		COVER_HEIGHT,
		COVER_COLOR,
		parent
	)
	bush.Material = Enum.Material.Grass
	bush.Transparency = 0.25
end

local function buildMarker(
	map: Types.Map,
	name: string,
	point: Types.MapPoint,
	radius: number,
	color: Color3,
	parent: Instance
)
	local y = Map.heightAt(map, point.x, point.z) + MARKER_LIFT
	local marker = disc(name, point.x, y, point.z, radius, MARKER_THICKNESS, color, parent)
	marker.CastShadow = false
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
	local props, covers = 0, 0
	for _, point in map.points do
		local floor = Map.heightAt(map, point.x, point.z)
		for _, prop in point.props do
			props += 1
			buildProp(map, "Prop" .. props, prop, floor, propFolder)
		end
		for _, spot in point.cover do
			covers += 1
			buildBush(map, config, "Cover" .. covers, spot, root)
		end
	end
	for _, spot in map.fieldCover do
		covers += 1
		buildBush(map, config, "Cover" .. covers, spot, root)
	end
	for index, id in map.zonePoints do
		local point = map.points[id]
		buildMarker(map, "Zone" .. index, point, config.map.zoneRadius, ZONE_MARKER_COLOR, root)
	end
	for index, id in map.entries do
		local point = map.points[id]
		buildMarker(map, "Entry" .. index, point, ENTRY_MARKER_RADIUS, ENTRY_MARKER_COLOR, root)
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
-- them.
function MapBuilder.clear()
	workspace.Terrain:Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return MapBuilder
