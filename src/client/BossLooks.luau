--!strict
-- The silhouettes of the forest's bosses (ADR-0010 greybox stand-ins, drawn
-- by EnemyView from a few parts each). Sizes are for scale 1; EnemyView
-- multiplies them by the kind's scale from Config, so a boss towers over its
-- grunts. The front is -Z. Purely presentation.

type Piece = {
	role: "body" | "detail" | "glow",
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	on: number?,
	transparency: number?,
	telegraphPose: CFrame?,
	strike: CFrame?,
	swell: number?,
	spin: number?,
	telegraphSpin: number?,
	bob: number?,
	glowsOnTelegraph: boolean?,
}
type Chevrons = { on: number, at: Vector3, scale: number }
export type Look = { pieces: { Piece }, chevrons: Chevrons }

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball

-- A pose `lean` radians tipped forward (its top toward the front).
local function pose(x: number, y: number, z: number, lean: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(-(lean or 0), 0, 0)
end

local BossLooks = {}

BossLooks.looks = {} :: { [string]: Look }
local looks: { [string]: Look } = {
	-- Thornback: a boar, long and low, spines on its back, tusks that glow.
	thornback = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(2.6, 2, 3.8),
				color = Color3.fromRGB(94, 64, 50),
				offset = pose(0, 1.3, 0.2),
				telegraphPose = pose(0, 1.2, 0.9, -0.15),
				strike = pose(0, 1.3, -0.6, 0.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(2, 1.7, 1.8),
				color = Color3.fromRGB(110, 76, 58),
				offset = pose(0, 1.2, -2.4, 0.2),
				telegraphPose = pose(0, 1.5, -1.8, -0.1),
				strike = pose(0, 0.9, -3.2, 0.5),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.5, 1.4, 0.5),
				color = Color3.fromRGB(70, 46, 36),
				offset = pose(0, 2.8, -0.4, 0.5),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.5, 1.2, 0.5),
				color = Color3.fromRGB(70, 46, 36),
				offset = pose(0, 2.7, 0.8, 0.5),
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.3, 0.3, 1.2),
				color = Color3.fromRGB(255, 240, 200),
				offset = pose(-0.8, 0.7, -3.6, -0.4),
				glowsOnTelegraph = true,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.3, 0.3, 1.2),
				color = Color3.fromRGB(255, 240, 200),
				offset = pose(0.8, 0.7, -3.6, -0.4),
				glowsOnTelegraph = true,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 1.1, 1.9), scale = 1.2 },
	},
	-- Mossmaw: a toad, wide and squat, that swells before it spits or leaps.
	mossmaw = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(3.6, 2.2, 3.2),
				color = Color3.fromRGB(88, 134, 60),
				offset = pose(0, 1.2, 0.2),
				telegraphPose = pose(0, 1.4, 0.2),
				swell = 1.25,
				strike = pose(0, 1, -0.4, 0.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(3.2, 1.4, 2),
				color = Color3.fromRGB(110, 160, 70),
				offset = pose(0, 1.6, -1.8),
				telegraphPose = pose(0, 2, -1.6, -0.3),
				strike = pose(0, 1.2, -2.4, 0.4),
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.8, 0.8, 0.8),
				color = Color3.fromRGB(255, 230, 90),
				offset = pose(-1.1, 2.5, -2.3),
				swell = 1.5,
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.8, 0.8, 0.8),
				color = Color3.fromRGB(255, 230, 90),
				offset = pose(1.1, 2.5, -2.3),
				swell = 1.5,
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 1.2, 2.4),
				color = Color3.fromRGB(70, 110, 50),
				offset = pose(-2.1, 0.6, 0.6, -0.4),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 1.2, 2.4),
				color = Color3.fromRGB(70, 110, 50),
				offset = pose(2.1, 0.6, 0.6, -0.4),
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 1.2, 1.6), scale = 1.2 },
	},
	-- Hollow Shade: a hooded wraith with no legs, drifting and bobbing, a
	-- dark ring turning at its feet.
	hollowShade = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(2.2, 4.4, 1.8),
				color = Color3.fromRGB(44, 52, 64),
				offset = pose(0, 2.8, 0),
				transparency = 0.25,
				telegraphPose = pose(0, 3.2, 0.2, -0.1),
				strike = pose(0, 2.6, -0.6, 0.3),
				bob = 0.3,
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(2.6, 1.8, 2.2),
				color = Color3.fromRGB(30, 36, 46),
				offset = pose(0, 5.1, -0.2, 0.2),
				telegraphPose = pose(0, 5.6, 0, 0),
				bob = 0.3,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.5, 0.25, 0.3),
				color = Color3.fromRGB(150, 240, 255),
				offset = pose(-0.55, 4.9, -1.2),
				swell = 1.6,
				bob = 0.3,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.5, 0.25, 0.3),
				color = Color3.fromRGB(150, 240, 255),
				offset = pose(0.55, 4.9, -1.2),
				swell = 1.6,
				bob = 0.3,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(6, 0.15, 6),
				color = Color3.fromRGB(70, 90, 140),
				offset = pose(0, 0.12, 0),
				transparency = 0.5,
				spin = 0.8,
				telegraphSpin = 4,
				swell = 1.3,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.3, 1), scale = 1.2 },
	},
	-- Bramble Matron: a spider, a round abdomen behind a small head, four
	-- legs splayed, eyes that glow.
	brambleMatron = {
		pieces = {
			{
				role = "body",
				shape = BALL,
				size = Vector3.new(3.6, 3.2, 3.6),
				color = Color3.fromRGB(70, 36, 110),
				offset = pose(0, 2, 1.2),
				telegraphPose = pose(0, 2.4, 1.4),
				swell = 1.15,
				strike = pose(0, 1.8, 0.6, 0.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(2, 1.6, 1.8),
				color = Color3.fromRGB(96, 50, 140),
				offset = pose(0, 1.6, -1.4),
				telegraphPose = pose(0, 1.9, -1.2, -0.3),
				strike = pose(0, 1.3, -2.2, 0.4),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.4, 0.4, 4.2),
				color = Color3.fromRGB(50, 26, 80),
				offset = CFrame.new(-2.2, 1.6, 0) * CFrame.Angles(0, math.rad(60), math.rad(-25)),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.4, 0.4, 4.2),
				color = Color3.fromRGB(50, 26, 80),
				offset = CFrame.new(2.2, 1.6, 0) * CFrame.Angles(0, math.rad(-60), math.rad(25)),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.4, 0.4, 4.2),
				color = Color3.fromRGB(50, 26, 80),
				offset = CFrame.new(-2.2, 1.6, 1.6)
					* CFrame.Angles(0, math.rad(115), math.rad(-25)),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.4, 0.4, 4.2),
				color = Color3.fromRGB(50, 26, 80),
				offset = CFrame.new(2.2, 1.6, 1.6) * CFrame.Angles(0, math.rad(-115), math.rad(25)),
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.5, 0.5, 0.5),
				color = Color3.fromRGB(255, 80, 120),
				offset = pose(-0.5, 1.9, -2.3),
				swell = 1.6,
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.5, 0.5, 0.5),
				color = Color3.fromRGB(255, 80, 120),
				offset = pose(0.5, 1.9, -2.3),
				swell = 1.6,
			},
		},
		chevrons = { on = 2, at = Vector3.new(0, 0.95, 0.4), scale = 1.2 },
	},
	-- Ironbark Warden: a treant, a trunk with two heavy arms and a crown of
	-- leaves; the arms rise for the slam.
	ironbarkWarden = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(2.8, 5, 2.4),
				color = Color3.fromRGB(78, 54, 36),
				offset = pose(0, 2.6, 0),
				telegraphPose = pose(0, 2.9, 0.2, -0.1),
				strike = pose(0, 2.4, -0.3, 0.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 3.6, 1),
				color = Color3.fromRGB(64, 44, 30),
				offset = pose(-2, 3, -0.4, 0.3),
				telegraphPose = pose(-2.1, 5.2, 0.4, -1.2),
				strike = pose(-2, 1.6, -2.2, 1.3),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 3.6, 1),
				color = Color3.fromRGB(64, 44, 30),
				offset = pose(2, 3, -0.4, 0.3),
				telegraphPose = pose(2.1, 5.2, 0.4, -1.2),
				strike = pose(2, 1.6, -2.2, 1.3),
			},
			{
				role = "detail",
				shape = BALL,
				size = Vector3.new(3.6, 2.6, 3.6),
				color = Color3.fromRGB(70, 130, 60),
				offset = pose(0, 5.8, 0.2),
				telegraphPose = pose(0, 6.1, 0.2),
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(1.2, 0.5, 0.3),
				color = Color3.fromRGB(190, 255, 120),
				offset = pose(0, 4, -1.25),
				glowsOnTelegraph = true,
				swell = 1.4,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.55, 1.3), scale = 1.3 },
	},
	-- Ashen Stag: a stag with antlers, embers burning along its back; it
	-- lowers its head to charge.
	ashenStag = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(2, 2.2, 4),
				color = Color3.fromRGB(70, 48, 44),
				offset = pose(0, 2.6, 0.4),
				telegraphPose = pose(0, 2.4, 0.9, -0.2),
				strike = pose(0, 2.6, -0.4, 0.15),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 2.6, 1),
				color = Color3.fromRGB(60, 40, 38),
				offset = pose(0, 3.6, -2, 0.6),
				telegraphPose = pose(0, 2.8, -2.4, 1.1),
				strike = pose(0, 3.2, -2.6, 0.9),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.2, 1, 1.8),
				color = Color3.fromRGB(80, 56, 50),
				offset = pose(0, 4.8, -2.8, 0.2),
				telegraphPose = pose(0, 3.6, -3.4, 0.9),
				strike = pose(0, 4.2, -3.6, 0.6),
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.35, 2.4, 0.35),
				color = Color3.fromRGB(255, 150, 60),
				offset = CFrame.new(-0.7, 6, -2.9) * CFrame.Angles(0, 0, math.rad(-30)),
				glowsOnTelegraph = true,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.35, 2.4, 0.35),
				color = Color3.fromRGB(255, 150, 60),
				offset = CFrame.new(0.7, 6, -2.9) * CFrame.Angles(0, 0, math.rad(30)),
				glowsOnTelegraph = true,
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(1.1, 1.1, 1.1),
				color = Color3.fromRGB(255, 110, 40),
				offset = pose(0, 3.9, 0.6),
				bob = 0.15,
				swell = 1.5,
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.5, 1.6, 0.5),
				color = Color3.fromRGB(50, 34, 32),
				offset = pose(-0.7, 0.8, -1.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.5, 1.6, 0.5),
				color = Color3.fromRGB(50, 34, 32),
				offset = pose(0.7, 0.8, 1.6),
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 1.15, 2), scale = 1.2 },
	},
	-- The Forest Heart: an ancient trunk on splayed roots, a crown of three
	-- canopies and a glowing heart in its chest.
	forestHeart = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(3.4, 5.6, 3),
				color = Color3.fromRGB(56, 40, 28),
				offset = pose(0, 3.4, 0),
				telegraphPose = pose(0, 3.8, 0.2, -0.1),
				strike = pose(0, 3, -0.4, 0.15),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.2, 1.2, 3.6),
				color = Color3.fromRGB(48, 34, 24),
				offset = CFrame.new(-1.8, 0.6, 1.2) * CFrame.Angles(0, math.rad(40), 0),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.2, 1.2, 3.6),
				color = Color3.fromRGB(48, 34, 24),
				offset = CFrame.new(1.8, 0.6, 1.2) * CFrame.Angles(0, math.rad(-40), 0),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.2, 1.2, 3.6),
				color = Color3.fromRGB(48, 34, 24),
				offset = CFrame.new(0, 0.6, -1.8),
			},
			{
				role = "detail",
				shape = BALL,
				size = Vector3.new(4.2, 3, 4.2),
				color = Color3.fromRGB(60, 120, 56),
				offset = pose(0, 7, 0),
			},
			{
				role = "detail",
				shape = BALL,
				size = Vector3.new(3, 2.4, 3),
				color = Color3.fromRGB(84, 150, 64),
				offset = pose(-1.8, 6.4, 0.6),
			},
			{
				role = "detail",
				shape = BALL,
				size = Vector3.new(3, 2.4, 3),
				color = Color3.fromRGB(44, 100, 50),
				offset = pose(1.8, 6.4, -0.6),
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(1.4, 1.4, 1.4),
				color = Color3.fromRGB(150, 255, 120),
				offset = pose(0, 3.6, -1.5),
				bob = 0.2,
				swell = 1.6,
				glowsOnTelegraph = true,
			},
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(7, 0.15, 7),
				color = Color3.fromRGB(110, 220, 90),
				offset = pose(0, 0.12, 0),
				transparency = 0.55,
				spin = 0.4,
				telegraphSpin = 3,
				swell = 1.3,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.85, 1.6), scale = 1.4 },
	},
}

BossLooks.looks = looks

return BossLooks
