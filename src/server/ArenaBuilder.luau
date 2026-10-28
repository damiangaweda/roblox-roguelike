--!strict
-- Builds the forest map in the workspace from the core's arena (ADR-0014):
-- a round ground, an invisible wall at the edge, low-poly obstacles built
-- from parts whose solid body is exactly the core's circle, and the extraction
-- chest. Everything here is presentation; the rules live in the core.

local Types = require(game:GetService("ReplicatedStorage").Shared.Core.Types)

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
local START_STONE_COLOR = Color3.fromRGB(170, 160, 140)
local CHEST_WOOD = Color3.fromRGB(120, 72, 36)
local CHEST_BAND = Color3.fromRGB(230, 190, 90)
local CHEST_GLOW = Color3.fromRGB(255, 220, 130)

local folder: Folder? = nil
local chestModel: Model? = nil
local chestLid: Part? = nil

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

-- Dressing that nothing collides with or queries.
local function decor(name: string, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = newPart(name, color, material, parent)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- An invisible, anchored body: what stops characters is exactly the core's circle.
local function body(
	name: string,
	x: number,
	z: number,
	radius: number,
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
	part.CFrame = CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = parent
	return part
end

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
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

-- A tree: a trunk and a crown of a few overlapping balls, the crown leaning a
-- little so no two trees read the same.
local function buildTree(obstacle: Types.Obstacle, big: boolean, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = if big then "BigTree" else "Tree"
	local r = obstacle.radius
	local trunkRadius = r * (if big then 0.32 else 0.28)
	local height = r * (if big then 3.2 else 2.6) + random:NextNumber(-1, 1)
	local trunk = pick(TRUNK_COLORS, random)
	cylinder(
		"Trunk",
		obstacle.x,
		obstacle.z,
		-0.5,
		height * 0.55,
		trunkRadius,
		trunk,
		Enum.Material.Wood,
		model
	)
	-- Roots: three short blocks splayed at the base.
	for index = 1, 3 do
		local angle = obstacle.rotation + index * 2 * math.pi / 3
		local position = Vector3.new(
			obstacle.x + math.cos(angle) * trunkRadius * 1.2,
			0.4,
			obstacle.z + math.sin(angle) * trunkRadius * 1.2
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
		local angle = obstacle.rotation + index * 2 * math.pi / balls
		local spread = if index == 1 then 0 else r * 0.55
		local diameter = r * (if index == 1 then 2.2 else 1.6) * random:NextNumber(0.9, 1.1)
		local position = Vector3.new(
			obstacle.x + math.cos(angle) * spread,
			height * 0.55 + diameter * 0.35 + (if index == 1 then r * 0.5 else 0),
			obstacle.z + math.sin(angle) * spread
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
	body("Body", obstacle.x, obstacle.z, r, height, model)
	model.Parent = parent
end

-- A rock: two or three tilted blocks, the biggest capped with moss.
local function buildRock(
	obstacle: Types.Obstacle,
	boulder: boolean,
	parent: Instance,
	random: Random
)
	local model = Instance.new("Model")
	model.Name = if boulder then "Boulder" else "Rock"
	local r = obstacle.radius
	local color = pick(ROCK_COLORS, random)
	local pieces = if boulder then 3 else 2
	for index = 1, pieces do
		local angle = obstacle.rotation + index * 2.1
		local offset = if index == 1 then 0 else r * 0.45
		local size = r * (if index == 1 then 1.5 else 1.0) * random:NextNumber(0.85, 1.15)
		local position = Vector3.new(
			obstacle.x + math.cos(angle) * offset,
			size * 0.38,
			obstacle.z + math.sin(angle) * offset
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
			Vector3.new(obstacle.x, r * 0.9, obstacle.z),
			r * 1.3,
			MOSS_COLOR,
			Enum.Material.Grass,
			model
		)
		moss.Size = Vector3.new(r * 1.4, r * 0.5, r * 1.4)
	end
	body("Body", obstacle.x, obstacle.z, r, r * 1.6, model)
	model.Parent = parent
end

-- A ruin: a broken ring of wall pieces and a fallen column.
local function buildRuin(obstacle: Types.Obstacle, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "Ruin"
	local r = obstacle.radius
	local pieces = 5
	for index = 1, pieces do
		if index == 3 then
			continue -- the gap
		end
		local angle = obstacle.rotation + index * 2 * math.pi / pieces
		local height = r * random:NextNumber(0.5, 1.1)
		local position = Vector3.new(
			obstacle.x + math.cos(angle) * r * 0.75,
			height / 2,
			obstacle.z + math.sin(angle) * r * 0.75
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
	local fallen = CFrame.new(obstacle.x, 0.6, obstacle.z)
		* CFrame.Angles(0, obstacle.rotation, math.pi / 2)
	local column = decor("Column", RUIN_COLOR, Enum.Material.Cobblestone, model)
	column.Shape = Enum.PartType.Cylinder
	column.Size = Vector3.new(r * 1.2, 1.2, 1.2)
	column.CFrame = fallen
	body("Body", obstacle.x, obstacle.z, r, r * 1.2, model)
	model.Parent = parent
end

local function buildObstacle(obstacle: Types.Obstacle, parent: Instance, random: Random)
	if obstacle.kind == "tree" then
		buildTree(obstacle, false, parent, random)
	elseif obstacle.kind == "bigTree" then
		buildTree(obstacle, true, parent, random)
	elseif obstacle.kind == "rock" then
		buildRock(obstacle, false, parent, random)
	elseif obstacle.kind == "boulder" then
		buildRock(obstacle, true, parent, random)
	else
		buildRuin(obstacle, parent, random)
	end
end

-- The ground is terrain: a grass disc with patches of other materials
-- blended in, which gives the forest floor its texture and swaying grass for
-- nothing per frame; above it the start's ring of stones and a few flowers.
local function buildGround(arena: Types.Arena, parent: Instance, random: Random)
	local terrain = workspace.Terrain
	local outer = arena.radius + GROUND_OVERHANG
	terrain:FillCylinder(
		CFrame.new(0, -GROUND_THICKNESS / 2, 0),
		GROUND_THICKNESS,
		outer,
		Enum.Material.Grass
	)
	for index = 1, PATCH_COUNT do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = arena.radius * math.sqrt(random:NextNumber())
		local radius = random:NextNumber(PATCH_RADIUS_MIN, PATCH_RADIUS_MAX)
		local material = PATCH_MATERIALS[random:NextInteger(1, #PATCH_MATERIALS)]
		terrain:FillCylinder(
			CFrame.new(
				math.cos(angle) * distance,
				-GROUND_THICKNESS / 2,
				math.sin(angle) * distance
			),
			GROUND_THICKNESS,
			radius,
			material
		)
		if index % 40 == 0 then
			task.wait()
		end
	end

	local ground = Instance.new("Model")
	ground.Name = "Ground"
	for index = 1, FLOWER_COUNT do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = arena.radius * math.sqrt(random:NextNumber())
		local flower = block(
			"Flower" .. index,
			CFrame.new(math.cos(angle) * distance, 0.35, math.sin(angle) * distance)
				* CFrame.Angles(0, angle, 0),
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
		local position = Vector3.new(math.cos(angle) * 7, 0.15, math.sin(angle) * 7)
		block(
			"StartStone",
			CFrame.lookAt(position, Vector3.new(0, 0.15, 0)),
			Vector3.new(2.2, 0.3, 1.4),
			START_STONE_COLOR,
			Enum.Material.Slate,
			ground
		)
	end
	ground.Parent = parent
end

-- A dense line of trees just outside the edge: the forest closes the map,
-- so the invisible wall reads as something. Dressing only; the wall stops
-- the characters.
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
			local obstacle: Types.Obstacle = {
				id = 0,
				kind = "bigTree",
				x = math.cos(angle) * (radius + wobble),
				z = math.sin(angle) * (radius + wobble),
				radius = TREE_LINE_RADIUS * random:NextNumber(0.85, 1.2),
				rotation = angle,
				group = 0,
				anchor = true,
			}
			buildTree(obstacle, ring == 1, line, random)
			count += 1
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

-- The extraction chest: a wooden box with a golden band and a soft glow,
-- standing where the core put it.
local function buildChest(arena: Types.Arena, parent: Instance)
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
	local glow = block(
		"Glow",
		CFrame.new(x, 0.1, z),
		Vector3.new(10, 0.1, 10),
		CHEST_GLOW,
		Enum.Material.Neon,
		model
	)
	glow.Transparency = 0.6
	local light = Instance.new("PointLight")
	light.Color = CHEST_GLOW
	light.Brightness = 2.5
	light.Range = 24
	light.Parent = base
	model.Parent = parent
	chestModel = model
	chestLid = lid
end

-- Replaces the previous run's map with this one. Yields between batches of
-- obstacles, so a frame never builds everything at once.
function ArenaBuilder.build(arena: Types.Arena)
	ArenaBuilder.clear()
	local root = Instance.new("Folder")
	root.Name = "World"
	folder = root
	-- Only the look varies with it: colours and tilts.
	local random = Random.new(arena.chestX * 1000 + arena.chestZ)
	buildGround(arena, root, random)
	buildWall(arena, root)
	buildTreeLine(arena, root, random)
	buildChest(arena, root)
	root.Parent = workspace

	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = root
	for index, obstacle in arena.obstacles do
		buildObstacle(obstacle, obstacles, random)
		if index % BUILD_BATCH == 0 then
			task.wait()
		end
	end
end

-- Opens the chest's lid once the run says it was opened.
function ArenaBuilder.setChestOpened(opened: boolean)
	local lid = chestLid
	local model = chestModel
	if lid == nil or model == nil then
		return
	end
	local pivot = model:GetPivot()
	if opened then
		lid.CFrame = CFrame.new(pivot.Position.X, 4.8, pivot.Position.Z - 2)
			* CFrame.Angles(math.rad(-70), 0, 0)
	else
		lid.CFrame = CFrame.new(pivot.Position.X, 3.8, pivot.Position.Z)
	end
end

-- Removes the current map and what a default place brings: the baseplate and
-- any spawn location. Characters reach the map through the run's teleport.
function ArenaBuilder.clear()
	workspace.Terrain:Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	chestModel = nil
	chestLid = nil
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
