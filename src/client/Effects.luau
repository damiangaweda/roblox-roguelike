--!strict
-- Combat and world effects: skills, hits, statuses, bursts, areas, totems,
-- telegraphs, projectiles, crystals, food, the chest's beam, the extraction
-- spell and its portal. Everything here is drawn from events and snapshots
-- the server sent; nothing is decided on the client (AGENTS.md rule 1).
-- Every effect comes from a pool with a cap, particles are thrown in bursts
-- from pooled hosts and lights are capped, so the frame budget holds however
-- much fires at once. Nothing here is a gameplay number: every constant is a
-- look; durations and radii come from the events and the configuration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Camera = require(script.Parent.Camera)
local Net = require(script.Parent.Net)
local EnemyView = require(script.Parent.EnemyView)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Effects = {}

-- The palette: one tint per tag, reused by every effect of it. `color` is the
-- tag's own; `core` the near-white centre of its flashes.
type Tint = { color: Color3, core: Color3 }
local WHITE = Color3.new(1, 1, 1)

local function rgb(r: number, g: number, b: number, cr: number, cg: number, cb: number): Tint
	return { color = Color3.fromRGB(r, g, b), core = Color3.fromRGB(cr, cg, cb) }
end

local FIRE = rgb(255, 95, 30, 255, 225, 150)
local ICE = rgb(150, 215, 255, 235, 250, 255)
local LIGHTNING = rgb(255, 238, 100, 255, 255, 235)
local ARCANE = rgb(165, 85, 255, 240, 225, 255)
local PHYSICAL = rgb(205, 215, 230, 255, 255, 255)
local BLEED = rgb(200, 20, 45, 255, 170, 170)
local POISON = rgb(150, 255, 40, 225, 255, 180)
local NATURE = rgb(80, 200, 60, 210, 255, 190)
local TAG_TINTS: { [string]: Tint } = {
	fire = FIRE,
	ice = ICE,
	lightning = LIGHTNING,
	arcane = ARCANE,
	physical = PHYSICAL,
	bleed = BLEED,
	poison = POISON,
	nature = NATURE,
}
-- Damage-over-time ticks arrive as hits named by their status.
local DOT_TINTS: { [string]: Tint } = { burning = FIRE, bleeding = BLEED, poisoned = POISON }
-- A status put on an enemy flashes in its colour.
local STATUS_TINTS: { [string]: Tint } = {
	slowed = ICE,
	chilled = ICE,
	rooted = NATURE,
	stunned = LIGHTNING,
	feared = rgb(165, 90, 230, 235, 210, 255),
	weakened = rgb(140, 140, 140, 220, 220, 220),
	burning = FIRE,
	bleeding = BLEED,
	poisoned = POISON,
}
-- The enemies' own: the exploder's blast, the heal, and the gold, danger and
-- shadow of the run's big moments.
local EXPLODER = rgb(255, 70, 30, 255, 210, 160)
local HEAL = rgb(90, 255, 130, 215, 255, 225)
local GOLD = rgb(255, 200, 60, 255, 245, 200)
local DANGER = rgb(255, 40, 40, 255, 190, 170)
local SHADOW = rgb(45, 20, 55, 130, 90, 150)
local BARRIER = rgb(140, 200, 255, 225, 245, 255)
-- Plain colours: a grey block, grey smoke, pale puffs, scorched and frosted ground.
local SHIELD_COLOR = Color3.fromRGB(175, 180, 190)
local SMOKE_COLOR = Color3.fromRGB(70, 66, 62)
local PUFF_COLOR = Color3.fromRGB(220, 215, 225)
local DUST_COLOR = Color3.fromRGB(150, 130, 100)
local SCORCH_COLOR = Color3.fromRGB(60, 30, 18)
local FROST_COLOR = Color3.fromRGB(205, 235, 255)
local WOOD_COLOR = Color3.fromRGB(105, 72, 44)
local MEAT_COLOR = Color3.fromRGB(170, 70, 50)
local BONE_COLOR = Color3.fromRGB(240, 232, 214)

-- Textures that ship with the engine; no store assets.
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local EMBER_TEXTURE = "rbxasset://textures/particles/fire_sparks_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FLASH_TEXTURE = "rbxasset://textures/particles/explosion01_core_main.dds"
local IMPLOSION_TEXTURE = "rbxasset://textures/particles/explosion01_implosion_main.dds"
local GLOW_TEXTURE = "rbxasset://textures/particles/forcefield_glow_main.dds"

-- Effects farther than this from the camera are not drawn at all.
local VIEW_RANGE = 160
-- How long a skill hit holds the enemy still (the hit-stop).
local HIT_STOP_SECONDS = 0.07
-- Skills that hit everything near the hero every moment hold nothing still.
local NO_HIT_STOP: { [string]: boolean } = { aura = true, orbit = true, thorns = true }

-- Pool sizes: the most of each kind alive at once; a new one past the cap
-- reuses the oldest.
local STREAK_POOL = 160
local LIGHTNING_POOL = 160
local GLOW_POOL = 64
local RING_POOL = 40
local DISC_POOL = 32
local GROUND_POOL = 16
local SHARD_POOL = 64
local NUMBER_POOL = 60
-- Flash lights at once. With TRACKED_LIGHTS, the portal's and the bosses'
-- this keeps the PointLights near a dozen.
local LIGHT_POOL = 5
local TRACKED_LIGHTS = 4
-- Areas drawn at once; past it the oldest goes.
local AREA_CAP = 24

-- Streaks: neon bars between two points (bolts, slashes, lightning, beams).
-- They end this share of their width wide; anything shorter is not drawn.
local STREAK_THIN = 0.3
local MIN_STREAK = 0.05
-- A travelling streak's head reaches the end in this share of its life; the
-- tail follows over the whole of it.
local TRAVEL_HEAD = 0.3
-- How much a flickering streak's transparency jumps frame to frame.
local FLICKER = 0.35

-- The hero's middle stands this high when its character is not there yet;
-- its hands this far above the root and towards the target.
local HERO_RISE = 2.5
local HAND_RISE = 0.6
local HAND_REACH = 1.2

-- A bolt cast: a flash at the hand and a short streak toward each target;
-- the projectile itself is a tracked part.
local BOLT_SECONDS = 0.14
local BOLT_LEAD = 5
local BOLT_CORE_WIDTH = 0.3
local BOLT_SLEEVE_WIDTH = 0.9
local BOLT_SLEEVE_FADE = 0.45
local MUZZLE_SECONDS = 0.1
local MUZZLE_DIAMETER = 1.4
-- A strike: a bar of light falling onto the target, a flash and sparks.
local STRIKE_HEIGHT = 14
local STRIKE_SECONDS = 0.18
local STRIKE_CORE_WIDTH = 0.5
local STRIKE_SLEEVE_WIDTH = 1.6
local STRIKE_DIAMETER = 3.2
local STRIKE_SPARKS = 10
-- A melee swing: a slash across this arc in front of the hero.
local MELEE_ARC = math.rad(150)
-- A cone: travelling streaks fanned across it, ending in particles.
local CONE_STREAKS = 7
local CONE_SECONDS = 0.28
local CONE_WIDTH = 1.4
local CONE_FADE = 0.35
local CONE_REACH = 0.9
local CONE_PARTICLES = 4
-- A scatter: thin streaks to each target and a small flash there.
local SCATTER_WIDTH = 0.35
local SCATTER_SECONDS = 0.16
local SCATTER_DIAMETER = 1.6
-- An aura's pulse: a faint ring at its edge.
local AURA_SECONDS = 0.35
local AURA_STUDS = 0.35
local AURA_FADE = 0.55
local AURA_FROM = 0.85
-- An orbit's zap: a thin flickering streak to each target.
local ZAP_WIDTH = 0.25
local ZAP_SECONDS = 0.12
-- Thorns: spikes thrown out round the hero and a ring.
local THORN_SHARDS = 10
local THORN_REACH = 4
local THORN_SCALE = 0.45
local THORN_SECONDS = 0.35
local THORN_RING_DIAMETER = 8
-- A self heal: motes rising off the hero.
local HEAL_MOTES = 16
local HEAL_SECONDS = 0.7
local HEAL_RING_FROM = 2
local HEAL_RING_TO = 5
local HEAL_RING_RISE = 4

-- Hit impacts: a flash at the enemy and sparks in the skill's tint.
local IMPACT_SECONDS = 0.12
local IMPACT_DIAMETER = 1.8
local IMPACT_SPARKS = 8
local SYNERGY_IMPACT_DIAMETER = 3.6
local SYNERGY_SPARKS = 20
local BLOCK_SECONDS = 0.1
local BLOCK_DIAMETER = 1.2
local BLOCK_SPARKS = 7
local BLOCK_SHARDS = 2
local BLOCK_SHARD_SCALE = 0.35
-- How far in front of an enemy's centre its shield is.
local BLOCK_REACH = 1.5
-- A status landing: a small flash in its colour.
local STATUS_SECONDS = 0.2
local STATUS_DIAMETER = 2.4
local STATUS_FADE = 0.55

-- Synergies: a ring on the ground in the synergy's tint, plus its own extra.
local SYNERGY_RING_SECONDS = 0.35
local SYNERGY_RING_DIAMETER = 7
local SYNERGY_RING_STUDS = 0.4
local SHATTER_SHARDS = 6
local SHATTER_REACH = 4
local SHATTER_SCALE = 0.6
local SYNERGY_GLINTS = 14

-- Lightning: a jagged bolt of short segments, a core in a halo, with forks
-- off it; a light where it starts.
local LIGHTNING_SECONDS = 0.22
local LIGHTNING_STEP = 2.5
local LIGHTNING_MAX_SEGMENTS = 10
local LIGHTNING_KINK = 0.9
local LIGHTNING_CORE_WIDTH = 0.22
local LIGHTNING_HALO_WIDTH = 0.75
local LIGHTNING_HALO_FADE = 0.55
local FORK_MIN = 1
local FORK_MAX = 2
local FORK_MIN_LENGTH = 1.5
local FORK_MAX_LENGTH = 3.5
local FORK_SPREAD = 1.2
local FORK_WIDTH = 0.14
local LIGHTNING_LIGHT_BRIGHTNESS = 5
local LIGHTNING_LIGHT_RANGE = 18

-- Explosions (fire bursts, the exploder): a core flash, a wider glow, a
-- shockwave ring, flames, embers, smoke, a light and scorched ground. Sizes
-- follow the burst radius; counts are multiplied by the explosion's scale.
local EXPLOSION_RISE = 1.5
local EXPLOSION_CORE_SECONDS = 0.22
local EXPLOSION_GLOW_SECONDS = 0.38
local EXPLOSION_GLOW_FADE = 0.55
local EXPLOSION_RING_SECONDS = 0.4
local EXPLOSION_RING_STUDS = 0.7
local EXPLOSION_FLAMES = 14
local EXPLOSION_EMBERS = 26
local EXPLOSION_SMOKE = 9
local EXPLOSION_FLASHES = 3
local EXPLOSION_LIGHT_SECONDS = 0.45
local EXPLOSION_LIGHT_BRIGHTNESS = 7
local SCORCH_SECONDS = 2.6
local SCORCH_FADE = 0.15
-- The exploder's blast and a non-fire burst against a fire burst.
local EXPLODER_SCALE = 0.6
local BURST_SCALE = 0.6

-- Novas: an expanding ring, a pale sweep, particles and a light; an ice nova
-- adds spinning shards, mist and frost left on the ground.
local NOVA_RING_SECONDS = 0.35
local NOVA_RING_STUDS = 0.55
local NOVA_SWEEP_SECONDS = 0.3
local NOVA_SWEEP_FADE = 0.55
local NOVA_SHARDS = 10
local NOVA_SHARD_SECONDS = 0.45
local NOVA_MIST = 18
local NOVA_GLINTS = 16
local NOVA_SPARKS = 14
local FROST_SECONDS = 2.6
local FROST_FADE = 0.35
local NOVA_LIGHT_BRIGHTNESS = 4
local NOVA_LIGHT_SECONDS = 0.4
-- Ice shards: tall neon wedges that fly out, rise a little, tilt and spin.
local SHARD_SIZE = Vector3.new(0.5, 2.6, 1.2)
local SHARD_LIFT = 1.2
local SHARD_TILT = 1.1
local SHARD_SPIN = 4
local SHARD_FADE = 0.1

-- Kills: a puff and motes in the kind's colour and a small flash.
local KILL_MOTES = 10
local KILL_PUFFS = 5
local KILL_FLASH_DIAMETER = 3
local KILL_FLASH_SECONDS = 0.25

-- The hero hurt: red shards and a shake that grows with the hit.
local HURT_SHARDS = 5
local HURT_SHARD_SCALE = 0.35
local HURT_SHARD_SECONDS = 0.35
local HURT_SHAKE = 0.3
local HURT_SHAKE_PER_DAMAGE = 0.02
local HURT_SHAKE_MAX = 1.2
-- Damage the barrier took: a shimmer round the hero.
local ABSORB_GLINTS = 12
local ABSORB_DIAMETER = 6
-- Knocked back: dust at the feet.
local KNOCK_PUFFS = 5
-- The shaman's heal landing on an enemy; the hero healed; food eaten.
local HEALED_MOTES = 6
local HERO_HEALED_MOTES = 10
local FOOD_MOTES = 14

-- Enemy attacks landing. A melee hit is a slash: a tapered arc of streaks in
-- front of the enemy; an all-round slam, a burst or a leap is a ring.
local SLASH_SECONDS = 0.16
local SLASH_SEGMENTS = 5
local SLASH_WIDTH = 0.6
local SLASH_REACH = 0.7
local SLASH_ARC_SHARE = 0.8
local SLASH_SPARKS = 6
local SLAM_SECONDS = 0.3
local SLAM_STUDS = 0.6
local SLAM_PUFFS = 8
local MUZZLE_PUFFS = 6
local CHARGE_PUFFS = 6
local SUMMON_MOTES = 16
-- Splashes of enemy projectiles that land with a radius.
local SPLASH_SECONDS = 0.3
local SPLASH_SPARKS = 10

-- Discs: flat neon cylinders on the ground. Heights here are above the
-- ground, which Net.groundY gives.
local DISC_HEIGHT = 0.15
-- Lays a cylinder flat: its axis (X) points up.
local LIE = CFrame.Angles(0, 0, math.pi / 2)
-- Ground marks (scorch, frost) spread over this share of their life and hold
-- until this share, then fade.
local GROUND_SPREAD = 0.12
local GROUND_HOLD = 0.45
-- Rings: a thin line on a flat SurfaceGui, this many canvas pixels per stud,
-- fewer for a ring so wide its canvas would pass RING_MAX_CANVAS pixels.
local RING_THICKNESS = 0.05
local RING_PIXELS_PER_STUD = 16
local RING_MAX_CANVAS = 1024
local RING_BRIGHTNESS = 2.5
-- Studs of open middle a ring keeps at its narrowest.
local RING_MIN_HOLE = 0.5

-- Camera shake: how hard, and how near the local character a burst must be.
local SHAKE_RANGE = 30
local BURST_SHAKE = 0.6
local EXPLOSION_SHAKE = 1
local BOSS_SHAKE = 1.4

-- Telegraphs: a translucent base, a brighter fill growing from the centre
-- (or from the start of a charge's line) and a rim at the edge that
-- brightens as the attack nears.
local TELEGRAPH_BASE_COLOR = Color3.fromRGB(200, 30, 30)
local TELEGRAPH_FILL_COLOR = Color3.fromRGB(255, 70, 50)
local TELEGRAPH_RIM_COLOR = Color3.fromRGB(255, 150, 120)
local TELEGRAPH_BASE_TRANSPARENCY = 0.72
local TELEGRAPH_FILL_TRANSPARENCY = 0.4
local TELEGRAPH_RIM_STUDS = 0.3
local TELEGRAPH_RIM_FADE = 0.5
local TELEGRAPH_THICKNESS = 0.1
local TELEGRAPH_MIN_FILL = 0.1
-- Studs between a telegraph's layers: the base below, the fill above, the rim on top.
local TELEGRAPH_LAYER = 0.03
-- An attack that hits an arc narrower than a full turn: a wedge on the ground
-- drawn from triangle slices.
local SECTOR_SLICES = 6
local SECTOR_THICKNESS = 0.08
local SECTOR_MIN_RADIUS = 0.3
-- The exploder's swelling, pulsing shell.
local SWELL_FROM = 3
local SWELL_TO = 6
local SWELL_PULSE = 0.08
local SWELL_HERTZ = 7
local SWELL_FADE = 0.35
-- A shooter's orb at its mouth, from enemy centre: forward and up.
local ORB_FROM = 0.2
local ORB_TO = 1
local MOUTH_FORWARD = 1.3
local MOUTH_RISE = 0.7
-- The heal's motes and a summon's pulses rise round the enemy this often
-- while it winds up; a summon's pulses stand on a ring at least this wide.
local MOTE_SECONDS = 0.25
local WIND_UP_MOTES = 6
local HEAL_BASE_TRANSPARENCY = 0.85
local HEAL_FILL_TRANSPARENCY = 0.7
local SUMMON_POINTS = 6
local SUMMON_MIN_RADIUS = 4
local SUMMON_PULSE_DIAMETER = 1.6
local SUMMON_TINT = rgb(150, 70, 220, 230, 200, 255)

local NUMBER_SECONDS = 0.8
local NUMBER_RISE = 5
local NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
local CRIT_COLOR = Color3.fromRGB(255, 225, 50)
local BLOCKED_COLOR = Color3.fromRGB(160, 160, 160)
local SYNERGY_COLOR = Color3.fromRGB(255, 150, 40)
local NUMBER_TEXT_SIZE = 22
local DOT_TEXT_SIZE = 16
local CRIT_TEXT_SIZE = 32
local SYNERGY_TEXT_SIZE = 36
-- The pop: a number starts at NUMBER_POP_FROM of its size, overshoots to
-- NUMBER_POP_PEAK, then settles, each over this share of its life.
local NUMBER_POP_SHARE = 0.12
local NUMBER_POP_FROM = 0.5
local NUMBER_POP_PEAK = 1.35

-- Areas on the ground: a disc pulsing with each tick and a rim; a player's
-- in its tag's colour with particles falling from above (ice, fire) or
-- glinting, an enemy's a dark pool in the kind's colour, bubbling.
local AREA_HEIGHT = 0.12
local AREA_TRANSPARENCY = 0.72
local AREA_PULSE = 0.3
local AREA_POOL_TRANSPARENCY = 0.25
local AREA_POOL_DARKEN = 0.45
local AREA_RIM_STUDS = 0.35
local AREA_RIM_FADE = 0.35
local AREA_FADE_IN = 0.15
local AREA_FADE_OUT = 0.3
-- Particles per second per square stud of area, and how high the falling start.
local AREA_PARTICLE_DENSITY = 0.05
local AREA_FALL_HEIGHT = 10
-- An area the snapshot no longer shows is let go after this long.
local AREA_GRACE = 0.5

-- Totems: a wooden pole with a glowing bird on top, idling.
local TOTEM_POLE = Vector3.new(4, 0.6, 0.6)
local TOTEM_BODY = Vector3.new(0.9, 0.8, 1.6)
local TOTEM_WING = Vector3.new(1.6, 0.15, 0.8)
local TOTEM_BIRD_RISE = 4.4
local TOTEM_GLOW_HZ = 1.2
local TOTEM_GLOW_MIN = 0
local TOTEM_GLOW_MAX = 0.35
local TOTEM_FLAP_HZ = 1.5
local TOTEM_FLAP = 0.5
local TOTEM_TURN = 0.8

-- Crystals: small floating neon gems, spinning and bobbing; collected ones
-- fly to the hero, then sparkle.
local GEM_SIZE = Vector3.new(0.7, 0.7, 0.7)
local GEM_BIG = 1.3
local GEM_RISE = 1.1
local GEM_BOB = 0.25
local GEM_BOB_HZ = 0.7
local GEM_SPIN = 2.2
-- Colours by the crystal's experience: up to SMALL_XP, up to MEDIUM_XP, more.
local SMALL_XP = 4
local MEDIUM_XP = 12
local GEM_SMALL = Color3.fromRGB(80, 160, 255)
local GEM_MEDIUM = Color3.fromRGB(80, 235, 110)
local GEM_LARGE = Color3.fromRGB(190, 90, 255)
local GEM_FLY_SECONDS = 0.25
local GEM_SPARKLE = 6
-- Where a crystal let go was, remembered this long for its collection.
local GEM_MEMORY = 1
local PREWARM_GEMS = 120

-- Food: a meat leg on the ground, glowing softly.
local MEAT_SIZE = Vector3.new(1.4, 1.2, 1.2)
local BONE_SIZE = Vector3.new(1.4, 0.35, 0.35)
local MEAT_RISE = 0.6

-- The chest, once the compass points at it: a soft beam of light above it.
local BEAM_HEIGHT = 60
local BEAM_WIDTH = 3
local BEAM_TRANSPARENCY = 0.7
local BEAM_PULSE = 0.12
local BEAM_HZ = 0.5
local CHEST_SPARKS = 40
local CHEST_EMBERS = 24

-- The barrier: a translucent sphere round the hero while it holds.
local SHIELD_DIAMETER = 7
local SHIELD_TRANSPARENCY = 0.35
-- Sprinting: speed lines behind the hero this often.
local SPRINT_LINE_SECONDS = 0.07
local SPRINT_LINES = 2
local SPRINT_LINE_LENGTH = 4
local SPRINT_LINE_WIDTH = 0.15
local SPRINT_LINE_SECONDS_LIVE = 0.22
local SPRINT_MIN_SPEED = 2

-- The extraction spell's cast: a ring under the hero and motes swirling round it.
local CAST_RING_DIAMETER = 7
local CAST_RING_STUDS = 0.35
local CAST_MOTES = 6
local CAST_MOTE_SIZE = 0.45
local CAST_SWIRL = 3
local CAST_SHARDS = 10

-- The portal: a tall ring of glowing segments standing tilted toward the
-- camera, spinning, round a shimmering face, with a light and motes; it
-- grows in and shrinks before it closes.
local PORTAL_SEGMENTS = 16
local PORTAL_SEGMENT = Vector3.new(0.7, 0.7, 1.6)
local PORTAL_TILT = math.rad(30)
local PORTAL_SPIN = 1.4
local PORTAL_GROW = 0.5
local PORTAL_SHRINK = 1.5
local PORTAL_FACE_TRANSPARENCY = 0.45
local PORTAL_LIGHT_BRIGHTNESS = 3
local PORTAL_MOTE_RATE = 30
local PORTAL_TINT = rgb(120, 90, 255, 220, 210, 255)

-- Extraction: the hero fades out over this long under a column of light.
local EXTRACT_SECONDS = 1.2
local COLUMN_HEIGHT = 50
local COLUMN_WIDTH = 5
local COLUMN_CORE_WIDTH = 1.6
local COLUMN_SECONDS = 1.4
local COLUMN_FADE = 0.2
local COLUMN_MOTES = 30
-- A boss arriving: a column of light on it and a shockwave on the ground.
local BOSS_COLUMN_HEIGHT = 80
local BOSS_COLUMN_WIDTH = 7
local BOSS_WAVE_DIAMETER = 50
local BOSS_WAVE_SECONDS = 0.8
local BOSS_WAVE_STUDS = 1.2
-- How long a boss announced before its snapshot is waited for.
local BOSS_WAIT = 2
-- A boss's second phase: a red flash as big as the boss and a shockwave.
local PHASE_FLASH_SHARE = 1.6
local PHASE_SECONDS = 0.5
-- The closing ring: a brief ring of light where it spawns.
local CLOSING_SECONDS = 1.2
local CLOSING_STUDS = 0.9
local CLOSING_FROM = 0.92
-- Death: a dark burst.
local DEATH_SMOKE = 16
local DEATH_DIAMETER = 6
local DEATH_SECONDS = 0.6
-- Level up: a golden ring rising round the hero.
local LEVEL_SECONDS = 0.8
local LEVEL_MOTES = 18

-- Particle presets. Each is thrown in bursts (`Emit`) from a pooled host, or
-- streams at a rate from a tracked part (a projectile, an area, a totem).
type Preset = {
	texture: string,
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: NumberRange,
	speed: NumberRange,
	-- Degrees round the emission direction (up); 180 is every way.
	spread: Vector2,
	acceleration: Vector3,
	drag: number,
	rotSpeed: NumberRange,
	lightEmission: number,
	-- How far towards white the colour starts; it ends as the tint.
	whiten: number,
	-- Moves with the part that gives it off instead of staying in the air.
	locked: boolean,
}

local function curve(values: { number }): NumberSequence
	local keypoints = {}
	for index, value in values do
		keypoints[index] = NumberSequenceKeypoint.new((index - 1) / (#values - 1), value)
	end
	return NumberSequence.new(keypoints)
end

local EVERY_WAY = Vector2.new(180, 180)
local NO_SPIN = NumberRange.new(0)
local PRESETS: { [string]: Preset } = {
	-- Hit sparks: quick, bright, thrown every way and falling.
	sparks = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.6, 0.1 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.2, 0.45),
		speed = NumberRange.new(14, 28),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, -40, 0),
		drag = 4,
		rotSpeed = NO_SPIN,
		lightEmission = 1,
		whiten = 0.5,
		locked = false,
	},
	-- Embers: slower sparks that drift up after an explosion.
	embers = {
		texture = EMBER_TEXTURE,
		size = curve({ 0.7, 0.2 }),
		transparency = curve({ 0, 0.2, 1 }),
		lifetime = NumberRange.new(0.6, 1.2),
		speed = NumberRange.new(10, 24),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, 4, 0),
		drag = 3,
		rotSpeed = NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Blaze: the big, short flames of an explosion.
	blaze = {
		texture = FIRE_TEXTURE,
		size = curve({ 3, 6, 4 }),
		transparency = curve({ 0.1, 0.4, 1 }),
		lifetime = NumberRange.new(0.3, 0.55),
		speed = NumberRange.new(6, 14),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, 10, 0),
		drag = 6,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
	-- Flash: the white-hot heart of an explosion.
	flash = {
		texture = FLASH_TEXTURE,
		size = curve({ 4, 9 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.15, 0.25),
		speed = NumberRange.new(0),
		spread = EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = NumberRange.new(-60, 60),
		lightEmission = 1,
		whiten = 0.6,
		locked = false,
	},
	-- Smoke: slow grey puffs that rise and spread.
	smoke = {
		texture = SMOKE_TEXTURE,
		size = curve({ 2.5, 6 }),
		transparency = curve({ 0.45, 0.7, 1 }),
		lifetime = NumberRange.new(1.4, 2.2),
		speed = NumberRange.new(2, 6),
		spread = Vector2.new(60, 60),
		acceleration = Vector3.new(0, 2, 0),
		drag = 2,
		rotSpeed = NumberRange.new(-30, 30),
		lightEmission = 0,
		whiten = 0,
		locked = false,
	},
	-- Puff: a soft, pale burst (deaths, slams, shots).
	puff = {
		texture = SMOKE_TEXTURE,
		size = curve({ 1.5, 4 }),
		transparency = curve({ 0.5, 1 }),
		lifetime = NumberRange.new(0.5, 0.8),
		speed = NumberRange.new(3, 6),
		spread = EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 3,
		rotSpeed = NumberRange.new(-40, 40),
		lightEmission = 0.3,
		whiten = 0.6,
		locked = false,
	},
	-- Motes: sparkles that rise and fade (deaths, heals).
	motes = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.2, 0.8, 0.1 }),
		transparency = curve({ 0, 0.2, 1 }),
		lifetime = NumberRange.new(0.7, 1.3),
		speed = NumberRange.new(3, 7),
		spread = Vector2.new(35, 35),
		acceleration = Vector3.new(0, 5, 0),
		drag = 2,
		rotSpeed = NumberRange.new(-120, 120),
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Mist: low, wide, slow puffs on the ground (ice novas).
	mist = {
		texture = SMOKE_TEXTURE,
		size = curve({ 3, 7 }),
		transparency = curve({ 0.55, 0.75, 1 }),
		lifetime = NumberRange.new(1.2, 2),
		speed = NumberRange.new(1, 3),
		spread = Vector2.new(80, 80),
		acceleration = Vector3.new(0, 0.5, 0),
		drag = 1,
		rotSpeed = NumberRange.new(-20, 20),
		lightEmission = 0.3,
		whiten = 0.5,
		locked = false,
	},
	-- Shimmer: sparkles that hang in the air (frost glints, synergies, the barrier).
	shimmer = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.15, 0.7, 0 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(1, 4),
		spread = EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 2,
		rotSpeed = NumberRange.new(-180, 180),
		lightEmission = 1,
		whiten = 0.5,
		locked = false,
	},
	-- Implosion: a ring of light pulled in (a closing portal, a cast).
	implosion = {
		texture = IMPLOSION_TEXTURE,
		size = curve({ 5, 1 }),
		transparency = curve({ 0.3, 1 }),
		lifetime = NumberRange.new(0.2, 0.25),
		speed = NumberRange.new(0),
		spread = EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Streams from tracked parts. Flame: a fire bolt's burning core.
	flame = {
		texture = FIRE_TEXTURE,
		size = curve({ 1.8, 0.4 }),
		transparency = curve({ 0.1, 1 }),
		lifetime = NumberRange.new(0.2, 0.35),
		speed = NumberRange.new(0.5, 2),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, 3, 0),
		drag = 0,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
	-- Trail smoke: what a fire bolt leaves in the air behind it.
	trailSmoke = {
		texture = SMOKE_TEXTURE,
		size = curve({ 0.8, 2.6 }),
		transparency = curve({ 0.5, 1 }),
		lifetime = NumberRange.new(0.6, 1),
		speed = NumberRange.new(0.2, 1),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, 2, 0),
		drag = 0,
		rotSpeed = NumberRange.new(-30, 30),
		lightEmission = 0,
		whiten = 0,
		locked = false,
	},
	-- Drips: small sparks falling off an enemy projectile.
	drips = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.45, 0 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.25, 0.4),
		speed = NumberRange.new(0.5, 2),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, -8, 0),
		drag = 0,
		rotSpeed = NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Halo: a soft glow that stays on a totem, the chest's beam or food.
	halo = {
		texture = GLOW_TEXTURE,
		size = curve({ 2.2, 2.8 }),
		transparency = curve({ 1, 0.55, 1 }),
		lifetime = NumberRange.new(0.9, 1.1),
		speed = NumberRange.new(0),
		spread = Vector2.zero,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = NO_SPIN,
		lightEmission = 1,
		whiten = 0,
		locked = true,
	},
	-- Flakes: snow falling through an ice area.
	flakes = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.3, 0.5, 0.2 }),
		transparency = curve({ 1, 0.1, 0.3, 1 }),
		lifetime = NumberRange.new(1.2, 1.6),
		speed = NumberRange.new(0.5, 1.5),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, -6, 0),
		drag = 0.5,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 0.6,
		whiten = 0.6,
		locked = false,
	},
	-- Cinders: burning sparks raining into a fire area.
	cinders = {
		texture = EMBER_TEXTURE,
		size = curve({ 0.6, 0.3 }),
		transparency = curve({ 1, 0, 0.5, 1 }),
		lifetime = NumberRange.new(0.7, 1),
		speed = NumberRange.new(2, 5),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, -16, 0),
		drag = 0.5,
		rotSpeed = NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Bubbles: small, slow globs rising off an enemy's pool and popping.
	bubbles = {
		texture = GLOW_TEXTURE,
		size = curve({ 0.3, 0.8, 0.1 }),
		transparency = curve({ 0.3, 0.2, 1 }),
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(0.5, 1.5),
		spread = Vector2.new(20, 20),
		acceleration = Vector3.new(0, 1, 0),
		drag = 1,
		rotSpeed = NO_SPIN,
		lightEmission = 0.4,
		whiten = 0.2,
		locked = false,
	},
	-- Swirl: motes circling up the portal's face.
	swirl = {
		texture = SPARK_TEXTURE,
		size = curve({ 0.3, 0.7, 0 }),
		transparency = curve({ 0, 0.3, 1 }),
		lifetime = NumberRange.new(0.8, 1.4),
		speed = NumberRange.new(1, 3),
		spread = EVERY_WAY,
		acceleration = Vector3.new(0, 3, 0),
		drag = 1,
		rotSpeed = NumberRange.new(-180, 180),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
}
-- A burst host's size when it throws from a point.
local EMIT_POINT = Vector3.new(0.2, 0.2, 0.2)

-- Projectiles: one pooled part per id, styled by what fired it.
type Stream = { preset: string, color: Color3, rate: number }
type Style = {
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	transparency: number,
	-- The trail's and the light's colour.
	glow: Color3,
	-- Height of the centre above the ground.
	height: number,
	-- Whether it carries a light, and how far it reaches.
	lightRange: number?,
	-- A trail behind it this many studs wide; 0 for none.
	trail: number,
	-- Particles it gives off while it is live.
	streams: { Stream },
}
local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local CYLINDER = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local PROJECTILE_HEIGHT = 2.5
local TRAIL_SECONDS = 0.18
local TRAIL_TRANSPARENCY = 0.15
local TRACKED_LIGHT_BRIGHTNESS = 2
-- An arrow: a thin bar along its flight; an orb: a ball, bigger with a splash.
local ARROW_SIZE = Vector3.new(0.3, 0.3, 2.4)
local ORB_DIAMETER = 1
local ORB_SPLASH_DIAMETER = 1.6
-- A toughest-first bolt (the big single shot) is drawn this much bigger.
local TOUGHEST_SHARE = 1.5
local ENEMY_SHOT_DIAMETER = 1.1
-- Tags whose bolts are arrows rather than orbs.
local ARROW_TAGS: { [string]: boolean } = { physical = true, poison = true, bleed = true }

local function fromHex(value: number): Color3
	return Color3.fromRGB(bit32.rshift(value, 16) % 256, bit32.rshift(value, 8) % 256, value % 256)
end

local function tintFrom(color: Color3): Tint
	return { color = color, core = color:Lerp(WHITE, 0.6) }
end

-- A skill's tint is its first tag's; a hit named by a status (a dot) takes
-- the status's; anything else is arcane.
local SKILL_TINTS: { [string]: Tint } = {}
for id, skill in Config.skills do
	local tag = skill.tags[1]
	SKILL_TINTS[id] = if tag then TAG_TINTS[tag] or ARCANE else ARCANE
end

local function tintOf(skill: string?): Tint
	if skill == nil then
		return ARCANE
	end
	return SKILL_TINTS[skill] or DOT_TINTS[skill] or ARCANE
end

-- An enemy kind's tint, from its colour.
local KIND_TINTS: { [string]: Tint } = {}
for id, kind in Config.enemies do
	KIND_TINTS[id] = tintFrom(fromHex(kind.colour))
end

local function kindTint(kind: string?): Tint
	return if kind then KIND_TINTS[kind] or EXPLODER else EXPLODER
end

local function boltStyle(skill: Types.SkillConfig): Style
	local tag = skill.tags[1] or "arcane"
	local tint = TAG_TINTS[tag] or ARCANE
	local grow = if skill.toughest then TOUGHEST_SHARE else 1
	if ARROW_TAGS[tag] then
		return {
			shape = BLOCK,
			size = ARROW_SIZE * grow,
			color = tint.core,
			material = NEON,
			transparency = 0,
			glow = tint.color,
			height = PROJECTILE_HEIGHT,
			trail = 0.3 * grow,
			streams = if tag == "physical"
				then {}
				else { { preset = "drips", color = tint.color, rate = 14 } },
		}
	end
	local diameter = (if skill.radius > 0 then ORB_SPLASH_DIAMETER else ORB_DIAMETER) * grow
	local streams: { Stream } = {}
	if tag == "fire" then
		streams = {
			{ preset = "flame", color = tint.color, rate = 45 },
			{ preset = "trailSmoke", color = SMOKE_COLOR, rate = 18 },
		}
	elseif tag == "ice" or tag == "arcane" then
		streams = { { preset = "shimmer", color = tint.color, rate = 20 } }
	else
		streams = { { preset = "drips", color = tint.color, rate = 14 } }
	end
	return {
		shape = BALL,
		size = Vector3.one * diameter,
		color = tint.core,
		material = NEON,
		transparency = 0,
		glow = tint.color,
		height = PROJECTILE_HEIGHT,
		lightRange = if tag == "fire" then 16 else nil,
		trail = diameter * 0.7,
		streams = streams,
	}
end

local function shotStyle(kind: string): Style
	local tint = kindTint(kind)
	return {
		shape = BALL,
		size = Vector3.one * ENEMY_SHOT_DIAMETER,
		color = tint.color,
		material = NEON,
		transparency = 0,
		glow = tint.color,
		height = PROJECTILE_HEIGHT,
		trail = 0.7,
		streams = { { preset = "drips", color = tint.color, rate = 16 } },
	}
end

local STYLES: { [string]: Style } = {}
for id, skill in Config.skills do
	if skill.speed > 0 then
		STYLES[id] = boltStyle(skill)
	end
end
for id in Config.enemies do
	STYLES[id] = shotStyle(id)
end
local DEFAULT_PROJECTILE: Style = shotStyle("")

-- Synergies by id: their name and the tint they flash in (shatter's is ice,
-- the status it breaks; the rest their tag's).
local SYNERGY_NAMES: { [string]: string } = {}
local SYNERGY_TINTS: { [string]: Tint } = {}
local SYNERGY_CONFIGS: { [string]: Types.SynergyConfig } = {}
for _, class in Config.classes do
	for _, synergy in class.synergies do
		SYNERGY_NAMES[synergy.id] = synergy.name
		SYNERGY_CONFIGS[synergy.id] = synergy
		SYNERGY_TINTS[synergy.id] = if synergy.status == "chilled"
			then ICE
			else TAG_TINTS[synergy.tag] or ARCANE
	end
end

-- Utilities by id.
local UTILITIES: { [string]: Types.UtilityConfig } = {}
for _, utility in Config.utilities do
	UTILITIES[utility.id] = utility
end
local random = Random.new()
local UP = Vector3.yAxis

local function easeOut(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

local folder: Folder

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = NEON
end

local function newEffectPart(): Part
	local part = Instance.new("Part")
	quiet(part)
	return part
end

local function newWedge(): WedgePart
	local wedge = Instance.new("WedgePart")
	quiet(wedge)
	return wedge
end

-- Rings: a part with no look of its own and a round line on its top face.
type Ring = { part: Part, gui: SurfaceGui, frame: Frame, stroke: UIStroke }

local function newRing(): Ring
	local part = newEffectPart()
	part.Transparency = 1
	part.Size = Vector3.new(1, RING_THICKNESS, 1)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = RING_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Brightness = RING_BRIGHTNESS
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Parent = frame
	return { part = part, gui = gui, frame = frame, stroke = stroke }
end

-- Sets a ring's line: `studs` thick, in `color`, kept inside the canvas of a
-- ring up to `diameter` studs wide.
local function setRingLine(ring: Ring, studs: number, color: Color3, diameter: number)
	local density = math.min(RING_PIXELS_PER_STUD, RING_MAX_CANVAS / math.max(diameter, 1))
	ring.gui.PixelsPerStud = density
	local pixels = math.max(1, studs * density)
	ring.stroke.Thickness = pixels
	ring.stroke.Color = color
	ring.frame.Size = UDim2.new(1, -2 * pixels, 1, -2 * pixels)
end

-- An effect that lives for a moment. A pool is a ring of slots: a new effect
-- takes the next slot, so when all are alive the oldest is reused.
type Built = {
	part: BasePart,
	label: TextLabel?,
	scale: UIScale?,
	ring: Ring?,
	light: PointLight?,
}

type Slot = {
	part: BasePart,
	label: TextLabel?,
	scale: UIScale?,
	ring: Ring?,
	light: PointLight?,
	active: boolean,
	startedAt: number,
	endsAt: number,
	-- A streak's start; the centre of anything else.
	origin: Vector3,
	-- A streak's end; a shard's direction.
	target: Vector3,
	-- Where a ring lies.
	frame: CFrame,
	-- The size at the start and at the end: a diameter, a width, a radius or
	-- a brightness, by pool.
	from: number,
	to: number,
	-- Transparency at the start.
	fade: number,
	-- Studs a ring rises over its life; radians a shard spins.
	drift: number,
	-- How a streak moves: "fade", "travel" or "flicker".
	mode: string,
}

type Pool = {
	size: number,
	cursor: number,
	-- Slots alive now; a pool with none is skipped.
	live: number,
	slots: { Slot },
	build: () -> Built,
	animate: (slot: Slot, alpha: number) -> (),
}

local pools: { Pool } = {}

local function newPool(size: number, build: () -> Built, animate: (Slot, number) -> ()): Pool
	local pool: Pool = {
		size = size,
		cursor = 0,
		live = 0,
		slots = {},
		build = build,
		animate = animate,
	}
	table.insert(pools, pool)
	return pool
end

-- Takes the next slot, parented and live for `seconds`.
local function start(pool: Pool, seconds: number, origin: Vector3): Slot
	pool.cursor = pool.cursor % pool.size + 1
	local slot = pool.slots[pool.cursor]
	if slot == nil then
		local built = pool.build()
		slot = {
			part = built.part,
			label = built.label,
			scale = built.scale,
			ring = built.ring,
			light = built.light,
			active = false,
			startedAt = 0,
			endsAt = 0,
			origin = origin,
			target = origin,
			frame = CFrame.identity,
			from = 0,
			to = 0,
			fade = 0,
			drift = 0,
			mode = "fade",
		}
		pool.slots[pool.cursor] = slot
	end
	if not slot.active then
		pool.live += 1
	end
	local now = os.clock()
	slot.active = true
	slot.startedAt = now
	slot.endsAt = now + seconds
	slot.origin = origin
	slot.target = origin
	slot.frame = CFrame.new(origin)
	slot.from = 0
	slot.to = 0
	slot.fade = 0
	slot.drift = 0
	slot.mode = "fade"
	slot.part.Parent = folder
	return slot
end

local function step()
	local now = os.clock()
	for _, pool in pools do
		if pool.live == 0 then
			continue
		end
		for _, slot in pool.slots do
			if slot.active then
				local alpha = (now - slot.startedAt) / (slot.endsAt - slot.startedAt)
				if alpha >= 1 then
					slot.active = false
					slot.part.Parent = nil
					pool.live -= 1
				else
					pool.animate(slot, alpha)
				end
			end
		end
	end
end

local function buildBlock(): Built
	return { part = newEffectPart() }
end

-- Streaks: a bar from origin to target that thins and fades. A travelling one
-- shoots its head to the target, then pulls its tail after it; a flickering
-- one jumps in brightness.
local function animateStreak(slot: Slot, alpha: number)
	local part = slot.part
	local width = slot.from + (slot.to - slot.from) * alpha
	local head, tail = slot.target, slot.origin
	if slot.mode == "travel" then
		head = slot.origin:Lerp(slot.target, math.min(1, alpha / TRAVEL_HEAD))
		tail = slot.origin:Lerp(slot.target, alpha * alpha)
	end
	local length = (head - tail).Magnitude
	if length < MIN_STREAK then
		part.Transparency = 1
		return
	end
	part.Size = Vector3.new(width, width, length)
	if slot.mode == "travel" then
		part.CFrame = CFrame.lookAt((tail + head) / 2, head)
	end
	local transparency = slot.fade + (1 - slot.fade) * alpha
	if slot.mode == "flicker" then
		transparency += random:NextNumber(0, FLICKER)
	end
	part.Transparency = math.min(transparency, 1)
end

local streaks = newPool(STREAK_POOL, buildBlock, animateStreak)
local lightning = newPool(LIGHTNING_POOL, buildBlock, animateStreak)

-- Glows: neon balls that swell and fade (flashes).
local glows = newPool(GLOW_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Ball
	return { part = part }
end, function(slot, alpha)
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	slot.part.Size = Vector3.new(diameter, diameter, diameter)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Rings: a thin line on the ground that widens, fades and may rise.
local rings = newPool(RING_POOL, function()
	local ring = newRing()
	return { part = ring.part, ring = ring }
end, function(slot, alpha)
	local ring = slot.ring
	if ring == nil then
		return
	end
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	ring.part.Size = Vector3.new(diameter, RING_THICKNESS, diameter)
	if slot.drift ~= 0 then
		ring.part.CFrame = slot.frame + UP * (slot.drift * easeOut(alpha))
	end
	ring.stroke.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Discs lie flat, so the cylinder's axis (X) points up. They widen and fade.
local discs = newPool(DISC_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	return { part = part }
end, function(slot, alpha)
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	slot.part.Size = Vector3.new(0.2, diameter, diameter)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Ground marks (scorch, frost): a disc that spreads in the first part of its
-- life, holds, then fades.
local grounds = newPool(GROUND_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	return { part = part }
end, function(slot, alpha)
	if alpha < GROUND_SPREAD then
		local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha / GROUND_SPREAD)
		slot.part.Size = Vector3.new(0.1, diameter, diameter)
	end
	local fading = math.max(0, (alpha - GROUND_HOLD) / (1 - GROUND_HOLD))
	slot.part.Transparency = slot.fade + (1 - slot.fade) * fading
end)

-- Shards: wedges that fly out from the centre along `target`, lift, tilt and spin.
local shards = newPool(SHARD_POOL, function()
	return { part = newWedge() }
end, function(slot, alpha)
	local radius = slot.from + (slot.to - slot.from) * easeOut(alpha)
	local direction = slot.target
	local position = slot.origin
		+ direction * radius
		+ UP * (SHARD_LIFT * math.sin(alpha * math.pi))
	slot.part.CFrame = CFrame.lookAt(position, position + direction)
		* CFrame.Angles(-SHARD_TILT * alpha, 0, slot.drift * alpha)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha * alpha
end)

-- Lights: a capped few PointLights that flash and die out.
local lights = newPool(LIGHT_POOL, function()
	local part = newEffectPart()
	part.Transparency = 1
	part.Size = EMIT_POINT
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Parent = part
	return { part = part, light = light }
end, function(slot, alpha)
	local light = slot.light
	if light then
		light.Brightness = slot.from * (1 - alpha) * (1 - alpha)
	end
end)

-- The pop of a damage number: up past its size, then back.
local function pop(alpha: number): number
	if alpha < NUMBER_POP_SHARE then
		return NUMBER_POP_FROM + (NUMBER_POP_PEAK - NUMBER_POP_FROM) * alpha / NUMBER_POP_SHARE
	end
	local settle = math.min(1, (alpha - NUMBER_POP_SHARE) / NUMBER_POP_SHARE)
	return NUMBER_POP_PEAK + (1 - NUMBER_POP_PEAK) * settle
end

-- Damage numbers: text on a billboard that pops, rises and fades.
local numbers = newPool(NUMBER_POOL, function()
	local part = newEffectPart()
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 70)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return { part = part, label = label, scale = scale }
end, function(slot, alpha)
	slot.part.Position = slot.origin + UP * (NUMBER_RISE * easeOut(alpha))
	local label = slot.label
	if label then
		label.TextTransparency = alpha * alpha
		label.TextStrokeTransparency = 0.4 + 0.6 * alpha * alpha
	end
	local scale = slot.scale
	if scale then
		scale.Scale = pop(alpha)
	end
end)

-- Particle bursts: one hidden host part per preset and colour, moved to where
-- the burst is and told to `Emit`. The particles stay where they were thrown.
type Burst = { host: Part, emitter: ParticleEmitter }
local bursts: { [string]: Burst } = {}

local function configureEmitter(emitter: ParticleEmitter, preset: Preset, color: Color3)
	emitter.Texture = preset.texture
	emitter.Color = ColorSequence.new(color:Lerp(WHITE, preset.whiten), color)
	emitter.Size = preset.size
	emitter.Transparency = preset.transparency
	emitter.Lifetime = preset.lifetime
	emitter.Speed = preset.speed
	emitter.SpreadAngle = preset.spread
	emitter.Acceleration = preset.acceleration
	emitter.Drag = preset.drag
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = preset.rotSpeed
	emitter.LightEmission = preset.lightEmission
	emitter.LightInfluence = 0
	emitter.LockedToPart = preset.locked
	emitter.EmissionDirection = Enum.NormalId.Top
end

local function burstFor(name: string, color: Color3): Burst
	local key = name .. color:ToHex()
	local existing = bursts[key]
	if existing then
		return existing
	end
	local host = newEffectPart()
	host.Name = "Burst_" .. key
	host.Transparency = 1
	host.Size = EMIT_POINT
	host.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	configureEmitter(emitter, PRESETS[name], color)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = host
	local made = { host = host, emitter = emitter }
	bursts[key] = made
	return made
end

-- Throws `count` particles of preset `name` from `at`, spread through a box
-- `area` wide (a point when nil).
local function emit(name: string, color: Color3, at: Vector3, count: number, area: Vector3?)
	if count < 1 then
		return
	end
	local burst = burstFor(name, color)
	burst.host.Size = area or EMIT_POINT
	burst.host.CFrame = CFrame.new(at)
	burst.emitter:Emit(math.round(count))
end

local function characterRoot(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Whether a point is near enough the camera to be worth drawing.
local function onScreen(at: Vector3): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return true
	end
	return (camera.CFrame.Position - at).Magnitude <= VIEW_RANGE
end

-- Where the hero's middle is: its character's root, or (x, z) before it has one.
local function heroAt(userId: number, x: number, z: number): Vector3
	local root = characterRoot(userId)
	if root then
		return root.Position
	end
	return Vector3.new(x, Net.groundY() + HERO_RISE, z)
end

-- Where a hand of a hero standing at `at` is, reaching towards `toward`.
local function handOf(at: Vector3, toward: Vector3?): Vector3
	local position = at + UP * HAND_RISE
	if toward then
		local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
		if flat.Magnitude > 1e-3 then
			position += flat.Unit * HAND_REACH
		end
	end
	return position
end

local function groundAt(x: number, z: number, rise: number): Vector3
	return Vector3.new(x, Net.groundY() + rise, z)
end

-- The flat ground at (x, z), lifted `rise`.
local function groundFrame(x: number, z: number, rise: number): CFrame
	return CFrame.new(x, Net.groundY() + rise, z)
end

-- The local player's character root, if it has one.
local function localRoot(): BasePart?
	return characterRoot(Players.LocalPlayer.UserId)
end

-- Whether a point on the ground is close to the local character.
local function nearLocal(x: number, z: number): boolean
	local root = localRoot()
	if root == nil then
		return false
	end
	local position = root.Position
	local dx, dz = position.X - x, position.Z - z
	return dx * dx + dz * dz <= SHAKE_RANGE * SHAKE_RANGE
end

local function showStreak(
	pool: Pool,
	from: Vector3,
	to: Vector3,
	color: Color3,
	width: number,
	fade: number,
	seconds: number,
	mode: string
)
	if (to - from).Magnitude < MIN_STREAK then
		return
	end
	local slot = start(pool, seconds, from)
	slot.target = to
	slot.from = width
	slot.to = width * STREAK_THIN
	slot.fade = fade
	slot.mode = mode
	slot.part.Color = color
	slot.part.CFrame = CFrame.lookAt((from + to) / 2, to)
	pool.animate(slot, 0)
end

local function showGlow(
	at: Vector3,
	color: Color3,
	from: number,
	to: number,
	fade: number,
	seconds: number
)
	local slot = start(glows, seconds, at)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Color = color
	slot.part.CFrame = CFrame.new(at)
	glows.animate(slot, 0)
end

-- A ring on the ground at (x, z) widening from `from` to `to` studs, its line
-- `studs` thick, rising `rise` studs as it goes.
local function showRing(
	x: number,
	z: number,
	color: Color3,
	from: number,
	to: number,
	studs: number,
	fade: number,
	rise: number,
	seconds: number
)
	local frame = groundFrame(x, z, DISC_HEIGHT)
	local slot = start(rings, seconds, frame.Position)
	slot.frame = frame
	local ring = slot.ring
	if ring == nil then
		return
	end
	-- Never narrower than its own line, which would turn the canvas inside out.
	slot.from = math.max(from, studs * 2 + RING_MIN_HOLE)
	slot.to = math.max(to, slot.from)
	slot.fade = fade
	slot.drift = rise
	setRingLine(ring, studs, color, slot.to)
	ring.part.CFrame = frame
	rings.animate(slot, 0)
end

-- A flat disc on the ground at (x, z) growing from `from` to `to` studs wide.
local function showDisc(
	x: number,
	z: number,
	from: number,
	to: number,
	seconds: number,
	color: Color3,
	fade: number
)
	local frame = groundFrame(x, z, DISC_HEIGHT)
	local slot = start(discs, seconds, frame.Position)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Color = color
	slot.part.CFrame = frame * LIE
	discs.animate(slot, 0)
end

-- A mark left on the ground: scorch or frost.
local function showGround(
	x: number,
	z: number,
	material: Enum.Material,
	color: Color3,
	from: number,
	to: number,
	fade: number,
	seconds: number
)
	local frame = groundFrame(x, z, DISC_HEIGHT * 0.5)
	local slot = start(grounds, seconds, frame.Position)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Material = material
	slot.part.Color = color
	slot.part.Size = Vector3.new(0.1, from, from)
	slot.part.CFrame = frame * LIE
	grounds.animate(slot, 0)
end

-- `count` shards flying out from `centre` to `reach` studs, `scale` times the
-- full size, alternating the tint's colour and core.
local function showShards(
	centre: Vector3,
	count: number,
	reach: number,
	tint: Tint,
	scale: number,
	seconds: number
)
	local offset = random:NextNumber(0, 2 * math.pi)
	for index = 1, count do
		local angle = offset + (index + random:NextNumber(-0.3, 0.3)) * 2 * math.pi / count
		local slot = start(shards, seconds, centre)
		slot.target = Vector3.new(math.cos(angle), 0, math.sin(angle))
		slot.from = 0.5
		slot.to = reach
		slot.fade = SHARD_FADE
		slot.drift = random:NextNumber(-SHARD_SPIN, SHARD_SPIN)
		slot.part.Size = SHARD_SIZE * scale
		slot.part.Color = if index % 2 == 0 then tint.core else tint.color
		shards.animate(slot, 0)
	end
end

local function showLight(
	at: Vector3,
	color: Color3,
	brightness: number,
	range: number,
	seconds: number
)
	local slot = start(lights, seconds, at)
	slot.from = brightness
	slot.part.CFrame = CFrame.new(at)
	local light = slot.light
	if light then
		light.Color = color
		light.Range = range
	end
	lights.animate(slot, 0)
end

-- A number or word popping up over `at`.
local function showNumber(at: Vector3, text: string, color: Color3, size: number)
	local origin = at + Vector3.new(random:NextNumber(-1.5, 1.5), 3, random:NextNumber(-1.5, 1.5))
	local slot = start(numbers, NUMBER_SECONDS, origin)
	slot.part.Position = origin
	local label = slot.label
	if label then
		label.Text = text
		label.TextColor3 = color
		label.TextSize = size
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.4
	end
	numbers.animate(slot, 0)
end

-- The latest snapshot's enemies: which way each faces and what kind it is.
local enemyFacing: { [number]: number } = {}
local enemyKind: { [number]: string } = {}
-- Bosses announced before a snapshot drew them, and when.
local pendingBosses: { [number]: number } = {}

local function forwardOf(enemyId: number): Vector3
	local facing = enemyFacing[enemyId] or 0
	return Vector3.new(math.cos(facing), 0, math.sin(facing))
end

-- The first of the kind's attacks of `attackKind`.
local function attackOf(kindId: string?, attackKind: Types.AttackKind): Types.AttackConfig?
	local kind = if kindId then Config.enemies[kindId] else nil
	if kind == nil then
		return nil
	end
	for _, attack in kind.attacks do
		if attack.kind == attackKind then
			return attack
		end
	end
	return nil
end

-- Telegraphs: the wind-up of an enemy attack, one per enemy so that a second
-- telegraph replaces the first. The look follows the attack's kind: a wedge
-- for a melee arc, a disc for an all-round melee, a burst, a leap or a
-- ground attack, a swelling shell for the exploder's burst, an orb at the
-- mouth for a shot, a strip along a charge's line, pulses round a summoner
-- and a green disc for a heal.
type Marker = {
	look: string,
	base: Part,
	fill: Part,
	rim: Ring,
	orb: Part,
	-- A charge's line: the faint strip and the fill growing along it.
	strip: Part,
	stripFill: Part,
	-- The wedge's slices, two wedge parts each: the faint base and the fill.
	sector: { WedgePart },
	sectorFill: { WedgePart },
	-- The ground under the centre.
	frame: CFrame,
	radius: number,
	-- The wedge's width in radians and the way it points.
	arc: number,
	facing: number,
	-- A charge's line: where it starts, which way and how long.
	lineFrom: Vector3,
	lineDirection: Vector3,
	lineLength: number,
	orbTint: Tint,
	startedAt: number,
	endsAt: number,
	-- When the next motes or pulses rise (a heal, a summon).
	motesAt: number,
}
local markers: { [number]: Marker } = {}
local freeMarkers: { Marker } = {}

local function newDisc(name: string): Part
	local part = newEffectPart()
	part.Name = name
	part.Shape = CYLINDER
	return part
end

local function newMarker(): Marker
	local rim = newRing()
	rim.part.Name = "TelegraphRim"
	local orb = newEffectPart()
	orb.Name = "TelegraphOrb"
	orb.Shape = BALL
	local strip = newEffectPart()
	strip.Name = "TelegraphStrip"
	local stripFill = newEffectPart()
	stripFill.Name = "TelegraphStripFill"
	return {
		look = "disc",
		base = newDisc("TelegraphBase"),
		fill = newDisc("TelegraphFill"),
		rim = rim,
		orb = orb,
		strip = strip,
		stripFill = stripFill,
		sector = {},
		sectorFill = {},
		frame = CFrame.identity,
		radius = 0,
		arc = 0,
		facing = 0,
		lineFrom = Vector3.zero,
		lineDirection = Vector3.xAxis,
		lineLength = 0,
		orbTint = EXPLODER,
		startedAt = 0,
		endsAt = 0,
		motesAt = 0,
	}
end

local function hideSector(wedges: { WedgePart })
	for _, wedge in wedges do
		wedge.Parent = nil
	end
end

local function removeMarker(enemyId: number)
	local marker = markers[enemyId]
	if marker then
		markers[enemyId] = nil
		marker.base.Parent = nil
		marker.fill.Parent = nil
		marker.rim.part.Parent = nil
		marker.orb.Parent = nil
		marker.strip.Parent = nil
		marker.stripFill.Parent = nil
		hideSector(marker.sector)
		hideSector(marker.sectorFill)
		table.insert(freeMarkers, marker)
	end
end

-- Lays triangle abc flat with two right-angled wedges, split at the foot of
-- the height onto the longest side.
local function drawTriangle(a: Vector3, b: Vector3, c: Vector3, first: WedgePart, second: WedgePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	first.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	second.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

-- A wedge of `arc` radians round `facing`, `radius` studs long, from slices,
-- lying in the plane of `frame` round its origin.
local function drawSector(
	wedges: { WedgePart },
	frame: CFrame,
	facing: number,
	arc: number,
	radius: number
)
	radius = math.max(radius, SECTOR_MIN_RADIUS)
	local centre = frame.Position
	for slice = 0, SECTOR_SLICES - 1 do
		local from = facing - arc / 2 + arc * slice / SECTOR_SLICES
		local to = from + arc / SECTOR_SLICES
		local p0 = frame:PointToWorldSpace(Vector3.new(math.cos(from), 0, math.sin(from)) * radius)
		local p1 = frame:PointToWorldSpace(Vector3.new(math.cos(to), 0, math.sin(to)) * radius)
		drawTriangle(centre, p0, p1, wedges[slice * 2 + 1], wedges[slice * 2 + 2])
	end
end

-- A telegraph's layer: `frame` moved `offset` studs along its up.
local function layer(frame: CFrame, offset: number): CFrame
	return frame * CFrame.new(0, offset, 0)
end

local function showSector(wedges: { WedgePart }, color: Color3, transparency: number)
	if #wedges == 0 then
		for index = 1, SECTOR_SLICES * 2 do
			wedges[index] = newWedge()
		end
	end
	for _, wedge in wedges do
		wedge.Color = color
		wedge.Transparency = transparency
		wedge.Parent = folder
	end
end

local function telegraphLook(
	attackKind: Types.AttackKind,
	attack: Types.AttackConfig?,
	kindId: string?
): string
	if attackKind == "heal" then
		return "heal"
	elseif attackKind == "summon" then
		return "summon"
	elseif attackKind == "charge" then
		return "strip"
	elseif attackKind == "projectile" then
		return "spit"
	elseif attackKind == "burst" then
		local kind = if kindId then Config.enemies[kindId] else nil
		return if kind and kind.diesOnAttack then "swell" else "disc"
	elseif attackKind == "melee" and attack and (attack.arcDegrees or 360) < 360 then
		return "wedge"
	end
	return "disc"
end

-- A strip lying on the ground from `from` along `direction`, `length` long.
local function placeStrip(
	part: Part,
	from: Vector3,
	direction: Vector3,
	length: number,
	width: number
)
	local shown = math.max(length, TELEGRAPH_MIN_FILL)
	local middle = from + direction * (shown / 2)
	part.Size = Vector3.new(width, TELEGRAPH_THICKNESS, shown)
	part.CFrame = CFrame.lookAt(middle, middle + direction)
end

type TelegraphEvent = {
	enemyId: number,
	attackKind: Types.AttackKind,
	x: number,
	z: number,
	radius: number,
	seconds: number,
	endX: number?,
	endZ: number?,
}

local function showTelegraph(event: TelegraphEvent)
	local enemyId = event.enemyId
	removeMarker(enemyId)
	EnemyView.telegraph(enemyId, event.seconds)
	local kindId = enemyKind[enemyId]
	local attack = attackOf(kindId, event.attackKind)
	local look = telegraphLook(event.attackKind, attack, kindId)
	local x, z, radius = event.x, event.z, event.radius

	local marker = table.remove(freeMarkers) or newMarker()
	local now = os.clock()
	marker.look = look
	marker.radius = radius
	marker.startedAt = now
	marker.endsAt = now + math.max(event.seconds, 0.05)
	marker.motesAt = now
	marker.frame = groundFrame(x, z, DISC_HEIGHT)
	marker.facing = enemyFacing[enemyId] or 0
	marker.arc = math.rad(if attack then attack.arcDegrees or 360 else 360)
	marker.orbTint = kindTint(kindId)
	markers[enemyId] = marker

	if look == "wedge" then
		showSector(marker.sector, TELEGRAPH_BASE_COLOR, TELEGRAPH_BASE_TRANSPARENCY)
		showSector(marker.sectorFill, TELEGRAPH_FILL_COLOR, TELEGRAPH_FILL_TRANSPARENCY)
		local below = layer(marker.frame, -TELEGRAPH_LAYER)
		drawSector(marker.sector, below, marker.facing, marker.arc, radius)
		local above = layer(marker.frame, TELEGRAPH_LAYER)
		drawSector(marker.sectorFill, above, marker.facing, marker.arc, 0)
		return
	end

	if look == "strip" then
		local endX, endZ = event.endX or x, event.endZ or z
		local from = groundAt(x, z, DISC_HEIGHT)
		local along = Vector3.new(endX - x, 0, endZ - z)
		local length = along.Magnitude
		marker.lineFrom = from
		marker.lineDirection = if length > 1e-3 then along / length else forwardOf(enemyId)
		marker.lineLength = length
		local width = math.max(radius * 2, TELEGRAPH_MIN_FILL)
		marker.strip.Color = TELEGRAPH_BASE_COLOR
		marker.strip.Transparency = TELEGRAPH_BASE_TRANSPARENCY
		placeStrip(marker.strip, from - UP * TELEGRAPH_LAYER, marker.lineDirection, length, width)
		marker.stripFill.Color = TELEGRAPH_FILL_COLOR
		marker.stripFill.Transparency = TELEGRAPH_FILL_TRANSPARENCY
		placeStrip(marker.stripFill, from, marker.lineDirection, 0, width)
		marker.strip.Parent = folder
		marker.stripFill.Parent = folder
		return
	end

	if look == "summon" then
		marker.radius = math.max(radius, SUMMON_MIN_RADIUS)
	end
	-- The fill sits a hair above the base, the rim above both. A shot that
	-- strikes only what it hits has no area to mark.
	if look ~= "spit" or radius > 0 then
		local heal = look == "heal"
		local tint = if heal then HEAL elseif look == "summon" then SUMMON_TINT else nil
		local diameter = marker.radius * 2
		marker.base.Color = if tint then tint.color else TELEGRAPH_BASE_COLOR
		marker.base.Transparency = if tint
			then HEAL_BASE_TRANSPARENCY
			else TELEGRAPH_BASE_TRANSPARENCY
		marker.base.Size = Vector3.new(TELEGRAPH_THICKNESS, diameter, diameter)
		marker.base.CFrame = layer(marker.frame, -TELEGRAPH_LAYER) * LIE
		marker.fill.Color = if tint then tint.color else TELEGRAPH_FILL_COLOR
		marker.fill.Transparency = if tint
			then HEAL_FILL_TRANSPARENCY
			else TELEGRAPH_FILL_TRANSPARENCY
		marker.fill.Size = Vector3.new(TELEGRAPH_THICKNESS, TELEGRAPH_MIN_FILL, TELEGRAPH_MIN_FILL)
		marker.fill.CFrame = layer(marker.frame, TELEGRAPH_LAYER) * LIE
		setRingLine(
			marker.rim,
			TELEGRAPH_RIM_STUDS,
			if tint then tint.core else TELEGRAPH_RIM_COLOR,
			diameter
		)
		marker.rim.stroke.Transparency = TELEGRAPH_RIM_FADE
		marker.rim.part.Size = Vector3.new(diameter, RING_THICKNESS, diameter)
		marker.rim.part.CFrame = layer(marker.frame, 2 * TELEGRAPH_LAYER)
		marker.base.Parent = folder
		marker.fill.Parent = folder
		marker.rim.part.Parent = folder
	end

	if look == "swell" then
		marker.orb.Material = Enum.Material.ForceField
		marker.orb.Color = EXPLODER.color
		marker.orb.Size = Vector3.one * SWELL_FROM
		marker.orb.Transparency = SWELL_FADE
	elseif look == "spit" then
		marker.orb.Material = NEON
		marker.orb.Color = marker.orbTint.color
		marker.orb.Size = Vector3.one * ORB_FROM
		marker.orb.Transparency = 0
	end
	if look == "swell" or look == "spit" then
		local at = EnemyView.position(enemyId)
		if at then
			marker.orb.CFrame = CFrame.new(at)
		end
		marker.orb.Parent = folder
	end
end

local function stepMarkers()
	local now = os.clock()
	for enemyId, marker in markers do
		local alpha = (now - marker.startedAt) / (marker.endsAt - marker.startedAt)
		if alpha >= 1 then
			removeMarker(enemyId)
			continue
		end
		local look = marker.look
		if look == "wedge" then
			-- The facing comes with snapshots; the event may have come first.
			local facing = enemyFacing[enemyId]
			if facing and facing ~= marker.facing then
				marker.facing = facing
				local below = layer(marker.frame, -TELEGRAPH_LAYER)
				drawSector(marker.sector, below, facing, marker.arc, marker.radius)
			end
			local above = layer(marker.frame, TELEGRAPH_LAYER)
			drawSector(marker.sectorFill, above, marker.facing, marker.arc, marker.radius * alpha)
			continue
		elseif look == "strip" then
			placeStrip(
				marker.stripFill,
				marker.lineFrom,
				marker.lineDirection,
				marker.lineLength * alpha,
				marker.stripFill.Size.X
			)
			continue
		end

		local diameter = math.max(marker.radius * 2 * alpha, TELEGRAPH_MIN_FILL)
		marker.fill.Size = Vector3.new(TELEGRAPH_THICKNESS, diameter, diameter)
		marker.rim.stroke.Transparency = TELEGRAPH_RIM_FADE * (1 - alpha)

		if look == "swell" or look == "spit" then
			local at = EnemyView.position(enemyId)
			if at then
				if look == "spit" then
					at += forwardOf(enemyId) * MOUTH_FORWARD + UP * MOUTH_RISE
				end
				marker.orb.CFrame = CFrame.new(at)
			end
			if look == "swell" then
				local pulse = 1 + SWELL_PULSE * math.sin(now * SWELL_HERTZ * 2 * math.pi)
				local size = (SWELL_FROM + (SWELL_TO - SWELL_FROM) * alpha) * pulse
				marker.orb.Size = Vector3.one * size
				marker.orb.Transparency = SWELL_FADE * (1 - alpha)
			else
				marker.orb.Size = Vector3.one * (ORB_FROM + (ORB_TO - ORB_FROM) * easeOut(alpha))
			end
		elseif (look == "heal" or look == "summon") and now >= marker.motesAt then
			marker.motesAt = now + MOTE_SECONDS
			local at = EnemyView.position(enemyId)
			if at and onScreen(at) then
				if look == "heal" then
					emit("motes", HEAL.color, at, WIND_UP_MOTES, Vector3.new(4, 1, 4))
				else
					local offset = random:NextNumber(0, 2 * math.pi)
					local ground = groundAt(at.X, at.Z, 1)
					for index = 1, SUMMON_POINTS do
						local angle = offset + index * 2 * math.pi / SUMMON_POINTS
						local point = ground
							+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * marker.radius
						showGlow(
							point,
							SUMMON_TINT.color,
							0.3,
							SUMMON_PULSE_DIAMETER,
							0.3,
							MOTE_SECONDS
						)
					end
				end
			end
		end
	end
end
-- Projectiles: pooled parts, one per id, drawn from the snapshots. A part
-- keeps its style for life, so its trail and particles are built once; a
-- part let go is hidden in place so its smoke can die out.
type Tracked = {
	part: Part,
	style: Style,
	light: PointLight?,
	trail: Trail?,
	streams: { ParticleEmitter },
}
type Tracker = {
	free: { [Style]: { Tracked } },
	live: { [number]: Tracked },
	stamps: { [number]: number },
}

local function newTracker(): Tracker
	return { free = {}, live = {}, stamps = {} }
end

local projectileTracker = newTracker()
local trackGeneration = 0
-- The previous snapshot's projectiles by id.
local previousProjectiles: { [number]: Protocol.ProjectileView } = {}
-- Reused every frame for the bulk move.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function buildTracked(style: Style): Tracked
	local part = newEffectPart()
	part.Shape = style.shape
	part.Size = style.size
	part.Color = style.color
	part.Material = style.material

	local light: PointLight? = nil
	if style.lightRange then
		local lamp = Instance.new("PointLight")
		lamp.Color = style.glow
		lamp.Range = style.lightRange
		lamp.Brightness = TRACKED_LIGHT_BRIGHTNESS
		lamp.Shadows = false
		lamp.Enabled = false
		lamp.Parent = part
		light = lamp
	end

	local trail: Trail? = nil
	if style.trail > 0 then
		local top = Instance.new("Attachment")
		top.Position = UP * (style.trail / 2)
		top.Parent = part
		local bottom = Instance.new("Attachment")
		bottom.Position = -UP * (style.trail / 2)
		bottom.Parent = part
		local ribbon = Instance.new("Trail")
		ribbon.Attachment0 = top
		ribbon.Attachment1 = bottom
		ribbon.FaceCamera = true
		ribbon.Lifetime = TRAIL_SECONDS
		ribbon.LightEmission = 1
		ribbon.LightInfluence = 0
		ribbon.Color = ColorSequence.new(style.glow)
		ribbon.Transparency = curve({ TRAIL_TRANSPARENCY, 1 })
		ribbon.WidthScale = curve({ 1, 0.2 })
		ribbon.Enabled = false
		ribbon.Parent = part
		trail = ribbon
	end

	local streams = {}
	for _, stream in style.streams do
		local emitter = Instance.new("ParticleEmitter")
		configureEmitter(emitter, PRESETS[stream.preset], stream.color)
		emitter.Rate = stream.rate
		emitter.Enabled = false
		emitter.Parent = part
		table.insert(streams, emitter)
	end

	return { part = part, style = style, light = light, trail = trail, streams = streams }
end

-- Hides a part let go and hands it back to its style's pool.
local function release(tracker: Tracker, id: number, tracked: Tracked)
	tracker.live[id] = nil
	tracker.stamps[id] = nil
	tracked.part.Transparency = 1
	if tracked.trail then
		tracked.trail.Enabled = false
	end
	for _, stream in tracked.streams do
		stream.Enabled = false
	end
	if tracked.light then
		tracked.light.Enabled = false
	end
	local free = tracker.free[tracked.style]
	if free == nil then
		free = {}
		tracker.free[tracked.style] = free
	end
	table.insert(free, tracked)
end

-- The part drawing `id`, taken from the pool the first time it is seen or
-- when its style changes.
local function trackPart(tracker: Tracker, id: number, style: Style, x: number, z: number)
	tracker.stamps[id] = trackGeneration
	local live = tracker.live[id]
	if live then
		if live.style == style then
			return
		end
		release(tracker, id, live)
		tracker.stamps[id] = trackGeneration
	end
	local free = tracker.free[style]
	local tracked = (if free then table.remove(free) else nil) or buildTracked(style)
	tracked.part.CFrame = CFrame.new(x, Net.groundY() + style.height, z)
	tracked.part.Transparency = style.transparency
	tracked.part.Parent = folder
	local trail = tracked.trail
	if trail then
		trail:Clear()
		trail.Enabled = true
	end
	for _, stream in tracked.streams do
		stream.Enabled = true
	end
	tracker.live[id] = tracked
end

local function sweep(tracker: Tracker)
	for id, tracked in tracker.live do
		if tracker.stamps[id] ~= trackGeneration then
			release(tracker, id, tracked)
		end
	end
end

-- Lights the first live parts that carry a light, up to the cap; returns how
-- many are lit so far.
local function lightTracked(tracker: Tracker, lit: number): number
	for _, tracked in tracker.live do
		local light = tracked.light
		if light then
			light.Enabled = lit < TRACKED_LIGHTS
			if light.Enabled then
				lit += 1
			end
		end
	end
	return lit
end

-- Where the culling measures from: the local character, or the camera.
local function viewCenter(): Vector3?
	local root = localRoot()
	if root then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function inView(center: Vector3?, x: number, z: number): boolean
	if center == nil then
		return true
	end
	local dx, dz = x - center.X, z - center.Z
	return dx * dx + dz * dz <= VIEW_RANGE * VIEW_RANGE
end

-- Crystals: one pooled gem per id, parked while out of view. A collected
-- one leaves the set and flies; a crystal the snapshot dropped is
-- remembered a moment for the event that collects it.
type Gem = { part: Part, x: number, z: number, xp: number, phase: number, parked: boolean }
type Flight = { part: Part, from: Vector3, player: number, startedAt: number, color: Color3 }
local gems: { [number]: Gem } = {}
local gemStamps: { [number]: number } = {}
local freeGems: { Part } = {}
local lostGems: { [number]: { x: number, z: number, xp: number, at: number } } = {}
-- Collected crystals a late snapshot may still list, and when.
local collected: { [number]: number } = {}
local flights: { Flight } = {}
local PARKED = CFrame.new(0, -10000, 0)
-- Turns a cube onto a corner: a gem.
local GEM_TURN = CFrame.Angles(math.pi / 4, 0, math.pi / 4)

local function newGemPart(): Part
	local part = newEffectPart()
	part.Name = "Crystal"
	part.Size = GEM_SIZE
	return part
end

local function gemColor(xp: number): Color3
	if xp <= SMALL_XP then
		return GEM_SMALL
	elseif xp <= MEDIUM_XP then
		return GEM_MEDIUM
	end
	return GEM_LARGE
end

local function takeGem(xp: number): Part
	local part = table.remove(freeGems) or newGemPart()
	part.Color = gemColor(xp)
	part.Size = if xp > MEDIUM_XP then GEM_SIZE * GEM_BIG else GEM_SIZE
	part.Transparency = 0
	part.Parent = folder
	return part
end

local function giveGem(part: Part)
	part.Parent = nil
	table.insert(freeGems, part)
end

local function syncCrystals(crystals: { Protocol.CrystalView })
	local now = os.clock()
	for _, crystal in crystals do
		local id = crystal.id
		gemStamps[id] = trackGeneration
		local gem = gems[id]
		if gem == nil and collected[id] == nil then
			gem = {
				part = takeGem(crystal.xp),
				x = crystal.x,
				z = crystal.z,
				xp = crystal.xp,
				phase = (id * 0.618) % 1,
				parked = false,
			}
			gems[id] = gem
		end
		if gem then
			gem.x = crystal.x
			gem.z = crystal.z
		end
	end
	for id, gem in gems do
		if gemStamps[id] ~= trackGeneration then
			lostGems[id] = { x = gem.x, z = gem.z, xp = gem.xp, at = now }
			giveGem(gem.part)
			gems[id] = nil
			gemStamps[id] = nil
		end
	end
	for id, lost in lostGems do
		if now - lost.at > GEM_MEMORY then
			lostGems[id] = nil
		end
	end
	for id, at in collected do
		if now - at > GEM_MEMORY then
			collected[id] = nil
		end
	end
end

-- Crystal `id` was collected by `player`: it flies to them.
local function collectGem(id: number, player: number)
	local now = os.clock()
	collected[id] = now
	local part: Part
	local from: Vector3
	local xp: number
	local gem = gems[id]
	if gem then
		gems[id] = nil
		gemStamps[id] = nil
		part = gem.part
		xp = gem.xp
		from = if gem.parked then groundAt(gem.x, gem.z, GEM_RISE) else part.Position
	else
		local lost = lostGems[id]
		if lost == nil then
			return
		end
		lostGems[id] = nil
		xp = lost.xp
		from = groundAt(lost.x, lost.z, GEM_RISE)
		part = takeGem(xp)
	end
	if not onScreen(from) then
		giveGem(part)
		return
	end
	table.insert(
		flights,
		{ part = part, from = from, player = player, startedAt = now, color = gemColor(xp) }
	)
end

-- Food: a meat leg per id, placed once.
type Meal = { meat: Part, bone: Part }
local meals: { [number]: Meal } = {}
local mealStamps: { [number]: number } = {}
local freeMeals: { Meal } = {}

local function newMeal(): Meal
	local meat = newEffectPart()
	meat.Name = "Food"
	meat.Shape = BALL
	meat.Size = MEAT_SIZE
	meat.Material = Enum.Material.SmoothPlastic
	meat.Color = MEAT_COLOR
	local halo = Instance.new("ParticleEmitter")
	configureEmitter(halo, PRESETS.halo, HEAL.color)
	halo.Rate = 2
	halo.Parent = meat
	local bone = newEffectPart()
	bone.Name = "FoodBone"
	bone.Shape = CYLINDER
	bone.Size = BONE_SIZE
	bone.Material = Enum.Material.SmoothPlastic
	bone.Color = BONE_COLOR
	return { meat = meat, bone = bone }
end

local function syncFoods(foods: { Protocol.FoodView })
	for _, food in foods do
		mealStamps[food.id] = trackGeneration
		if meals[food.id] == nil then
			local meal = table.remove(freeMeals) or newMeal()
			local turn = CFrame.Angles(0, (food.id * 0.618 % 1) * 2 * math.pi, 0)
			local at = groundFrame(food.x, food.z, MEAT_RISE) * turn
			meal.meat.CFrame = at
			meal.bone.CFrame = at * CFrame.new(MEAT_SIZE.X * 0.55, 0, 0)
			meal.meat.Parent = folder
			meal.bone.Parent = folder
			meals[food.id] = meal
		end
	end
	for id, meal in meals do
		if mealStamps[id] ~= trackGeneration then
			meal.meat.Parent = nil
			meal.bone.Parent = nil
			meals[id] = nil
			mealStamps[id] = nil
			table.insert(freeMeals, meal)
		end
	end
end

-- Areas: a disc, a rim and particles per id, from the event that placed it
-- and kept to the snapshots' lifetime.
type AreaVisual = {
	disc: Part,
	rim: Ring,
	host: Part,
	emitter: ParticleEmitter,
	-- The disc's transparency between pulses.
	baseTransparency: number,
	startedAt: number,
	endsAt: number,
	-- Seconds from the start to the first tick, and between ticks.
	firstTick: number,
	tick: number,
	-- When a snapshot last showed it.
	seen: number,
}
local areaVisuals: { [number]: AreaVisual } = {}
local freeAreas: { AreaVisual } = {}
local areaCount = 0

local function newAreaVisual(): AreaVisual
	local disc = newDisc("Area")
	local rim = newRing()
	rim.part.Name = "AreaRim"
	local host = newEffectPart()
	host.Name = "AreaParticles"
	host.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Parent = host
	return {
		disc = disc,
		rim = rim,
		host = host,
		emitter = emitter,
		baseTransparency = AREA_TRANSPARENCY,
		startedAt = 0,
		endsAt = 0,
		firstTick = 0,
		tick = 1,
		seen = 0,
	}
end

local function removeArea(id: number)
	local visual = areaVisuals[id]
	if visual == nil then
		return
	end
	areaVisuals[id] = nil
	areaCount -= 1
	visual.disc.Parent = nil
	visual.rim.part.Parent = nil
	visual.emitter.Enabled = false
	visual.host.Parent = nil
	table.insert(freeAreas, visual)
end

-- The oldest area drawn, to make room past the cap.
local function oldestArea(): number?
	local oldest: number? = nil
	local at = math.huge
	for id, visual in areaVisuals do
		if visual.startedAt < at then
			at = visual.startedAt
			oldest = id
		end
	end
	return oldest
end

local function placeArea(
	id: number,
	owner: "player" | "enemy",
	areaKind: string,
	x: number,
	z: number,
	radius: number,
	seconds: number
)
	if areaVisuals[id] or seconds <= 0 or radius <= 0 then
		return
	end
	if areaCount >= AREA_CAP then
		local oldest = oldestArea()
		if oldest then
			removeArea(oldest)
		end
	end
	local visual = table.remove(freeAreas) or newAreaVisual()
	local now = os.clock()
	local diameter = radius * 2
	local tint: Tint
	local preset: string
	local rise = 1
	if owner == "player" then
		tint = tintOf(areaKind)
		local skill = Config.skills[areaKind]
		local tag = if skill then skill.tags[1] else nil
		if tag == "ice" then
			preset = "flakes"
			rise = AREA_FALL_HEIGHT
		elseif tag == "fire" then
			preset = "cinders"
			rise = AREA_FALL_HEIGHT
		else
			preset = "shimmer"
		end
		visual.disc.Material = NEON
		visual.disc.Color = tint.color
		visual.baseTransparency = AREA_TRANSPARENCY
		visual.firstTick = Config.ranks.areaFirstTickSeconds
		visual.tick = Config.ranks.areaTickSeconds
	else
		tint = kindTint(areaKind)
		preset = "bubbles"
		visual.disc.Material = Enum.Material.SmoothPlastic
		visual.disc.Color = tint.color:Lerp(Color3.new(0, 0, 0), AREA_POOL_DARKEN)
		visual.baseTransparency = AREA_POOL_TRANSPARENCY
		local attack = attackOf(areaKind, "ground")
		visual.tick = if attack then attack.groundTickSeconds or 0.5 else 0.5
		visual.firstTick = visual.tick
	end
	visual.startedAt = now
	visual.endsAt = now + seconds
	visual.seen = now

	visual.disc.Size = Vector3.new(AREA_HEIGHT, diameter, diameter)
	visual.disc.CFrame = groundFrame(x, z, AREA_HEIGHT / 2) * LIE
	visual.disc.Transparency = 1
	setRingLine(visual.rim, AREA_RIM_STUDS, tint.core, diameter)
	visual.rim.stroke.Transparency = 1
	visual.rim.part.Size = Vector3.new(diameter, RING_THICKNESS, diameter)
	visual.rim.part.CFrame = groundFrame(x, z, AREA_HEIGHT + TELEGRAPH_LAYER)
	configureEmitter(visual.emitter, PRESETS[preset], tint.color)
	visual.emitter.Rate = math.clamp(AREA_PARTICLE_DENSITY * math.pi * radius * radius, 4, 60)
	visual.host.Size = Vector3.new(diameter * 0.9, 0.5, diameter * 0.9)
	visual.host.CFrame = groundFrame(x, z, rise)
	visual.emitter.Enabled = true
	visual.disc.Parent = folder
	visual.rim.part.Parent = folder
	visual.host.Parent = folder
	areaVisuals[id] = visual
	areaCount += 1
end

local function syncAreas(areas: { Protocol.AreaView })
	local now = os.clock()
	for _, area in areas do
		local visual = areaVisuals[area.id]
		if visual == nil then
			placeArea(
				area.id,
				area.owner,
				area.areaKind,
				area.x,
				area.z,
				area.radius,
				area.secondsLeft
			)
			visual = areaVisuals[area.id]
		end
		if visual then
			visual.seen = now
			visual.endsAt = now + area.secondsLeft
		end
	end
	for id, visual in areaVisuals do
		if now - visual.seen > AREA_GRACE then
			removeArea(id)
		end
	end
end

-- Fades areas in and out and pulses each with its ticks.
local function stepAreas(now: number)
	for id, visual in areaVisuals do
		if now >= visual.endsAt then
			removeArea(id)
			continue
		end
		local shown = math.min(
			1,
			(now - visual.startedAt) / AREA_FADE_IN,
			(visual.endsAt - now) / AREA_FADE_OUT
		)
		local flash = 0
		local since = now - visual.startedAt - visual.firstTick
		if since >= 0 and visual.tick > 0 then
			local phase = (since % visual.tick) / visual.tick
			flash = (1 - phase) ^ 3
		end
		local opaque = (1 - visual.baseTransparency) * shown + AREA_PULSE * flash * shown
		visual.disc.Transparency = math.clamp(1 - opaque, 0, 1)
		visual.rim.stroke.Transparency = 1 - (1 - AREA_RIM_FADE) * shown
	end
end

-- Totems: a pole and a glowing bird per id.
type TotemVisual = {
	pole: Part,
	body: Part,
	wings: { Part },
	halo: ParticleEmitter,
	x: number,
	z: number,
	phase: number,
	endsAt: number,
	seen: number,
}
local totemVisuals: { [number]: TotemVisual } = {}
local freeTotems: { TotemVisual } = {}

local function newTotemVisual(): TotemVisual
	local pole = newEffectPart()
	pole.Name = "TotemPole"
	pole.Shape = CYLINDER
	pole.Size = TOTEM_POLE
	pole.Material = Enum.Material.Wood
	pole.Color = WOOD_COLOR
	local body = newEffectPart()
	body.Name = "TotemBird"
	body.Size = TOTEM_BODY
	local wings = {}
	for index = 1, 2 do
		local wing = newEffectPart()
		wing.Name = "TotemWing"
		wing.Size = TOTEM_WING
		wings[index] = wing
	end
	local halo = Instance.new("ParticleEmitter")
	halo.Parent = body
	return {
		pole = pole,
		body = body,
		wings = wings,
		halo = halo,
		x = 0,
		z = 0,
		phase = 0,
		endsAt = 0,
		seen = 0,
	}
end

local function removeTotem(id: number)
	local visual = totemVisuals[id]
	if visual == nil then
		return
	end
	totemVisuals[id] = nil
	visual.pole.Parent = nil
	visual.body.Parent = nil
	for _, wing in visual.wings do
		wing.Parent = nil
	end
	visual.halo.Enabled = false
	table.insert(freeTotems, visual)
end

local function placeTotem(id: number, skill: string, x: number, z: number, seconds: number)
	local now = os.clock()
	local existing = totemVisuals[id]
	if existing then
		existing.endsAt = now + seconds
		existing.seen = now
		return
	end
	local visual = table.remove(freeTotems) or newTotemVisual()
	local tint = tintOf(skill)
	visual.x = x
	visual.z = z
	visual.phase = (id * 0.618) % 1
	visual.endsAt = now + seconds
	visual.seen = now
	visual.pole.CFrame = groundFrame(x, z, TOTEM_POLE.X / 2) * LIE
	visual.body.Color = tint.color
	for _, wing in visual.wings do
		wing.Color = tint.core
		wing.Parent = folder
	end
	configureEmitter(visual.halo, PRESETS.halo, tint.color)
	visual.halo.Rate = 2
	visual.halo.Enabled = true
	visual.pole.Parent = folder
	visual.body.Parent = folder
	totemVisuals[id] = visual
end

local function syncTotems(totems: { Protocol.TotemView })
	local now = os.clock()
	for _, totem in totems do
		placeTotem(totem.id, totem.skill, totem.x, totem.z, totem.secondsLeft)
	end
	for id, visual in totemVisuals do
		if now - visual.seen > AREA_GRACE then
			removeTotem(id)
		end
	end
end

-- The bird idles: it glows in and out, turns its head and flaps.
local function stepTotems(now: number)
	for id, visual in totemVisuals do
		if now >= visual.endsAt then
			removeTotem(id)
			continue
		end
		local wave = math.sin((now * TOTEM_GLOW_HZ + visual.phase) * 2 * math.pi)
		visual.body.Transparency = TOTEM_GLOW_MIN
			+ (TOTEM_GLOW_MAX - TOTEM_GLOW_MIN) * (0.5 + 0.5 * wave)
		local turn = TOTEM_TURN * math.sin((now * 0.3 + visual.phase) * 2 * math.pi)
		local bird = groundFrame(visual.x, visual.z, TOTEM_BIRD_RISE) * CFrame.Angles(0, turn, 0)
		visual.body.CFrame = bird
		local flap = TOTEM_FLAP * math.sin((now * TOTEM_FLAP_HZ + visual.phase) * 2 * math.pi)
		local reach = (TOTEM_BODY.X + TOTEM_WING.X) / 2
		visual.wings[1].CFrame = bird * CFrame.Angles(0, 0, flap) * CFrame.new(-reach, 0, 0)
		visual.wings[2].CFrame = bird * CFrame.Angles(0, 0, -flap) * CFrame.new(reach, 0, 0)
	end
end

-- The portal: built the first time it opens, then reused.
type PortalVisual = {
	segments: { Part },
	face: Part,
	light: PointLight,
	emitter: ParticleEmitter,
	rim: Ring,
	x: number,
	z: number,
	openedAt: number,
	endsAt: number,
	active: boolean,
}
local portal: PortalVisual? = nil

local function buildPortal(): PortalVisual
	local segments = {}
	for index = 1, PORTAL_SEGMENTS do
		local segment = newEffectPart()
		segment.Name = "PortalSegment"
		segment.Size = PORTAL_SEGMENT
		segment.Color = if index % 2 == 0 then PORTAL_TINT.core else PORTAL_TINT.color
		segments[index] = segment
	end
	local face = newDisc("PortalFace")
	face.Material = Enum.Material.ForceField
	face.Color = PORTAL_TINT.color
	face.Transparency = PORTAL_FACE_TRANSPARENCY
	local light = Instance.new("PointLight")
	light.Color = PORTAL_TINT.color
	light.Shadows = false
	light.Parent = face
	local emitter = Instance.new("ParticleEmitter")
	configureEmitter(emitter, PRESETS.swirl, PORTAL_TINT.color)
	emitter.Rate = PORTAL_MOTE_RATE
	emitter.Enabled = false
	emitter.Parent = face
	local rim = newRing()
	rim.part.Name = "PortalRim"
	return {
		segments = segments,
		face = face,
		light = light,
		emitter = emitter,
		rim = rim,
		x = 0,
		z = 0,
		openedAt = 0,
		endsAt = 0,
		active = false,
	}
end

local function openPortal(x: number, z: number, seconds: number)
	local visual = portal or buildPortal()
	portal = visual
	local now = os.clock()
	visual.endsAt = now + seconds
	if visual.active and visual.x == x and visual.z == z then
		-- A snapshot of the portal already standing: only its time left.
		return
	end
	if not visual.active then
		visual.openedAt = now
	end
	visual.active = true
	visual.x = x
	visual.z = z
	local diameter = Config.extraction.portalRadius * 2
	setRingLine(visual.rim, CAST_RING_STUDS * 2, PORTAL_TINT.core, diameter)
	visual.rim.stroke.Transparency = 0.2
	visual.rim.part.Size = Vector3.new(diameter, RING_THICKNESS, diameter)
	visual.rim.part.CFrame = groundFrame(x, z, DISC_HEIGHT)
	visual.rim.part.Parent = folder
	for _, segment in visual.segments do
		segment.Parent = folder
	end
	visual.face.Parent = folder
	visual.emitter.Enabled = true
end

local function closePortal()
	local visual = portal
	if visual == nil or not visual.active then
		return
	end
	visual.active = false
	for _, segment in visual.segments do
		segment.Parent = nil
	end
	visual.face.Parent = nil
	visual.rim.part.Parent = nil
	visual.emitter.Enabled = false
	local centre = groundAt(visual.x, visual.z, Config.extraction.portalRadius)
	if onScreen(centre) then
		emit("implosion", PORTAL_TINT.color, centre, 1)
		emit("shimmer", PORTAL_TINT.core, centre, 20, Vector3.new(4, 4, 4))
	end
end

-- Spins the ring, grows it in and shrinks it before it closes.
local function renderPortal(now: number)
	local visual = portal
	if visual == nil or not visual.active then
		return
	end
	local grow = math.min(1, (now - visual.openedAt) / PORTAL_GROW)
	local shrink = math.clamp((visual.endsAt - now) / PORTAL_SHRINK, 0, 1)
	local scale = easeOut(math.min(grow, shrink))
	local full = Config.extraction.portalRadius
	local radius = math.max(full * scale, 0.05)
	local basis = groundFrame(visual.x, visual.z, full + 0.5) * CFrame.Angles(-PORTAL_TILT, 0, 0)
	local spin = now * PORTAL_SPIN
	for index, segment in visual.segments do
		local angle = spin + index * 2 * math.pi / PORTAL_SEGMENTS
		segment.CFrame = basis
			* CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			* CFrame.Angles(0, 0, angle + math.pi / 2)
	end
	local face = radius * 2 * 0.95
	visual.face.Size = Vector3.new(0.2, face, face)
	visual.face.CFrame = basis * CFrame.Angles(0, math.pi / 2, 0)
	visual.light.Brightness = PORTAL_LIGHT_BRIGHTNESS * scale
	visual.light.Range = full * 4
end

local function syncPortal(view: Protocol.PortalView?)
	if view then
		openPortal(view.x, view.z, view.secondsLeft)
		return
	end
	local visual = portal
	if visual and visual.active and os.clock() - visual.openedAt > AREA_GRACE then
		closePortal()
	end
end

-- The chest's beam, while the compass points at an unopened chest.
local beam: Part? = nil
local beamHost: Part? = nil

local function syncChest(world: Protocol.WorldView)
	local want = world.compassOn and not world.chest.opened
	local part = beam
	local host = beamHost
	if want and part == nil then
		local made = newEffectPart()
		made.Name = "ChestBeam"
		made.Shape = CYLINDER
		made.Size = Vector3.new(BEAM_HEIGHT, BEAM_WIDTH, BEAM_WIDTH)
		made.Color = GOLD.color
		made.Transparency = BEAM_TRANSPARENCY
		local light = Instance.new("PointLight")
		light.Color = GOLD.color
		light.Range = 16
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = made
		local glow = newEffectPart()
		glow.Name = "ChestGlints"
		glow.Transparency = 1
		glow.Size = Vector3.new(BEAM_WIDTH, BEAM_HEIGHT / 3, BEAM_WIDTH)
		local glints = Instance.new("ParticleEmitter")
		configureEmitter(glints, PRESETS.shimmer, GOLD.color)
		glints.Rate = 8
		glints.Parent = glow
		part = made
		host = glow
		beam = made
		beamHost = glow
	end
	if part and host then
		if want then
			local x, z = world.chest.x, world.chest.z
			part.CFrame = groundFrame(x, z, BEAM_HEIGHT / 2) * LIE
			host.CFrame = groundFrame(x, z, BEAM_HEIGHT / 6)
			part.Parent = folder
			host.Parent = folder
		else
			part.Parent = nil
			host.Parent = nil
		end
	end
end

local function renderBeam(now: number)
	local part = beam
	if part and part.Parent then
		local wave = math.sin(now * BEAM_HZ * 2 * math.pi)
		part.Transparency = BEAM_TRANSPARENCY + BEAM_PULSE * wave
	end
end

-- Barrier spheres by player, while the barrier holds; who is sprinting.
local shields: { [number]: Part } = {}
local freeShields: { Part } = {}
local sprinting: { [number]: number } = {}

local function newShield(): Part
	local sphere = newEffectPart()
	sphere.Name = "Barrier"
	sphere.Shape = BALL
	sphere.Size = Vector3.one * SHIELD_DIAMETER
	sphere.Material = Enum.Material.ForceField
	sphere.Color = BARRIER.color
	sphere.Transparency = SHIELD_TRANSPARENCY
	return sphere
end

local function syncPlayers(players: { Protocol.PlayerView })
	local holding: { [number]: boolean } = {}
	local running: { [number]: boolean } = {}
	for _, player in players do
		if player.state == "alive" and player.barrier > 0 then
			holding[player.id] = true
			if not shields[player.id] then
				shields[player.id] = table.remove(freeShields) or newShield()
			end
		end
		if player.state == "alive" and player.sprinting then
			running[player.id] = true
			sprinting[player.id] = sprinting[player.id] or 0
		end
	end
	for id, sphere in shields do
		if not holding[id] then
			sphere.Parent = nil
			shields[id] = nil
			table.insert(freeShields, sphere)
		end
	end
	for id in sprinting do
		if not running[id] then
			sprinting[id] = nil
		end
	end
end

local function followShields()
	for id, sphere in shields do
		local root = characterRoot(id)
		if root then
			sphere.CFrame = CFrame.new(root.Position)
			sphere.Parent = folder
		else
			sphere.Parent = nil
		end
	end
end

-- Speed lines behind each sprinting hero, along the way it runs.
local function stepSprint(now: number)
	for id, nextAt in sprinting do
		if now < nextAt then
			continue
		end
		sprinting[id] = now + SPRINT_LINE_SECONDS
		local root = characterRoot(id)
		if root == nil or not onScreen(root.Position) then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude < SPRINT_MIN_SPEED then
			continue
		end
		local back = -flat.Unit
		local side = Vector3.new(-back.Z, 0, back.X)
		for _ = 1, SPRINT_LINES do
			local from = root.Position
				+ back
				+ side * random:NextNumber(-1.2, 1.2)
				+ UP * random:NextNumber(-1.5, 1.2)
			showStreak(
				streaks,
				from,
				from + back * SPRINT_LINE_LENGTH,
				WHITE,
				SPRINT_LINE_WIDTH,
				0.3,
				SPRINT_LINE_SECONDS_LIVE,
				"fade"
			)
		end
	end
end

-- The extraction spell's cast circle, by player.
type CastCircle = { rim: Ring, motes: { Part }, startedAt: number, endsAt: number }
local castCircles: { [number]: CastCircle } = {}
local freeCircles: { CastCircle } = {}

local function endCast(player: number)
	local circle = castCircles[player]
	if circle == nil then
		return
	end
	castCircles[player] = nil
	circle.rim.part.Parent = nil
	for _, mote in circle.motes do
		mote.Parent = nil
	end
	table.insert(freeCircles, circle)
end

local function newCastCircle(): CastCircle
	local rim = newRing()
	rim.part.Name = "CastCircle"
	local motes = {}
	for index = 1, CAST_MOTES do
		local mote = newEffectPart()
		mote.Name = "CastMote"
		mote.Shape = BALL
		mote.Size = Vector3.one * CAST_MOTE_SIZE
		mote.Color = if index % 2 == 0 then PORTAL_TINT.core else PORTAL_TINT.color
		motes[index] = mote
	end
	return { rim = rim, motes = motes, startedAt = 0, endsAt = 0 }
end

local function startCast(player: number, seconds: number)
	endCast(player)
	local circle = table.remove(freeCircles) or newCastCircle()
	local now = os.clock()
	circle.startedAt = now
	circle.endsAt = now + seconds
	setRingLine(circle.rim, CAST_RING_STUDS, PORTAL_TINT.core, CAST_RING_DIAMETER)
	circle.rim.stroke.Transparency = 0.1
	circle.rim.part.Size = Vector3.new(CAST_RING_DIAMETER, RING_THICKNESS, CAST_RING_DIAMETER)
	castCircles[player] = circle
end

-- The circle follows its caster; its motes swirl round and climb as the cast nears its end.
local function stepCasts(now: number)
	for player, circle in castCircles do
		if now >= circle.endsAt then
			endCast(player)
			continue
		end
		local root = characterRoot(player)
		if root == nil then
			circle.rim.part.Parent = nil
			continue
		end
		local position = root.Position
		local progress = (now - circle.startedAt) / (circle.endsAt - circle.startedAt)
		local ground = groundFrame(position.X, position.Z, DISC_HEIGHT)
		circle.rim.part.CFrame = ground * CFrame.Angles(0, now * CAST_SWIRL, 0)
		circle.rim.part.Parent = folder
		local radius = CAST_RING_DIAMETER / 2 * (1 - 0.35 * progress)
		for index, mote in circle.motes do
			local angle = now * CAST_SWIRL + index * 2 * math.pi / CAST_MOTES
			mote.CFrame = ground
				* CFrame.new(
					math.cos(angle) * radius,
					0.5 + progress * 3 + 0.3 * math.sin(angle * 2),
					math.sin(angle) * radius
				)
			mote.Parent = folder
		end
	end
end

-- Heroes fading out as they extract.
type Fade = { parts: { BasePart }, startedAt: number }
local fades: { Fade } = {}

local function stepFades(now: number)
	for index = #fades, 1, -1 do
		local fade = fades[index]
		local alpha = math.min(1, (now - fade.startedAt) / EXTRACT_SECONDS)
		for _, part in fade.parts do
			part.LocalTransparencyModifier = alpha
		end
		if alpha >= 1 then
			fades[index] = fades[#fades]
			fades[#fades] = nil
		end
	end
end

local function syncTracked(snapshot: Net.Snapshot)
	trackGeneration += 1
	table.clear(previousProjectiles)
	local previous = Net.previous
	if previous then
		for _, projectile in previous.projectiles do
			previousProjectiles[projectile.id] = projectile
		end
	end
	for _, projectile in snapshot.projectiles do
		local style = STYLES[projectile.kind] or DEFAULT_PROJECTILE
		trackPart(projectileTracker, projectile.id, style, projectile.x, projectile.z)
	end
	sweep(projectileTracker)
	lightTracked(projectileTracker, 0)
	syncCrystals(snapshot.crystals)
end

-- Moves the projectiles (glided like enemies), the crystals (spinning and
-- bobbing, parked out of view) and the collected crystals in flight.
local function renderTracked(now: number)
	local latest = Net.latest
	if latest == nil then
		return
	end
	local alpha = EnemyView.interpolation()
	local count = 0
	local ground = Net.groundY()

	for _, projectile in latest.projectiles do
		local tracked = projectileTracker.live[projectile.id]
		if tracked then
			local x, z = projectile.x, projectile.z
			local before = previousProjectiles[projectile.id]
			if before then
				x = before.x + (x - before.x) * alpha
				z = before.z + (z - before.z) * alpha
			end
			count += 1
			moveParts[count] = tracked.part
			moveFrames[count] = CFrame.new(x, ground + tracked.style.height, z)
				* CFrame.Angles(0, -projectile.angle - math.pi / 2, 0)
		end
	end

	local center = viewCenter()
	for _, gem in gems do
		if not inView(center, gem.x, gem.z) then
			if not gem.parked then
				gem.parked = true
				count += 1
				moveParts[count] = gem.part
				moveFrames[count] = PARKED
			end
			continue
		end
		gem.parked = false
		local bob = GEM_BOB * math.sin((now * GEM_BOB_HZ + gem.phase) * 2 * math.pi)
		count += 1
		moveParts[count] = gem.part
		moveFrames[count] = CFrame.new(gem.x, ground + GEM_RISE + bob, gem.z)
			* CFrame.Angles(0, now * GEM_SPIN + gem.phase * 6, 0)
			* GEM_TURN
	end

	for index = #flights, 1, -1 do
		local flight = flights[index]
		local progress = (now - flight.startedAt) / GEM_FLY_SECONDS
		local target = heroAt(flight.player, flight.from.X, flight.from.Z)
		if progress >= 1 then
			emit("shimmer", flight.color, target, GEM_SPARKLE)
			giveGem(flight.part)
			flights[index] = flights[#flights]
			flights[#flights] = nil
		else
			local position = flight.from:Lerp(target, progress * progress)
				+ UP * (math.sin(progress * math.pi) * 1.5)
			count += 1
			moveParts[count] = flight.part
			moveFrames[count] = CFrame.new(position) * GEM_TURN
		end
	end

	for index = #moveParts, count + 1, -1 do
		moveParts[index] = nil
		moveFrames[index] = nil
	end
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- A jagged bolt in `tint`: segments with kinks pushed off the straight
-- line, a white core in a halo, and a fork or two off the side.
local boltPoints: { Vector3 } = {}

local function showLightning(from: Vector3, to: Vector3, tint: Tint)
	local along = to - from
	local length = along.Magnitude
	if length < 0.1 then
		return
	end
	local direction = along / length
	local sideA = direction:Cross(UP)
	sideA = if sideA.Magnitude < 1e-3 then Vector3.xAxis else sideA.Unit
	local sideB = direction:Cross(sideA).Unit
	local segments = math.clamp(math.ceil(length / LIGHTNING_STEP), 2, LIGHTNING_MAX_SEGMENTS)

	local previous = from
	for index = 1, segments do
		local point = to
		if index < segments then
			point = from
				+ along * (index / segments)
				+ sideA * random:NextNumber(-LIGHTNING_KINK, LIGHTNING_KINK)
				+ sideB * random:NextNumber(-LIGHTNING_KINK, LIGHTNING_KINK) * 0.5
		end
		showStreak(
			lightning,
			previous,
			point,
			tint.core,
			LIGHTNING_CORE_WIDTH,
			0,
			LIGHTNING_SECONDS,
			"flicker"
		)
		showStreak(
			lightning,
			previous,
			point,
			tint.color,
			LIGHTNING_HALO_WIDTH,
			LIGHTNING_HALO_FADE,
			LIGHTNING_SECONDS,
			"flicker"
		)
		boltPoints[index] = point
		previous = point
	end

	for _ = 1, random:NextInteger(FORK_MIN, FORK_MAX) do
		local base = boltPoints[random:NextInteger(1, segments - 1)]
		local spread = sideA * random:NextNumber(-FORK_SPREAD, FORK_SPREAD)
			+ sideB * random:NextNumber(-FORK_SPREAD, FORK_SPREAD) * 0.5
		local tip = base
			+ (direction + spread).Unit * random:NextNumber(FORK_MIN_LENGTH, FORK_MAX_LENGTH)
		local kink = (base + tip) / 2
			+ sideA * random:NextNumber(-LIGHTNING_KINK, LIGHTNING_KINK) * 0.5
		showStreak(lightning, base, kink, tint.core, FORK_WIDTH, 0, LIGHTNING_SECONDS, "flicker")
		showStreak(lightning, kink, tip, tint.core, FORK_WIDTH, 0, LIGHTNING_SECONDS, "flicker")
	end
	table.clear(boltPoints)
end

-- An explosion of `radius` studs in `tint`, its counts `scale` times the full.
local function showExplosion(x: number, z: number, radius: number, tint: Tint, scale: number)
	local centre = groundAt(x, z, EXPLOSION_RISE)
	if not onScreen(centre) then
		return
	end
	local diameter = radius * 2
	showGlow(centre, tint.core, 1, diameter * 0.6, 0, EXPLOSION_CORE_SECONDS)
	showGlow(
		centre,
		tint.color,
		radius,
		diameter * 1.1,
		EXPLOSION_GLOW_FADE,
		EXPLOSION_GLOW_SECONDS
	)
	showRing(
		x,
		z,
		tint.color,
		1,
		diameter * 1.15,
		EXPLOSION_RING_STUDS,
		0,
		0,
		EXPLOSION_RING_SECONDS
	)
	local area = Vector3.new(radius, 1, radius)
	emit("flash", tint.core, centre, EXPLOSION_FLASHES * scale)
	emit("blaze", tint.color, centre, EXPLOSION_FLAMES * scale, area)
	emit("embers", tint.color, centre, EXPLOSION_EMBERS * scale)
	emit("smoke", SMOKE_COLOR, centre, EXPLOSION_SMOKE * scale, area)
	showGround(
		x,
		z,
		Enum.Material.CrackedLava,
		SCORCH_COLOR,
		1,
		diameter * 0.8,
		SCORCH_FADE,
		SCORCH_SECONDS
	)
	showLight(
		centre,
		tint.color,
		EXPLOSION_LIGHT_BRIGHTNESS,
		diameter * 1.5,
		EXPLOSION_LIGHT_SECONDS
	)
end

-- A burst that is not fire: a disc and a ring of the radius in the tint, sparks.
local function showBurstDisc(x: number, z: number, radius: number, tint: Tint)
	local ground = groundAt(x, z, DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(x, z, tint.color, 1, diameter, SLAM_STUDS, 0, 0, SPLASH_SECONDS)
	showDisc(x, z, 1, diameter, SPLASH_SECONDS, tint.color, 0.5)
	emit("sparks", tint.color, ground + UP, SPLASH_SPARKS * BURST_SCALE * 2)
end

-- A nova from (x, z) in `tint`: a ring sweeping out to the radius, sparks and a light.
local function showNova(x: number, z: number, radius: number, tint: Tint)
	local ground = groundAt(x, z, DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(x, z, tint.color, 1, diameter, NOVA_RING_STUDS, 0, 0, NOVA_RING_SECONDS)
	showDisc(x, z, 1, diameter, NOVA_SWEEP_SECONDS, tint.core, NOVA_SWEEP_FADE)
	local area = Vector3.new(diameter * 0.9, 1, diameter * 0.9)
	emit("sparks", tint.color, ground + UP, NOVA_SPARKS, area)
	showLight(ground + UP * 2, tint.color, NOVA_LIGHT_BRIGHTNESS, diameter, NOVA_LIGHT_SECONDS)
end

-- An ice nova: the nova with spinning shards, mist, glints and frost left behind.
local function showFrostNova(x: number, z: number, radius: number)
	local ground = groundAt(x, z, DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(x, z, ICE.color, 1, diameter, NOVA_RING_STUDS, 0, 0, NOVA_RING_SECONDS)
	showDisc(x, z, 1, diameter, NOVA_SWEEP_SECONDS, ICE.core, NOVA_SWEEP_FADE)
	showShards(ground + UP * 1, NOVA_SHARDS, radius, ICE, 1, NOVA_SHARD_SECONDS)
	local area = Vector3.new(diameter * 0.9, 1, diameter * 0.9)
	emit("mist", ICE.color, ground + UP * 0.5, NOVA_MIST, area)
	emit("shimmer", ICE.core, ground + UP * 1, NOVA_GLINTS, area)
	showGround(x, z, Enum.Material.Ice, FROST_COLOR, 2, diameter, FROST_FADE, FROST_SECONDS)
	showLight(ground + UP * 2, ICE.color, NOVA_LIGHT_BRIGHTNESS, diameter, NOVA_LIGHT_SECONDS)
end

-- What a synergy looks like on the enemy it fired on, besides its name.
local function showSynergy(synergy: string, at: Vector3)
	local tint = SYNERGY_TINTS[synergy]
	local config = SYNERGY_CONFIGS[synergy]
	if tint == nil or config == nil then
		return
	end
	if config.kind == "spread" then
		-- The status spreads this far: a ring as wide as the reach.
		local reach = (config.radius or SYNERGY_RING_DIAMETER / 2) * 2
		showRing(at.X, at.Z, tint.color, 1, reach, SYNERGY_RING_STUDS, 0, 0, SYNERGY_RING_SECONDS)
		emit("embers", tint.color, at, SYNERGY_SPARKS)
		return
	end
	showRing(
		at.X,
		at.Z,
		tint.color,
		1,
		SYNERGY_RING_DIAMETER,
		SYNERGY_RING_STUDS,
		0,
		0,
		SYNERGY_RING_SECONDS
	)
	if config.status == "chilled" then
		showShards(at, SHATTER_SHARDS, SHATTER_REACH, tint, SHATTER_SCALE, NOVA_SHARD_SECONDS)
	else
		emit("shimmer", tint.color, at, SYNERGY_GLINTS, Vector3.new(3, 3, 3))
	end
end

local function showImpact(at: Vector3, tint: Tint, synergy: string?)
	if synergy then
		showGlow(at, tint.core, 0.5, SYNERGY_IMPACT_DIAMETER, 0.1, IMPACT_SECONDS * 1.5)
		emit("sparks", tint.color, at, SYNERGY_SPARKS)
		showSynergy(synergy, at)
	else
		showGlow(at, tint.core, 0.4, IMPACT_DIAMETER, 0.2, IMPACT_SECONDS)
		emit("sparks", tint.color, at, IMPACT_SPARKS)
	end
end

-- A slash: a tapered arc of streaks across the front of `at`, facing `facing`.
local function showSlash(at: Vector3, facing: number, radius: number, arc: number, color: Color3)
	local reach = radius * SLASH_REACH
	local half = arc / 2 * SLASH_ARC_SHARE
	local previous: Vector3? = nil
	for index = 0, SLASH_SEGMENTS do
		local angle = facing - half + 2 * half * index / SLASH_SEGMENTS
		local point = at + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
		if previous then
			local taper = math.sin(math.pi * (index - 0.5) / SLASH_SEGMENTS)
			showStreak(
				streaks,
				previous,
				point,
				color,
				SLASH_WIDTH * taper,
				0,
				SLASH_SECONDS,
				"fade"
			)
		end
		previous = point
	end
	local middle = at + Vector3.new(math.cos(facing), 0, math.sin(facing)) * reach
	emit("sparks", color, middle, SLASH_SPARKS)
end

-- A strike: a bar of light falling onto `at`, a flash and sparks.
local function showStrike(at: Vector3, tint: Tint)
	local top = at + UP * STRIKE_HEIGHT
	showStreak(streaks, top, at, tint.core, STRIKE_CORE_WIDTH, 0, STRIKE_SECONDS, "travel")
	showStreak(streaks, top, at, tint.color, STRIKE_SLEEVE_WIDTH, 0.5, STRIKE_SECONDS, "travel")
	showGlow(at, tint.core, 0.5, STRIKE_DIAMETER, 0.2, STRIKE_SECONDS)
	emit("sparks", tint.color, at, STRIKE_SPARKS)
end

-- A cone from `from` toward `facing`, `radius` long: streaks fanned across it.
local function showCone(from: Vector3, facing: number, radius: number, tint: Tint)
	local half = math.rad(Config.ranks.coneHalfAngleDegrees)
	local reach = radius * CONE_REACH
	local preset = if tint == ICE then "mist" elseif tint == FIRE then "blaze" else "sparks"
	for index = 0, CONE_STREAKS - 1 do
		local angle = facing - half + 2 * half * index / (CONE_STREAKS - 1)
		local tip = from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
		showStreak(
			streaks,
			from,
			tip,
			if index % 2 == 0 then tint.color else tint.core,
			CONE_WIDTH,
			CONE_FADE,
			CONE_SECONDS,
			"travel"
		)
		emit(preset, tint.color, tip, CONE_PARTICLES)
	end
end

-- A heal on the hero at `at`: a ring rising round it and motes.
local function showHeroHeal(at: Vector3, motes: number)
	showRing(
		at.X,
		at.Z,
		HEAL.color,
		HEAL_RING_FROM,
		HEAL_RING_TO,
		0.35,
		0,
		HEAL_RING_RISE,
		HEAL_SECONDS
	)
	emit("motes", HEAL.color, at, motes, Vector3.new(2, 3, 2))
end

type CastEvent = {
	player: number,
	skill: string,
	x: number,
	z: number,
	targetX: number?,
	targetZ: number?,
	radius: number,
	targets: { number },
}

-- A skill firing, drawn by how it targets in its first tag's tint. Ground
-- areas, totems and bursts have their own events; the barrier is drawn while
-- the snapshot shows it.
local function onCast(event: CastEvent)
	local skill = Config.skills[event.skill]
	if skill == nil then
		return
	end
	local from = heroAt(event.player, event.x, event.z)
	if not onScreen(from) then
		return
	end
	local tint = tintOf(event.skill)
	local targeting = skill.targeting
	local targetX, targetZ = event.targetX, event.targetZ
	local facing = if targetX and targetZ
		then math.atan2(targetZ - event.z, targetX - event.x)
		else 0

	if targeting == "bolt" or targeting == "scatter" or targeting == "orbit" then
		for _, id in event.targets do
			local at = EnemyView.position(id)
			if at == nil then
				continue
			end
			local hand = handOf(from, at)
			if targeting == "bolt" then
				showGlow(hand, tint.core, 0.3, MUZZLE_DIAMETER, 0.2, MUZZLE_SECONDS)
				local along = at - hand
				local tip = if skill.speed > 0 and along.Magnitude > BOLT_LEAD
					then hand + along.Unit * BOLT_LEAD
					else at
				showStreak(
					streaks,
					hand,
					tip,
					tint.core,
					BOLT_CORE_WIDTH,
					0,
					BOLT_SECONDS,
					"travel"
				)
				showStreak(
					streaks,
					hand,
					tip,
					tint.color,
					BOLT_SLEEVE_WIDTH,
					BOLT_SLEEVE_FADE,
					BOLT_SECONDS,
					"travel"
				)
			elseif targeting == "scatter" then
				showStreak(
					streaks,
					hand,
					at,
					tint.color,
					SCATTER_WIDTH,
					0.2,
					SCATTER_SECONDS,
					"travel"
				)
				showGlow(at, tint.core, 0.3, SCATTER_DIAMETER, 0.2, SCATTER_SECONDS)
			else
				showStreak(lightning, from, at, tint.core, ZAP_WIDTH, 0, ZAP_SECONDS, "flicker")
			end
		end
	elseif targeting == "strike" then
		for _, id in event.targets do
			local at = EnemyView.position(id)
			if at then
				showStrike(at, tint)
			end
		end
	elseif targeting == "melee" then
		showSlash(from, facing, skill.range, MELEE_ARC, tint.core)
	elseif targeting == "nova" then
		if skill.tags[1] == "ice" then
			showFrostNova(event.x, event.z, event.radius)
		else
			showNova(event.x, event.z, event.radius, tint)
		end
	elseif targeting == "cone" then
		showCone(from, facing, event.radius, tint)
	elseif targeting == "chain" then
		local previous = handOf(from, nil)
		for index, id in event.targets do
			local at = EnemyView.position(id)
			if at == nil then
				continue
			end
			showLightning(previous, at, tint)
			if index == 1 then
				showLight(
					at,
					tint.color,
					LIGHTNING_LIGHT_BRIGHTNESS,
					LIGHTNING_LIGHT_RANGE,
					LIGHTNING_SECONDS
				)
			end
			previous = at
		end
	elseif targeting == "aura" then
		local diameter = event.radius * 2
		showRing(
			event.x,
			event.z,
			tint.color,
			diameter * AURA_FROM,
			diameter,
			AURA_STUDS,
			AURA_FADE,
			0,
			AURA_SECONDS
		)
	elseif targeting == "shield" then
		showGlow(from, BARRIER.core, 1, SHIELD_DIAMETER, 0.3, BOLT_SECONDS * 2)
		emit("shimmer", BARRIER.color, from, ABSORB_GLINTS, Vector3.new(4, 4, 4))
	elseif targeting == "heal" then
		showHeroHeal(from, HEAL_MOTES)
	elseif targeting == "thorns" then
		showShards(from, THORN_SHARDS, THORN_REACH, tint, THORN_SCALE, THORN_SECONDS)
		local ground = groundAt(from.X, from.Z, 0)
		showRing(
			ground.X,
			ground.Z,
			tint.color,
			1,
			THORN_RING_DIAMETER,
			SLAM_STUDS,
			0,
			0,
			THORN_SECONDS
		)
	end
end

type HitEvent = {
	source: number,
	enemyId: number,
	amount: number,
	skill: string,
	crit: boolean,
	synergy: string?,
	blocked: boolean,
}

local function onHit(event: HitEvent)
	local enemyId = event.enemyId
	local at = EnemyView.position(enemyId)
	if at == nil then
		return
	end
	local visible = onScreen(at)
	local dot = DOT_TINTS[event.skill]
	local skill = Config.skills[event.skill]

	if event.blocked then
		if visible then
			local shield = at + forwardOf(enemyId) * BLOCK_REACH
			showGlow(shield, SHIELD_COLOR, 0.3, BLOCK_DIAMETER, 0.3, BLOCK_SECONDS)
			emit("sparks", SHIELD_COLOR, shield, BLOCK_SPARKS)
			showShards(
				shield,
				BLOCK_SHARDS,
				SHATTER_REACH * 0.5,
				tintFrom(SHIELD_COLOR),
				BLOCK_SHARD_SCALE,
				SYNERGY_RING_SECONDS
			)
			showNumber(at, "Blocked", BLOCKED_COLOR, NUMBER_TEXT_SIZE)
		end
		return
	end

	if dot then
		if visible then
			showNumber(at, tostring(math.round(event.amount)), dot.color, DOT_TEXT_SIZE)
		end
		return
	end
	EnemyView.flash(enemyId)
	if skill == nil or not NO_HIT_STOP[skill.targeting] then
		EnemyView.hitStop(enemyId, HIT_STOP_SECONDS)
	end
	if not visible then
		return
	end
	local synergy = event.synergy
	showImpact(at, tintOf(event.skill), synergy)
	local amount = tostring(math.round(event.amount))
	if synergy then
		local name = SYNERGY_NAMES[synergy] or synergy
		showNumber(at, name .. "! " .. amount, SYNERGY_COLOR, SYNERGY_TEXT_SIZE)
	elseif event.crit then
		showNumber(at, amount .. "!", CRIT_COLOR, CRIT_TEXT_SIZE)
	else
		showNumber(at, amount, NUMBER_COLOR, NUMBER_TEXT_SIZE)
	end
end

local function onBurst(x: number, z: number, radius: number, source: string)
	local skill = Config.skills[source]
	if skill == nil then
		-- An enemy's shot landing with a splash, in the kind's colour.
		showBurstDisc(x, z, radius, kindTint(source))
		return
	end
	local tag = skill.tags[1]
	local tint = tintOf(source)
	if tag == "fire" then
		showExplosion(x, z, radius, tint, if skill.targeting == "bolt" then BURST_SCALE else 1)
	elseif tag == "ice" then
		showFrostNova(x, z, radius)
	else
		showBurstDisc(x, z, radius, tint)
	end
	if tag == "fire" and skill.targeting ~= "bolt" and nearLocal(x, z) then
		Camera.shake(BURST_SHAKE)
	end
end

type EnemyAttackEvent = {
	enemyId: number,
	enemyKind: string,
	attackKind: Types.AttackKind,
	x: number,
	z: number,
	radius: number,
}

local function onEnemyAttack(event: EnemyAttackEvent)
	local enemyId = event.enemyId
	local x, z, radius = event.x, event.z, event.radius
	local at = EnemyView.position(enemyId) or groundAt(x, z, 1)
	if not onScreen(at) then
		return
	end
	local tint = kindTint(event.enemyKind)
	local kind = event.attackKind
	local ground = groundAt(x, z, DISC_HEIGHT)
	if kind == "melee" then
		local attack = attackOf(event.enemyKind, "melee")
		local arc = if attack then attack.arcDegrees or 360 else 360
		if arc < 360 then
			showSlash(at, enemyFacing[enemyId] or 0, radius, math.rad(arc), WHITE)
		else
			showRing(x, z, WHITE, 1, radius * 2, SLAM_STUDS, 0, 0, SLAM_SECONDS)
			emit("puff", PUFF_COLOR, ground + UP, SLAM_PUFFS, Vector3.new(radius, 1, radius))
		end
	elseif kind == "projectile" then
		local mouth = at + forwardOf(enemyId) * MOUTH_FORWARD + UP * MOUTH_RISE
		emit("sparks", tint.color, mouth, MUZZLE_PUFFS)
	elseif kind == "burst" or kind == "leap" then
		showRing(x, z, tint.color, 1, radius * 2, SLAM_STUDS, 0, 0, SLAM_SECONDS)
		showDisc(x, z, 1, radius * 2, SLAM_SECONDS, tint.color, 0.5)
		emit("puff", DUST_COLOR, ground + UP, SLAM_PUFFS, Vector3.new(radius, 1, radius))
		if kind == "leap" and nearLocal(x, z) then
			Camera.shake(BURST_SHAKE)
		end
	elseif kind == "charge" then
		emit("puff", DUST_COLOR, ground + UP, CHARGE_PUFFS, Vector3.new(3, 1, 3))
	elseif kind == "summon" then
		local reach = math.max(radius, SUMMON_MIN_RADIUS) * 2
		showRing(x, z, SUMMON_TINT.color, 1, reach, SLAM_STUDS, 0, 0, SLAM_SECONDS)
		emit("motes", SUMMON_TINT.color, ground + UP, SUMMON_MOTES, Vector3.new(reach, 1, reach))
	end
end

-- A kill: the body dissolves (EnemyView), a puff and motes in the kind's colour.
local function onKill(enemyId: number, kindId: string, x: number, z: number)
	local at = EnemyView.position(enemyId) or groundAt(x, z, 1)
	if not onScreen(at) then
		return
	end
	local tint = kindTint(kindId)
	emit("puff", tint.color, at, KILL_PUFFS)
	emit("motes", tint.color, at, KILL_MOTES, Vector3.new(2, 2, 2))
	showGlow(at, tint.core, 1, KILL_FLASH_DIAMETER, 0.5, KILL_FLASH_SECONDS)
end

-- A boss arriving: a column of light on it and a shockwave on the ground.
local function showBossArrival(enemyId: number): boolean
	local at = EnemyView.position(enemyId)
	if at == nil then
		return false
	end
	local ground = groundAt(at.X, at.Z, 0)
	if onScreen(ground) then
		local top = ground + UP * BOSS_COLUMN_HEIGHT
		showStreak(
			streaks,
			ground,
			top,
			DANGER.color,
			BOSS_COLUMN_WIDTH,
			COLUMN_FADE,
			COLUMN_SECONDS,
			"fade"
		)
		showStreak(streaks, ground, top, DANGER.core, COLUMN_CORE_WIDTH, 0, COLUMN_SECONDS, "fade")
		showRing(
			at.X,
			at.Z,
			DANGER.color,
			2,
			BOSS_WAVE_DIAMETER,
			BOSS_WAVE_STUDS,
			0,
			0,
			BOSS_WAVE_SECONDS
		)
		emit("smoke", SMOKE_COLOR, ground + UP, DEATH_SMOKE, Vector3.new(8, 1, 8))
		showLight(ground + UP * 4, DANGER.color, EXPLOSION_LIGHT_BRIGHTNESS, 40, COLUMN_SECONDS)
	end
	if nearLocal(at.X, at.Z) then
		Camera.shake(BOSS_SHAKE)
	end
	return true
end

local function onBossPhase(enemyId: number)
	local at = EnemyView.position(enemyId)
	if at == nil or not onScreen(at) then
		return
	end
	local size = (EnemyView.height(enemyId) or 6) * PHASE_FLASH_SHARE
	showGlow(at, DANGER.color, size * 0.5, size, 0.3, PHASE_SECONDS)
	showRing(at.X, at.Z, DANGER.color, 2, BOSS_WAVE_DIAMETER, BOSS_WAVE_STUDS, 0, 0, PHASE_SECONDS)
	emit("embers", DANGER.color, at, EXPLOSION_EMBERS)
	showLight(at, DANGER.color, EXPLOSION_LIGHT_BRIGHTNESS, size * 3, PHASE_SECONDS)
	if nearLocal(at.X, at.Z) then
		Camera.shake(BOSS_SHAKE)
	end
end

local function onExtracted(player: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	local ground = groundAt(position.X, position.Z, 0)
	local top = ground + UP * COLUMN_HEIGHT
	showStreak(
		streaks,
		ground,
		top,
		PORTAL_TINT.color,
		COLUMN_WIDTH,
		COLUMN_FADE,
		COLUMN_SECONDS,
		"fade"
	)
	showStreak(streaks, ground, top, WHITE, COLUMN_CORE_WIDTH, 0, COLUMN_SECONDS, "fade")
	emit("motes", PORTAL_TINT.core, position, COLUMN_MOTES, Vector3.new(3, 5, 3))
	showLight(position, PORTAL_TINT.color, EXPLOSION_LIGHT_BRIGHTNESS, 30, COLUMN_SECONDS)
	local character = root.Parent
	if character then
		local parts: { BasePart } = {}
		for _, item in character:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
			end
		end
		table.insert(fades, { parts = parts, startedAt = os.clock() })
	end
end

local function onDied(player: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	if onScreen(position) then
		showGlow(position, SHADOW.color, 1, DEATH_DIAMETER, 0.2, DEATH_SECONDS)
		showRing(
			position.X,
			position.Z,
			DANGER.color,
			1,
			DEATH_DIAMETER * 2,
			SLAM_STUDS,
			0,
			0,
			DEATH_SECONDS
		)
		emit("smoke", SHADOW.color, position, DEATH_SMOKE, Vector3.new(3, 3, 3))
		emit("embers", DANGER.color, position, KILL_MOTES)
	end
	if player == Players.LocalPlayer.UserId then
		Camera.shake(EXPLOSION_SHAKE)
	end
end

local function onPlayerHurt(player: number, amount: number, absorbed: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	if absorbed > 0 then
		showGlow(position, BARRIER.core, 1, ABSORB_DIAMETER, 0.6, BLOCK_SECONDS * 2)
		emit("shimmer", BARRIER.color, position, ABSORB_GLINTS, Vector3.new(4, 4, 4))
	end
	if amount > 0 then
		if onScreen(position) then
			showShards(position, HURT_SHARDS, 3, DANGER, HURT_SHARD_SCALE, HURT_SHARD_SECONDS)
		end
		if player == Players.LocalPlayer.UserId then
			Camera.shake(math.min(HURT_SHAKE + amount * HURT_SHAKE_PER_DAMAGE, HURT_SHAKE_MAX))
		end
	end
end

-- Puts a hero-centred effect at the player's character: motes, a heal.
local function atHero(player: number): Vector3?
	local root = characterRoot(player)
	if root and onScreen(root.Position) then
		return root.Position
	end
	return nil
end

local function onUtility(player: number, utilityId: string)
	local utility = UTILITIES[utilityId]
	local at = atHero(player)
	if utility == nil or at == nil then
		return
	end
	if utility.kind == "sprint" then
		local ground = groundAt(at.X, at.Z, 0)
		emit("puff", DUST_COLOR, ground + UP, KNOCK_PUFFS, Vector3.new(2, 1, 2))
		showRing(
			ground.X,
			ground.Z,
			WHITE,
			1,
			SHIELD_DIAMETER,
			SLAM_STUDS * 0.5,
			0.3,
			0,
			AURA_SECONDS
		)
		sprinting[player] = sprinting[player] or 0
	elseif utility.kind == "barrier" then
		showGlow(at, BARRIER.core, 1, SHIELD_DIAMETER, 0.3, BOLT_SECONDS * 2)
		emit("shimmer", BARRIER.color, at, ABSORB_GLINTS, Vector3.new(4, 4, 4))
	else
		showHeroHeal(at, HEAL_MOTES)
	end
end

local function chestPosition(): Vector3?
	local latest = Net.latest
	if latest == nil then
		return nil
	end
	local chest = latest.world.chest
	return groundAt(chest.x, chest.z, 1)
end

local function onEvents(events: { Types.Event }, _self: Protocol.SelfView?)
	for _, event in events do
		if event.kind == "cast" then
			onCast(event)
		elseif event.kind == "hit" then
			onHit(event)
		elseif event.kind == "burst" then
			onBurst(event.x, event.z, event.radius, event.skill)
		elseif event.kind == "areaPlaced" then
			placeArea(
				event.id,
				event.owner,
				event.areaKind,
				event.x,
				event.z,
				event.radius,
				event.seconds
			)
		elseif event.kind == "totemPlaced" then
			placeTotem(event.id, event.skill, event.x, event.z, event.seconds)
			local ground = groundAt(event.x, event.z, 1)
			if onScreen(ground) then
				local tint = tintOf(event.skill)
				showRing(event.x, event.z, tint.color, 1, 6, SLAM_STUDS, 0, 0, SLAM_SECONDS)
				emit("motes", tint.color, ground, WIND_UP_MOTES * 2, Vector3.new(2, 4, 2))
			end
		elseif event.kind == "statusApplied" then
			EnemyView.markStatus(event.enemyId, event.status, event.seconds)
			local at = EnemyView.position(event.enemyId)
			local tint = STATUS_TINTS[event.status]
			if at and tint and onScreen(at) then
				showGlow(at, tint.color, 0.5, STATUS_DIAMETER, STATUS_FADE, STATUS_SECONDS)
			end
		elseif event.kind == "kill" then
			removeMarker(event.enemyId)
			onKill(event.enemyId, event.enemyKind, event.x, event.z)
		elseif event.kind == "playerHurt" then
			onPlayerHurt(event.player, event.amount, event.absorbed)
		elseif event.kind == "knockback" then
			local at = atHero(event.player)
			if at then
				emit("puff", DUST_COLOR, at - UP * 2, KNOCK_PUFFS, Vector3.new(2, 1, 2))
			end
		elseif event.kind == "healed" then
			local at = atHero(event.player)
			if at then
				emit("motes", HEAL.color, at, HERO_HEALED_MOTES, Vector3.new(2, 3, 2))
			end
		elseif event.kind == "utility" then
			onUtility(event.player, event.utility)
		elseif event.kind == "telegraph" then
			showTelegraph(event)
		elseif event.kind == "enemyAttack" then
			removeMarker(event.enemyId)
			onEnemyAttack(event)
		elseif event.kind == "exploded" then
			removeMarker(event.enemyId)
			showExplosion(event.x, event.z, event.radius, EXPLODER, EXPLODER_SCALE)
			if nearLocal(event.x, event.z) then
				Camera.shake(EXPLOSION_SHAKE)
			end
		elseif event.kind == "enemyHealed" then
			local at = EnemyView.position(event.enemyId)
			if at and onScreen(at) then
				emit("motes", HEAL.color, at, HEALED_MOTES, Vector3.new(2, 2, 2))
			end
		elseif event.kind == "bossSpawned" then
			if not showBossArrival(event.enemyId) then
				pendingBosses[event.enemyId] = os.clock()
			end
		elseif event.kind == "bossPhase" then
			onBossPhase(event.enemyId)
		elseif event.kind == "closingRing" then
			local root = localRoot()
			if root then
				local diameter = Config.horde.ringRadius * 2
				local position = root.Position
				showRing(
					position.X,
					position.Z,
					DANGER.color,
					diameter * CLOSING_FROM,
					diameter,
					CLOSING_STUDS,
					0.1,
					0,
					CLOSING_SECONDS
				)
			end
		elseif event.kind == "crystalCollected" then
			collectGem(event.id, event.player)
		elseif event.kind == "foodEaten" then
			local at = atHero(event.player)
			if at then
				emit("motes", HEAL.color, at, FOOD_MOTES, Vector3.new(2, 3, 2))
			end
		elseif event.kind == "chestOpened" then
			local at = chestPosition()
			if at and onScreen(at) then
				emit("sparks", GOLD.color, at, CHEST_SPARKS, Vector3.new(2, 1, 2))
				emit("embers", GOLD.color, at, CHEST_EMBERS)
				showGlow(at, GOLD.core, 1, 6, 0.3, KILL_FLASH_SECONDS * 2)
				showLight(at, GOLD.color, EXPLOSION_LIGHT_BRIGHTNESS, 24, EXPLOSION_LIGHT_SECONDS)
			end
		elseif event.kind == "castStarted" then
			startCast(event.player, event.seconds)
		elseif event.kind == "castInterrupted" then
			local at = atHero(event.player)
			endCast(event.player)
			if at then
				showShards(at - UP * 2, CAST_SHARDS, 4, PORTAL_TINT, THORN_SCALE, THORN_SECONDS)
				emit("implosion", PORTAL_TINT.color, at, 1)
			end
		elseif event.kind == "portalOpened" then
			openPortal(event.x, event.z, event.seconds)
			local ground = groundAt(event.x, event.z, 1)
			if onScreen(ground) then
				showRing(
					event.x,
					event.z,
					PORTAL_TINT.color,
					1,
					BOSS_WAVE_DIAMETER * 0.5,
					BOSS_WAVE_STUDS,
					0,
					0,
					BOSS_WAVE_SECONDS
				)
				emit("motes", PORTAL_TINT.core, ground, COLUMN_MOTES, Vector3.new(6, 2, 6))
			end
		elseif event.kind == "portalClosed" then
			closePortal()
		elseif event.kind == "extracted" then
			endCast(event.player)
			onExtracted(event.player)
		elseif event.kind == "died" then
			endCast(event.player)
			onDied(event.player)
		elseif event.kind == "levelUp" then
			local at = atHero(event.player)
			if at then
				showRing(at.X, at.Z, GOLD.color, 2, 6, 0.4, 0, HEAL_RING_RISE, LEVEL_SECONDS)
				emit("motes", GOLD.color, at, LEVEL_MOTES, Vector3.new(2, 3, 2))
			end
		end
		-- The rest is the Hud's: offers, cards, the compass, the timers, the end.
	end
end

local function syncEnemies(snapshot: Net.Snapshot)
	table.clear(enemyFacing)
	table.clear(enemyKind)
	for _, enemy in snapshot.enemies do
		enemyFacing[enemy.id] = enemy.facing
		enemyKind[enemy.id] = enemy.kind
	end
	local now = os.clock()
	for id, at in pendingBosses do
		if showBossArrival(id) or now - at > BOSS_WAIT then
			pendingBosses[id] = nil
		end
	end
end

local function onWorld(snapshot: Net.Snapshot)
	syncEnemies(snapshot)
	syncTracked(snapshot)
	local world = snapshot.world
	syncFoods(world.foods)
	syncAreas(world.areas)
	syncTotems(world.totems)
	syncPortal(world.portal)
	syncChest(world)
	syncPlayers(world.players)
end

function Effects.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace

	for _ = 1, PREWARM_GEMS do
		table.insert(freeGems, newGemPart())
	end
	Net.onEvents(onEvents)
	Net.onWorld(onWorld)
	local latest = Net.latest
	if latest then
		onWorld(latest)
	end
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		step()
		stepMarkers()
		renderTracked(now)
		stepAreas(now)
		stepTotems(now)
		renderPortal(now)
		renderBeam(now)
		followShields()
		stepSprint(now)
		stepCasts(now)
		stepFades(now)
	end)
end

return Effects
