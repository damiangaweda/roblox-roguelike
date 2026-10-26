--!strict
-- Builds the greybox geometry of a generated world (ADR-0008): a floor and
-- walls per room and corridor, cover bushes, start pads. Plain parts in muted
-- colours (the plan's simplification register). Pure presentation of the
-- core's data; nothing here is read back by the rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Core.Types)

local WorldBuilder = {}

local FLOOR_THICKNESS = 2
local WALL_HEIGHT = 14
local WALL_THICKNESS = 2
local COVER_HEIGHT = 4
local WALL_COLOR = Color3.fromRGB(58, 60, 68)
local CORRIDOR_COLOR = Color3.fromRGB(80, 82, 88)
local START_COLOR = Color3.fromRGB(104, 124, 108)
local COVER_COLOR = Color3.fromRGB(70, 120, 60)
-- Floors darken and redden with the room level, so depth reads at a glance.
local LEVEL_COLORS = {
	Color3.fromRGB(106, 110, 112),
	Color3.fromRGB(104, 96, 96),
	Color3.fromRGB(100, 78, 80),
}

local folder: Folder? = nil

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

-- A floor whose top surface is at y = 0.
local function floor(name: string, rect: Types.Rect, color: Color3, parent: Instance)
	block(
		name,
		Vector3.new(rect.halfWidth * 2, FLOOR_THICKNESS, rect.halfDepth * 2),
		Vector3.new(rect.x, -FLOOR_THICKNESS / 2, rect.z),
		color,
		parent
	)
end

-- A wall along x (horizontal) or along z, between two coordinates, standing
-- just outside the floor it borders.
local function wallAlongX(fromX: number, toX: number, z: number, parent: Instance)
	if toX - fromX < 0.1 then
		return
	end
	block(
		"Wall",
		Vector3.new(toX - fromX, WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new((fromX + toX) / 2, WALL_HEIGHT / 2, z),
		WALL_COLOR,
		parent
	)
end

local function wallAlongZ(x: number, fromZ: number, toZ: number, parent: Instance)
	if toZ - fromZ < 0.1 then
		return
	end
	block(
		"Wall",
		Vector3.new(WALL_THICKNESS, WALL_HEIGHT, toZ - fromZ),
		Vector3.new(x, WALL_HEIGHT / 2, (fromZ + toZ) / 2),
		WALL_COLOR,
		parent
	)
end

-- The openings along one side of a room, as sorted [from, to] intervals of the
-- coordinate that runs along the side.
local function openings(
	world: Types.World,
	room: Types.Room,
	side: "north" | "south" | "west" | "east"
): { { number } }
	local result = {}
	for _, id in room.corridors do
		local corridor = world.corridors[id]
		local horizontal = corridor.halfWidth > corridor.halfDepth
		if horizontal and (side == "west" or side == "east") then
			local onSide = if side == "west" then corridor.x < room.x else corridor.x > room.x
			if onSide then
				table.insert(
					result,
					{ corridor.z - corridor.halfDepth, corridor.z + corridor.halfDepth }
				)
			end
		elseif not horizontal and (side == "north" or side == "south") then
			local onSide = if side == "north" then corridor.z < room.z else corridor.z > room.z
			if onSide then
				table.insert(
					result,
					{ corridor.x - corridor.halfWidth, corridor.x + corridor.halfWidth }
				)
			end
		end
	end
	table.sort(result, function(a, b)
		return a[1] < b[1]
	end)
	return result
end

-- Wall pieces along a side from `from` to `to`, skipping the openings.
local function segments(from: number, to: number, gaps: { { number } }): { { number } }
	local pieces = {}
	local cursor = from
	for _, gap in gaps do
		table.insert(pieces, { cursor, gap[1] })
		cursor = gap[2]
	end
	table.insert(pieces, { cursor, to })
	return pieces
end

local function buildRoom(
	world: Types.World,
	room: Types.Room,
	config: Types.Config,
	parent: Instance
)
	local color = LEVEL_COLORS[math.clamp(room.level, 1, #LEVEL_COLORS)]
	if room.isStart then
		color = START_COLOR
	end
	floor("Room" .. room.id, room, color, parent)

	local left, right = room.x - room.halfWidth, room.x + room.halfWidth
	local near, far = room.z - room.halfDepth, room.z + room.halfDepth
	local half = WALL_THICKNESS / 2
	for _, piece in
		segments(left - WALL_THICKNESS, right + WALL_THICKNESS, openings(world, room, "north"))
	do
		wallAlongX(piece[1], piece[2], near - half, parent)
	end
	for _, piece in
		segments(left - WALL_THICKNESS, right + WALL_THICKNESS, openings(world, room, "south"))
	do
		wallAlongX(piece[1], piece[2], far + half, parent)
	end
	for _, piece in segments(near, far, openings(world, room, "west")) do
		wallAlongZ(left - half, piece[1], piece[2], parent)
	end
	for _, piece in segments(near, far, openings(world, room, "east")) do
		wallAlongZ(right + half, piece[1], piece[2], parent)
	end

	if room.isStart then
		return
	end
	for index, spot in room.cover do
		local bush = Instance.new("Part")
		bush.Name = "Cover" .. index
		bush.Shape = Enum.PartType.Cylinder
		bush.Anchored = true
		bush.CanCollide = false
		bush.CanQuery = false
		bush.Color = COVER_COLOR
		bush.Material = Enum.Material.Grass
		bush.Transparency = 0.25
		local diameter = config.world.coverRadius * 2
		bush.Size = Vector3.new(COVER_HEIGHT, diameter, diameter)
		bush.CFrame = CFrame.new(spot.x, COVER_HEIGHT / 2, spot.z)
			* CFrame.Angles(0, 0, math.pi / 2)
		bush.Parent = parent
	end
end

local function buildCorridor(corridor: Types.Corridor, parent: Instance)
	floor("Corridor" .. corridor.id, corridor, CORRIDOR_COLOR, parent)
	local half = WALL_THICKNESS / 2
	if corridor.halfWidth > corridor.halfDepth then
		local from, to = corridor.x - corridor.halfWidth, corridor.x + corridor.halfWidth
		wallAlongX(from, to, corridor.z - corridor.halfDepth - half, parent)
		wallAlongX(from, to, corridor.z + corridor.halfDepth + half, parent)
	else
		local from, to = corridor.z - corridor.halfDepth, corridor.z + corridor.halfDepth
		wallAlongZ(corridor.x - corridor.halfWidth - half, from, to, parent)
		wallAlongZ(corridor.x + corridor.halfWidth + half, from, to, parent)
	end
end

-- Replaces the previous run's world with this one.
function WorldBuilder.build(world: Types.World, config: Types.Config)
	WorldBuilder.clear()
	local root = Instance.new("Folder")
	root.Name = "World"
	for _, room in world.rooms do
		buildRoom(world, room, config, root)
	end
	for _, corridor in world.corridors do
		buildCorridor(corridor, root)
	end
	root.Parent = workspace
	folder = root
end

function WorldBuilder.clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return WorldBuilder
