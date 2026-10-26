--!strict
-- The templates the generators read, never code. Positions are studs from the
-- centre.
--   rooms (ADR-0008): greybox rectangles with marked places for the camp, a
--     chest and cover; half extents keep a room inside its grid cell with
--     space for a corridor (Config.world.cellSize).
--   points (ADR-0012): discs flattened on the terrain with marked places for
--     the camp, a chest, a clue and cover, and solid props. Props keep at
--     least 6 studs from the centre and from the camp, so neither the start
--     ring nor a camp is ever inside one, and lie inside the radius.
--   entry: the template of every entry, without a camp.

local Types = require("./Core/Types")

local rooms: { Types.RoomTemplate } = {
	{
		id = "hall",
		halfWidth = 22,
		halfDepth = 16,
		camp = { x = 0, z = 0 },
		chest = { x = 16, z = -10 },
		cover = { { x = -14, z = 8 }, { x = 14, z = 8 } },
	},
	{
		id = "courtyard",
		halfWidth = 20,
		halfDepth = 20,
		camp = { x = 0, z = -4 },
		chest = { x = -14, z = 14 },
		cover = { { x = -12, z = -12 }, { x = 12, z = -12 }, { x = 0, z = 14 } },
	},
	{
		id = "cellar",
		halfWidth = 14,
		halfDepth = 14,
		camp = { x = 4, z = 4 },
		chest = { x = -9, z = -9 },
		cover = { { x = -9, z = 7 } },
	},
	{
		id = "grove",
		halfWidth = 24,
		halfDepth = 18,
		camp = { x = 8, z = 0 },
		chest = { x = -18, z = 0 },
		cover = {
			{ x = -12, z = -10 },
			{ x = -12, z = 10 },
			{ x = 4, z = -12 },
			{ x = 16, z = 12 },
		},
	},
	{
		id = "ruin",
		halfWidth = 18,
		halfDepth = 22,
		camp = { x = 0, z = 6 },
		chest = { x = 12, z = -16 },
		cover = { { x = -12, z = -8 }, { x = 12, z = 2 } },
	},
	{
		id = "crossing",
		halfWidth = 16,
		halfDepth = 16,
		camp = { x = 0, z = 0 },
		chest = { x = 10, z = 10 },
		cover = { { x = -10, z = -10 }, { x = 10, z = -10 }, { x = -10, z = 10 } },
	},
	{
		id = "gallery",
		halfWidth = 26,
		halfDepth = 12,
		camp = { x = -10, z = 0 },
		chest = { x = 20, z = 0 },
		cover = { { x = 0, z = -7 }, { x = 10, z = 7 } },
	},
	{
		id = "pit",
		halfWidth = 18,
		halfDepth = 18,
		camp = { x = 0, z = 0 },
		chest = { x = 13, z = -13 },
		cover = { { x = -13, z = 13 }, { x = 13, z = 13 } },
	},
}

local points: { Types.PointTemplate } = {
	{
		id = "hall",
		radius = 20,
		camp = { x = 0, z = 0 },
		chest = { x = 16, z = -10 },
		clue = { x = -14, z = -8 },
		cover = { { x = -14, z = 8 }, { x = 14, z = 8 } },
		-- A broken column.
		props = { { x = 0, z = -10, halfWidth = 1.5, halfDepth = 1.5 } },
	},
	{
		id = "courtyard",
		radius = 22,
		camp = { x = 0, z = -4 },
		chest = { x = -14, z = 14 },
		clue = { x = 14, z = 10 },
		cover = { { x = -12, z = -12 }, { x = 12, z = -12 }, { x = 0, z = 14 } },
		props = {},
	},
	{
		id = "cellar",
		radius = 14,
		camp = { x = 4, z = 4 },
		chest = { x = -9, z = -9 },
		clue = { x = 8, z = -8 },
		cover = { { x = -9, z = 7 } },
		-- A pillar.
		props = { { x = -8, z = 0, halfWidth = 1.5, halfDepth = 1.5 } },
	},
	{
		id = "grove",
		radius = 22,
		camp = { x = 8, z = 0 },
		chest = { x = -18, z = 0 },
		clue = { x = 6, z = 14 },
		cover = {
			{ x = -12, z = -10 },
			{ x = -12, z = 10 },
			{ x = 4, z = -12 },
			{ x = 16, z = 12 },
		},
		props = {},
	},
	{
		id = "ruin",
		radius = 22,
		camp = { x = 0, z = 6 },
		chest = { x = 12, z = -16 },
		clue = { x = -8, z = 14 },
		cover = { { x = -12, z = -8 }, { x = 12, z = 2 } },
		-- Three wall segments: west, north and east.
		props = {
			{ x = -15, z = 0, halfWidth = 1, halfDepth = 6 },
			{ x = -4, z = -14, halfWidth = 6, halfDepth = 1 },
			{ x = 15, z = 4, halfWidth = 1, halfDepth = 6 },
		},
	},
	{
		id = "crossing",
		radius = 16,
		camp = { x = 0, z = 0 },
		chest = { x = 10, z = 10 },
		clue = { x = -12, z = 0 },
		cover = { { x = -10, z = -10 }, { x = 10, z = -10 }, { x = -10, z = 10 } },
		-- A well.
		props = { { x = 0, z = 10, halfWidth = 2, halfDepth = 2 } },
	},
	{
		id = "gallery",
		radius = 22,
		camp = { x = -10, z = 0 },
		chest = { x = 20, z = 0 },
		clue = { x = 0, z = 8 },
		cover = { { x = 0, z = -7 }, { x = 10, z = 7 } },
		-- A pillar.
		props = { { x = 10, z = -6, halfWidth = 1, halfDepth = 1 } },
	},
	{
		id = "pit",
		radius = 20,
		camp = { x = 0, z = 0 },
		chest = { x = 13, z = -13 },
		clue = { x = -13, z = -13 },
		cover = { { x = -13, z = 13 }, { x = 13, z = 13 } },
		props = {},
	},
}

local entry: Types.PointTemplate = {
	id = "clearing",
	radius = 14,
	camp = nil,
	chest = { x = 8, z = 6 },
	clue = { x = -8, z = 6 },
	cover = { { x = -7, z = -7 }, { x = 7, z = -7 } },
	props = {},
}

return {
	rooms = rooms,
	points = points,
	entry = entry,
}
