--!strict
-- Draws the enemies. The server owns them as data (ADR-0004); this keeps one
-- pooled model of a few anchored parts per enemy id and glides it between
-- snapshots, every part moved by one bulk move per frame. Enemies out of the
-- local character's range are parked and cost nothing per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Net = require(script.Parent.Net)

local EnemyView = {}

-- Greybox stand-in (ADR-0010): two to four plain parts per archetype, each
-- with its own silhouette and colour family so it reads from the top-down
-- camera. The rigged store pack replaces `LOOKS` and `spawnRig`; nothing else
-- here cares what an enemy looks like.
--
-- A piece's role picks its pool: `body` and `detail` pieces are solid, aim
-- targets and take the enemy's tint (level, health, status); `glow` pieces are
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

-- One small neon block per level on top of piece `on`: the first at `at`,
-- the rest stepping toward the front.
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
	campLeader = {
		pieces = {
			-- The biggest body, drawn up in the telegraph and slamming down.
			{
				role = "body",
				shape = BLOCK,
				size = Vector3.new(5, 5.6, 3.6),
				color = Color3.fromRGB(112, 22, 28),
				offset = pose(0, 3, 0.3),
				telegraphPose = pose(0, 3.4, 0.4, -0.08),
				strike = pose(0, 2.6, 0, 0.15),
			},
			{
				role = "detail",
				shape = BLOCK,
				size = Vector3.new(2.4, 1.8, 2.2),
				color = Color3.fromRGB(132, 28, 34),
				offset = pose(0, 6.7, -0.5),
				telegraphPose = pose(0, 7.2, -0.3),
				strike = pose(0, 6.1, -1),
			},
			-- The crown: a gold band on the head.
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(2.7, 0.8, 2.5),
				color = Color3.fromRGB(255, 196, 64),
				on = 2,
				offset = pose(0, 1.3, 0),
			},
			-- The ring at its feet: a translucent gold plate turning slowly,
			-- fast and wider in the telegraph.
			{
				role = "glow",
				shape = BLOCK,
				size = Vector3.new(8, 0.15, 8),
				color = Color3.fromRGB(255, 176, 48),
				offset = pose(0, 0.12, 0),
				transparency = 0.55,
				swell = 1.25,
				spin = 0.6,
				telegraphSpin = 5,
			},
		},
		chevrons = { on = 1, at = Vector3.new(0, 2.85, 1.45), scale = 1.5 },
	},
}

local CHILLED_COLOR = Color3.fromRGB(150, 210, 255)
local BURNING_COLOR = Color3.fromRGB(255, 140, 30)
local BRITTLE_COLOR = Color3.fromRGB(255, 235, 120)
local BUFFED_COLOR = Color3.fromRGB(120, 255, 130)
local FLICKER_COLOR = Color3.fromRGB(255, 220, 90)
local CHEVRON_COLOR = Color3.fromRGB(255, 236, 160)
local WHITE = Color3.new(1, 1, 1)
-- How far a status colour pulls the archetype's own colour.
local STATUS_BLEND = 0.55
local BUFFED_BLEND = 0.3
-- Colour multiplier by level (1, 2, 3 and beyond).
local LEVEL_SHADE = { 1, 0.85, 0.7 }
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
-- A burning enemy flickers toward `FLICKER_COLOR` in a few steps, so the
-- colour is rewritten only when the step changes.
local FLICKER_SPEED = 21
local FLICKER_STEPS = 3
local FLICKER_BLEND = 0.45
-- After a telegraph: a snap into the strike pose, a hold, then back to rest.
local STRIKE_SNAP = 0.08
local STRIKE_HOLD = 0.25
local SETTLE_SECONDS = 0.3
local SETTLE_END = STRIKE_SNAP + STRIKE_HOLD + SETTLE_SECONDS
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
-- Parts made at the start so the first camps do not hitch; each pool grows
-- past this on demand, never during a frame.
local PREWARM_BODIES = 40
local PREWARM_DETAILS = 60
local PREWARM_GLOWS = 80
-- Enemies farther than this from the local character, on the ground plane, are
-- not laid out or painted: their parts are parked once at `PARKED`, far below
-- the map, until they come back in range. The same range as Effects.
local VIEW_RANGE = 160
local PARKED = CFrame.new(0, -10000, 0)
-- Roblox draws at most 31 Highlights; the nearest buffed enemies in range get
-- the green rim, the rest keep only their tint.
local MAX_RIMS = 24

-- Enemies are drawn one snapshot interval behind the newest data, so there is
-- always a next position to glide to.
local interval = 1 / Config.net.snapshotHz

type Rig = {
	look: Look,
	model: Model,
	-- The look's pieces in order, then the chevrons.
	parts: { Part },
	roles: { Role },
	-- Each chevron's place on its piece.
	chevronOffsets: { CFrame },
	-- Every part's world frame this frame, in the order of `parts`.
	frames: { CFrame },
	scales: { number },
	angles: { number },
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
	level: number,
	-- How long the archetype's shortest telegraph lasts.
	telegraphSeconds: number,
	telegraphAt: number?,
	-- When the last telegraph ended, how far it got and whether an attack landed.
	endedAt: number?,
	reached: number,
	struck: boolean,
	flashUntil: number,
	-- Held still until then by a skill hit (the hit-stop).
	holdUntil: number,
	stamp: number,
	-- The green rim of a buffed enemy.
	rim: Highlight?,
	-- The latest snapshot's position.
	x: number,
	z: number,
	-- Beyond `VIEW_RANGE` at the latest snapshot, and whether its parts are parked.
	culled: boolean,
	parked: boolean,
	-- Squared distance to the local character at the latest snapshot, for the rims.
	distance: number,
}

type Dying = { rig: Rig, at: number, locals: { CFrame } }

local folder: Folder
-- The free parts of each role.
local freeBodies: { Part } = {}
local freeDetails: { Part } = {}
local freeGlows: { Part } = {}
local freeModels: { Model } = {}
local freeRims: { Highlight } = {}
local rigs: { [number]: Rig } = {}
local dying: { Dying } = {}
local shortestTelegraphs: { [string]: number } = {}
local generation = 0
-- The previous snapshot's enemies by id.
local previousById: { [number]: Protocol.EnemyView } = {}
local departed: { [number]: Vector3 } = {}
local departedAt: { [number]: number } = {}
-- Reused every frame for the bulk move.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
-- Reused every snapshot: the buffed enemies in range, and those given a rim.
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
	-- Solid pieces are queryable so the mouse aim lands on an enemy (Input).
	part.CanQuery = role ~= "glow"
	return part
end

local function give(role: Role, part: Part)
	part.Parent = nil
	table.insert(poolOf(role), part)
end

local function telegraphOf(archetype: string): number
	local known = shortestTelegraphs[archetype]
	if known then
		return known
	end
	local shortest = math.huge
	local config = Config.enemies.archetypes[archetype]
	if config then
		for _, attack in config.attacks do
			shortest = math.min(shortest, attack.telegraphSeconds)
		end
	end
	local seconds = if shortest < math.huge and shortest > 0 then shortest else 0.5
	shortestTelegraphs[archetype] = seconds
	return seconds
end

local function rootFrame(x: number, z: number, facing: number): CFrame
	-- The front is -Z; the facing is measured from +X toward +Z.
	return CFrame.new(x, Net.heightAt(x, z), z) * CFrame.Angles(0, -facing - math.pi / 2, 0)
end

-- One chevron per level (up to `MAX_CHEVRONS`), replacing any it had.
local function setChevrons(rig: Rig, level: number)
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
	local size = CHEVRON_SIZE * chevrons.scale
	local on = rig.frames[chevrons.on] or rig.root
	for step = 1, math.clamp(level, 1, MAX_CHEVRONS) do
		local part = take("glow")
		part.Shape = BLOCK
		part.Size = size
		part.Transparency = 0
		local offset =
			CFrame.new(chevrons.at - Vector3.new(0, 0, (step - 1) * CHEVRON_GAP * chevrons.scale))
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
	rig.level = level
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
	local endedAt = rig.endedAt
	local since = if endedAt then now - endedAt else math.huge
	local pieces = rig.look.pieces
	for index, piece in pieces do
		local offset = piece.offset
		local raised = piece.telegraphPose
		if telegraphAt then
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
			rig.parts[index].Size = piece.size * scale
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

		rig.frames[index] = (if on then rig.frames[on] else rig.root) * offset
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

local function spawnRig(id: number, enemy: Protocol.EnemyView): Rig
	local look = LOOKS[enemy.archetype] or GRUNT
	local model = table.remove(freeModels) or Instance.new("Model")
	model.Name = enemy.archetype
	local rig: Rig = {
		look = look,
		model = model,
		parts = {},
		roles = {},
		chevronOffsets = {},
		frames = {},
		scales = {},
		angles = {},
		base = {},
		shown = {},
		materials = {},
		root = rootFrame(enemy.x, enemy.z, enemy.facing),
		phase = (id * 0.618) % 1,
		state = enemy.state,
		colorKey = -1,
		level = enemy.level,
		telegraphSeconds = telegraphOf(enemy.archetype),
		telegraphAt = if enemy.state == "telegraph" then os.clock() else nil,
		endedAt = nil,
		reached = 0,
		struck = false,
		flashUntil = 0,
		holdUntil = 0,
		stamp = generation,
		rim = nil,
		x = enemy.x,
		z = enemy.z,
		culled = false,
		parked = false,
		distance = 0,
	}
	for index, piece in look.pieces do
		local part = take(piece.role)
		part.Shape = piece.shape
		part.Size = piece.size
		part.Transparency = piece.transparency or 0
		part.Parent = model
		rig.parts[index] = part
		rig.roles[index] = piece.role
		rig.scales[index] = 1
		rig.angles[index] = 0
		rig.materials[index] = part.Material
	end
	model.PrimaryPart = rig.parts[1]
	-- Appears where it is, not where a stale pooled part was.
	layout(rig, os.clock(), 0, 0)
	for index, part in rig.parts do
		part.CFrame = rig.frames[index]
	end
	setChevrons(rig, enemy.level)
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
		-- Adorns its parent, the enemy's model.
		fresh.Parent = rig.model
		rig.rim = fresh
	elseif not on and rim then
		rim.Parent = nil
		table.insert(freeRims, rim)
		rig.rim = nil
	end
end

local function shade(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

-- The colour of a solid piece at rest: its own, shaded by level, tinted by
-- the status the enemy carries (chilled > burning > brittle > buffed), darker
-- as its health falls.
local function baseColor(own: Color3, enemy: Protocol.EnemyView): Color3
	local color = shade(own, LEVEL_SHADE[math.min(enemy.level, #LEVEL_SHADE)] or 1)
	if enemy.chilled then
		color = color:Lerp(CHILLED_COLOR, STATUS_BLEND)
	elseif enemy.burning then
		color = color:Lerp(BURNING_COLOR, STATUS_BLEND)
	elseif enemy.brittle then
		color = color:Lerp(BRITTLE_COLOR, STATUS_BLEND)
	elseif enemy.buffed then
		color = color:Lerp(BUFFED_COLOR, BUFFED_BLEND)
	end
	local health = math.round(math.clamp(enemy.health, 0, 1) * HEALTH_STEPS) / HEALTH_STEPS
	return shade(color, HEALTH_FLOOR + (1 - HEALTH_FLOOR) * health)
end

local function colorKey(enemy: Protocol.EnemyView): number
	local flags = (if enemy.chilled then 1 else 0)
		+ (if enemy.burning then 2 else 0)
		+ (if enemy.brittle then 4 else 0)
		+ (if enemy.buffed then 8 else 0)
	local health = math.round(math.clamp(enemy.health, 0, 1) * HEALTH_STEPS)
	return enemy.level * 1024 + flags * 64 + health
end

-- The material of a solid piece: icy when chilled, cracked when brittle (the
-- tint's order), neon when it glows in the telegraph.
local function materialOf(piece: Piece, enemy: Protocol.EnemyView): Enum.Material
	if piece.role == "glow" or (piece.glowsOnTelegraph and enemy.state == "telegraph") then
		return Enum.Material.Neon
	elseif enemy.chilled then
		return Enum.Material.Ice
	elseif enemy.brittle and not enemy.burning then
		return Enum.Material.CrackedLava
	end
	return Enum.Material.SmoothPlastic
end

local function recycle(rig: Rig)
	for index, part in rig.parts do
		give(rig.roles[index], part)
	end
	rig.model.PrimaryPart = nil
	rig.model.Parent = nil
	table.insert(freeModels, rig.model)
end

-- Where a parked enemy is: its snapshot position on the ground.
local function groundPosition(rig: Rig): Vector3
	return Vector3.new(rig.x, Net.heightAt(rig.x, rig.z), rig.z)
end

local function kill(id: number, rig: Rig, now: number)
	departedAt[id] = now
	rigs[id] = nil
	setRim(rig, false)
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

-- Gives the green rim to the nearest `MAX_RIMS` buffed enemies in range and
-- takes it from every other.
local function assignRims()
	if #rimCandidates > MAX_RIMS then
		table.sort(rimCandidates, function(a: Rig, b: Rig): boolean
			return a.distance < b.distance
		end)
	end
	for index = 1, math.min(#rimCandidates, MAX_RIMS) do
		rimmed[rimCandidates[index]] = true
	end
	for _, rig in rigs do
		setRim(rig, rimmed[rig] == true)
	end
	table.clear(rimmed)
	table.clear(rimCandidates)
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
		if enemy.buffed and not rig.culled then
			table.insert(rimCandidates, rig)
		end

		local state: Types.EnemyState = enemy.state
		if state ~= rig.state then
			if state == "telegraph" then
				rig.telegraphAt = now
				rig.endedAt = nil
			elseif rig.state == "telegraph" then
				local telegraphAt = rig.telegraphAt or now
				rig.reached = math.clamp((now - telegraphAt) / rig.telegraphSeconds, 0, 1)
				rig.telegraphAt = nil
				rig.endedAt = now
				-- A telegraph followed by a recovery is an attack that landed.
				rig.struck = state == "recover"
			end
			rig.state = state
		end

		if enemy.level ~= rig.level then
			setChevrons(rig, enemy.level)
		end
		local key = colorKey(enemy)
		if rig.colorKey ~= key then
			rig.colorKey = key
			local pieces = rig.look.pieces
			for index in rig.parts do
				local piece = pieces[index]
				if piece == nil then
					rig.base[index] = CHEVRON_COLOR
				elseif piece.role == "glow" then
					rig.base[index] = piece.color
				else
					rig.base[index] = baseColor(piece.color, enemy)
				end
			end
		end
		for index, piece in rig.look.pieces do
			local material = materialOf(piece, enemy)
			if rig.materials[index] ~= material then
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

-- Writes each part's colour for this frame: white in a hit flash, pulsing
-- toward white in a telegraph, flickering while burning.
local function paint(rig: Rig, enemy: Protocol.EnemyView, now: number, pulse: number)
	local flash = rig.flashUntil > now
	local telegraph = enemy.state == "telegraph"
	local flicker = 0
	if enemy.burning and not enemy.chilled then
		local wave = math.sin(now * FLICKER_SPEED + rig.phase * 7)
			* math.sin(now * FLICKER_SPEED * 0.61 + rig.phase * 13)
		flicker = math.round((0.5 + 0.5 * wave) * FLICKER_STEPS) / FLICKER_STEPS * FLICKER_BLEND
	end
	for index, part in rig.parts do
		local color = rig.base[index]
		if flash then
			color = WHITE
		elseif telegraph then
			color = color:Lerp(WHITE, TELEGRAPH_FLASH * pulse)
		elseif flicker > 0 and rig.roles[index] ~= "glow" then
			color = color:Lerp(FLICKER_COLOR, flicker)
		end
		if rig.shown[index] ~= color then
			rig.shown[index] = color
			part.Color = color
		end
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
				rig.parked = false
				layout(rig, now, pulse, dt)
				for index, part in rig.parts do
					count += 1
					moveParts[count] = part
					moveFrames[count] = rig.frames[index]
				end
				paint(rig, enemy, now, pulse)
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

-- Where the enemy's body is drawn now, or was drawn just before it vanished;
-- for an enemy out of range, its snapshot position on the ground.
function EnemyView.position(id: number): Vector3?
	local rig = rigs[id]
	if rig then
		return if rig.parked then groundPosition(rig) else rig.parts[1].Position
	end
	return departed[id]
end

function EnemyView.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEnemies"
	folder.Parent = workspace

	prewarm("body", PREWARM_BODIES)
	prewarm("detail", PREWARM_DETAILS)
	prewarm("glow", PREWARM_GLOWS)

	Net.onWorld(sync)
	local latest = Net.latest
	if latest then
		sync(latest)
	end
	RunService.RenderStepped:Connect(render)
end

return EnemyView
