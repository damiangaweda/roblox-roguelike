--!strict
-- The room templates (ADR-0008): data the generator reads, never code. Each is
-- a greybox rectangle with marked places for the camp, a chest and cover.
-- Points are studs from the room's centre; half extents keep a room inside
-- its grid cell with space for a corridor (Config.world.cellSize).

local Types = require("./Core/Types")

local Templates: { Types.RoomTemplate } = {
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

return Templates
