--!strict
-- Draws the enemies. The server owns them as data (ADR-0004); this keeps one
-- pooled model of a few anchored parts per enemy id and glides it between
-- snapshots, every part moved by one bulk move per frame. Enemies out of the
-- local character's range are parked and cost nothing per frame. A lair's
-- sleeping boss and guard (ADR-0021) lie dimmed in a faint glow of the lair's
-- colour; the wire carries no sleep flag, so the lair view decides it.
--
-- A kind with an entry in Config.enemyMeshes (ADR-0022) is drawn as one
-- pooled mesh in place of its pieces, once the mesh has loaded; a kind
-- without one, or whose mesh failed, keeps its pieces.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local BossLooks = require(script.Parent.BossLooks)
local Net = require(script.Parent.Net)

local EnemyView = {}

-- Greybox stand-in (ADR-0010): two to four plain parts per archetype, each
-- with its own silhouette so it reads from the top-down camera; a kind draws
-- its archetype's look at its own scale, tinted toward its own colour, and a
-- boss draws its look from BossLooks. The rigged store pack replaces `LOOKS`
-- and `spawnRig`; nothing else here cares what an enemy looks like.
--
-- A piece's role picks its pool: `body` and `detail` pieces are solid, aim
-- targets and take the enemy's tint (kind, health, status); `glow` pieces are
-- neon, keep their own colour and are not aim targets.
type Role = "body" | "detail" | "glow"

type Piece = {
	role: Role,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	-- Where the piece rests: relative to the ground under the enemy's centre,
	-- facing its facing (the front is -Z), or to piece `on` when set.
	offset: CFrame,
	on: number?,
	transparency: number?,
	-- The telegraph pose: reached at the end of the telegraph.
	telegraphPose: CFrame?,
	-- The pose right after the attack lands.
	strike: CFrame?,
	-- How many times bigger the piece is at the end of the telegraph.
	swell: number?,
	-- Turning about its up axis, radians per second, at rest and in the telegraph.
	spin: number?,
	telegraphSpin: number?,
	-- Floating up and down by this many studs.
	bob: number?,
	-- Turns neon during the telegraph.
	glowsOnTelegraph: boolean?,
}

-- Small neon blocks on top of piece `on`, one per boss phase from the
-- second: the first at `at`, the rest stepping toward the front.
type Chevrons = { on: number, at: Vector3, scale: number }

type Look = { pieces: { Piece }, chevrons: Chevrons }

local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball

-- A pose `lean` radians tipped forward (its top toward the front).
local function pose(x: number, y: number, z: number, lean: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(-(lean or 0), 0, 0)
end

local GRUNT: Look = {
	pieces = {
		-- A low hunched body.
		{
			role = "body",
			shape = BLOCK,
			size = Vector3.new(2.6, 1.8, 2.6),
			color = Color3.fromRGB(130, 72, 58),
			offset = pose(0, 1, 0.3, 0.3),
			telegraphPose = pose(0, 0.9, 0.5, 0.55),
			strike = pose(0, 1, -0.5, 0.45),
		},
		-- A big head that ducks in the telegraph and lunges on the attack.
		{
			role = "detail",
			shape = BLOCK,
			size = Vector3.new(2.2, 1.7, 2),
			color = Color3.fromRGB(150, 84, 66),
			offset = pose(0, 2.2, -1),
			telegraphPose = pose(0, 1.8, -1.2, 0.25),
			strike = pose(0, 1.7, -2.2, 0.35),
		},
		-- Two glowing eyes, so the horde reads as a crowd of faces from above.
		{
			role = "glow",
			shape = BALL,
			size = Vector3.new(0.45, 0.45, 0.45),
			color = Color3.fromRGB(255, 230, 120),
			on = 2,
			offset = pose(-0.55, 0.25, -1.02),
		},
		{
			role = "glow",
			shape = BALL,
			size = Vector3.new(0.45, 0.45, 0.45),
			color = Color3.fromRGB(255, 230, 120),
			on = 2,
			offset = pose(0.55, 0.25, -1.02),
		},
		-- A spiky back ridge that breaks the box.
		{
			role = "detail",
			shape = BLOCK,
			size = Vector3.new(0.6, 1.1, 1.6),
			color = Color3.fromRGB(96, 50, 40),
			offset = pose(0, 2.2, 0.6, 0.5),
		},
	},
	chevrons = { on = 1, at = Vector3.new(0, 0.95, 0.9), scale = 1 },
}

local LOOKS: { [string]: Look } = {
	grunt = GRUNT,
	brute = {
		pieces = {
			-- A tall wide body that leans back as the hammer rises.
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(4.2, 4.6, 3.2),
				color = Color3.fromRGB(96, 116, 88),
				offset = pose(0, 2.4, 0.2, 0.1),
				telegraphPose = pose(0, 2.6, 0.5, -0.1),
				strike = pose(0, 2.2, -0.4, 0.3),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(2, 1.5, 1.8),
				color = Color3.fromRGB(110, 132, 100),
				offset = pose(0, 5.2, -0.6, 0.1),
				telegraphPose = pose(0, 5.4, 0.1, -0.1),
				strike = pose(0, 4.6, -1.4, 0.3),
			},
			-- The hammer: hangs at its right side, rises overhead in the
			-- telegraph and lies forward on the ground after the blow.
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.2, 4.6, 1.2),
				color = Color3.fromRGB(72, 76, 74),
				offset = pose(2.9, 2.3, -0.4),
				telegraphPose = pose(2.6, 6.4, 1, -0.5),
				strike = pose(1.6, 1.4, -3.6, math.pi / 2),
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.35, 1.2), scale = 1.2 },
	},
	spitter = {
		pieces = {
			-- A thin tall body.
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(1.5, 3.2, 1.6),
				color = Color3.fromRGB(150, 168, 62),
				offset = pose(0, 1.6, 0.3),
				telegraphPose = pose(0, 1.6, 0.5, -0.15),
				strike = pose(0, 1.6, 0.1, 0.15),
			},
			-- A long neck and head that rears back in the telegraph and spits
			-- forward.
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1, 1, 2.8),
				color = Color3.fromRGB(168, 186, 74),
				offset = pose(0, 3.5, -0.9, -0.25),
				telegraphPose = pose(0, 3.9, -0.1, -0.6),
				strike = pose(0, 3.2, -1.6, 0.1),
			},
			-- The glowing mouth at the front of the head.
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.8, 0.6, 0.3),
				color = Color3.fromRGB(190, 255, 70),
				on = 2,
				offset = pose(0, 0, -1.45),
			},
		},
		-- On the head: the neck hides the body's top.
		chevrons = { on = 2, at = Vector3.new(0, 0.6, 1.1), scale = 1 },
	},
	exploder = {
		pieces = {
			-- A round body that swells in the telegraph.
			{
				role = "body",
				shape = BALL,
				size = Vector3.new(2.8, 2.8, 2.8),
				color = Color3.fromRGB(228, 84, 36),
				offset = pose(0, 1.4, 0),
				swell = 1.4,
				glowsOnTelegraph = true,
			},
			-- A short glowing fuse at the front of the top.
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(0.35, 0.9, 0.35),
				color = Color3.fromRGB(255, 214, 90),
				on = 1,
				offset = pose(0, 1.45, -0.7, 0.5),
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 1.35, 0.7), scale = 1 },
	},
	shieldbearer = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(3, 3.6, 2.2),
				color = Color3.fromRGB(112, 118, 128),
				offset = pose(0, 1.8, 0.4),
				telegraphPose = pose(0, 1.8, 0.5, 0.1),
				strike = pose(0, 1.8, -0.2, 0.2),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.5, 1.3, 1.5),
				color = Color3.fromRGB(128, 134, 144),
				offset = pose(0, 4.25, 0.3),
				strike = pose(0, 4.1, -0.3),
			},
			-- The shield on its front, the blocking side: drawn in for the
			-- telegraph, thrust out on the bash.
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(4.2, 3.8, 0.45),
				color = Color3.fromRGB(150, 156, 166),
				offset = pose(0, 2.1, -1.35),
				telegraphPose = pose(0, 2.6, -0.9, -0.25),
				strike = pose(0, 2, -2.9, 0.15),
			},
			-- The bright rim: a slightly larger plate just behind the shield.
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(4.6, 4.2, 0.25),
				color = Color3.fromRGB(210, 240, 255),
				on = 3,
				offset = pose(0, 0, 0.25),
			},
		},
		-- On the head: the head hides the body's top.
		chevrons = { on = 2, at = Vector3.new(0, 0.7, 0.5), scale = 1 },
	},
	-- Doom's wraith: a tall translucent shape hovering over the ground, two
	-- violet eyes, and two fainter copies trailing behind it as it rushes.
	wraith = {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(1.8, 4.6, 1.3),
				color = Color3.fromRGB(43, 27, 61),
				offset = pose(0, 3.4, 0, 0.15),
				transparency = 0.35,
				bob = 0.3,
			},
			-- The hood, riding the body's bob.
			{
				role = "detail",
				shape = BALL,
				size = Vector3.new(1.9, 1.9, 1.9),
				color = Color3.fromRGB(43, 27, 61),
				on = 1,
				offset = pose(0, 2.9, -0.2),
				transparency = 0.35,
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.38, 0.38, 0.38),
				color = Color3.fromRGB(200, 120, 255),
				on = 2,
				offset = pose(-0.42, 0.1, -0.85),
			},
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(0.38, 0.38, 0.38),
				color = Color3.fromRGB(200, 120, 255),
				on = 2,
				offset = pose(0.42, 0.1, -0.85),
			},
			-- The afterimage: the body again, behind and fading.
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.6, 4.2, 1.2),
				color = Color3.fromRGB(43, 27, 61),
				offset = pose(0, 3.2, 1.8, 0.25),
				transparency = 0.65,
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(1.4, 3.8, 1.1),
				color = Color3.fromRGB(43, 27, 61),
				offset = pose(0, 3, 3.5, 0.35),
				transparency = 0.82,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.4, 0.7), scale = 1 },
	},
	shaman = {
		pieces = {
			-- A slim body.
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(1.6, 3.8, 1.6),
				color = Color3.fromRGB(112, 62, 165),
				offset = pose(0, 1.9, 0.1),
				telegraphPose = pose(0, 2, 0.2, -0.1),
			},
			-- The staff: raised overhead in the telegraph, thrust forward on the cast.
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(0.3, 4.8, 0.3),
				color = Color3.fromRGB(72, 44, 104),
				offset = pose(1.2, 2.4, -0.4, 0.1),
				telegraphPose = pose(0.9, 4.2, -0.6, -0.15),
				strike = pose(1, 2.6, -1.4, 0.6),
			},
			-- The orb floating above: rises and grows in the telegraph.
			{
				role = "glow",
				shape = BALL,
				size = Vector3.new(1.1, 1.1, 1.1),
				color = Color3.fromRGB(205, 150, 255),
				offset = pose(0, 4.9, -0.5),
				telegraphPose = pose(0, 6.3, -0.5),
				swell = 1.5,
				bob = 0.25,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 1.95, 0.55), scale = 1 },
	},
}

-- Status tints, strongest first: slowed (chilled) > burning > poisoned >
-- bleeding > feared > rooted > weakened > buffed. A stunned enemy flickers
-- yellow over whichever it shows; a burning one flickers orange.
local SLOWED_COLOR = Color3.fromRGB(150, 210, 255)
local BURNING_COLOR = Color3.fromRGB(255, 140, 30)
local POISONED_COLOR = Color3.fromRGB(120, 230, 60)
local BLEEDING_COLOR = Color3.fromRGB(130, 10, 20)
local FEARED_COLOR = Color3.fromRGB(165, 90, 230)
local ROOTED_COLOR = Color3.fromRGB(110, 140, 60)
local WEAKENED_COLOR = Color3.fromRGB(130, 130, 130)
local BUFFED_COLOR = Color3.fromRGB(120, 255, 130)
local FLICKER_COLOR = Color3.fromRGB(255, 220, 90)
local STUNNED_COLOR = Color3.fromRGB(255, 245, 80)
local CHEVRON_COLOR = Color3.fromRGB(255, 236, 160)
local WHITE = Color3.new(1, 1, 1)
-- How far a status colour pulls the kind's own colour.
local STATUS_BLEND = 0.55
local BUFFED_BLEND = 0.3
-- How far a solid piece's look colour is pulled toward its kind's colour: a
-- grunt's all the way but for a hint of the look, an elite's halfway, a
-- boss's not at all (its look is its kind's own).
local GRUNT_BLEND = 0.8
local ELITE_BLEND = 0.45
-- A detail piece is drawn this much brighter than the body, so a tinted head
-- stays apart from its body.
local DETAIL_SHADE = 1.15
-- The colour keeps this share of its brightness at no health, plus the rest
-- scaled by health.
local HEALTH_FLOOR = 0.6
-- Health is bucketed so the colour is rebuilt only when it visibly changes.
local HEALTH_STEPS = 20
local TELEGRAPH_HZ = 8
local TELEGRAPH_FLASH = 0.7
-- A swelling piece throbs by this share of its swell with the telegraph pulse.
local SWELL_PULSE = 0.25
local HIT_FLASH_SECONDS = 0.08
-- A burning or stunned enemy flickers in a few steps, so the colour is
-- rewritten only when the step changes.
local FLICKER_SPEED = 21
local FLICKER_STEPS = 3
local FLICKER_BLEND = 0.45
local STUN_FLICKER_BLEND = 0.65
-- After a telegraph: a snap into the strike pose, a hold, then back to rest.
local STRIKE_SNAP = 0.08
local STRIKE_HOLD = 0.25
local SETTLE_SECONDS = 0.3
local SETTLE_END = STRIKE_SNAP + STRIKE_HOLD + SETTLE_SECONDS
-- A charge holds the strike pose thrust this many studs forward, every piece
-- this many times longer front to back.
local CHARGE_LUNGE = 0.6
local CHARGE_STRETCH = 1.3
local BOB_HZ = 0.8
local CHEVRON_SIZE = Vector3.new(0.9, 0.22, 0.32)
local CHEVRON_GAP = 0.5
local MAX_CHEVRONS = 3
-- A dead enemy's parts fade out while sinking to this share of their height.
local DISSOLVE_SECONDS = 0.4
local COLLAPSE = 0.35
-- How long the last drawn position of a vanished enemy stays answerable, so
-- the hit that killed it can still find it.
local DEPARTED_SECONDS = 1
-- Parts made at the start so a full horde (220 alive, mostly two-part grunts)
-- does not hitch; each pool grows past this on demand, never during a frame.
local PREWARM_BODIES = 240
local PREWARM_DETAILS = 360
local PREWARM_GLOWS = 240
local PREWARM_MODELS = 240
-- Enemies farther than this from the local character, on the ground plane, are
-- not laid out or painted: their parts are parked once at `PARKED`, far below
-- the map, until they come back in range. The same range as Effects.
local VIEW_RANGE = 160
local PARKED = CFrame.new(0, -10000, 0)
-- Roblox draws at most 31 Highlights; the boss and elite meshes in range and
-- then the nearest buffed enemies get one, the rest keep only their tint.
local MAX_RIMS = 24
-- A boss stands inside a red glow as tall as its scaled look times
-- AURA_SHARE, pulsing between two transparencies, with a red light.
local BOSS_AURA_COLOR = Color3.fromRGB(255, 40, 40)
local BOSS_AURA_SHARE = 1.6
local BOSS_AURA_THICKNESS = 0.35
-- The ring floats this far above the ground, clear of the terrain's grass.
local BOSS_AURA_RISE = 0.9
local BOSS_AURA_HZ = 0.8
local BOSS_AURA_MIN = 0.45
local BOSS_AURA_MAX = 0.7
local BOSS_LIGHT_BRIGHTNESS = 2
local BOSS_LIGHT_RANGE = 18
-- A sleeping boss or guard: darker, lying on its side and sunk a little,
-- in a faint glow of its lair's colour.
local SLEEP_DIM = 0.55
local SLEEP_TILT = math.rad(70)
local SLEEP_SINK = 0.4
local SLEEP_GLOW_MIN = 0.72
local SLEEP_GLOW_MAX = 0.88
local SLEEP_GLOW_HZ = 0.35
local SLEEP_LIGHT_BRIGHTNESS = 0.6
-- A telegraph's length before the event that names it arrives.
local DEFAULT_TELEGRAPH = 0.5

-- A mesh (ADR-0022) has no pieces to pose, and a textured mesh ignores its
-- Color: it moves, tilts, scales and fades as a whole, and shows its tints
-- through a Highlight (bosses and elites) or a ring at its feet (the rest).
-- The walk: a hop of this share of its height and a lean of up to this much
-- toward where it moves, both at the kind's full speed, so many steps a second.
local WALK_BOB_SHARE = 0.05
local WALK_LEAN = math.rad(8)
local WALK_STEPS_HZ = 2.4
-- How fast the drawn velocity follows the measured one, per second.
local WALK_SMOOTHING = 10
-- The telegraph: a rise by this share of its height, rearing back.
local MESH_RISE_SHARE = 0.12
local MESH_REAR = math.rad(6)
-- The attack: a lunge forward by this share of its depth and back, leaning in.
local MESH_LUNGE_SHARE = 0.35
local MESH_LUNGE_SECONDS = 0.15
local MESH_LUNGE_LEAN = math.rad(12)
-- The charge: tipped forward.
local MESH_CHARGE_TILT = math.rad(16)
-- A mesh without a Highlight pops this much bigger in the hit flash.
local MESH_HIT_POP = 1.08
-- A dead mesh tips over forward by this much while it fades.
local MESH_DEATH_TIP = math.rad(85)
-- A sleeping mesh is dimmed by transparency, since its colour does not show.
local MESH_SLEEP_TRANSPARENCY = 0.4
-- A boss's or elite's Highlight: the fill's transparency for a status, a hit
-- flash and the end of the telegraph.
local SHELL_STATUS_FILL = 0.6
local SHELL_FLASH_FILL = 0.3
local SHELL_TELEGRAPH_FILL = 0.45
local SHELL_TELEGRAPH_COLOR = Color3.fromRGB(255, 240, 200)
-- The share of the telegraph's glow that throbs with its pulse.
local SHELL_TELEGRAPH_PULSE = 0.35
-- The status ring of a mesh without a Highlight: as wide as its footprint
-- times this share, with a small light of the status's colour.
local STATUS_RING_SHARE = 1.2
local STATUS_RING_THICKNESS = 0.2
local STATUS_RING_RISE = 0.6
local STATUS_RING_TRANSPARENCY = 0.35
local STATUS_LIGHT_BRIGHTNESS = 1
local STATUS_LIGHT_RANGE = 6
-- Meshes cloned for each kind by its role once its mesh has loaded.
local PREWARM_MESHES: { [string]: number } =
	{ grunt = 30, elite = 6, boss = 1, finalBoss = 1, wraith = 4 }
-- The telegraph swell and the idle hover of a mesh, by look, as that look's
-- pieces swell and hover.
local MESH_SWELL: { [string]: number } = { exploder = 1.4 }
local MESH_HOVER: { [string]: number } = { wraith = 0.3 }
-- A kind whose mesh does not face -Z: its turn about up, radians, by kind id.
local MESH_FACING: { [string]: number } = {}

-- Enemies are drawn one snapshot interval behind the newest data, so there is
-- always a next position to glide to.
local interval = 1 / Config.net.snapshotHz

-- The lair kinds by id, for a sleeping enemy's glow.
local lairKinds: { [string]: Types.LairKindConfig } = {}
for _, lairKind in Config.lairs.kinds do
	lairKinds[lairKind.id] = lairKind
end

type Rig = {
	look: Look,
	model: Model,
	kindId: string,
	-- The look's pieces in order, then the chevrons; a mesh rig's one piece
	-- is its mesh.
	parts: { BasePart },
	roles: { Role },
	-- Each chevron's place on its piece.
	chevronOffsets: { CFrame },
	-- Every part's world frame this frame, in the order of `parts`.
	frames: { CFrame },
	scales: { number },
	angles: { number },
	-- Each piece's colour tinted toward the kind's, before statuses and health.
	own: { Color3 },
	-- Each part's colour apart from flashes, and the colour and material last
	-- written to it.
	base: { Color3 },
	shown: { Color3 },
	materials: { Enum.Material },
	-- The ground frame under the enemy's centre, turned to its facing.
	root: CFrame,
	-- A per-enemy offset so bobs and flickers do not move in step.
	phase: number,
	state: Types.EnemyState,
	colorKey: number,
	chevronCount: number,
	-- How long the telegraph in progress lasts: the kind's first attack's
	-- until a telegraph event names the attack's own.
	telegraphSeconds: number,
	telegraphAt: number?,
	-- When the last telegraph ended, how far it got and whether an attack landed.
	endedAt: number?,
	reached: number,
	struck: boolean,
	-- When the charge in progress started.
	chargeAt: number?,
	-- How many times longer front to back the pieces are drawn (the charge).
	stretch: number,
	flashUntil: number,
	-- Held still until then by a skill hit (the hit-stop).
	holdUntil: number,
	-- Weakened until then: the wire carries no flag for it, the event does.
	weakenedUntil: number,
	stamp: number,
	-- The green rim of a buffed enemy.
	rim: Highlight?,
	-- How many times bigger than its look it is drawn: the kind's scale.
	size: number,
	boss: boolean,
	-- The boss's red glow, and how high its centre sits and how wide it is.
	aura: Part?,
	auraRise: number,
	auraDiameter: number,
	-- The latest snapshot's position.
	x: number,
	z: number,
	-- Beyond `VIEW_RANGE` at the latest snapshot, and whether its parts are parked.
	culled: boolean,
	parked: boolean,
	-- Squared distance to the local character at the latest snapshot, for the rims.
	distance: number,
	-- Asleep in its lair, in the lair's colour; the pose it lies in (identity awake).
	sleepColor: Color3?,
	pose: CFrame,
	-- Drawn as its kind's mesh rather than pieces.
	mesh: MeshPart?,
	-- A boss's or elite's mesh shows its tints in its Highlight (the rim),
	-- and the fill and outline last written to it.
	shell: boolean,
	shellColor: Color3?,
	shellFill: number,
	shellOutline: number,
	-- The mesh's transparency apart from the death's fade.
	meshTransparency: number,
	-- The status ring of a mesh without a Highlight, the colour it shows,
	-- and the colour the latest snapshot asks for.
	ring: Part?,
	ringColor: Color3?,
	statusColor: Color3?,
	-- The mesh's walk: its drawn velocity, the root's position last frame,
	-- the steps taken and the kind's speed.
	velocity: Vector3,
	lastPosition: Vector3?,
	walkPhase: number,
	walkSpeed: number,
	-- The mesh's telegraph swell, idle hover and turn to its front.
	swell: number,
	hover: number,
	turn: CFrame,
}

type Dying = { rig: Rig, at: number, locals: { CFrame } }

local folder: Folder
-- The free parts of each role.
local freeBodies: { Part } = {}
local freeDetails: { Part } = {}
local freeGlows: { Part } = {}
local freeModels: { Model } = {}
local freeRims: { Highlight } = {}
local freeAuras: { Part } = {}
local freeRings: { Part } = {}
-- Each kind's loaded mesh, the look drawn from it and its free clones.
local meshTemplates: { [string]: MeshPart } = {}
local meshLooks: { [string]: Look } = {}
local freeMeshes: { [string]: { MeshPart } } = {}
local rigs: { [number]: Rig } = {}
local dying: { Dying } = {}
local firstTelegraphs: { [string]: number } = {}
local generation = 0
-- The previous snapshot's enemies by id.
local previousById: { [number]: Protocol.EnemyView } = {}
local departed: { [number]: Vector3 } = {}
local departedAt: { [number]: number } = {}
-- Reused every frame for the bulk move.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
-- Reused every snapshot: the boss and elite meshes in range, the buffed
-- enemies in range, and those given a rim.
local shellCandidates: { Rig } = {}
local rimCandidates: { Rig } = {}
local rimmed: { [Rig]: boolean } = {}

local function newPart(role: Role): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = if role == "glow" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	return part
end

local function poolOf(role: Role): { Part }
	if role == "body" then
		return freeBodies
	elseif role == "detail" then
		return freeDetails
	end
	return freeGlows
end

local function prewarm(role: Role, count: number)
	local pool = poolOf(role)
	for _ = 1, count do
		table.insert(pool, newPart(role))
	end
end

local function take(role: Role): Part
	local part = table.remove(poolOf(role)) or newPart(role)
	-- Solid pieces are queryable, so a ray from the camera can land on an enemy.
	part.CanQuery = role ~= "glow"
	return part
end

local function give(role: Role, part: BasePart)
	part.Parent = nil
	table.insert(poolOf(role), part :: Part)
end

-- The telegraph of the kind's first attack.
local function telegraphOf(kindId: string): number
	local known = firstTelegraphs[kindId]
	if known then
		return known
	end
	local kind = Config.enemies[kindId]
	local first = if kind then kind.attacks[1] else nil
	local seconds = if first and first.telegraphSeconds > 0
		then first.telegraphSeconds
		else DEFAULT_TELEGRAPH
	firstTelegraphs[kindId] = seconds
	return seconds
end

local function rootFrame(x: number, z: number, facing: number): CFrame
	-- The front is -Z; the facing is measured from +X toward +Z.
	return CFrame.new(x, Net.groundY(x, z), z) * CFrame.Angles(0, -facing - math.pi / 2, 0)
end

local function assetId(id: string): string
	if id ~= "" and tonumber(id) ~= nil then
		return "rbxassetid://" .. id
	end
	return id
end

-- A look of one piece, the mesh: its native size times its entry's scale,
-- its base `yOffset` above the ground, the chevrons on its top toward the back.
local function meshLookOf(template: MeshPart, entry: Types.PropConfig): Look
	local size = template.Size * entry.scale
	return {
		pieces = {
			{
				role = "body",
				shape = BLOCK,
				size = size,
				color = WHITE,
				offset = CFrame.new(0, entry.yOffset + size.Y / 2, 0),
			},
		},
		chevrons = {
			on = 1,
			at = Vector3.new(0, size.Y / 2 + 0.1, size.Z * 0.2),
			scale = math.max(1, size.X / 3),
		},
	}
end

-- Loads kind `kindId`'s mesh and clones its pool; until it has loaded, or
-- when it fails, the kind is drawn from parts.
local function loadMesh(kindId: string, entry: Types.PropConfig)
	local ok, result = pcall(function(): MeshPart
		return InsertService:CreateMeshPartAsync(
			assetId(entry.meshId),
			Enum.CollisionFidelity.Box,
			Enum.RenderFidelity.Automatic
		)
	end)
	if not ok then
		warn(`EnemyView: the mesh of {kindId} ({entry.meshId}) did not load, using parts: {result}`)
		return
	end
	local template: MeshPart = result
	template.Name = kindId
	template.Anchored = true
	template.CanCollide = false
	template.CanQuery = false
	template.CanTouch = false
	template.CastShadow = true
	if entry.textureId ~= "" then
		template.TextureID = assetId(entry.textureId)
	end
	local kind = Config.enemies[kindId]
	local pool: { MeshPart } = {}
	for _ = 1, if kind then PREWARM_MESHES[kind.role] or 0 else 0 do
		table.insert(pool, template:Clone())
	end
	freeMeshes[kindId] = pool
	meshLooks[kindId] = meshLookOf(template, entry)
	meshTemplates[kindId] = template
end

-- `count` chevrons (up to `MAX_CHEVRONS`; 0 for none), replacing any it had.
local function setChevrons(rig: Rig, count: number)
	local first = #rig.look.pieces + 1
	for index = #rig.parts, first, -1 do
		give("glow", rig.parts[index])
		rig.parts[index] = nil
		rig.roles[index] = nil
		rig.frames[index] = nil
		rig.base[index] = nil
		rig.shown[index] = nil
		rig.materials[index] = nil
	end
	table.clear(rig.chevronOffsets)
	local chevrons = rig.look.chevrons
	local size = CHEVRON_SIZE * chevrons.scale * rig.size
	local on = rig.frames[chevrons.on] or rig.root
	for step = 1, math.min(count, MAX_CHEVRONS) do
		local part = take("glow")
		part.Shape = BLOCK
		part.Size = size
		part.Transparency = 0
		local offset = CFrame.new(
			(chevrons.at - Vector3.new(0, 0, (step - 1) * CHEVRON_GAP * chevrons.scale)) * rig.size
		)
		local index = first + step - 1
		-- A parked enemy's new chevrons wait with its other parts.
		part.CFrame = if rig.parked then PARKED else on * offset
		part.Parent = rig.model
		rig.parts[index] = part
		rig.roles[index] = "glow"
		rig.frames[index] = part.CFrame
		rig.materials[index] = Enum.Material.Neon
		rig.chevronOffsets[step] = offset
	end
	rig.chevronCount = count
	-- The new chevrons need their colours.
	rig.colorKey = -1
end

-- Lays out every part of `rig` around its root into `rig.frames`.
local function layout(rig: Rig, now: number, pulse: number, dt: number)
	local progress = 0
	local telegraphAt = rig.telegraphAt
	if telegraphAt then
		progress = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
	end
	local chargeAt = rig.chargeAt
	local endedAt = rig.endedAt
	local since = if endedAt then now - endedAt else math.huge
	local pieces = rig.look.pieces
	for index, piece in pieces do
		local offset = piece.offset
		local raised = piece.telegraphPose
		if chargeAt then
			-- The charge: snapped from the telegraph's pose into the strike's, thrust forward.
			local from = if raised then offset:Lerp(raised, rig.reached) else offset
			local strike = CFrame.new(0, 0, -CHARGE_LUNGE) * (piece.strike or raised or offset)
			offset = from:Lerp(strike, math.min(1, (now - chargeAt) / STRIKE_SNAP))
		elseif telegraphAt then
			if raised then
				offset = offset:Lerp(raised, progress)
			end
		elseif since < SETTLE_END then
			local from = if raised then offset:Lerp(raised, rig.reached) else offset
			local strike = piece.strike
			if rig.struck and strike then
				if since < STRIKE_SNAP then
					offset = from:Lerp(strike, since / STRIKE_SNAP)
				elseif since < STRIKE_SNAP + STRIKE_HOLD then
					offset = strike
				else
					local back = (since - STRIKE_SNAP - STRIKE_HOLD) / SETTLE_SECONDS
					offset = strike:Lerp(offset, math.min(1, back))
				end
			else
				offset = from:Lerp(offset, math.min(1, since / SETTLE_SECONDS))
			end
		end

		local scale = 1
		local swell = piece.swell
		if swell and telegraphAt then
			scale = 1 + (swell - 1) * progress * (1 - SWELL_PULSE + SWELL_PULSE * pulse)
		end
		if scale ~= rig.scales[index] then
			rig.scales[index] = scale
			local size = piece.size * scale * rig.size
			rig.parts[index].Size = Vector3.new(size.X, size.Y, size.Z * rig.stretch)
		end
		local on = piece.on
		if on then
			-- Rides a swelling parent's surface outward.
			local parentScale = rig.scales[on]
			if parentScale ~= 1 then
				offset = CFrame.new(offset.Position * (parentScale - 1)) * offset
			end
		elseif scale ~= 1 then
			-- Stays standing on the ground as it grows.
			offset = CFrame.new(0, (scale - 1) * piece.size.Y / 2, 0) * offset
		end

		local spin = if telegraphAt then piece.telegraphSpin or piece.spin else piece.spin
		if spin then
			rig.angles[index] += spin * dt
			offset *= CFrame.Angles(0, rig.angles[index], 0)
		end
		local bob = piece.bob
		if bob then
			offset = CFrame.new(0, bob * math.sin((now * BOB_HZ + rig.phase) * 2 * math.pi), 0)
				* offset
		end
		-- A bigger look: every step from the root grows alike, so the whole scales about it.
		if rig.size ~= 1 then
			offset = offset.Rotation + offset.Position * rig.size
		end

		rig.frames[index] = (if on then rig.frames[on] else rig.root * rig.pose) * offset
	end

	local chevrons = rig.look.chevrons
	local carrier = rig.frames[chevrons.on]
	local carrierScale = rig.scales[chevrons.on]
	for step, offset in rig.chevronOffsets do
		if carrierScale ~= 1 then
			offset = CFrame.new(offset.Position * (carrierScale - 1)) * offset
		end
		rig.frames[#pieces + step] = carrier * offset
	end
end

-- Lays out a mesh rig into `rig.frames`: the walk's hop and lean, the
-- telegraph's rise, the attack's lunge and the charge's tilt all move the one
-- mesh, pivoting at its feet.
local function layoutMesh(rig: Rig, now: number, pulse: number, dt: number)
	local mesh = rig.mesh :: MeshPart
	local piece = rig.look.pieces[1]
	local size = piece.size * rig.size
	local height = size.Y

	-- The walk, from how far the drawn root moved since the last frame.
	local position = rig.root.Position
	local last = rig.lastPosition
	local measured = if last and dt > 0 then (position - last) / dt else Vector3.zero
	rig.lastPosition = position
	rig.velocity = rig.velocity:Lerp(measured, math.min(1, dt * WALK_SMOOTHING))
	local moving = rig.root:VectorToObjectSpace(rig.velocity)
	local forward = -moving.Z / rig.walkSpeed
	local side = moving.X / rig.walkSpeed
	local pace = math.sqrt(forward * forward + side * side)
	if pace > 1 then
		forward, side, pace = forward / pace, side / pace, 1
	end
	rig.walkPhase += dt * WALK_STEPS_HZ * pace
	local bob = WALK_BOB_SHARE * height * pace * math.abs(math.sin(rig.walkPhase * math.pi))
	if rig.hover > 0 then
		bob += rig.hover * rig.size * math.sin((now * BOB_HZ + rig.phase) * 2 * math.pi)
	end

	local progress = 0
	local telegraphAt = rig.telegraphAt
	if telegraphAt then
		progress = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
	end
	local chargeAt = rig.chargeAt
	local endedAt = rig.endedAt
	local since = if endedAt then now - endedAt else math.huge
	local rise, rear, push, tilt = 0, 0, 0, 0
	if chargeAt then
		local snap = math.min(1, (now - chargeAt) / STRIKE_SNAP)
		rise = MESH_RISE_SHARE * height * rig.reached * (1 - snap)
		tilt = MESH_CHARGE_TILT * snap
	elseif telegraphAt then
		rise = MESH_RISE_SHARE * height * progress
		rear = MESH_REAR * progress
	elseif since < SETTLE_END then
		local settle = math.max(0, 1 - since / SETTLE_SECONDS)
		rise = MESH_RISE_SHARE * height * rig.reached * settle
		rear = MESH_REAR * rig.reached * settle
		if rig.struck and since < MESH_LUNGE_SECONDS then
			local out = math.sin(math.pi * since / MESH_LUNGE_SECONDS)
			push = MESH_LUNGE_SHARE * size.Z * out
			tilt = MESH_LUNGE_LEAN * out
		end
	end

	local scale = 1
	if telegraphAt and rig.swell ~= 1 then
		scale = 1 + (rig.swell - 1) * progress * (1 - SWELL_PULSE + SWELL_PULSE * pulse)
	end
	if rig.flashUntil > now and not rig.shell then
		scale *= MESH_HIT_POP
	end
	if scale ~= rig.scales[1] then
		rig.scales[1] = scale
		mesh.Size = size * scale
	end
	-- Stands on the ground as it grows.
	local lift = piece.offset.Position.Y * rig.size + (scale - 1) * height / 2

	local lean = CFrame.Angles(-(WALK_LEAN * forward + tilt - rear), 0, -WALK_LEAN * side)
	local body = rig.root
		* rig.pose
		* CFrame.new(0, 0, -push)
		* lean
		* CFrame.new(0, lift + rise + bob, 0)
	rig.frames[1] = body * rig.turn
	for step, offset in rig.chevronOffsets do
		if scale ~= 1 then
			offset = CFrame.new(offset.Position * (scale - 1)) * offset
		end
		rig.frames[1 + step] = body * offset
	end
end

-- Lays out a rig of either kind.
local function place(rig: Rig, now: number, pulse: number, dt: number)
	if rig.mesh then
		layoutMesh(rig, now, pulse, dt)
	else
		layout(rig, now, pulse, dt)
	end
end

-- How tall a look stands: the top of its highest piece resting on the ground.
local function heightOf(look: Look): number
	local top = 0
	for _, piece in look.pieces do
		if piece.on == nil then
			top = math.max(top, piece.offset.Position.Y + piece.size.Y / 2)
		end
	end
	return top
end

local function newAura(): Part
	local aura = Instance.new("Part")
	aura.Name = "BossAura"
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura.CastShadow = false
	aura.Shape = Enum.PartType.Cylinder
	aura.Material = Enum.Material.Neon
	aura.Color = BOSS_AURA_COLOR
	aura.Transparency = BOSS_AURA_MAX
	local light = Instance.new("PointLight")
	light.Color = BOSS_AURA_COLOR
	light.Brightness = BOSS_LIGHT_BRIGHTNESS
	light.Range = BOSS_LIGHT_RANGE
	light.Shadows = false
	light.Parent = aura
	return aura
end

local function newRing(): Part
	local ring = Instance.new("Part")
	ring.Name = "StatusRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = STATUS_RING_TRANSPARENCY
	local light = Instance.new("PointLight")
	light.Brightness = STATUS_LIGHT_BRIGHTNESS
	light.Range = STATUS_LIGHT_RANGE
	light.Shadows = false
	light.Parent = ring
	return ring
end

local function ringFrame(rig: Rig): CFrame
	return (rig.root + Vector3.new(0, STATUS_RING_RISE, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

-- Shows a mesh's status ring in `color`, or takes it back when nil.
local function setRing(rig: Rig, color: Color3?)
	local ring = rig.ring
	if color then
		if ring == nil then
			local fresh = table.remove(freeRings) or newRing()
			local footprint = rig.look.pieces[1].size
			local diameter = math.max(footprint.X, footprint.Z) * rig.size * STATUS_RING_SHARE
			fresh.Size = Vector3.new(STATUS_RING_THICKNESS, diameter, diameter)
			fresh.CFrame = if rig.parked then PARKED else ringFrame(rig)
			fresh.Parent = rig.model
			rig.ring = fresh
			ring = fresh
		end
		if ring and rig.ringColor ~= color then
			rig.ringColor = color
			ring.Color = color
			local light = ring:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = color
			end
		end
	elseif ring then
		ring.Parent = nil
		table.insert(freeRings, ring)
		rig.ring = nil
		rig.ringColor = nil
	end
end

-- Gives the boss its glow or takes it back.
local function setAura(rig: Rig, on: boolean)
	local aura = rig.aura
	if on and aura == nil then
		local fresh = table.remove(freeAuras) or newAura()
		local diameter = rig.auraDiameter
		fresh.Size = Vector3.new(BOSS_AURA_THICKNESS, diameter, diameter)
		fresh.CFrame = if rig.parked
			then PARKED
			else (rig.root + Vector3.new(0, rig.auraRise, 0)) * CFrame.Angles(
				0,
				0,
				math.pi / 2
			)
		fresh.Parent = rig.model
		rig.aura = fresh
	elseif not on and aura then
		aura.Parent = nil
		table.insert(freeAuras, aura)
		rig.aura = nil
	end
end

local function clampColor(r: number, g: number, b: number): Color3
	return Color3.new(math.min(r, 1), math.min(g, 1), math.min(b, 1))
end

local function shade(color: Color3, factor: number): Color3
	return clampColor(color.R * factor, color.G * factor, color.B * factor)
end

local function fromHex(rgb: number): Color3
	return Color3.fromRGB(bit32.rshift(rgb, 16) % 256, bit32.rshift(rgb, 8) % 256, rgb % 256)
end

-- The look a kind is drawn with and how far its pieces take the kind's colour.
local function lookOf(kind: Types.EnemyKindConfig?): (Look, number)
	if kind == nil then
		return GRUNT, 0
	end
	local boss = BossLooks.looks[kind.look]
	if boss then
		return boss, 0
	end
	local look = LOOKS[kind.look]
	if look == nil or look == GRUNT then
		return GRUNT, GRUNT_BLEND
	end
	-- A wraith is its kind's colour through and through.
	return look, if kind.role == "wraith" then 1 else ELITE_BLEND
end

local function isBoss(kind: Types.EnemyKindConfig?): boolean
	return kind ~= nil and (kind.role == "boss" or kind.role == "finalBoss")
end

-- The chevrons a phase shows: one per phase from the second.
local function chevronsFor(phase: number): number
	return if phase >= 2 then phase else 0
end

local function spawnRig(id: number, enemy: Protocol.EnemyView): Rig
	local kind = Config.enemies[enemy.kind]
	local template: MeshPart? = meshTemplates[enemy.kind]

	local look, blend
	if template then
		look, blend = meshLooks[enemy.kind], 0
	else
		look, blend = lookOf(kind)
	end
	local size = if kind then kind.scale else 1
	local tint = if kind then fromHex(kind.colour) else WHITE
	local boss = isBoss(kind)
	local model = table.remove(freeModels) or Instance.new("Model")
	model.Name = enemy.kind
	local rig: Rig = {
		look = look,
		model = model,
		kindId = enemy.kind,
		parts = {},
		roles = {},
		chevronOffsets = {},
		frames = {},
		scales = {},
		angles = {},
		own = {},
		base = {},
		shown = {},
		materials = {},
		root = rootFrame(enemy.x, enemy.z, enemy.facing),
		phase = (id * 0.618) % 1,
		state = enemy.state,
		colorKey = -1,
		chevronCount = 0,
		telegraphSeconds = telegraphOf(enemy.kind),
		telegraphAt = if enemy.state == "telegraph" then os.clock() else nil,
		endedAt = nil,
		reached = 0,
		struck = false,
		chargeAt = if enemy.state == "charge" then os.clock() else nil,
		stretch = if enemy.state == "charge" then CHARGE_STRETCH else 1,
		flashUntil = 0,
		holdUntil = 0,
		weakenedUntil = 0,
		stamp = generation,
		rim = nil,
		size = size,
		boss = boss,
		aura = nil,
		auraRise = 0,
		auraDiameter = 0,
		x = enemy.x,
		z = enemy.z,
		culled = false,
		parked = false,
		distance = 0,
		sleepColor = nil,
		pose = CFrame.identity,
		mesh = nil,
		shell = template ~= nil and kind ~= nil and (boss or kind.role == "elite"),
		shellColor = nil,
		shellFill = -1,
		shellOutline = -1,
		meshTransparency = 0,
		ring = nil,
		ringColor = nil,
		statusColor = nil,
		velocity = Vector3.zero,
		lastPosition = nil,
		walkPhase = 0,
		walkSpeed = if kind then math.max(kind.speed, 1) else 1,
		swell = if kind then MESH_SWELL[kind.look] or 1 else 1,
		hover = if kind then MESH_HOVER[kind.look] or 0 else 0,
		turn = CFrame.Angles(0, MESH_FACING[enemy.kind] or 0, 0),
	}
	for index, piece in look.pieces do
		local part: BasePart
		if template then
			local mesh = table.remove(freeMeshes[enemy.kind]) or template:Clone()
			mesh.Size = piece.size * size
			mesh.Transparency = 0
			rig.mesh = mesh
			part = mesh
		else
			local fresh = take(piece.role)
			fresh.Shape = piece.shape
			local scaled = piece.size * size
			fresh.Size = Vector3.new(scaled.X, scaled.Y, scaled.Z * rig.stretch)
			fresh.Transparency = piece.transparency or 0
			part = fresh
		end
		part.Parent = model
		rig.parts[index] = part
		rig.roles[index] = piece.role
		rig.scales[index] = 1
		rig.angles[index] = 0
		rig.materials[index] = part.Material
		local own = piece.color
		if piece.role ~= "glow" and blend > 0 then
			own = own:Lerp(tint, blend)
			if piece.role == "detail" then
				own = shade(own, DETAIL_SHADE)
			end
		end
		rig.own[index] = own
	end
	model.PrimaryPart = rig.parts[1]
	-- Appears where it is, not where a stale pooled part was.
	place(rig, os.clock(), 0, 0)
	for index, part in rig.parts do
		part.CFrame = rig.frames[index]
	end
	setChevrons(rig, chevronsFor(enemy.phase))
	-- A flat ring of light at the boss's feet, so its silhouette stays readable;
	-- a sleeping guard lies in one too.
	rig.auraRise = BOSS_AURA_RISE
	rig.auraDiameter = heightOf(look) * size * BOSS_AURA_SHARE
	if boss then
		setAura(rig, true)
	end
	model.Parent = folder
	rigs[id] = rig
	departed[id] = nil
	departedAt[id] = nil
	return rig
end

local function newRim(): Highlight
	local rim = Instance.new("Highlight")
	rim.FillTransparency = 1
	rim.OutlineColor = BUFFED_COLOR
	rim.OutlineTransparency = 0
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	return rim
end

local function setRim(rig: Rig, on: boolean)
	local rim = rig.rim
	if on and rim == nil then
		local fresh = table.remove(freeRims) or newRim()
		-- A pooled Highlight may come from a boss's or elite's mesh.
		fresh.FillTransparency = 1
		fresh.OutlineColor = BUFFED_COLOR
		fresh.OutlineTransparency = if rig.shell then 1 else 0
		rig.shellColor = nil
		rig.shellFill = 1
		rig.shellOutline = fresh.OutlineTransparency
		-- Adorns the mesh, or its parent, the enemy's model.
		fresh.Adornee = rig.mesh
		fresh.Parent = rig.model
		rig.rim = fresh
	elseif not on and rim then
		rim.Parent = nil
		rim.Adornee = nil
		table.insert(freeRims, rim)
		rig.rim = nil
	end
end

-- The status colour an enemy shows, strongest first, and how far it pulls.
-- How much of a status tint a boss takes, as a share of a grunt's.
local BOSS_STATUS_SHARE = 0.35

local function statusTint(enemy: Protocol.EnemyView, weakened: boolean): (Color3?, number)
	if enemy.slowed then
		return SLOWED_COLOR, STATUS_BLEND
	elseif enemy.burning then
		return BURNING_COLOR, STATUS_BLEND
	elseif enemy.poisoned then
		return POISONED_COLOR, STATUS_BLEND
	elseif enemy.bleeding then
		return BLEEDING_COLOR, STATUS_BLEND
	elseif enemy.feared then
		return FEARED_COLOR, STATUS_BLEND
	elseif enemy.rooted then
		return ROOTED_COLOR, STATUS_BLEND
	elseif weakened then
		return WEAKENED_COLOR, STATUS_BLEND
	elseif enemy.buffed then
		return BUFFED_COLOR, BUFFED_BLEND
	end
	return nil, 0
end

-- The colour of a solid piece at rest: its kind-tinted own, pulled toward the
-- status it carries, darker as its health falls.
local function baseColor(own: Color3, enemy: Protocol.EnemyView, weakened: boolean): Color3
	local color = own
	local status, blend = statusTint(enemy, weakened)
	if status then
		-- A boss keeps most of its own colour, or a chilled boss would be a pale slab.
		local kind = Config.enemies[enemy.kind]
		if kind and (kind.role == "boss" or kind.role == "finalBoss") then
			blend *= BOSS_STATUS_SHARE
		end
		color = color:Lerp(status, blend)
	end
	local health = math.round(math.clamp(enemy.health, 0, 1) * HEALTH_STEPS) / HEALTH_STEPS
	return shade(color, HEALTH_FLOOR + (1 - HEALTH_FLOOR) * health)
end

local function colorKey(enemy: Protocol.EnemyView, weakened: boolean, asleep: boolean): number
	local flags = (if enemy.slowed then 1 else 0)
		+ (if enemy.burning then 2 else 0)
		+ (if enemy.poisoned then 4 else 0)
		+ (if enemy.bleeding then 8 else 0)
		+ (if enemy.feared then 16 else 0)
		+ (if enemy.rooted then 32 else 0)
		+ (if weakened then 64 else 0)
		+ (if enemy.buffed then 128 else 0)
		+ (if asleep then 256 else 0)
	local health = math.round(math.clamp(enemy.health, 0, 1) * HEALTH_STEPS)
	return flags * 64 + health
end

-- The material of a piece: neon when it glows, or when it glows in the
-- telegraph and the charge; icy when slowed.
local function materialOf(piece: Piece, enemy: Protocol.EnemyView): Enum.Material
	local windUp = enemy.state == "telegraph" or enemy.state == "charge"
	if piece.role == "glow" or (piece.glowsOnTelegraph and windUp) then
		return Enum.Material.Neon
	elseif enemy.slowed then
		return Enum.Material.Ice
	end
	return Enum.Material.SmoothPlastic
end

local function recycle(rig: Rig)
	local mesh = rig.mesh
	for index, part in rig.parts do
		if mesh and index == 1 then
			mesh.Parent = nil
			table.insert(freeMeshes[rig.kindId], mesh)
		else
			give(rig.roles[index], part)
		end
	end
	rig.model.PrimaryPart = nil
	rig.model.Parent = nil
	table.insert(freeModels, rig.model)
end

-- Where a parked enemy is: its snapshot position on the ground.
local function groundPosition(rig: Rig): Vector3
	return Vector3.new(rig.x, Net.groundY(rig.x, rig.z), rig.z)
end

local function kill(id: number, rig: Rig, now: number)
	departedAt[id] = now
	rigs[id] = nil
	setRim(rig, false)
	setAura(rig, false)
	setRing(rig, nil)
	if rig.parked then
		-- Out of sight: no collapse to draw.
		departed[id] = groundPosition(rig)
		recycle(rig)
		return
	end
	departed[id] = rig.parts[1].Position
	-- Each part's place relative to the ground frame, for the collapse.
	local locals: { CFrame } = {}
	for index, part in rig.parts do
		part.CanQuery = false
		locals[index] = rig.root:ToObjectSpace(rig.frames[index] or part.CFrame)
	end
	table.insert(dying, { rig = rig, at = now, locals = locals })
end

-- Where the culling measures from: the local character, or the camera before
-- it has one; nil when neither is there.
local function viewCenter(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function nearer(a: Rig, b: Rig): boolean
	return a.distance < b.distance
end

-- Of the `MAX_RIMS` Highlights, gives one to the boss and elite meshes in
-- range first (bosses, then the nearest elites: it is their only tint), the
-- rest as the green rim to the nearest buffed enemies, and takes it from every
-- other. A mesh without a Highlight shows its status as a ring at its feet.
local function assignRims()
	table.sort(shellCandidates, function(a: Rig, b: Rig): boolean
		if a.boss ~= b.boss then
			return a.boss
		end
		return a.distance < b.distance
	end)
	local shells = math.min(#shellCandidates, MAX_RIMS)
	for index = 1, shells do
		rimmed[shellCandidates[index]] = true
	end
	local budget = MAX_RIMS - shells
	if #rimCandidates > budget then
		table.sort(rimCandidates, nearer)
	end
	for index = 1, math.min(#rimCandidates, budget) do
		rimmed[rimCandidates[index]] = true
	end
	for _, rig in rigs do
		setRim(rig, rimmed[rig] == true)
		if rig.mesh then
			local color = rig.statusColor
			if rig.rim and (rig.shell or color == BUFFED_COLOR) then
				color = nil
			end
			setRing(rig, color)
		end
	end
	table.clear(rimmed)
	table.clear(shellCandidates)
	table.clear(rimCandidates)
end

-- Draws every size anew on the next layout (the stretch changed).
local function resize(rig: Rig)
	for index in rig.scales do
		rig.scales[index] = -1
	end
end

-- Follows the enemy's state: the telegraph's wind-up, the charge's lunge and
-- the strike pose after an attack.
local function setState(rig: Rig, state: Types.EnemyState, now: number)
	local was = rig.state
	if state == was then
		return
	end
	if state == "telegraph" then
		rig.telegraphAt = now
		rig.endedAt = nil
		rig.chargeAt = nil
	elseif state == "charge" then
		if was == "telegraph" then
			local telegraphAt = rig.telegraphAt or now
			rig.reached = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
		end
		rig.telegraphAt = nil
		rig.endedAt = nil
		rig.chargeAt = now
	elseif was == "charge" then
		-- Out of the charge: the strike pose held, then back to rest.
		rig.chargeAt = nil
		rig.endedAt = now - STRIKE_SNAP
		rig.struck = true
	elseif was == "telegraph" then
		local telegraphAt = rig.telegraphAt or now
		rig.reached = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
		rig.telegraphAt = nil
		rig.endedAt = now
		-- A telegraph followed by a recovery is an attack that landed.
		rig.struck = state == "recover"
	end
	rig.state = state
	local stretch = if state == "charge" then CHARGE_STRETCH else 1
	if stretch ~= rig.stretch then
		rig.stretch = stretch
		resize(rig)
	end
end

-- The colour of the lair enemy `enemy` sleeps in, or nil when it is awake: a
-- lair's boss while the lair sleeps, or an elite standing still inside a
-- sleeping lair (its guard).
local function sleepingIn(enemy: Protocol.EnemyView, lairs: { Protocol.LairView }): Color3?
	if not enemy.asleep then
		return nil
	end
	-- The glow takes the colour of the nearest lair.
	local best: Protocol.LairView? = nil
	local bestDistance = math.huge
	for _, lair in lairs do
		local distance = (enemy.x - lair.x) ^ 2 + (enemy.z - lair.z) ^ 2
		if distance < bestDistance then
			best, bestDistance = lair, distance
		end
	end
	local lairKind = if best then lairKinds[best.kind] else nil
	return if lairKind then fromHex(lairKind.colour) else WHITE
end

-- Runs once per snapshot: pairs models with enemies and sets how they look.
local function sync(snapshot: Net.Snapshot)
	generation += 1
	table.clear(previousById)
	local previous = Net.previous
	if previous then
		for _, enemy in previous.enemies do
			previousById[enemy.id] = enemy
		end
	end

	local now = os.clock()
	local center = viewCenter()
	local range = VIEW_RANGE * VIEW_RANGE
	for _, enemy in snapshot.enemies do
		local id = enemy.id
		local rig = rigs[id] or spawnRig(id, enemy)
		rig.stamp = generation
		rig.x = enemy.x
		rig.z = enemy.z
		if center then
			local dx, dz = enemy.x - center.X, enemy.z - center.Z
			rig.distance = dx * dx + dz * dz
		else
			rig.distance = 0
		end
		rig.culled = rig.distance > range
		if not rig.culled then
			if rig.shell then
				table.insert(shellCandidates, rig)
			elseif enemy.buffed and not rig.boss then
				-- The boss's glow says more than the green rim.
				table.insert(rimCandidates, rig)
			end
		end

		setState(rig, enemy.state, now)

		local sleepColor = sleepingIn(enemy, snapshot.world.lairs or {})
		if (sleepColor ~= nil) ~= (rig.sleepColor ~= nil) then
			rig.pose = if sleepColor
				then CFrame.new(0, -SLEEP_SINK * rig.size, 0) * CFrame.Angles(0, 0, SLEEP_TILT)
				else CFrame.identity
			setAura(rig, rig.boss or sleepColor ~= nil)
			local mesh = rig.mesh
			if mesh then
				rig.meshTransparency = if sleepColor then MESH_SLEEP_TRANSPARENCY else 0
				mesh.Transparency = rig.meshTransparency
			end
		end
		rig.sleepColor = sleepColor

		local chevrons = chevronsFor(enemy.phase)
		if chevrons ~= rig.chevronCount then
			setChevrons(rig, chevrons)
		end
		local weakened = rig.weakenedUntil > now
		local asleep = sleepColor ~= nil
		if rig.mesh then
			rig.statusColor = if enemy.stunned then STUNNED_COLOR else (statusTint(enemy, weakened))
		end
		local key = colorKey(enemy, weakened, asleep)
		if rig.colorKey ~= key then
			rig.colorKey = key
			local pieces = rig.look.pieces
			for index in rig.parts do
				local piece = pieces[index]
				local color
				if piece == nil then
					color = CHEVRON_COLOR
				elseif piece.role == "glow" then
					color = piece.color
				else
					color = baseColor(rig.own[index], enemy, weakened)
				end
				rig.base[index] = if asleep then shade(color, SLEEP_DIM) else color
			end
		end
		for index, piece in rig.look.pieces do
			local material = materialOf(piece, enemy)
			-- A mesh keeps its own material: its texture is its look.
			if rig.materials[index] ~= material and rig.mesh == nil then
				rig.materials[index] = material
				rig.parts[index].Material = material
			end
		end
	end

	for id, rig in rigs do
		if rig.stamp ~= generation then
			kill(id, rig, now)
		end
	end
	assignRims()

	for id, at in departedAt do
		if now - at > DEPARTED_SECONDS then
			departedAt[id] = nil
			departed[id] = nil
		end
	end
end

-- How far between the previous and the latest snapshot the drawing is now.
function EnemyView.interpolation(): number
	local latest = Net.latest
	local previous = Net.previous
	if latest == nil or previous == nil then
		return 1
	end
	local span = latest.receivedAt - previous.receivedAt
	if span <= 1e-3 then
		return 1
	end
	return math.clamp((os.clock() - interval - previous.receivedAt) / span, 0, 1)
end

-- The shortest way from angle `from` to angle `to`, as a signed difference.
local function angleDelta(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- A flicker in FLICKER_STEPS steps, offset by the rig's phase.
local function flickerOf(rig: Rig, now: number, blend: number): number
	local wave = math.sin(now * FLICKER_SPEED + rig.phase * 7)
		* math.sin(now * FLICKER_SPEED * 0.61 + rig.phase * 13)
	return math.round((0.5 + 0.5 * wave) * FLICKER_STEPS) / FLICKER_STEPS * blend
end

-- Writes each part's colour for this frame: white in a hit flash, pulsing
-- toward white in a telegraph, flickering yellow while stunned and orange
-- while burning.
local function paint(rig: Rig, enemy: Protocol.EnemyView, now: number, pulse: number)
	local flash = rig.flashUntil > now
	local telegraph = enemy.state == "telegraph"
	local flicker = 0
	local flickerColor = FLICKER_COLOR
	if enemy.stunned then
		flicker = flickerOf(rig, now, STUN_FLICKER_BLEND)
		flickerColor = STUNNED_COLOR
	elseif enemy.burning and not enemy.slowed then
		flicker = flickerOf(rig, now, FLICKER_BLEND)
	end
	for index, part in rig.parts do
		-- A textured mesh ignores its colour.
		if index == 1 and rig.mesh then
			continue
		end
		local color = rig.base[index]
		if flash then
			color = WHITE
		elseif telegraph then
			color = color:Lerp(WHITE, TELEGRAPH_FLASH * pulse)
		elseif flicker > 0 and rig.roles[index] ~= "glow" then
			color = color:Lerp(flickerColor, flicker)
		end
		if rig.shown[index] ~= color then
			rig.shown[index] = color
			part.Color = color
		end
	end
end

-- Writes a boss's or elite's mesh Highlight for this frame: white in a hit
-- flash, a glow rising through the telegraph, the stunned or burning flicker,
-- the strongest status's colour; outlined green while buffed.
local function paintShell(rig: Rig, enemy: Protocol.EnemyView, now: number, pulse: number)
	local shell = rig.rim
	if shell == nil then
		return
	end
	local color: Color3? = nil
	local fill = 1
	local telegraphAt = rig.telegraphAt
	local status = statusTint(enemy, rig.weakenedUntil > now)
	if rig.flashUntil > now then
		color, fill = WHITE, SHELL_FLASH_FILL
	elseif telegraphAt then
		local progress = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
		local glow = progress * (1 - SHELL_TELEGRAPH_PULSE + SHELL_TELEGRAPH_PULSE * pulse)

		color, fill = SHELL_TELEGRAPH_COLOR, 1 - (1 - SHELL_TELEGRAPH_FILL) * glow
	elseif enemy.stunned then
		color = STUNNED_COLOR
		fill = SHELL_STATUS_FILL + (1 - SHELL_STATUS_FILL) * flickerOf(rig, now, STUN_FLICKER_BLEND)
	elseif enemy.burning and not enemy.slowed then
		color = BURNING_COLOR
		fill = SHELL_STATUS_FILL + (1 - SHELL_STATUS_FILL) * flickerOf(rig, now, FLICKER_BLEND)
	elseif status and status ~= BUFFED_COLOR then
		color, fill = status, SHELL_STATUS_FILL
	end
	if color and color ~= rig.shellColor then
		rig.shellColor = color
		shell.FillColor = color
	end
	if fill ~= rig.shellFill then
		rig.shellFill = fill
		shell.FillTransparency = fill
	end
	local outline = if enemy.buffed then 0 else 1
	if outline ~= rig.shellOutline then
		rig.shellOutline = outline
		shell.OutlineTransparency = outline
	end
end

-- Fades and sinks the dead, then hands their parts back to the pools.
local function dissolve(now: number, count: number): number
	for index = #dying, 1, -1 do
		local entry = dying[index]
		local rig = entry.rig
		local progress = (now - entry.at) / DISSOLVE_SECONDS
		if progress >= 1 then
			recycle(rig)
			dying[index] = dying[#dying]
			dying[#dying] = nil
		elseif rig.mesh then
			-- A mesh tips over forward at its feet as it fades.
			local fallen = rig.root
				* CFrame.Angles(-MESH_DEATH_TIP * math.sin(progress * math.pi / 2), 0, 0)
			for partIndex, part in rig.parts do
				count += 1
				moveParts[count] = part
				moveFrames[count] = fallen * entry.locals[partIndex]
				local opaque = if partIndex == 1 then rig.meshTransparency else 0
				part.Transparency = opaque + (1 - opaque) * progress
			end
		else
			local sink = 1 - COLLAPSE * progress
			local pieces = rig.look.pieces
			for partIndex, part in rig.parts do
				local placed = entry.locals[partIndex]
				count += 1
				moveParts[count] = part
				moveFrames[count] = rig.root
					* CFrame.new(placed.X, placed.Y * sink, placed.Z)
					* placed.Rotation
				local piece = pieces[partIndex]
				local opaque = if piece then piece.transparency or 0 else 0
				part.Transparency = opaque + (1 - opaque) * progress
			end
		end
	end
	return count
end

local function render(dt: number)
	local now = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(now * TELEGRAPH_HZ * 2 * math.pi)
	local count = 0

	local latest = Net.latest
	if latest then
		local alpha = EnemyView.interpolation()
		for _, enemy in latest.enemies do
			local id = enemy.id
			local rig = rigs[id]
			if rig and rig.culled then
				if not rig.parked then
					rig.parked = true
					for _, part in rig.parts do
						count += 1
						moveParts[count] = part
						moveFrames[count] = PARKED
					end
					local aura = rig.aura
					if aura then
						count += 1
						moveParts[count] = aura
						moveFrames[count] = PARKED
					end
					local ring = rig.ring
					if ring then
						count += 1
						moveParts[count] = ring
						moveFrames[count] = PARKED
					end
				end
			elseif rig then
				-- The hit-stop: the enemy stays where it was drawn; one coming
				-- back from parking is placed anew.
				if rig.holdUntil <= now or rig.parked then
					local x, z, facing = enemy.x, enemy.z, enemy.facing
					local before = previousById[id]
					if before then
						x = before.x + (x - before.x) * alpha
						z = before.z + (z - before.z) * alpha
						facing = before.facing + angleDelta(before.facing, facing) * alpha
					end
					rig.root = rootFrame(x, z, facing)
				end
				if rig.parked then
					-- Back from parking: no walk measured across the jump.
					rig.lastPosition = nil
				end
				rig.parked = false
				place(rig, now, pulse, dt)
				for index, part in rig.parts do
					count += 1
					moveParts[count] = part
					moveFrames[count] = rig.frames[index]
				end
				local aura = rig.aura
				if aura then
					count += 1
					moveParts[count] = aura
					moveFrames[count] = (rig.root + Vector3.new(0, rig.auraRise, 0))
						* CFrame.Angles(0, 0, math.pi / 2)
					-- Red and pulsing awake; faint and slow in the lair's colour asleep.
					local sleepColor = rig.sleepColor
					local glowColor = sleepColor or BOSS_AURA_COLOR
					if aura.Color ~= glowColor then
						aura.Color = glowColor
						local light = aura:FindFirstChildOfClass("PointLight")
						if light then
							light.Color = glowColor
							light.Brightness = if sleepColor
								then SLEEP_LIGHT_BRIGHTNESS
								else BOSS_LIGHT_BRIGHTNESS
						end
					end
					local hz = if sleepColor then SLEEP_GLOW_HZ else BOSS_AURA_HZ
					local low = if sleepColor then SLEEP_GLOW_MIN else BOSS_AURA_MIN
					local high = if sleepColor then SLEEP_GLOW_MAX else BOSS_AURA_MAX
					local wave = 0.5 + 0.5 * math.sin((now * hz + rig.phase) * 2 * math.pi)
					aura.Transparency = low + (high - low) * wave
				end
				local ring = rig.ring
				if ring then
					count += 1
					moveParts[count] = ring
					moveFrames[count] = ringFrame(rig)
				end
				paint(rig, enemy, now, pulse)
				if rig.shell then
					paintShell(rig, enemy, now, pulse)
				end
			end
		end
	end
	count = dissolve(now, count)

	for index = #moveParts, count + 1, -1 do
		moveParts[index] = nil
		moveFrames[index] = nil
	end
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Turns the enemy white for a moment: a hit landed on it.
function EnemyView.flash(id: number)
	local rig = rigs[id]
	if rig then
		rig.flashUntil = os.clock() + HIT_FLASH_SECONDS
	end
end

-- Holds the enemy still for `seconds`: the hit-stop of a skill.
function EnemyView.hitStop(id: number, seconds: number)
	local rig = rigs[id]
	if rig then
		rig.holdUntil = math.max(rig.holdUntil, os.clock() + seconds)
	end
end

-- The telegraph event names how long the wind-up of enemy `id` lasts.
function EnemyView.telegraph(id: number, seconds: number)
	local rig = rigs[id]
	if rig and seconds > 0 then
		rig.telegraphSeconds = seconds
	end
end

-- A status the wire carries no flag for (weakened) was put on enemy `id`.
function EnemyView.markStatus(id: number, status: Types.Status, seconds: number)
	local rig = rigs[id]
	if rig and status == "weakened" then
		rig.weakenedUntil = math.max(rig.weakenedUntil, os.clock() + seconds)
		rig.colorKey = -1
	end
end

-- Where the enemy's body is drawn now, or was drawn just before it vanished;
-- for an enemy out of range, its snapshot position on the ground.
function EnemyView.position(id: number): Vector3?
	local rig = rigs[id]
	if rig then
		return if rig.parked then groundPosition(rig) else rig.parts[1].Position
	end
	return departed[id]
end

-- How tall enemy `id` stands as drawn, for effects placed above it.
function EnemyView.height(id: number): number?
	local rig = rigs[id]
	if rig then
		return heightOf(rig.look) * rig.size
	end
	return nil
end

function EnemyView.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEnemies"
	folder.Parent = workspace

	prewarm("body", PREWARM_BODIES)
	prewarm("detail", PREWARM_DETAILS)
	prewarm("glow", PREWARM_GLOWS)
	for _ = 1, PREWARM_MODELS do
		table.insert(freeModels, Instance.new("Model"))
	end
	-- The meshes load in the background; their kinds use parts meanwhile.
	for kindId, entry in Config.enemyMeshes do
		task.spawn(loadMesh, kindId, entry)
	end

	Net.onWorld(sync)
	local latest = Net.latest
	if latest then
		sync(latest)
	end
	RunService.RenderStepped:Connect(render)
end

return EnemyView
