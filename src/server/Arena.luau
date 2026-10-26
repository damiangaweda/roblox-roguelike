--!strict
-- The greybox arena: a flat floor, four walls and the spawn at the origin.
-- Plain parts in muted colours (the plan's simplification register).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Core.Types)

local Arena = {}

local FLOOR_THICKNESS = 2
local WALL_HEIGHT = 24
local WALL_THICKNESS = 4
local FLOOR_COLOR = Color3.fromRGB(96, 100, 104)
local WALL_COLOR = Color3.fromRGB(64, 66, 72)
local SPAWN_COLOR = Color3.fromRGB(120, 124, 110)

local function block(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function Arena.build(config: Types.Config)
	local half = config.arena.halfSize
	local folder = Instance.new("Folder")
	folder.Name = "Arena"

	-- The floor's top surface is at y = 0.
	block(
		"Floor",
		Vector3.new(half * 2, FLOOR_THICKNESS, half * 2),
		Vector3.new(0, -FLOOR_THICKNESS / 2, 0),
		FLOOR_COLOR,
		folder
	)

	-- Walls stand just outside the floor; the north and south ones span the corners.
	local reach = half + WALL_THICKNESS / 2
	local length = half * 2 + WALL_THICKNESS * 2
	local y = WALL_HEIGHT / 2
	block(
		"WallNorth",
		Vector3.new(length, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(0, y, -reach),
		WALL_COLOR,
		folder
	)
	block(
		"WallSouth",
		Vector3.new(length, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(0, y, reach),
		WALL_COLOR,
		folder
	)
	block(
		"WallWest",
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, half * 2),
		Vector3.new(-reach, y, 0),
		WALL_COLOR,
		folder
	)
	block(
		"WallEast",
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, half * 2),
		Vector3.new(reach, y, 0),
		WALL_COLOR,
		folder
	)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.Position = Vector3.new(0, 0.1, 0)
	spawn.Color = SPAWN_COLOR
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- No spawn shield and no team: everyone spawns here.
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	folder.Parent = workspace
end

return Arena
