--!strict
-- Builds the forest map in the workspace from the core's arena (ADR-0014,
-- ADR-0020): a round terrain ground sculpted from the arena's terrain
-- (ADR-0023: plateaus, the stream, ponds, gently rolling ground) with the
-- places' clearings and the paths to them (stage 3b),
-- an invisible wall at the edge, a prop per obstacle drawn from its kind's
-- mesh (or built from parts while the kind has none), an invisible solid body
-- per obstacle circle, the shrines, the extraction chest and the portal's
-- arch, each from its own mesh with parts as the fallback, the lairs' columns
-- of light (ADR-0021) and the final boss's rise point. Everything here is
-- presentation; the rules live in the core.

local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local ArenaBuilder = {}

-- Presentation constants, not gameplay numbers.
local GROUND_THICKNESS = 4
local GROUND_OVERHANG = 80
local PATCH_MATERIALS = {
	Enum.Material.LeafyGrass,
	Enum.Material.Ground,
	Enum.Material.LeafyGrass,
	Enum.Material.Grass,
}
local PATCH_COUNT = 120
local PATCH_RADIUS_MIN, PATCH_RADIUS_MAX = 6, 18
-- Clearings: a lighter grass disc under every place. Terrain colours are per
-- material, so the clearings take a material nothing else uses, recoloured.
local CLEARING_MATERIAL = Enum.Material.Snow
local CLEARING_COLOR = Color3.fromRGB(138, 170, 88)
-- The paths: dirt bands along the core's polylines, a disc every PATH_STEP
-- studs, kept off the start's ring of stones.
local PATH_MATERIAL = Enum.Material.Mud
local PATH_COLOR = Color3.fromRGB(128, 102, 68)
local PATH_STEP = 3
local PATH_START_GAP = 10
local FLOWER_COUNT = 50
local FLOWER_COLORS = {
	Color3.fromRGB(240, 200, 80),
	Color3.fromRGB(230, 120, 150),
	Color3.fromRGB(220, 230, 240),
}
local WALL_SEGMENTS = 48
local TREE_LINE_RINGS = 2
local TREE_LINE_OFFSET = 8
local TREE_LINE_SPACING = 11
local TREE_LINE_RADIUS = 5
local WALL_HEIGHT = 40
local WALL_THICKNESS = 4
local BODY_HEIGHT = 12
-- How far an obstacle's body reaches below the ground, and where around its
-- circle the ground is read (the centre and four points on the edge).
local BODY_SINK = 1
local BODY_SAMPLES = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- Obstacle kinds the sculpted ground draws: no prop, only the body.
local SCULPTED_KINDS: { [string]: boolean } = { cliff = true, channel = true }
local BUILD_BATCH = 40

local TRUNK_COLORS =
	{ Color3.fromRGB(96, 66, 42), Color3.fromRGB(80, 54, 36), Color3.fromRGB(112, 80, 52) }
local CANOPY_COLORS = {
	Color3.fromRGB(58, 125, 62),
	Color3.fromRGB(44, 104, 54),
	Color3.fromRGB(92, 150, 70),
	Color3.fromRGB(150, 120, 50),
	Color3.fromRGB(176, 92, 48),
}
local ROCK_COLORS =
	{ Color3.fromRGB(120, 122, 128), Color3.fromRGB(96, 98, 104), Color3.fromRGB(140, 138, 130) }
local MOSS_COLOR = Color3.fromRGB(96, 140, 72)
local RUIN_COLOR = Color3.fromRGB(150, 140, 120)
local RUIN_DARK = Color3.fromRGB(104, 96, 84)
local FENCE_COLOR = Color3.fromRGB(122, 90, 60)
local WATER_COLOR = Color3.fromRGB(64, 138, 140)
local POND_BED_COLOR = Color3.fromRGB(52, 60, 44)
local POND_RIM_MATERIAL = Enum.Material.Sand
local START_STONE_COLOR = Color3.fromRGB(170, 160, 140)
local CHEST_WOOD = Color3.fromRGB(120, 72, 36)
local CHEST_BAND = Color3.fromRGB(230, 190, 90)
local CHEST_GLOW = Color3.fromRGB(255, 220, 130)
local CHEST_GLOW_TRANSPARENCY = 0.6
local CHEST_GLOW_SPENT = 0.9
local CHEST_LIGHT_BRIGHTNESS = 2.5
local CHEST_LIGHT_SPENT = 0.8
-- An opened chest mesh rises a little and turns, so the change reads.
local CHEST_OPEN_LIFT = 0.5
local CHEST_OPEN_TURN = math.rad(15)

-- Shrines: the kind's mesh (or a stone plinth and a floating emblem) and a
-- beam in the kind's colour.
local SHRINE_PROPS: { [string]: string } = {
	boon = "shrineBoon",
	pact = "shrinePact",
	trial = "shrineTrial",
	spring = "shrineSpring",
}
local SHRINE_COLORS: { [string]: Color3 } = {
	boon = Color3.fromRGB(255, 200, 80),
	pact = Color3.fromRGB(220, 60, 80),
	trial = Color3.fromRGB(170, 90, 255),
	spring = Color3.fromRGB(80, 220, 230),
}
local SHRINE_STONE = Color3.fromRGB(132, 128, 120)
local SHRINE_STONE_DARK = Color3.fromRGB(98, 94, 88)
local SHRINE_SPENT = Color3.fromRGB(120, 120, 124)
local SHRINE_EMBLEM_HEIGHT = 5
local BEAM_HEIGHT = 60
local BEAM_RADIUS = 0.5
local BEAM_GLOW_RADIUS = 1.4
local BEAM_TRANSPARENCY = 0.35
local BEAM_GLOW_TRANSPARENCY = 0.85
local BEAM_DIM_TRANSPARENCY = 0.8
local SHRINE_LIGHT_BRIGHTNESS = 3
local SHRINE_LIGHT_DIM = 0.8
-- A textured mesh ignores Color, so a used shrine's mesh fades instead.
local SHRINE_SPENT_TRANSPARENCY = 0.4
-- The invisible plinth under a shrine mesh, as tall as the part plinth.
local SHRINE_BODY_HEIGHT = 1

-- Lairs (ADR-0021): a column of light in the kind's colour over the landmark
-- the arena already drew, pulsing slowly while the lair sleeps, steady and
-- brighter once it wakes, out once it is silenced; embers rise at its base.
local LAIR_BEAM_HEIGHT = 80
local LAIR_BEAM_RADIUS = 1.2
local LAIR_GLOW_RADIUS = 3.5
local LAIR_BEAM_AWAKE = 0.15
local LAIR_GLOW_AWAKE = 0.7
-- A sleeping column's transparency swings between these.
local LAIR_BEAM_ASLEEP = { 0.45, 0.75 }
local LAIR_GLOW_ASLEEP = { 0.85, 0.95 }
local LAIR_LIGHT_ASLEEP = { 1, 3 }
local LAIR_LIGHT_AWAKE = 6
local LAIR_LIGHT_RANGE = 32
local LAIR_PULSE_SECONDS = 2.5
local LAIR_EMBER_AREA = 14
local LAIR_EMBER_RATE_ASLEEP = 8
local LAIR_EMBER_RATE_AWAKE = 24
-- The final boss's rise point: a cracked ring of light on the ground with
-- thin beams radiating from it.
local RISE_COLOR = Color3.fromRGB(255, 96, 64)
local RISE_RADIUS = 14
local RISE_RING_SEGMENTS = 24
local RISE_RING_WIDTH = 1.2
local RISE_CRACKS = 10
local RISE_CRACK_LENGTH = 12
local RISE_CRACK_WIDTH = 0.35
local RISE_BEAM_HEIGHT = 30
local RISE_BEAM_RADIUS = 0.25

-- The sculpted ground (stage 3d, ADR-0023): the core's terrain description
-- turned into a height at every point, sampled per voxel column at build and
-- per character per heartbeat. These depths and slopes are the look; the
-- shapes and the slow factor are the core's.
local VOXEL = 4
-- Voxel columns per WriteVoxelChannels call, along each side.
local SCULPT_CHUNK = 16
local SCULPT_CHUNKS_PER_FRAME = 4
-- The lowest voxel layer's bottom: the ground is solid from here up.
local SCULPT_FLOOR = -8
-- The side of the buckets that list which features reach a point.
local BUCKET_SIZE = 32
local CHANNEL_DEPTH = -3
local SHALLOW_DEPTH = -1
local WATER_LEVEL = -0.5
-- The step from the channel's floor to the bank's, centred on its edge.
local CHANNEL_STEP = 1
-- The bank's lip, from the shallows' floor up to the plain.
local SHORE_LIP = 2
-- A ford fades into the channel over this much beyond its radius.
local FORD_BLEND = 3
-- The rolling ground returns over this much beyond a feature's edge.
local FEATURE_FALLOFF = 8
local PAD_FALLOFF = 6
-- A ramp climbs from the plain to the plateau's top across this band around
-- the plateau's edge (inside, outside): 12 studs for 6-8 high.
local RAMP_INNER = 6
local RAMP_OUTER = 6
-- Elsewhere the edge drops sheer over this much, and the ground around it is
-- rock: a rim on top and scree at the foot.
local CLIFF_FALL = 1
local ROCK_RIM = 3
local ROCK_FOOT = 2
-- The rolling ground: two octaves of noise, gained and clipped so its range
-- spans Config.terrain.rollingHeight.
local ROLL_SCALE = 90
local ROLL_DETAIL_SCALE = 35
local ROLL_DETAIL = 0.5
local ROLL_GAIN = 1.6
local BED_MATERIAL = Enum.Material.Mud
local SHORE_MATERIAL = Enum.Material.Sand
local CLIFF_MATERIAL = Enum.Material.Rock
local RAMP_MATERIAL = Enum.Material.Ground
local GRASS_MATERIAL = Enum.Material.Grass

-- What covers a point of ground, beyond the painted discs of the plain.
local SURFACE_PLAIN = 0
local SURFACE_ROCK = 1
local SURFACE_SHORE = 2
local SURFACE_BED = 3
local SURFACE_RAMP = 4
-- The bucket key's offset, so negative bucket indices make positive keys.
local BUCKET_OFFSET = 2048
local BUCKET_STRIDE = 4096

type Disc = { x: number, z: number, radius: number }
type Paint = { x: number, z: number, radius: number, material: Enum.Material }
type PlateauShape = {
	x: number,
	z: number,
	radius: number,
	height: number,
	ramps: { number },
	-- Half a ramp's width along the edge, in studs.
	rampHalf: number,
}
type Segment = { ax: number, az: number, dx: number, dz: number, inverse: number }
type Bucket = {
	pads: { Disc },
	plateaus: { PlateauShape },
	ponds: { Types.Pond },
	segments: { Segment },
	fords: { Types.Ford },
	paints: { Paint },
}
type Heightmap = {
	buckets: { [number]: Bucket },
	-- Half the rolling ground's range: zero on a map without terrain.
	rolling: number,
	ox: number,
	oz: number,
	detailX: number,
	detailZ: number,
	channelHalfWidth: number,
	-- The shallows' outer edge from the stream's centre line.
	shallowEdge: number,
	-- The highest the ground rises, for the voxel layers.
	highest: number,
}

-- The current map's ground; nil while none is built, which reads as flat.
local heightmap: Heightmap? = nil

local function smoothstep(from: number, to: number, value: number): number
	if value <= from then
		return 0
	elseif value >= to then
		return 1
	end
	local t = (value - from) / (to - from)
	return t * t * (3 - 2 * t)
end

local function lerp(from: number, to: number, t: number): number
	return from + (to - from) * t
end

local function bucketKey(ix: number, iz: number): number
	return (ix + BUCKET_OFFSET) * BUCKET_STRIDE + iz + BUCKET_OFFSET
end

-- The buckets a box over the ground touches, created as needed.
local function bucketsOver(
	map: Heightmap,
	x0: number,
	z0: number,
	x1: number,
	z1: number
): { Bucket }
	local result = {}
	for ix = math.floor(x0 / BUCKET_SIZE), math.floor(x1 / BUCKET_SIZE) do
		for iz = math.floor(z0 / BUCKET_SIZE), math.floor(z1 / BUCKET_SIZE) do
			local key = bucketKey(ix, iz)
			local bucket = map.buckets[key]
			if bucket == nil then
				bucket =
					{ pads = {}, plateaus = {}, ponds = {}, segments = {}, fords = {}, paints = {} }
				map.buckets[key] = bucket
			end
			table.insert(result, bucket)
		end
	end
	return result
end

local function around(map: Heightmap, x: number, z: number, reach: number): { Bucket }
	return bucketsOver(map, x - reach, z - reach, x + reach, z + reach)
end

-- The heightmap of an arena's terrain. An arena without plateaus, stream or
-- ponds stays flat, as the map was before the terrain.
local function newHeightmap(arena: Types.Arena): Heightmap
	local terrain = arena.terrain
	local shaped = #terrain.plateaus > 0 or terrain.stream ~= nil or #terrain.ponds > 0
	-- The noise's offsets come from the map, so a map always rolls the same.
	local random = Random.new(arena.chestX * 7919 + arena.chestZ * 104729 + 1)
	local stream = terrain.stream
	local map: Heightmap = {
		buckets = {},
		rolling = if shaped then Config.terrain.rollingHeight / 2 else 0,
		ox = random:NextNumber(-1000, 1000),
		oz = random:NextNumber(-1000, 1000),
		detailX = random:NextNumber(-1000, 1000),
		detailZ = random:NextNumber(-1000, 1000),
		channelHalfWidth = if stream then stream.channelHalfWidth else 0,
		shallowEdge = if stream then stream.channelHalfWidth + stream.bankWidth else 0,
		highest = 0,
	}
	map.highest = map.rolling
	for _, pad in terrain.pads do
		local disc = { x = pad.x, z = pad.z, radius = pad.radius }
		for _, bucket in around(map, pad.x, pad.z, pad.radius + PAD_FALLOFF) do
			table.insert(bucket.pads, disc)
		end
	end
	for _, plateau in terrain.plateaus do
		local shape: PlateauShape = {
			x = plateau.x,
			z = plateau.z,
			radius = plateau.radius,
			height = plateau.height,
			ramps = plateau.ramps,
			rampHalf = Config.terrain.rampWidth / 2,
		}
		map.highest = math.max(map.highest, plateau.height)
		local reach = plateau.radius + RAMP_OUTER + FEATURE_FALLOFF
		for _, bucket in around(map, plateau.x, plateau.z, reach) do
			table.insert(bucket.plateaus, shape)
		end
	end
	for _, pond in terrain.ponds do
		for _, bucket in around(map, pond.x, pond.z, pond.radius + SHORE_LIP + FEATURE_FALLOFF) do
			table.insert(bucket.ponds, pond)
		end
	end
	if stream then
		local reach = map.shallowEdge + SHORE_LIP + FEATURE_FALLOFF
		for index = 2, #stream.points do
			local a, b = stream.points[index - 1], stream.points[index]
			local dx, dz = b.x - a.x, b.z - a.z
			local length = dx * dx + dz * dz
			local segment: Segment = {
				ax = a.x,
				az = a.z,
				dx = dx,
				dz = dz,
				inverse = if length > 0 then 1 / length else 0,
			}
			local buckets = bucketsOver(
				map,
				math.min(a.x, b.x) - reach,
				math.min(a.z, b.z) - reach,
				math.max(a.x, b.x) + reach,
				math.max(a.z, b.z) + reach
			)
			for _, bucket in buckets do
				table.insert(bucket.segments, segment)
			end
		end
		for _, ford in stream.fords do
			for _, bucket in around(map, ford.x, ford.z, ford.radius + FORD_BLEND) do
				table.insert(bucket.fords, ford)
			end
		end
	end
	return map
end

-- A disc of `material` on the plain; a later disc covers an earlier one.
local function addPaint(
	map: Heightmap,
	x: number,
	z: number,
	radius: number,
	material: Enum.Material
)
	local paint = { x = x, z = z, radius = radius, material = material }
	for _, bucket in around(map, x, z, radius) do
		table.insert(bucket.paints, paint)
	end
end

local function rollingAt(map: Heightmap, x: number, z: number): number
	local n = math.noise(x / ROLL_SCALE + map.ox, z / ROLL_SCALE + map.oz)
		+ ROLL_DETAIL
			* math.noise(x / ROLL_DETAIL_SCALE + map.detailX, z / ROLL_DETAIL_SCALE + map.detailZ)
	return map.rolling * math.clamp(n * ROLL_GAIN, -1, 1)
end

-- The floor of water whose deep part ends `edge` from its centre and whose
-- shallows end `shallow` from it, at distance `d`.
local function waterFloor(d: number, edge: number, shallow: number): number
	if d < edge + CHANNEL_STEP then
		return lerp(
			CHANNEL_DEPTH,
			SHALLOW_DEPTH,
			smoothstep(edge - CHANNEL_STEP, edge + CHANNEL_STEP, d)
		)
	end
	return lerp(SHALLOW_DEPTH, 0, smoothstep(shallow, shallow + SHORE_LIP, d))
end

-- The ground's height at (x, z), what covers it and whether water stands on it.
local function sample(map: Heightmap, x: number, z: number): (number, number, boolean)
	local bucket = map.buckets[bucketKey(math.floor(x / BUCKET_SIZE), math.floor(z / BUCKET_SIZE))]
	local rolling = if map.rolling > 0 then rollingAt(map, x, z) else 0
	if bucket == nil then
		return rolling, SURFACE_PLAIN, false
	end
	-- How far the rolling ground is flattened, from 0 (not) to 1 (flat).
	local flat = 0
	for _, pad in bucket.pads do
		local dx, dz = x - pad.x, z - pad.z
		local d = math.sqrt(dx * dx + dz * dz)
		flat = math.max(flat, 1 - smoothstep(pad.radius, pad.radius + PAD_FALLOFF, d))
	end
	-- The water's floor, where water cuts the ground.
	local cut = math.huge
	if #bucket.segments > 0 then
		local nearest = math.huge
		for _, segment in bucket.segments do
			local t = math.clamp(
				((x - segment.ax) * segment.dx + (z - segment.az) * segment.dz) * segment.inverse,
				0,
				1
			)
			local px, pz = segment.ax + segment.dx * t - x, segment.az + segment.dz * t - z
			nearest = math.min(nearest, px * px + pz * pz)
		end
		local d = math.sqrt(nearest)
		local edge = map.shallowEdge
		flat =
			math.max(flat, 1 - smoothstep(edge + SHORE_LIP, edge + SHORE_LIP + FEATURE_FALLOFF, d))
		if d < edge + SHORE_LIP then
			local floor = waterFloor(d, map.channelHalfWidth, edge)
			-- A ford is shallow across the whole width.
			for _, ford in bucket.fords do
				local fx, fz = x - ford.x, z - ford.z
				local shallow = 1
					- smoothstep(
						ford.radius,
						ford.radius + FORD_BLEND,
						math.sqrt(fx * fx + fz * fz)
					)
				if shallow > 0 and floor < SHALLOW_DEPTH then
					floor = lerp(floor, SHALLOW_DEPTH, shallow)
				end
			end
			cut = math.min(cut, floor)
		end
	end
	for _, pond in bucket.ponds do
		local dx, dz = x - pond.x, z - pond.z
		local d = math.sqrt(dx * dx + dz * dz)
		flat = math.max(
			flat,
			1 - smoothstep(pond.radius + SHORE_LIP, pond.radius + SHORE_LIP + FEATURE_FALLOFF, d)
		)
		if d < pond.radius + SHORE_LIP then
			cut = math.min(cut, waterFloor(d, pond.radius - pond.rimWidth, pond.radius))
		end
	end
	-- The plateaus' rise, and what covers it.
	local rise, riseSurface = 0, SURFACE_PLAIN
	for _, plateau in bucket.plateaus do
		local dx, dz = x - plateau.x, z - plateau.z
		local d = math.sqrt(dx * dx + dz * dz)
		local r = plateau.radius
		flat = math.max(flat, 1 - smoothstep(r + RAMP_OUTER, r + RAMP_OUTER + FEATURE_FALLOFF, d))
		if d < r + RAMP_OUTER then
			local onRamp = false
			if d > r - RAMP_INNER then
				local bearing = math.atan2(dz, dx)
				for _, ramp in plateau.ramps do
					local delta = math.abs((bearing - ramp + math.pi) % (2 * math.pi) - math.pi)
					if delta * r <= plateau.rampHalf then
						onRamp = true
						break
					end
				end
			end
			local top, surface
			if onRamp then
				top = plateau.height
					* math.clamp((r + RAMP_OUTER - d) / (RAMP_INNER + RAMP_OUTER), 0, 1)
				surface = SURFACE_RAMP
			else
				top = plateau.height * (1 - smoothstep(r, r + CLIFF_FALL, d))
				surface = if d >= r - ROCK_RIM and d <= r + CLIFF_FALL + ROCK_FOOT
					then SURFACE_ROCK
					else SURFACE_PLAIN
			end
			if top > rise or (top == rise and surface ~= SURFACE_PLAIN) then
				rise, riseSurface = top, surface
			end
		end
	end
	local height = rolling * (1 - flat)
	local surface = SURFACE_PLAIN
	if cut < height then
		height = cut
		surface = if cut < (CHANNEL_DEPTH + SHALLOW_DEPTH) / 2 then SURFACE_BED else SURFACE_SHORE
		return height, surface, height < WATER_LEVEL
	end
	if rise >= height then
		height = rise
		surface = riseSurface
	end
	return height, surface, false
end

-- The ground's height at (x, z) on the current map: 0 where none is built.
function ArenaBuilder.groundHeight(x: number, z: number): number
	local map = heightmap
	if map == nil then
		return 0
	end
	return (sample(map, x, z))
end

-- The material of a voxel column whose surface is `surface`: the painted
-- discs cover the plain, the last one over (x, z) on top.
local function columnMaterial(map: Heightmap, surface: number, x: number, z: number): Enum.Material
	if surface == SURFACE_ROCK then
		return CLIFF_MATERIAL
	elseif surface == SURFACE_SHORE then
		return SHORE_MATERIAL
	elseif surface == SURFACE_BED then
		return BED_MATERIAL
	elseif surface == SURFACE_RAMP then
		return RAMP_MATERIAL
	end
	local bucket = map.buckets[bucketKey(math.floor(x / BUCKET_SIZE), math.floor(z / BUCKET_SIZE))]
	local material = GRASS_MATERIAL
	if bucket then
		for _, paint in bucket.paints do
			local dx, dz = x - paint.x, z - paint.z
			if dx * dx + dz * dz <= paint.radius * paint.radius then
				material = paint.material
			end
		end
	end
	return material
end

-- Without shorelines a voxel holds a solid or water, not both: water takes
-- the voxels under the water line that are mostly empty.
local function legacyWater(materials: { any }, solids: { any }, liquids: { any })
	for i, plane in materials do
		for j, row in plane do
			for k, liquid in liquids[i][j] do
				if liquid > 0 and solids[i][j][k] < 0.5 then
					row[k] = Enum.Material.Water
					solids[i][j][k] = 1
				end
			end
		end
	end
end

-- Writes the heightmap into the Terrain over the disc of `outer`, in chunks
-- of voxel columns, yielding between batches of chunks.
local function sculpt(map: Heightmap, outer: number)
	local terrain = workspace.Terrain
	local top = math.ceil((map.highest + VOXEL) / VOXEL) * VOXEL
	local layers = (top - SCULPT_FLOOR) / VOXEL
	local span = SCULPT_CHUNK * VOXEL
	local channels = true
	local written = 0
	for cx = math.floor(-outer / span), math.ceil(outer / span) - 1 do
		for cz = math.floor(-outer / span), math.ceil(outer / span) - 1 do
			local x0, z0 = cx * span, cz * span
			-- The chunk's nearest point to the centre.
			local nx = math.clamp(0, x0, x0 + span)
			local nz = math.clamp(0, z0, z0 + span)
			if nx * nx + nz * nz > outer * outer then
				continue
			end
			local materials, solids, liquids = {}, {}, {}
			for i = 1, SCULPT_CHUNK do
				materials[i], solids[i], liquids[i] = {}, {}, {}
				for j = 1, layers do
					materials[i][j], solids[i][j], liquids[i][j] = {}, {}, {}
				end
			end
			for i = 1, SCULPT_CHUNK do
				local x = x0 + (i - 0.5) * VOXEL
				for k = 1, SCULPT_CHUNK do
					local z = z0 + (k - 0.5) * VOXEL
					local inside = x * x + z * z <= outer * outer
					local height, surface, wet = 0, SURFACE_PLAIN, false
					local material = Enum.Material.Air
					if inside then
						height, surface, wet = sample(map, x, z)
						material = columnMaterial(map, surface, x, z)
					end
					for j = 1, layers do
						local bottom = SCULPT_FLOOR + (j - 1) * VOXEL
						local solid = if inside
							then math.clamp((height - bottom) / VOXEL, 0, 1)
							else 0
						materials[i][j][k] = if solid > 0 then material else Enum.Material.Air
						solids[i][j][k] = solid
						liquids[i][j][k] = if wet
							then math.clamp((WATER_LEVEL - bottom) / VOXEL, 0, 1)
							else 0
					end
				end
			end
			local region = Region3.new(
				Vector3.new(x0, SCULPT_FLOOR, z0),
				Vector3.new(x0 + span, top, z0 + span)
			)
			if channels then
				local ok, problem = pcall(terrain.WriteVoxelChannels, terrain, region, VOXEL, {
					SolidMaterial = materials,
					SolidOccupancy = solids,
					LiquidOccupancy = liquids,
				})
				if not ok then
					warn(`ArenaBuilder: no voxel channels, writing water as voxels: {problem}`)
					channels = false
				end
			end
			if not channels then
				legacyWater(materials, solids, liquids)
				terrain:WriteVoxels(region, VOXEL, materials, solids)
			end
			written += 1
			if written % SCULPT_CHUNKS_PER_FRAME == 0 then
				task.wait()
			end
		end
	end
end

-- Moves every part in `container` up by `dy`: what was built on flat ground
-- stands on the sculpted ground.
local function lift(container: Instance, dy: number)
	if dy == 0 then
		return
	end
	local offset = Vector3.new(0, dy, 0)
	if container:IsA("BasePart") then
		container.CFrame += offset
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame += offset
		end
	end
end

type Look = { part: BasePart, color: Color3, material: Enum.Material }
type ShrineLook = {
	beam: Part,
	glow: Part,
	light: PointLight,
	emblem: { Look },
	mesh: MeshPart?,
	state: string?,
}

type LairLook = {
	beam: Part,
	glow: Part,
	light: PointLight,
	embers: ParticleEmitter,
	pulses: { Tween },
	state: string?,
}

-- A circle of a kind's footprint, offset from the prop's centre (Config.maps).
type FootprintCircle = { dx: number, dz: number, radius: number }

-- A prop to draw: where its centre is, how it turns, its size factor and
-- lean, and the world position of each circle of its kind's footprint.
type Prop = {
	kind: string,
	x: number,
	z: number,
	rotation: number,
	radius: number,
	group: number,
	scale: number,
	lean: number,
	circles: { { x: number, z: number, radius: number } },
}

local folder: Folder? = nil
-- The look's Random of the current map, kept for the shrines built after it.
local lookRandom: Random? = nil
local chestModel: Model? = nil
local chestLid: Part? = nil
local chestMesh: MeshPart? = nil
local chestClosed: CFrame? = nil
-- The ground's height under the chest, for the part chest's lid.
local chestGround = 0
local chestGlow: Part? = nil
local chestLight: PointLight? = nil
local portalArch: MeshPart? = nil
local shrineLooks: { [number]: ShrineLook } = {}
local lairLooks: { [number]: LairLook } = {}
local finalRise: Model? = nil
-- One loaded mesh per mesh id, cloned for every prop; false when it failed.
local templates: { [string]: MeshPart | false } = {}

local function newPart(name: string, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function quiet(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Dressing that nothing collides with or queries.
local function decor(name: string, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = newPart(name, color, material, parent)
	quiet(part)
	return part
end

-- An invisible, anchored body the character walks against and the knockback
-- and dash raycasts stop at. Its radius is the core's circle plus the
-- player's radius, so physics stops the character's centre where the rules
-- stop it; a narrower body let the character slide past the core's stop and
-- the server pulled it back every few hundred milliseconds.
local function body(
	name: string,
	x: number,
	z: number,
	radius: number,
	bottom: number,
	height: number,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Transparency = 1
	part.CastShadow = false
	part.CanQuery = true
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(x, bottom + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = parent
	return part
end

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

-- The core's rotation turns (dx, dz) by `rotation` in the x/z plane; the same
-- turn as a CFrame is a yaw of -rotation.
local function turn(dx: number, dz: number, rotation: number): (number, number)
	local c, s = math.cos(rotation), math.sin(rotation)
	return dx * c - dz * s, dx * s + dz * c
end

local function yaw(rotation: number): CFrame
	return CFrame.Angles(0, -rotation, 0)
end

local function cylinder(
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
	part.CFrame = CFrame.new(x, (bottom + top) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

local function ball(
	name: string,
	position: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = decor(name, color, material, parent)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Position = position
	return part
end

local function block(
	name: string,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = decor(name, color, material, parent)
	part.Size = size
	part.CFrame = cframe
	return part
end

local function assetId(id: string): string
	if id ~= "" and tonumber(id) ~= nil then
		return "rbxassetid://" .. id
	end
	return id
end

-- Loads a mesh once; a failed load is remembered, so the kind falls back to
-- parts without asking again.
local function template(meshId: string): MeshPart?
	local cached = templates[meshId]
	if cached ~= nil then
		return if typeof(cached) == "Instance" then cached :: MeshPart else nil
	end
	local ok, result = pcall(function()
		return InsertService:CreateMeshPartAsync(
			assetId(meshId),
			Enum.CollisionFidelity.Box,
			Enum.RenderFidelity.Automatic
		)
	end)
	if ok and result then
		templates[meshId] = result
		return result
	end
	warn(`ArenaBuilder: mesh {meshId} did not load, using parts: {result}`)
	templates[meshId] = false
	return nil
end

-- Loads every mesh the config lists before the map is drawn.
local function preloadProps()
	for _, variants in Config.props do
		for _, variant in variants do
			template(variant.meshId)
		end
	end
end

-- A clone of a props key's mesh (variant `choice`, wrapping), sized by its
-- scale times `factor`, standing on the ground at (x, z) turned by
-- `rotation`, in `parent`; nil when the key has no mesh or it failed to load.
local function placeMesh(
	key: string,
	choice: number,
	x: number,
	z: number,
	rotation: CFrame,
	parent: Instance,
	factor: number?
): MeshPart?
	local variants = Config.props[key]
	if variants == nil or #variants == 0 then
		return nil
	end
	local variant = variants[choice % #variants + 1]
	local source = template(variant.meshId)
	if source == nil then
		return nil
	end
	local mesh = source:Clone()
	mesh.Name = key
	mesh.Anchored = true
	quiet(mesh)
	if variant.textureId ~= "" then
		mesh.TextureID = assetId(variant.textureId)
	end
	local size = source.Size * variant.scale * (factor or 1)
	mesh.Size = size
	mesh.CFrame = CFrame.new(x, variant.yOffset + size.Y / 2, z) * rotation
	mesh.Parent = parent
	return mesh
end

-- Turns a placed mesh in place so its longer horizontal side runs along
-- `direction`; the meshes carry no "front", so their shape decides.
local function align(mesh: MeshPart, direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local rotation = CFrame.lookAt(Vector3.zero, flat.Unit)
	if mesh.Size.X > mesh.Size.Z then
		rotation *= CFrame.Angles(0, math.pi / 2, 0)
	end
	mesh.CFrame = CFrame.new(mesh.Position) * rotation
end

-- A prop's lean: a small tilt about its own x axis, after its yaw.
local function tilt(prop: Prop): CFrame
	return CFrame.Angles(prop.lean, 0, 0)
end

-- The kind's mesh, drawn at the prop's centre on the ground, sized and
-- leaning as the core says; false when the kind has no mesh or it failed to load.
local function meshProp(prop: Prop, parent: Instance): boolean
	return placeMesh(
		prop.kind,
		prop.group,
		prop.x,
		prop.z,
		yaw(prop.rotation) * tilt(prop),
		parent,
		prop.scale
	) ~= nil
end

-- A tree: a trunk and a crown of a few overlapping balls, the crown leaning a
-- little so no two trees read the same.
local function buildTree(
	x: number,
	z: number,
	r: number,
	rotation: number,
	big: boolean,
	parent: Instance,
	random: Random
)
	local model = Instance.new("Model")
	model.Name = if big then "BigTree" else "Tree"
	local trunkRadius = r * (if big then 0.32 else 0.28)
	local height = r * (if big then 3.2 else 2.6) + random:NextNumber(-1, 1)
	local trunk = pick(TRUNK_COLORS, random)
	cylinder("Trunk", x, z, -0.5, height * 0.55, trunkRadius, trunk, Enum.Material.Wood, model)
	-- Roots: three short blocks splayed at the base.
	for index = 1, 3 do
		local angle = rotation + index * 2 * math.pi / 3
		local position = Vector3.new(
			x + math.cos(angle) * trunkRadius * 1.2,
			0.4,
			z + math.sin(angle) * trunkRadius * 1.2
		)
		block(
			"Root",
			CFrame.lookAt(position, position + Vector3.new(math.cos(angle), 0, math.sin(angle)))
				* CFrame.Angles(math.rad(20), 0, 0),
			Vector3.new(trunkRadius * 0.8, 0.9, trunkRadius * 2),
			trunk,
			Enum.Material.Wood,
			model
		)
	end
	local crown = pick(CANOPY_COLORS, random)
	local crownShade = crown:Lerp(Color3.new(0, 0, 0), 0.18)
	local balls = if big then 5 else 3
	for index = 1, balls do
		local angle = rotation + index * 2 * math.pi / balls
		local spread = if index == 1 then 0 else r * 0.55
		local diameter = r * (if index == 1 then 2.2 else 1.6) * random:NextNumber(0.9, 1.1)
		local position = Vector3.new(
			x + math.cos(angle) * spread,
			height * 0.55 + diameter * 0.35 + (if index == 1 then r * 0.5 else 0),
			z + math.sin(angle) * spread
		)
		ball(
			"Crown",
			position,
			diameter,
			if index % 2 == 0 then crownShade else crown,
			Enum.Material.SmoothPlastic,
			model
		)
	end
	model.Parent = parent
end

-- A rock: two or three tilted blocks, the biggest capped with moss.
local function buildRock(prop: Prop, boulder: boolean, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = if boulder then "Boulder" else "Rock"
	local r = prop.radius
	local color = pick(ROCK_COLORS, random)
	local pieces = if boulder then 3 else 2
	for index = 1, pieces do
		local angle = prop.rotation + index * 2.1
		local offset = if index == 1 then 0 else r * 0.45
		local size = r * (if index == 1 then 1.5 else 1.0) * random:NextNumber(0.85, 1.15)
		local position = Vector3.new(
			prop.x + math.cos(angle) * offset,
			size * 0.38,
			prop.z + math.sin(angle) * offset
		)
		block(
			"Stone",
			CFrame.new(position)
				* CFrame.Angles(
					random:NextNumber(-0.25, 0.25),
					angle,
					random:NextNumber(-0.25, 0.25)
				),
			Vector3.new(size * 1.1, size * 0.9, size),
			if index == 1 then color else color:Lerp(Color3.new(0, 0, 0), 0.15),
			Enum.Material.Slate,
			model
		)
	end
	if boulder then
		local moss = ball(
			"Moss",
			Vector3.new(prop.x, r * 0.9, prop.z),
			r * 1.3,
			MOSS_COLOR,
			Enum.Material.Grass,
			model
		)
		moss.Size = Vector3.new(r * 1.4, r * 0.5, r * 1.4)
	end
	model.Parent = parent
end

-- A ruin: a broken ring of wall pieces and a fallen column, one per circle,
-- standing in for a building without its mesh.
local function buildRuin(prop: Prop, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "Ruin"
	for _, circle in prop.circles do
		local r = circle.radius
		local pieces = 5
		for index = 1, pieces do
			if index == 3 then
				continue -- the gap
			end
			local angle = prop.rotation + index * 2 * math.pi / pieces
			local height = r * random:NextNumber(0.5, 1.1)
			local position = Vector3.new(
				circle.x + math.cos(angle) * r * 0.75,
				height / 2,
				circle.z + math.sin(angle) * r * 0.75
			)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			block(
				"Wall",
				CFrame.lookAt(position, position + tangent),
				Vector3.new(1.2, height, r * 0.9),
				if index % 2 == 0 then RUIN_COLOR else RUIN_DARK,
				Enum.Material.Cobblestone,
				model
			)
		end
		local column = decor("Column", RUIN_COLOR, Enum.Material.Cobblestone, model)
		column.Shape = Enum.PartType.Cylinder
		column.Size = Vector3.new(r * 1.2, 1.2, 1.2)
		column.CFrame = CFrame.new(circle.x, 0.6, circle.z) * yaw(prop.rotation)
	end
	model.Parent = parent
end

-- A stump: a short trunk with a pale cut top.
local function buildStump(prop: Prop, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "Stump"
	local trunk = pick(TRUNK_COLORS, random)
	local r = prop.radius * 0.8
	cylinder("Trunk", prop.x, prop.z, -0.3, 1.6, r, trunk, Enum.Material.Wood, model)
	cylinder(
		"Cut",
		prop.x,
		prop.z,
		1.6,
		1.7,
		r * 0.85,
		trunk:Lerp(Color3.new(1, 1, 1), 0.35),
		Enum.Material.Wood,
		model
	)
	model.Parent = parent
end

-- The two footprint circles furthest apart, as world positions: a log's ends,
-- a fence's first and last post.
local function span(prop: Prop): (Vector3, Vector3, number)
	local first, last = prop.circles[1], prop.circles[#prop.circles]
	return Vector3.new(first.x, 0, first.z), Vector3.new(last.x, 0, last.z), first.radius
end

-- A fallen log lying across its footprint.
local function buildLog(prop: Prop, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "Log"
	local from, to, r = span(prop)
	local radius = r * 0.85
	local length = (to - from).Magnitude + r * 2
	local centre = (from + to) / 2 + Vector3.new(0, radius, 0)
	local log = decor("Log", pick(TRUNK_COLORS, random), Enum.Material.Wood, model)
	log.Shape = Enum.PartType.Cylinder
	log.Size = Vector3.new(length, radius * 2, radius * 2)
	log.CFrame = CFrame.new(centre) * yaw(prop.rotation)
	model.Parent = parent
end

-- A fence: a post at every footprint circle and two rails along them.
local function buildFence(prop: Prop, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Fence"
	for index, circle in prop.circles do
		block(
			"Post" .. index,
			CFrame.new(circle.x, 1.75, circle.z) * yaw(prop.rotation),
			Vector3.new(0.6, 3.5, 0.6),
			FENCE_COLOR,
			Enum.Material.Wood,
			model
		)
	end
	local from, to = span(prop)
	local length = (to - from).Magnitude + 1
	for index, height in { 1.2, 2.6 } do
		local centre = (from + to) / 2 + Vector3.new(0, height, 0)
		block(
			"Rail" .. index,
			CFrame.new(centre) * yaw(prop.rotation),
			Vector3.new(length, 0.35, 0.25),
			FENCE_COLOR:Lerp(Color3.new(0, 0, 0), 0.12),
			Enum.Material.Wood,
			model
		)
	end
	model.Parent = parent
end

-- A stone circle: a standing stone at every footprint circle.
local function buildStoneCircle(prop: Prop, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "StoneCircle"
	local color = pick(ROCK_COLORS, random)
	for index, circle in prop.circles do
		local height = random:NextNumber(4, 6.5)
		block(
			"Stone" .. index,
			CFrame.new(circle.x, height / 2 - 0.3, circle.z)
				* yaw(prop.rotation + index)
				* CFrame.Angles(random:NextNumber(-0.08, 0.08), 0, random:NextNumber(-0.08, 0.08)),
			Vector3.new(circle.radius * 1.3, height, circle.radius),
			color,
			Enum.Material.Slate,
			model
		)
	end
	model.Parent = parent
end

-- A pond, always from parts: the terrain is dug out and banked with sand, a
-- dark bed lies under a flat, slightly reflective water disc sunk below the
-- ground, so the bank's edge shows. The terrain is dug from `base`; the
-- parts are lifted with the rest of the prop.
local function buildPond(prop: Prop, parent: Instance, base: number)
	local terrain = workspace.Terrain
	local r = prop.radius
	terrain:FillCylinder(
		CFrame.new(prop.x, base - GROUND_THICKNESS / 2, prop.z),
		GROUND_THICKNESS,
		r + 6,
		POND_RIM_MATERIAL
	)
	terrain:FillCylinder(
		CFrame.new(prop.x, base - GROUND_THICKNESS / 2, prop.z),
		GROUND_THICKNESS + 1,
		r + 3,
		Enum.Material.Air
	)
	local model = Instance.new("Model")
	model.Name = "Pond"
	cylinder("Bed", prop.x, prop.z, -2.6, -2, r + 5, POND_BED_COLOR, Enum.Material.Mud, model)
	local water = cylinder(
		"Water",
		prop.x,
		prop.z,
		-0.9,
		-0.3,
		r + 4,
		WATER_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	water.Transparency = 0.2
	water.Reflectance = 0.15
	water.CastShadow = false
	model.Parent = parent
end

-- A stone circle from its mesh: one stone per footprint circle, its broad
-- face toward the ring's centre; false when the mesh failed to load.
local function meshStoneCircle(prop: Prop, parent: Instance): boolean
	local cx, cz = 0, 0
	for _, circle in prop.circles do
		cx += circle.x
		cz += circle.z
	end
	cx, cz = cx / #prop.circles, cz / #prop.circles
	local model = Instance.new("Model")
	model.Name = "StoneCircle"
	for index, circle in prop.circles do
		local stone = placeMesh(
			"stoneCircle",
			prop.group + index,
			circle.x,
			circle.z,
			CFrame.identity,
			model,
			prop.scale
		)
		if stone == nil then
			model:Destroy()
			return false
		end
		-- The broad face toward the centre: the long side along the ring.
		align(stone, Vector3.new(-(cz - circle.z), 0, cx - circle.x))
		stone.CFrame *= tilt(prop)
	end
	model.Parent = parent
	return true
end

-- A fence from its mesh: once at the middle of its footprint, along the
-- line of its circles; false when the mesh failed to load.
local function meshFence(prop: Prop, parent: Instance): boolean
	local from, to = span(prop)
	local centre = (from + to) / 2
	local fence =
		placeMesh("fence", prop.group, centre.X, centre.Z, yaw(prop.rotation), parent, prop.scale)
	if fence == nil then
		return false
	end
	align(fence, to - from)
	fence.CFrame *= tilt(prop)
	return true
end

-- The part look while a kind has no mesh: single-circle kinds grow with the
-- prop's scale; the lean is the meshes' only.
local function buildFallback(original: Prop, parent: Instance, random: Random)
	local prop = table.clone(original)
	prop.radius *= prop.scale
	local kind = prop.kind
	if kind == "pine" or kind == "tree" then
		buildTree(prop.x, prop.z, prop.radius, prop.rotation, false, parent, random)
	elseif kind == "oak" or kind == "bigTree" then
		buildTree(prop.x, prop.z, prop.radius, prop.rotation, true, parent, random)
	elseif kind == "stump" then
		buildStump(prop, parent, random)
	elseif kind == "rock" then
		buildRock(prop, false, parent, random)
	elseif kind == "boulder" then
		buildRock(prop, true, parent, random)
	elseif kind == "log" then
		buildLog(prop, parent, random)
	elseif kind == "fence" then
		buildFence(prop, parent)
	elseif kind == "stoneCircle" then
		buildStoneCircle(prop, parent, random)
	else
		-- chapel, tower, hut, well and anything new: a ruin until its mesh comes.
		buildRuin(prop, parent, random)
	end
end

-- Builds what `draw` puts in a holder on flat ground, lifts it by `base` and
-- moves it into `parent`.
local function onGround(parent: Instance, base: number, draw: (Instance) -> ())
	local holder = Instance.new("Folder")
	draw(holder)
	lift(holder, base)
	for _, child in holder:GetChildren() do
		child.Parent = parent
	end
	holder:Destroy()
end

-- The lowest ground under a prop's centre and its circles: a prop on a
-- slope sinks into it rather than float.
local function propBase(prop: Prop): number
	local base = ArenaBuilder.groundHeight(prop.x, prop.z)
	for _, circle in prop.circles do
		base = math.min(base, ArenaBuilder.groundHeight(circle.x, circle.z))
	end
	return base
end

local function drawFlat(prop: Prop, parent: Instance, random: Random, base: number)
	if prop.kind == "pond" then
		buildPond(prop, parent, base)
	elseif prop.kind == "stoneCircle" then
		if not meshStoneCircle(prop, parent) then
			buildFallback(prop, parent, random)
		end
	elseif prop.kind == "fence" then
		if not meshFence(prop, parent) then
			buildFallback(prop, parent, random)
		end
	elseif not meshProp(prop, parent) then
		buildFallback(prop, parent, random)
	end
end

local function drawProp(prop: Prop, parent: Instance, random: Random)
	local base = propBase(prop)
	onGround(parent, base, function(holder)
		drawFlat(prop, holder, random, base)
	end)
end

-- The footprints of the current map's kinds, by kind id.
local function footprints(): { [string]: { FootprintCircle } }
	local result = {}
	local map = Config.maps[Config.map]
	if map then
		for _, kind in map.obstacleKinds do
			if kind.footprint then
				result[kind.id] = kind.footprint
			end
		end
	end
	return result
end

-- The prop an anchor circle stands for. Its centre is the anchor's x/z, or,
-- when the core gave every circle of the footprint, the circles' mean less the
-- footprint's turned mean offset, so it holds whichever circle is the anchor.
local function propOf(
	anchor: Types.Obstacle,
	group: { Types.Obstacle },
	footprint: { FootprintCircle }?
): Prop
	local x, z = anchor.x, anchor.z
	local circles = {}
	if footprint and #footprint > 0 then
		if #group == #footprint then
			local sx, sz, ox, oz = 0, 0, 0, 0
			for _, circle in group do
				sx += circle.x
				sz += circle.z
			end
			for _, offset in footprint do
				ox += offset.dx
				oz += offset.dz
			end
			local tx, tz = turn(ox / #footprint, oz / #footprint, anchor.rotation)
			x, z = sx / #group - tx, sz / #group - tz
		end
		for _, offset in footprint do
			local dx, dz = turn(offset.dx, offset.dz, anchor.rotation)
			table.insert(circles, { x = x + dx, z = z + dz, radius = offset.radius })
		end
	else
		table.insert(circles, { x = x, z = z, radius = anchor.radius })
	end
	return {
		kind = anchor.kind,
		x = x,
		z = z,
		rotation = anchor.rotation,
		radius = anchor.radius,
		group = anchor.group,
		scale = anchor.scale,
		lean = anchor.lean,
		circles = circles,
	}
end

-- A lighter grass disc under every place, its clearing's radius.
local function buildClearings(arena: Types.Arena, map: Heightmap)
	for _, place in arena.places do
		addPaint(map, place.x, place.z, place.radius, CLEARING_MATERIAL)
	end
end

-- A dirt band along every path of the core: discs of the path's width,
-- jittered, every PATH_STEP studs along its polyline, none on the start's ring.
local function buildPaths(arena: Types.Arena, random: Random, ground: Heightmap)
	local map = Config.maps[Config.map]
	if map == nil then
		return
	end
	local radius = map.pathWidth / 2
	for _, path in arena.paths do
		for index = 2, #path do
			local from = Vector3.new(path[index - 1].x, 0, path[index - 1].z)
			local to = Vector3.new(path[index].x, 0, path[index].z)
			local steps = math.max(math.ceil((to - from).Magnitude / PATH_STEP), 1)
			for step = 0, steps - 1 do
				local point = from:Lerp(to, step / steps)
				if
					(point - Vector3.new(arena.startX, 0, arena.startZ)).Magnitude >= PATH_START_GAP
				then
					addPaint(
						ground,
						point.X,
						point.Z,
						radius * random:NextNumber(0.85, 1.15),
						PATH_MATERIAL
					)
				end
			end
		end
	end
end

-- The ground is terrain sculpted from the heightmap: grass with patches of
-- other materials, which gives the forest floor its texture and swaying grass
-- for nothing per frame; the places' clearings and the paths over them; rock,
-- sand and water where the terrain says; above it the start's ring of stones
-- and a few flowers.
local function buildGround(arena: Types.Arena, parent: Instance, random: Random, map: Heightmap)
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(CLEARING_MATERIAL, CLEARING_COLOR)
	terrain:SetMaterialColor(PATH_MATERIAL, PATH_COLOR)
	local outer = arena.radius + GROUND_OVERHANG
	for _ = 1, PATCH_COUNT do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = arena.radius * math.sqrt(random:NextNumber())
		local radius = random:NextNumber(PATCH_RADIUS_MIN, PATCH_RADIUS_MAX)
		local material = PATCH_MATERIALS[random:NextInteger(1, #PATCH_MATERIALS)]
		addPaint(map, math.cos(angle) * distance, math.sin(angle) * distance, radius, material)
	end
	buildClearings(arena, map)
	buildPaths(arena, random, map)
	sculpt(map, outer)

	local ground = Instance.new("Model")
	ground.Name = "Ground"
	for index = 1, FLOWER_COUNT do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = arena.radius * math.sqrt(random:NextNumber())
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		local flower = block(
			"Flower" .. index,
			CFrame.new(x, ArenaBuilder.groundHeight(x, z) + 0.35, z) * CFrame.Angles(0, angle, 0),
			Vector3.new(0.6, 0.5, 0.6),
			pick(FLOWER_COLORS, random),
			Enum.Material.SmoothPlastic,
			ground
		)
		flower.CastShadow = false
	end
	-- The start: a ring of flat stones.
	for index = 1, 8 do
		local angle = index * 2 * math.pi / 8
		local x, z = math.cos(angle) * 7, math.sin(angle) * 7
		local position = Vector3.new(x, ArenaBuilder.groundHeight(x, z) + 0.15, z)
		block(
			"StartStone",
			CFrame.lookAt(position, Vector3.new(0, position.Y, 0)),
			Vector3.new(2.2, 0.3, 1.4),
			START_STONE_COLOR,
			Enum.Material.Slate,
			ground
		)
	end
	ground.Parent = parent
end

-- A dense line of pines and oaks just outside the edge: the forest closes the
-- map, so the invisible wall reads as something. Dressing only; the wall
-- stops the characters.
local function buildTreeLine(arena: Types.Arena, parent: Instance, random: Random)
	local line = Instance.new("Model")
	line.Name = "TreeLine"
	local count = 0
	for ring = 1, TREE_LINE_RINGS do
		local radius = arena.radius + TREE_LINE_OFFSET + (ring - 1) * TREE_LINE_SPACING
		local trees = math.floor(2 * math.pi * radius / TREE_LINE_SPACING)
		for index = 1, trees do
			local angle = (index + ring * 0.5) * 2 * math.pi / trees
			local wobble = random:NextNumber(-TREE_LINE_SPACING * 0.3, TREE_LINE_SPACING * 0.3)
			local x = math.cos(angle) * (radius + wobble)
			local z = math.sin(angle) * (radius + wobble)
			local treeRadius = TREE_LINE_RADIUS * random:NextNumber(0.85, 1.2)
			count += 1
			local prop: Prop = {
				kind = if random:NextNumber() < 0.6 then "pine" else "oak",
				x = x,
				z = z,
				rotation = angle,
				radius = treeRadius,
				group = count,
				scale = 1,
				lean = 0,
				circles = { { x = x, z = z, radius = treeRadius } },
			}
			onGround(line, ArenaBuilder.groundHeight(x, z), function(holder)
				if not meshProp(prop, holder) then
					buildTree(x, z, treeRadius, angle, ring == 1, holder, random)
				end
			end)
			if count % BUILD_BATCH == 0 then
				task.wait()
			end
		end
	end
	line.Parent = parent
end

-- Segments of invisible wall just outside the edge, so nothing leaves the map.
local function buildWall(arena: Types.Arena, parent: Instance)
	local wall = Instance.new("Model")
	wall.Name = "Wall"
	local radius = arena.radius + WALL_THICKNESS / 2
	local length = 2 * math.pi * radius / WALL_SEGMENTS + 1
	for index = 1, WALL_SEGMENTS do
		local angle = index * 2 * math.pi / WALL_SEGMENTS
		local position =
			Vector3.new(math.cos(angle) * radius, WALL_HEIGHT / 2, math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local part = Instance.new("Part")
		part.Name = "Wall" .. index
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CanQuery = true
		part.CanTouch = false
		part.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length)
		part.CFrame = CFrame.lookAt(position, position + tangent)
		part.Parent = wall
	end
	wall.Parent = parent
end

-- The glow on the ground and the light that mark the chest, mesh or parts.
local function chestMarker(x: number, z: number, lit: BasePart, model: Model)
	local glow = block(
		"Glow",
		CFrame.new(x, 0.1, z),
		Vector3.new(10, 0.1, 10),
		CHEST_GLOW,
		Enum.Material.Neon,
		model
	)
	glow.Transparency = CHEST_GLOW_TRANSPARENCY
	local light = Instance.new("PointLight")
	light.Color = CHEST_GLOW
	light.Brightness = CHEST_LIGHT_BRIGHTNESS
	light.Range = 24
	light.Parent = lit
	chestGlow = glow
	chestLight = light
end

-- The extraction chest: its mesh, turned toward the start, over a soft glow,
-- standing where the core put it; a solid body, as the part chest was.
local function meshChest(arena: Types.Arena, parent: Instance): boolean
	local model = Instance.new("Model")
	model.Name = "ExtractionChest"
	local x, z = arena.chestX, arena.chestZ
	local facing = Vector3.new(arena.startX - x, 0, arena.startZ - z)
	local rotation = if facing.Magnitude > 1e-3
		then CFrame.lookAt(Vector3.zero, facing.Unit)
		else CFrame.identity
	local mesh = placeMesh("chest", 0, x, z, rotation, model)
	if mesh == nil then
		model:Destroy()
		return false
	end
	mesh.CanCollide = true
	mesh.CanQuery = true
	chestMarker(x, z, mesh, model)
	lift(model, chestGround)
	model.Parent = parent
	chestModel = model
	chestMesh = mesh
	chestClosed = mesh.CFrame
	return true
end

-- The part chest, while the mesh has not loaded: a wooden box with a golden
-- band and a soft glow.
local function buildChest(arena: Types.Arena, parent: Instance)
	chestGround = ArenaBuilder.groundHeight(arena.chestX, arena.chestZ)
	if meshChest(arena, parent) then
		return
	end
	local model = Instance.new("Model")
	model.Name = "ExtractionChest"
	local x, z = arena.chestX, arena.chestZ
	local base = block(
		"Base",
		CFrame.new(x, 1.6, z),
		Vector3.new(6.6, 3.2, 4.4),
		CHEST_WOOD,
		Enum.Material.Wood,
		model
	)
	base.CanCollide = true
	base.CanQuery = true
	block(
		"Band",
		CFrame.new(x, 1.6, z),
		Vector3.new(6.8, 0.7, 4.6),
		CHEST_BAND,
		Enum.Material.Neon,
		model
	)
	block(
		"BandSide",
		CFrame.new(x, 1.6, z),
		Vector3.new(1.2, 3.3, 4.5),
		CHEST_BAND,
		Enum.Material.Metal,
		model
	)
	local lid = block(
		"Lid",
		CFrame.new(x, 3.8, z),
		Vector3.new(6.6, 1.2, 4.4),
		CHEST_WOOD:Lerp(Color3.new(0, 0, 0), 0.15),
		Enum.Material.Wood,
		model
	)
	block(
		"Lock",
		CFrame.new(x, 2.2, z + 2.25),
		Vector3.new(1.2, 1.3, 0.3),
		CHEST_BAND,
		Enum.Material.Neon,
		model
	)
	chestMarker(x, z, base, model)
	lift(model, chestGround)
	model.Parent = parent
	chestModel = model
	chestLid = lid
end

-- The portal's arch, standing on the portal's spot across the camera's view,
-- so the client's ring stands inside it; nothing when the mesh fails, the
-- client's ring is the portal.
function ArenaBuilder.setPortal(x: number, z: number)
	ArenaBuilder.clearPortal()
	local root = folder
	if root == nil then
		return
	end
	local arch = placeMesh("portal", 0, x, z, CFrame.identity, root)
	if arch then
		arch.Name = "PortalArch"
		-- The client's ring faces the camera, which looks along -Z: the arch's
		-- span runs along X.
		align(arch, Vector3.xAxis)
		lift(arch, ArenaBuilder.groundHeight(x, z))
		portalArch = arch
	end
end

-- Takes the portal's arch away.
function ArenaBuilder.clearPortal()
	if portalArch then
		portalArch:Destroy()
		portalArch = nil
	end
end

-- The emblem floating over a shrine's plinth, by kind; returns its parts.
local function buildEmblem(
	kind: string,
	x: number,
	z: number,
	color: Color3,
	model: Model
): { BasePart }
	local y = SHRINE_EMBLEM_HEIGHT
	local parts: { BasePart } = {}
	if kind == "boon" then
		-- A golden orb in a glassy halo.
		table.insert(
			parts,
			ball("Orb", Vector3.new(x, y, z), 2.4, color, Enum.Material.Neon, model)
		)
		local halo = ball("Halo", Vector3.new(x, y, z), 3.4, color, Enum.Material.Glass, model)
		halo.Transparency = 0.6
		table.insert(parts, halo)
	elseif kind == "pact" then
		-- A crimson blade, point up, over a dark crossguard.
		table.insert(
			parts,
			block(
				"Blade",
				CFrame.new(x, y, z),
				Vector3.new(0.3, 3.2, 0.9),
				color,
				Enum.Material.Neon,
				model
			)
		)
		local tip = Instance.new("WedgePart")
		tip.Name = "Tip"
		tip.Anchored = true
		quiet(tip)
		tip.Color = color
		tip.Material = Enum.Material.Neon
		tip.Size = Vector3.new(0.3, 1.2, 0.9)
		tip.CFrame = CFrame.new(x, y + 2.2, z)
		tip.Parent = model
		table.insert(parts, tip)
		table.insert(
			parts,
			block(
				"Guard",
				CFrame.new(x, y - 1.7, z),
				Vector3.new(0.5, 0.4, 2.4),
				color:Lerp(Color3.new(0, 0, 0), 0.5),
				Enum.Material.Metal,
				model
			)
		)
	elseif kind == "trial" then
		-- A violet ring standing on edge.
		local pieces = 12
		for index = 1, pieces do
			local angle = index * 2 * math.pi / pieces
			table.insert(
				parts,
				block(
					"Ring" .. index,
					CFrame.new(x + math.cos(angle) * 1.8, y + math.sin(angle) * 1.8, z)
						* CFrame.Angles(0, 0, angle),
					Vector3.new(0.5, 1.05, 0.5),
					color,
					Enum.Material.Neon,
					model
				)
			)
		end
	else
		-- A spring: a stone basin of glowing water on the plinth, a drop above.
		cylinder("Basin", x, z, 1.6, 2.5, 2.2, SHRINE_STONE_DARK, Enum.Material.Slate, model)
		table.insert(
			parts,
			cylinder("Water", x, z, 2.5, 2.6, 1.8, color, Enum.Material.Neon, model)
		)
		table.insert(
			parts,
			ball("Drop", Vector3.new(x, y, z), 1.2, color, Enum.Material.Neon, model)
		)
	end
	return parts
end

-- A shrine's body from parts: a stone plinth and the kind's floating emblem;
-- returns the emblem's looks and the plinth's top.
local function partShrine(shrine: Types.Shrine, color: Color3, model: Model): ({ Look }, number)
	local x, z, r = shrine.x, shrine.z, shrine.radius
	local plinth =
		cylinder("Plinth", x, z, -0.2, 1, r, SHRINE_STONE, Enum.Material.Cobblestone, model)
	plinth.CanCollide = true
	plinth.CanQuery = true
	cylinder("Top", x, z, 1, 1.6, r * 0.7, SHRINE_STONE_DARK, Enum.Material.Slate, model)
	local emblem: { Look } = {}
	for _, part in buildEmblem(shrine.kind, x, z, color, model) do
		part.CastShadow = false
		table.insert(emblem, { part = part, color = part.Color, material = part.Material })
	end
	return emblem, 1.6
end

local function buildShrine(shrine: Types.Shrine, parent: Instance, random: Random)
	local color = SHRINE_COLORS[shrine.kind] or SHRINE_COLORS.boon
	local model = Instance.new("Model")
	model.Name = "Shrine_" .. shrine.id
	local x, z, r = shrine.x, shrine.z, shrine.radius
	local emblem: { Look } = {}
	local base = 0
	local lit: BasePart
	local mesh = placeMesh(
		SHRINE_PROPS[shrine.kind] or SHRINE_PROPS.boon,
		0,
		x,
		z,
		CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0),
		model
	)
	if mesh then
		mesh.Name = "Shrine"
		-- What the character and the raycasts stop at is the shrine's circle
		-- plus the player's radius, as every obstacle body.
		body("Plinth", x, z, r + Config.player.radius, 0, SHRINE_BODY_HEIGHT, model)
		base = mesh.Position.Y + mesh.Size.Y / 2
		lit = mesh
	else
		emblem, base = partShrine(shrine, color, model)
		lit = emblem[1].part
	end
	local beam = cylinder(
		"Beam",
		x,
		z,
		base,
		base + BEAM_HEIGHT,
		BEAM_RADIUS,
		color,
		Enum.Material.Neon,
		model
	)
	beam.CastShadow = false
	local glow = cylinder(
		"BeamGlow",
		x,
		z,
		base,
		base + BEAM_HEIGHT,
		BEAM_GLOW_RADIUS,
		color,
		Enum.Material.Neon,
		model
	)
	glow.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Parent = lit
	lift(model, ArenaBuilder.groundHeight(x, z))
	model.Parent = parent
	shrineLooks[shrine.id] =
		{ beam = beam, glow = glow, light = light, emblem = emblem, mesh = mesh }
	ArenaBuilder.setShrineState(shrine.id, shrine.used, true)
end

-- Replaces the previous run's map with this one. Yields between batches of
-- obstacles, so a frame never builds everything at once.
function ArenaBuilder.build(arena: Types.Arena)
	ArenaBuilder.clear()
	preloadProps()
	local root = Instance.new("Folder")
	root.Name = "World"
	folder = root
	-- Only the look varies with it: colours, tilts and the paths' jitter.
	local random = Random.new(arena.chestX * 1000 + arena.chestZ)
	lookRandom = random
	local map = newHeightmap(arena)
	heightmap = map
	buildGround(arena, root, random, map)
	buildWall(arena, root)
	buildTreeLine(arena, root, random)
	buildChest(arena, root)
	root.Parent = workspace

	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = root
	local groups: { [number]: { Types.Obstacle } } = {}
	for _, obstacle in arena.obstacles do
		local group = groups[obstacle.group]
		if group == nil then
			group = {}
			groups[obstacle.group] = group
		end
		table.insert(group, obstacle)
	end
	local kinds = footprints()
	for index, obstacle in arena.obstacles do
		-- Cliffs and the channel are the sculpted ground's; only their bodies
		-- stand here.
		if obstacle.anchor and not SCULPTED_KINDS[obstacle.kind] then
			local prop = propOf(obstacle, groups[obstacle.group], kinds[obstacle.kind])
			drawProp(prop, obstacles, random)
		end
		-- The body reaches from below the lowest ground around the circle to
		-- above the highest, so a cliff's stands from its foot past its top.
		local low, high = math.huge, -math.huge
		for _, offset in BODY_SAMPLES do
			local height = ArenaBuilder.groundHeight(
				obstacle.x + offset[1] * obstacle.radius,
				obstacle.z + offset[2] * obstacle.radius
			)
			low, high = math.min(low, height), math.max(high, height)
		end
		body(
			"Body" .. obstacle.id,
			obstacle.x,
			obstacle.z,
			obstacle.radius + Config.player.radius,
			low - BODY_SINK,
			high - low + BODY_SINK + BODY_HEIGHT,
			obstacles
		)
		if index % BUILD_BATCH == 0 then
			task.wait()
		end
	end
end

-- Puts the run's shrines on the map, in workspace.World.Shrines.
function ArenaBuilder.buildShrines(shrines: { Types.Shrine })
	local root = folder
	if root == nil then
		return
	end
	local existing = root:FindFirstChild("Shrines")
	if existing then
		existing:Destroy()
	end
	shrineLooks = {}
	local random = lookRandom or Random.new()
	local parent = Instance.new("Folder")
	parent.Name = "Shrines"
	for _, shrine in shrines do
		buildShrine(shrine, parent, random)
	end
	parent.Parent = root
end

-- Shows whether a shrine can be used: a used one loses its beam and its
-- emblem greys, or its mesh fades; a spring recharging (not ready) keeps a dim beam. Does
-- nothing when the state is the one already shown.
function ArenaBuilder.setShrineState(id: number, used: boolean, ready: boolean)
	local look = shrineLooks[id]
	if look == nil then
		return
	end
	local state = if used then "used" elseif ready then "ready" else "dim"
	if look.state == state then
		return
	end
	look.state = state
	look.beam.Transparency = if state == "ready"
		then BEAM_TRANSPARENCY
		elseif state == "dim" then BEAM_DIM_TRANSPARENCY
		else 1
	look.glow.Transparency = if state == "ready" then BEAM_GLOW_TRANSPARENCY else 1
	look.light.Enabled = state ~= "used"
	look.light.Brightness = if state == "ready" then SHRINE_LIGHT_BRIGHTNESS else SHRINE_LIGHT_DIM
	for _, part in look.emblem do
		part.part.Color = if used then SHRINE_SPENT else part.color
		part.part.Material = if used then Enum.Material.SmoothPlastic else part.material
	end
	if look.mesh then
		look.mesh.Transparency = if used then SHRINE_SPENT_TRANSPARENCY else 0
	end
end

-- A config colour (0xRRGGBB) as a Color3.
local function fromHex(value: number): Color3
	return Color3.fromRGB(bit32.rshift(value, 16) % 256, bit32.rshift(value, 8) % 256, value % 256)
end

local function lairColor(kind: string): Color3
	for _, config in Config.lairs.kinds do
		if config.id == kind then
			return fromHex(config.colour)
		end
	end
	return Color3.new(1, 1, 1)
end

-- A tween swinging `property` of `instance` from its value when it starts
-- playing to `target` and back, for as long as it plays.
local function pulse(instance: Instance, property: string, target: number): Tween
	return TweenService:Create(
		instance,
		TweenInfo.new(
			LAIR_PULSE_SECONDS,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ [property] = target }
	)
end

local function buildLair(lair: Types.Lair, parent: Instance)
	local color = lairColor(lair.kind)
	local model = Instance.new("Model")
	model.Name = "Lair_" .. lair.id
	local x, z = lair.x, lair.z
	local beam = cylinder(
		"Beam",
		x,
		z,
		0,
		LAIR_BEAM_HEIGHT,
		LAIR_BEAM_RADIUS,
		color,
		Enum.Material.Neon,
		model
	)
	beam.CastShadow = false
	local glow = cylinder(
		"BeamGlow",
		x,
		z,
		0,
		LAIR_BEAM_HEIGHT,
		LAIR_GLOW_RADIUS,
		color,
		Enum.Material.Neon,
		model
	)
	glow.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LAIR_LIGHT_RANGE
	light.Parent = beam
	-- The embers rise from an invisible slab around the column's foot.
	local base = block(
		"Embers",
		CFrame.new(x, 0.5, z),
		Vector3.new(LAIR_EMBER_AREA, 1, LAIR_EMBER_AREA),
		color,
		Enum.Material.SmoothPlastic,
		model
	)
	base.Transparency = 1
	base.CastShadow = false
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(color)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.Acceleration = Vector3.new(0, 1.5, 0)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = base
	lift(model, ArenaBuilder.groundHeight(x, z))
	model.Parent = parent
	lairLooks[lair.id] = {
		beam = beam,
		glow = glow,
		light = light,
		embers = embers,
		pulses = {
			pulse(beam, "Transparency", LAIR_BEAM_ASLEEP[1]),
			pulse(glow, "Transparency", LAIR_GLOW_ASLEEP[1]),
			pulse(light, "Brightness", LAIR_LIGHT_ASLEEP[2]),
		},
	}
	ArenaBuilder.setLairState(lair.id, lair.asleep, lair.silenced)
end

-- Puts the run's lairs' columns of light on the map, in workspace.World.Lairs;
-- their landmarks and kits are the arena's props.
function ArenaBuilder.buildLairs(lairs: { Types.Lair })
	local root = folder
	if root == nil then
		return
	end
	local existing = root:FindFirstChild("Lairs")
	if existing then
		existing:Destroy()
	end
	for _, look in lairLooks do
		for _, tween in look.pulses do
			tween:Cancel()
		end
	end
	lairLooks = {}
	local parent = Instance.new("Folder")
	parent.Name = "Lairs"
	for _, lair in lairs do
		buildLair(lair, parent)
	end
	parent.Parent = root
end

-- Shows a lair's state: asleep, the column pulses slowly; awake, it burns
-- steady and brighter; silenced, the column, the light and the embers go out
-- and only the landmark stays. Does nothing when the state is the one
-- already shown.
function ArenaBuilder.setLairState(id: number, asleep: boolean, silenced: boolean)
	local look = lairLooks[id]
	if look == nil then
		return
	end
	local state = if silenced then "silenced" elseif asleep then "asleep" else "awake"
	if look.state == state then
		return
	end
	look.state = state
	for _, tween in look.pulses do
		tween:Cancel()
	end
	if state == "asleep" then
		-- Each pulse swings from these values, so they are set before it plays.
		look.beam.Transparency = LAIR_BEAM_ASLEEP[2]
		look.glow.Transparency = LAIR_GLOW_ASLEEP[2]
		look.light.Brightness = LAIR_LIGHT_ASLEEP[1]
		for _, tween in look.pulses do
			tween:Play()
		end
		look.light.Enabled = true
		look.embers.Enabled = true
		look.embers.Rate = LAIR_EMBER_RATE_ASLEEP
	elseif state == "awake" then
		look.beam.Transparency = LAIR_BEAM_AWAKE
		look.glow.Transparency = LAIR_GLOW_AWAKE
		look.light.Enabled = true
		look.light.Brightness = LAIR_LIGHT_AWAKE
		look.embers.Enabled = true
		look.embers.Rate = LAIR_EMBER_RATE_AWAKE
	else
		look.beam.Transparency = 1
		look.glow.Transparency = 1
		look.light.Enabled = false
		look.embers.Enabled = false
	end
end

-- Marks where the final boss rises: a ring of cracked light flat on the
-- ground, cracks radiating from it and a thin beam at each crack's end.
function ArenaBuilder.setFinalRise(x: number, z: number)
	ArenaBuilder.clearFinalRise()
	local root = folder
	if root == nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "FinalRise"
	local arc = 2 * math.pi * RISE_RADIUS / RISE_RING_SEGMENTS
	for index = 1, RISE_RING_SEGMENTS do
		local angle = index * 2 * math.pi / RISE_RING_SEGMENTS
		local segment = block(
			"Ring" .. index,
			CFrame.new(x + math.cos(angle) * RISE_RADIUS, 0.1, z + math.sin(angle) * RISE_RADIUS)
				* CFrame.Angles(0, -angle, 0),
			Vector3.new(RISE_RING_WIDTH, 0.2, arc * 1.05),
			RISE_COLOR,
			Enum.Material.Neon,
			model
		)
		segment.CastShadow = false
	end
	for index = 1, RISE_CRACKS do
		-- The cracks are uneven, so the ring reads as broken ground.
		local angle = (index + 0.3 * math.sin(index * 2.7)) * 2 * math.pi / RISE_CRACKS
		local length = RISE_CRACK_LENGTH * (0.6 + 0.4 * math.abs(math.sin(index * 1.9)))
		local middle = RISE_RADIUS + length / 2
		local crack = block(
			"Crack" .. index,
			CFrame.new(x + math.cos(angle) * middle, 0.1, z + math.sin(angle) * middle)
				* CFrame.Angles(0, -angle, 0),
			Vector3.new(length, 0.2, RISE_CRACK_WIDTH),
			RISE_COLOR,
			Enum.Material.Neon,
			model
		)
		crack.CastShadow = false
		local reach = RISE_RADIUS + length
		local beam = cylinder(
			"Beam" .. index,
			x + math.cos(angle) * reach,
			z + math.sin(angle) * reach,
			0,
			RISE_BEAM_HEIGHT * (0.5 + 0.5 * math.abs(math.cos(index * 1.3))),
			RISE_BEAM_RADIUS,
			RISE_COLOR,
			Enum.Material.Neon,
			model
		)
		beam.CastShadow = false
		beam.Transparency = 0.3
	end
	local light = Instance.new("PointLight")
	light.Color = RISE_COLOR
	light.Range = 40
	light.Brightness = 4
	local centre = block(
		"Centre",
		CFrame.new(x, 1, z),
		Vector3.new(1, 1, 1),
		RISE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	centre.Transparency = 1
	light.Parent = centre
	lift(model, ArenaBuilder.groundHeight(x, z))
	model.Parent = root
	finalRise = model
end

-- Takes the rise point away.
function ArenaBuilder.clearFinalRise()
	if finalRise then
		finalRise:Destroy()
		finalRise = nil
	end
end

-- Shows the chest opened once the run says so: the part chest's lid opens,
-- the mesh rises a little and turns; the glow dims either way.
function ArenaBuilder.setChestOpened(opened: boolean)
	if chestGlow then
		chestGlow.Transparency = if opened then CHEST_GLOW_SPENT else CHEST_GLOW_TRANSPARENCY
	end
	if chestLight then
		chestLight.Brightness = if opened then CHEST_LIGHT_SPENT else CHEST_LIGHT_BRIGHTNESS
	end
	local mesh, closed = chestMesh, chestClosed
	if mesh and closed then
		mesh.CFrame = if opened
			then closed * CFrame.new(0, CHEST_OPEN_LIFT, 0) * CFrame.Angles(0, CHEST_OPEN_TURN, 0)
			else closed
		return
	end
	local lid = chestLid
	local model = chestModel
	if lid == nil or model == nil then
		return
	end
	local pivot = model:GetPivot()
	if opened then
		lid.CFrame = CFrame.new(pivot.Position.X, chestGround + 4.8, pivot.Position.Z - 2)
			* CFrame.Angles(math.rad(-70), 0, 0)
	else
		lid.CFrame = CFrame.new(pivot.Position.X, chestGround + 3.8, pivot.Position.Z)
	end
end

-- Removes the current map, its shrines and what a default place brings: the
-- baseplate and any spawn location. Characters reach the map through the
-- run's teleport.
function ArenaBuilder.clear()
	workspace.Terrain:Clear()
	heightmap = nil
	chestGround = 0
	if folder then
		folder:Destroy()
		folder = nil
	end
	lookRandom = nil
	chestModel = nil
	chestLid = nil
	chestMesh = nil
	chestClosed = nil
	chestGlow = nil
	chestLight = nil
	portalArch = nil
	shrineLooks = {}
	ArenaBuilder.clearFinalRise()
	for _, look in lairLooks do
		for _, tween in look.pulses do
			tween:Cancel()
		end
	end
	lairLooks = {}
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

return ArenaBuilder
