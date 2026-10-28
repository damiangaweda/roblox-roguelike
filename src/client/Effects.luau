--!strict
-- Combat and world effects: skills, hits, statuses, state.bursts, areas, totems,
-- telegraphs, projectiles, crystals, food, the chest's state.beam, the extraction
-- spell and its state.portal, a dash's afterimages and a shrine's activation
-- (the server draws the shrines themselves). Everything here is drawn from events and snapshots
-- the server sent; nothing is decided on the client (AGENTS.md rule 1).
-- Every effect comes from a pool with a cap, particles are thrown in state.bursts
-- from pooled hosts and state.lights are capped, so the frame budget holds however
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

-- The look's constants, by family (one local each keeps the chunk inside
-- Luau's 200 registers): colours, Config-derived lookups, shapes and frames,
-- the pooled primitives, skills, hero and enemy moments, telegraphs, and the
-- world's objects.
local PALETTE = {}
local DATA = {}
local SHAPE = {}
local DRAW = {}
local SKILL = {}
local WORLD = {}
local TELEGRAPH = {}
local OBJECT = {}
-- The module's mutable state: pools, trackers, markers and the drawn objects.
local state = {}
-- The effects and handlers past the primitives, as one table of functions.
local fx = {}

-- The palette: one tint per tag, reused by every effect of it. `color` is the
-- tag's own; `core` the near-white centre of its flashes.
type Tint = { color: Color3, core: Color3 }
PALETTE.WHITE = Color3.new(1, 1, 1)

local function rgb(r: number, g: number, b: number, cr: number, cg: number, cb: number): Tint
	return { color = Color3.fromRGB(r, g, b), core = Color3.fromRGB(cr, cg, cb) }
end

PALETTE.FIRE = rgb(255, 95, 30, 255, 225, 150)
PALETTE.ICE = rgb(150, 215, 255, 235, 250, 255)
PALETTE.LIGHTNING = rgb(255, 238, 100, 255, 255, 235)
PALETTE.ARCANE = rgb(165, 85, 255, 240, 225, 255)
PALETTE.PHYSICAL = rgb(205, 215, 230, 255, 255, 255)
PALETTE.BLEED = rgb(200, 20, 45, 255, 170, 170)
PALETTE.POISON = rgb(150, 255, 40, 225, 255, 180)
PALETTE.NATURE = rgb(80, 200, 60, 210, 255, 190)
PALETTE.TAG_TINTS = {
	fire = PALETTE.FIRE,
	ice = PALETTE.ICE,
	lightning = PALETTE.LIGHTNING,
	arcane = PALETTE.ARCANE,
	physical = PALETTE.PHYSICAL,
	bleed = PALETTE.BLEED,
	poison = PALETTE.POISON,
	nature = PALETTE.NATURE,
} :: { [string]: Tint }
-- Damage-over-time ticks arrive as hits named by their status.
PALETTE.DOT_TINTS = {
	burning = PALETTE.FIRE,
	bleeding = PALETTE.BLEED,
	poisoned = PALETTE.POISON,
} :: { [string]: Tint }
-- A status put on an enemy flashes in its colour.
PALETTE.STATUS_TINTS = {
	slowed = PALETTE.ICE,
	chilled = PALETTE.ICE,
	rooted = PALETTE.NATURE,
	stunned = PALETTE.LIGHTNING,
	feared = rgb(165, 90, 230, 235, 210, 255),
	weakened = rgb(140, 140, 140, 220, 220, 220),
	burning = PALETTE.FIRE,
	bleeding = PALETTE.BLEED,
	poisoned = PALETTE.POISON,
} :: { [string]: Tint }
-- The enemies' own: the exploder's blast, the heal, and the gold, danger and
-- shadow of the run's big moments.
PALETTE.EXPLODER = rgb(255, 70, 30, 255, 210, 160)
PALETTE.HEAL = rgb(90, 255, 130, 215, 255, 225)
PALETTE.GOLD = rgb(255, 200, 60, 255, 245, 200)
PALETTE.DANGER = rgb(255, 40, 40, 255, 190, 170)
PALETTE.SHADOW = rgb(45, 20, 55, 130, 90, 150)
PALETTE.BARRIER = rgb(140, 200, 255, 225, 245, 255)
-- Plain colours: a grey block, grey smoke, pale puffs, scorched and frosted ground.
PALETTE.SHIELD_COLOR = Color3.fromRGB(175, 180, 190)
PALETTE.SMOKE_COLOR = Color3.fromRGB(70, 66, 62)
PALETTE.PUFF_COLOR = Color3.fromRGB(220, 215, 225)
PALETTE.DUST_COLOR = Color3.fromRGB(150, 130, 100)
PALETTE.SCORCH_COLOR = Color3.fromRGB(60, 30, 18)
PALETTE.FROST_COLOR = Color3.fromRGB(205, 235, 255)
PALETTE.WOOD_COLOR = Color3.fromRGB(105, 72, 44)
PALETTE.MEAT_COLOR = Color3.fromRGB(170, 70, 50)
PALETTE.BONE_COLOR = Color3.fromRGB(240, 232, 214)

-- Textures that ship with the engine; no store assets.
PALETTE.SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
PALETTE.EMBER_TEXTURE = "rbxasset://textures/particles/fire_sparks_main.dds"
PALETTE.FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
PALETTE.SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
PALETTE.FLASH_TEXTURE = "rbxasset://textures/particles/explosion01_core_main.dds"
PALETTE.IMPLOSION_TEXTURE = "rbxasset://textures/particles/explosion01_implosion_main.dds"
PALETTE.GLOW_TEXTURE = "rbxasset://textures/particles/forcefield_glow_main.dds"

-- Effects farther than this from the camera are not drawn at all.
DRAW.VIEW_RANGE = 160
-- How long a skill hit holds the enemy still (the hit-stop).
SKILL.HIT_STOP_SECONDS = 0.07
-- Skills that hit everything near the hero every moment hold nothing still.
DATA.NO_HIT_STOP = { aura = true, orbit = true, thorns = true } :: { [string]: boolean }

-- Pool sizes: the most of each kind alive at once; a new one past the cap
-- reuses the oldest.
DRAW.STREAK_POOL = 160
DRAW.LIGHTNING_POOL = 160
DRAW.GLOW_POOL = 64
DRAW.RING_POOL = 40
DRAW.DISC_POOL = 32
DRAW.GROUND_POOL = 16
DRAW.SHARD_POOL = 64
DRAW.NUMBER_POOL = 60
-- Flash state.lights at once. With DRAW.TRACKED_LIGHTS, the state.portal's and the bosses'
-- this keeps the PointLights near a dozen.
DRAW.LIGHT_POOL = 5
DRAW.TRACKED_LIGHTS = 4
-- Areas drawn at once; past it the oldest goes.
DRAW.AREA_CAP = 24

-- Streaks: neon bars between two points (bolts, slashes, state.lightning, beams).
-- They end this share of their width wide; anything shorter is not drawn.
DRAW.STREAK_THIN = 0.3
DRAW.MIN_STREAK = 0.05
-- A travelling streak's head reaches the end in this share of its life; the
-- tail follows over the whole of it.
DRAW.TRAVEL_HEAD = 0.3
-- How much a flickering streak's transparency jumps frame to frame.
DRAW.FLICKER = 0.35

-- The hero's middle stands this high when its character is not there yet;
-- its hands this far above the root and towards the target.
SKILL.HERO_RISE = 2.5
SKILL.HAND_RISE = 0.6
SKILL.HAND_REACH = 1.2

-- A bolt cast: a flash at the hand and a short streak toward each target;
-- the projectile itself is a tracked part.
SKILL.BOLT_SECONDS = 0.14
SKILL.BOLT_LEAD = 5
SKILL.BOLT_CORE_WIDTH = 0.3
SKILL.BOLT_SLEEVE_WIDTH = 0.9
SKILL.BOLT_SLEEVE_FADE = 0.45
SKILL.MUZZLE_SECONDS = 0.1
SKILL.MUZZLE_DIAMETER = 1.4
-- A strike: a bar of light falling onto the target, a flash and sparks.
SKILL.STRIKE_HEIGHT = 14
SKILL.STRIKE_SECONDS = 0.18
SKILL.STRIKE_CORE_WIDTH = 0.5
SKILL.STRIKE_SLEEVE_WIDTH = 1.6
SKILL.STRIKE_DIAMETER = 3.2
SKILL.STRIKE_SPARKS = 10
-- A melee swing: a slash across this arc in front of the hero.
SKILL.MELEE_ARC = math.rad(150)
-- A cone: travelling state.streaks fanned across it, ending in particles.
SKILL.CONE_STREAKS = 7
SKILL.CONE_SECONDS = 0.28
SKILL.CONE_WIDTH = 1.4
SKILL.CONE_FADE = 0.35
SKILL.CONE_REACH = 0.9
SKILL.CONE_PARTICLES = 4
-- A scatter: thin state.streaks to each target and a small flash there.
SKILL.SCATTER_WIDTH = 0.35
SKILL.SCATTER_SECONDS = 0.16
SKILL.SCATTER_DIAMETER = 1.6
-- An aura's pulse: a faint ring at its edge.
SKILL.AURA_SECONDS = 0.35
SKILL.AURA_STUDS = 0.35
SKILL.AURA_FADE = 0.55
SKILL.AURA_FROM = 0.85
-- An orbit's zap: a thin flickering streak to each target.
SKILL.ZAP_WIDTH = 0.25
SKILL.ZAP_SECONDS = 0.12
-- Thorns: spikes thrown out round the hero and a ring.
SKILL.THORN_SHARDS = 10
SKILL.THORN_REACH = 4
SKILL.THORN_SCALE = 0.45
SKILL.THORN_SECONDS = 0.35
SKILL.THORN_RING_DIAMETER = 8
-- A self heal: motes rising off the hero.
SKILL.HEAL_MOTES = 16
SKILL.HEAL_SECONDS = 0.7
SKILL.HEAL_RING_FROM = 2
SKILL.HEAL_RING_TO = 5
SKILL.HEAL_RING_RISE = 4

-- Hit impacts: a flash at the enemy and sparks in the skill's tint.
SKILL.IMPACT_SECONDS = 0.12
SKILL.IMPACT_DIAMETER = 1.8
SKILL.IMPACT_SPARKS = 8
SKILL.SYNERGY_IMPACT_DIAMETER = 3.6
SKILL.SYNERGY_SPARKS = 20
SKILL.BLOCK_SECONDS = 0.1
SKILL.BLOCK_DIAMETER = 1.2
SKILL.BLOCK_SPARKS = 7
SKILL.BLOCK_SHARDS = 2
SKILL.BLOCK_SHARD_SCALE = 0.35
-- How far in front of an enemy's centre its shield is.
SKILL.BLOCK_REACH = 1.5
-- A status landing: a small flash in its colour.
SKILL.STATUS_SECONDS = 0.2
SKILL.STATUS_DIAMETER = 2.4
SKILL.STATUS_FADE = 0.55

-- Synergies: a ring on the ground in the synergy's tint, plus its own extra.
SKILL.SYNERGY_RING_SECONDS = 0.35
SKILL.SYNERGY_RING_DIAMETER = 7
SKILL.SYNERGY_RING_STUDS = 0.4
SKILL.SHATTER_SHARDS = 6
SKILL.SHATTER_REACH = 4
SKILL.SHATTER_SCALE = 0.6
SKILL.SYNERGY_GLINTS = 14

-- Lightning: a jagged bolt of short segments, a core in a halo, with forks
-- off it; a light where it starts.
SKILL.LIGHTNING_SECONDS = 0.22
SKILL.LIGHTNING_STEP = 2.5
SKILL.LIGHTNING_MAX_SEGMENTS = 10
SKILL.LIGHTNING_KINK = 0.9
SKILL.LIGHTNING_CORE_WIDTH = 0.22
SKILL.LIGHTNING_HALO_WIDTH = 0.75
SKILL.LIGHTNING_HALO_FADE = 0.55
SKILL.FORK_MIN = 1
SKILL.FORK_MAX = 2
SKILL.FORK_MIN_LENGTH = 1.5
SKILL.FORK_MAX_LENGTH = 3.5
SKILL.FORK_SPREAD = 1.2
SKILL.FORK_WIDTH = 0.14
SKILL.LIGHTNING_LIGHT_BRIGHTNESS = 5
SKILL.LIGHTNING_LIGHT_RANGE = 18

-- Explosions (fire state.bursts, the exploder): a core flash, a wider glow, a
-- shockwave ring, flames, embers, smoke, a light and scorched ground. Sizes
-- follow the burst radius; counts are multiplied by the explosion's scale.
SKILL.EXPLOSION_RISE = 1.5
SKILL.EXPLOSION_CORE_SECONDS = 0.22
SKILL.EXPLOSION_GLOW_SECONDS = 0.38
SKILL.EXPLOSION_GLOW_FADE = 0.55
SKILL.EXPLOSION_RING_SECONDS = 0.4
SKILL.EXPLOSION_RING_STUDS = 0.7
SKILL.EXPLOSION_FLAMES = 14
SKILL.EXPLOSION_EMBERS = 26
SKILL.EXPLOSION_SMOKE = 9
SKILL.EXPLOSION_FLASHES = 3
SKILL.EXPLOSION_LIGHT_SECONDS = 0.45
SKILL.EXPLOSION_LIGHT_BRIGHTNESS = 7
SKILL.SCORCH_SECONDS = 2.6
SKILL.SCORCH_FADE = 0.15
-- The exploder's blast and a non-fire burst against a fire burst.
SKILL.EXPLODER_SCALE = 0.6
SKILL.BURST_SCALE = 0.6

-- Novas: an expanding ring, a pale fx.sweep, particles and a light; an ice nova
-- adds spinning state.shards, mist and frost left on the ground.
SKILL.NOVA_RING_SECONDS = 0.35
SKILL.NOVA_RING_STUDS = 0.55
SKILL.NOVA_SWEEP_SECONDS = 0.3
SKILL.NOVA_SWEEP_FADE = 0.55
SKILL.NOVA_SHARDS = 10
SKILL.NOVA_SHARD_SECONDS = 0.45
SKILL.NOVA_MIST = 18
SKILL.NOVA_GLINTS = 16
SKILL.NOVA_SPARKS = 14
SKILL.FROST_SECONDS = 2.6
SKILL.FROST_FADE = 0.35
SKILL.NOVA_LIGHT_BRIGHTNESS = 4
SKILL.NOVA_LIGHT_SECONDS = 0.4
-- Ice state.shards: tall neon wedges that fly out, rise a little, tilt and spin.
SKILL.SHARD_SIZE = Vector3.new(0.5, 2.6, 1.2)
SKILL.SHARD_LIFT = 1.2
SKILL.SHARD_TILT = 1.1
SKILL.SHARD_SPIN = 4
SKILL.SHARD_FADE = 0.1

-- Kills: a puff and motes in the kind's colour and a small flash.
WORLD.KILL_MOTES = 10
WORLD.KILL_PUFFS = 5
WORLD.KILL_FLASH_DIAMETER = 3
WORLD.KILL_FLASH_SECONDS = 0.25

-- The hero hurt: red state.shards and a shake that grows with the hit.
WORLD.HURT_SHARDS = 5
WORLD.HURT_SHARD_SCALE = 0.35
WORLD.HURT_SHARD_SECONDS = 0.35
WORLD.HURT_SHAKE = 0.3
WORLD.HURT_SHAKE_PER_DAMAGE = 0.02
WORLD.HURT_SHAKE_MAX = 1.2
-- Damage the barrier took: a shimmer round the hero.
WORLD.ABSORB_GLINTS = 12
WORLD.ABSORB_DIAMETER = 6
-- Knocked back: dust at the feet.
WORLD.KNOCK_PUFFS = 5
-- The shaman's heal landing on an enemy; the hero healed; food eaten.
WORLD.HEALED_MOTES = 6
WORLD.HERO_HEALED_MOTES = 10
WORLD.FOOD_MOTES = 14

-- Enemy attacks landing. A melee hit is a slash: a tapered arc of state.streaks in
-- front of the enemy; an all-round slam, a burst or a leap is a ring.
WORLD.SLASH_SECONDS = 0.16
WORLD.SLASH_SEGMENTS = 5
WORLD.SLASH_WIDTH = 0.6
WORLD.SLASH_REACH = 0.7
WORLD.SLASH_ARC_SHARE = 0.8
WORLD.SLASH_SPARKS = 6
WORLD.SLAM_SECONDS = 0.3
WORLD.SLAM_STUDS = 0.6
WORLD.SLAM_PUFFS = 8
WORLD.MUZZLE_PUFFS = 6
WORLD.CHARGE_PUFFS = 6
WORLD.SUMMON_MOTES = 16
-- Splashes of enemy projectiles that land with a radius.
WORLD.SPLASH_SECONDS = 0.3
WORLD.SPLASH_SPARKS = 10

-- Discs: flat neon cylinders on the ground. Heights here are above the
-- ground, which Net.groundY gives.
DRAW.DISC_HEIGHT = 0.15
-- Lays a cylinder flat: its axis (X) points up.
SHAPE.LIE = CFrame.Angles(0, 0, math.pi / 2)
-- Ground marks (scorch, frost) spread over this share of their life and hold
-- until this share, then fade.
DRAW.GROUND_SPREAD = 0.12
DRAW.GROUND_HOLD = 0.45
-- Rings: a thin line on a flat SurfaceGui, this many canvas pixels per stud,
-- fewer for a ring so wide its canvas would pass DRAW.RING_MAX_CANVAS pixels.
DRAW.RING_THICKNESS = 0.05
DRAW.RING_PIXELS_PER_STUD = 16
DRAW.RING_MAX_CANVAS = 1024
DRAW.RING_BRIGHTNESS = 2.5
-- Studs of open middle a ring keeps at its narrowest.
DRAW.RING_MIN_HOLE = 0.5

-- Camera shake: how hard, and how near the local character a burst must be.
DRAW.SHAKE_RANGE = 30
WORLD.BURST_SHAKE = 0.6
WORLD.EXPLOSION_SHAKE = 1
WORLD.BOSS_SHAKE = 1.4

-- Telegraphs: a translucent base, a brighter fill growing from the centre
-- (or from the start of a charge's line) and a rim at the edge that
-- brightens as the attack nears.
PALETTE.TELEGRAPH_BASE_COLOR = Color3.fromRGB(200, 30, 30)
PALETTE.TELEGRAPH_FILL_COLOR = Color3.fromRGB(255, 70, 50)
PALETTE.TELEGRAPH_RIM_COLOR = Color3.fromRGB(255, 150, 120)
TELEGRAPH.TELEGRAPH_BASE_TRANSPARENCY = 0.72
TELEGRAPH.TELEGRAPH_FILL_TRANSPARENCY = 0.4
TELEGRAPH.TELEGRAPH_RIM_STUDS = 0.3
TELEGRAPH.TELEGRAPH_RIM_FADE = 0.5
TELEGRAPH.TELEGRAPH_THICKNESS = 0.1
TELEGRAPH.TELEGRAPH_MIN_FILL = 0.1
-- Studs between a telegraph's layers: the base below, the fill above, the rim on top.
TELEGRAPH.TELEGRAPH_LAYER = 0.03
-- An attack that hits an arc narrower than a full turn: a wedge on the ground
-- drawn from triangle slices.
TELEGRAPH.SECTOR_SLICES = 6
TELEGRAPH.SECTOR_THICKNESS = 0.08
TELEGRAPH.SECTOR_MIN_RADIUS = 0.3
-- The exploder's swelling, pulsing shell.
TELEGRAPH.SWELL_FROM = 3
TELEGRAPH.SWELL_TO = 6
TELEGRAPH.SWELL_PULSE = 0.08
TELEGRAPH.SWELL_HERTZ = 7
TELEGRAPH.SWELL_FADE = 0.35
-- A shooter's orb at its mouth, from enemy centre: forward and up.
TELEGRAPH.ORB_FROM = 0.2
TELEGRAPH.ORB_TO = 1
TELEGRAPH.MOUTH_FORWARD = 1.3
TELEGRAPH.MOUTH_RISE = 0.7
-- The heal's motes and a summon's pulses rise round the enemy this often
-- while it winds up; a summon's pulses stand on a ring at least this wide.
TELEGRAPH.MOTE_SECONDS = 0.25
TELEGRAPH.WIND_UP_MOTES = 6
TELEGRAPH.HEAL_BASE_TRANSPARENCY = 0.85
TELEGRAPH.HEAL_FILL_TRANSPARENCY = 0.7
TELEGRAPH.SUMMON_POINTS = 6
TELEGRAPH.SUMMON_MIN_RADIUS = 4
TELEGRAPH.SUMMON_PULSE_DIAMETER = 1.6
PALETTE.SUMMON_TINT = rgb(150, 70, 220, 230, 200, 255)

DRAW.NUMBER_SECONDS = 0.8
DRAW.NUMBER_RISE = 5
PALETTE.NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
PALETTE.CRIT_COLOR = Color3.fromRGB(255, 225, 50)
PALETTE.BLOCKED_COLOR = Color3.fromRGB(160, 160, 160)
PALETTE.SYNERGY_COLOR = Color3.fromRGB(255, 150, 40)
DRAW.NUMBER_TEXT_SIZE = 22
DRAW.DOT_TEXT_SIZE = 16
DRAW.CRIT_TEXT_SIZE = 32
SKILL.SYNERGY_TEXT_SIZE = 36
-- The pop: a number starts at DRAW.NUMBER_POP_FROM of its size, overshoots to
-- DRAW.NUMBER_POP_PEAK, then settles, each over this share of its life.
DRAW.NUMBER_POP_SHARE = 0.12
DRAW.NUMBER_POP_FROM = 0.5
DRAW.NUMBER_POP_PEAK = 1.35

-- Areas on the ground: a disc pulsing with each tick and a rim; a player's
-- in its tag's colour with particles falling from above (ice, fire) or
-- glinting, an enemy's a dark pool in the kind's colour, bubbling.
OBJECT.AREA_HEIGHT = 0.12
OBJECT.AREA_TRANSPARENCY = 0.72
OBJECT.AREA_PULSE = 0.3
OBJECT.AREA_POOL_TRANSPARENCY = 0.25
OBJECT.AREA_POOL_DARKEN = 0.45
OBJECT.AREA_RIM_STUDS = 0.35
OBJECT.AREA_RIM_FADE = 0.35
OBJECT.AREA_FADE_IN = 0.15
OBJECT.AREA_FADE_OUT = 0.3
-- Particles per second per square stud of area, and how high the falling start.
OBJECT.AREA_PARTICLE_DENSITY = 0.05
OBJECT.AREA_FALL_HEIGHT = 10
-- An area the snapshot no longer shows is let go after this long.
OBJECT.AREA_GRACE = 0.5

-- Totems: a wooden pole with a glowing bird on top, idling.
OBJECT.TOTEM_POLE = Vector3.new(4, 0.6, 0.6)
OBJECT.TOTEM_BODY = Vector3.new(0.9, 0.8, 1.6)
OBJECT.TOTEM_WING = Vector3.new(1.6, 0.15, 0.8)
OBJECT.TOTEM_BIRD_RISE = 4.4
OBJECT.TOTEM_GLOW_HZ = 1.2
OBJECT.TOTEM_GLOW_MIN = 0
OBJECT.TOTEM_GLOW_MAX = 0.35
OBJECT.TOTEM_FLAP_HZ = 1.5
OBJECT.TOTEM_FLAP = 0.5
OBJECT.TOTEM_TURN = 0.8

-- Crystals: small floating neon state.gems, spinning and bobbing; state.collected ones
-- fly to the hero, then sparkle.
OBJECT.GEM_SIZE = Vector3.new(2, 2, 2)
OBJECT.GEM_BIG = 1.3
OBJECT.GEM_RISE = 1.1
OBJECT.GEM_BOB = 0.25
OBJECT.GEM_BOB_HZ = 0.7
OBJECT.GEM_SPIN = 2.2
-- Colours by the crystal's experience: up to OBJECT.SMALL_XP, up to OBJECT.MEDIUM_XP, more.
OBJECT.SMALL_XP = 4
OBJECT.MEDIUM_XP = 12
PALETTE.GEM_SMALL = Color3.fromRGB(80, 160, 255)
PALETTE.GEM_MEDIUM = Color3.fromRGB(80, 235, 110)
PALETTE.GEM_LARGE = Color3.fromRGB(190, 90, 255)
OBJECT.GEM_FLY_SECONDS = 0.25
OBJECT.GEM_SPARKLE = 6
-- Where a crystal let go was, remembered this long for its collection.
OBJECT.GEM_MEMORY = 1
DRAW.PREWARM_GEMS = 120

-- Food: a meat leg on the ground, glowing softly.
OBJECT.MEAT_SIZE = Vector3.new(1.4, 1.2, 1.2)
OBJECT.BONE_SIZE = Vector3.new(1.4, 0.35, 0.35)
OBJECT.MEAT_RISE = 0.6

-- The chest, once the compass points at it: a soft state.beam of light above it.
OBJECT.BEAM_HEIGHT = 60
OBJECT.BEAM_WIDTH = 3
OBJECT.BEAM_TRANSPARENCY = 0.7
OBJECT.BEAM_PULSE = 0.12
OBJECT.BEAM_HZ = 0.5
OBJECT.CHEST_SPARKS = 40
OBJECT.CHEST_EMBERS = 24

-- The barrier: a translucent sphere round the hero while it holds.
OBJECT.SHIELD_DIAMETER = 7
OBJECT.SHIELD_TRANSPARENCY = 0.35
-- Sprinting: speed lines behind the hero this often.
OBJECT.SPRINT_LINE_SECONDS = 0.07
OBJECT.SPRINT_LINES = 2
OBJECT.SPRINT_LINE_LENGTH = 4
OBJECT.SPRINT_LINE_WIDTH = 0.15
OBJECT.SPRINT_LINE_SECONDS_LIVE = 0.22
OBJECT.SPRINT_MIN_SPEED = 2
-- A dash: translucent afterimages of the hero left along the way in its
-- class's colour, each fading out, and a puff where it set off.
OBJECT.DASH_IMAGES = 4
OBJECT.DASH_IMAGE_SIZE = Vector3.new(2, 4.5, 1)
OBJECT.DASH_IMAGE_SECONDS = 0.3
OBJECT.DASH_IMAGE_FADE = 0.55
DRAW.AFTERIMAGE_POOL = 24

-- A shrine's activation: a column of light, a widening ring, motes and a
-- flash in its kind's colour.
PALETTE.SHRINE_TINTS = {
	boon = rgb(255, 200, 60, 255, 245, 200),
	pact = rgb(200, 30, 50, 255, 170, 170),
	trial = rgb(150, 80, 240, 230, 210, 255),
	spring = rgb(70, 220, 240, 220, 255, 255),
} :: { [string]: Tint }
OBJECT.SHRINE_COLUMN_HEIGHT = 40
OBJECT.SHRINE_COLUMN_WIDTH = 4
OBJECT.SHRINE_COLUMN_FADE = 0.25
OBJECT.SHRINE_RING_DIAMETER = 18
OBJECT.SHRINE_RING_STUDS = 0.6
OBJECT.SHRINE_MOTES = 24
OBJECT.SHRINE_LIGHT_RANGE = 30
OBJECT.SHRINE_SECONDS = 1

-- The extraction spell's cast: a ring under the hero and motes swirling round it.
OBJECT.CAST_RING_DIAMETER = 7
OBJECT.CAST_RING_STUDS = 0.35
OBJECT.CAST_MOTES = 6
OBJECT.CAST_MOTE_SIZE = 0.45
OBJECT.CAST_SWIRL = 3
OBJECT.CAST_SHARDS = 10

-- The state.portal: a tall ring of glowing segments standing tilted toward the
-- camera, spinning, round a shimmering face, with a light and motes; it
-- grows in and shrinks before it closes.
OBJECT.PORTAL_SEGMENTS = 16
OBJECT.PORTAL_SEGMENT = Vector3.new(0.7, 0.7, 1.6)
OBJECT.PORTAL_TILT = math.rad(30)
OBJECT.PORTAL_SPIN = 1.4
OBJECT.PORTAL_GROW = 0.5
OBJECT.PORTAL_SHRINK = 1.5
OBJECT.PORTAL_FACE_TRANSPARENCY = 0.45
OBJECT.PORTAL_LIGHT_BRIGHTNESS = 3
OBJECT.PORTAL_MOTE_RATE = 30
PALETTE.PORTAL_TINT = rgb(120, 90, 255, 220, 210, 255)

-- Extraction: the hero state.fades out over this long under a column of light.
WORLD.EXTRACT_SECONDS = 1.2
WORLD.COLUMN_HEIGHT = 50
WORLD.COLUMN_WIDTH = 5
WORLD.COLUMN_CORE_WIDTH = 1.6
WORLD.COLUMN_SECONDS = 1.4
WORLD.COLUMN_FADE = 0.2
WORLD.COLUMN_MOTES = 30
-- A boss arriving: a column of light on it and a shockwave on the ground.
WORLD.BOSS_COLUMN_HEIGHT = 80
WORLD.BOSS_COLUMN_WIDTH = 7
WORLD.BOSS_WAVE_DIAMETER = 50
WORLD.BOSS_WAVE_SECONDS = 0.8
WORLD.BOSS_WAVE_STUDS = 1.2
-- How long a boss announced before its snapshot is waited for.
WORLD.BOSS_WAIT = 2
-- A boss's second phase: a red flash as big as the boss and a shockwave.
WORLD.PHASE_FLASH_SHARE = 1.6
WORLD.PHASE_SECONDS = 0.5
-- The closing ring: a brief ring of light where it spawns.
WORLD.CLOSING_SECONDS = 1.2
WORLD.CLOSING_STUDS = 0.9
WORLD.CLOSING_FROM = 0.92
-- Death: a dark burst.
WORLD.DEATH_SMOKE = 16
WORLD.DEATH_DIAMETER = 6
WORLD.DEATH_SECONDS = 0.6
-- Level up: a golden ring rising round the hero.
WORLD.LEVEL_SECONDS = 0.8
WORLD.LEVEL_MOTES = 18

-- Particle presets. Each is thrown in state.bursts (`Emit`) from a pooled host, or
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

SHAPE.EVERY_WAY = Vector2.new(180, 180)
SHAPE.NO_SPIN = NumberRange.new(0)
DATA.PRESETS = {
	-- Hit sparks: quick, bright, thrown every way and falling.
	sparks = {
		texture = PALETTE.SPARK_TEXTURE,
		size = curve({ 0.6, 0.1 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.2, 0.45),
		speed = NumberRange.new(14, 28),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, -40, 0),
		drag = 4,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 1,
		whiten = 0.5,
		locked = false,
	},
	-- Embers: slower sparks that drift up after an explosion.
	embers = {
		texture = PALETTE.EMBER_TEXTURE,
		size = curve({ 0.7, 0.2 }),
		transparency = curve({ 0, 0.2, 1 }),
		lifetime = NumberRange.new(0.6, 1.2),
		speed = NumberRange.new(10, 24),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, 4, 0),
		drag = 3,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Blaze: the big, short flames of an explosion.
	blaze = {
		texture = PALETTE.FIRE_TEXTURE,
		size = curve({ 3, 6, 4 }),
		transparency = curve({ 0.1, 0.4, 1 }),
		lifetime = NumberRange.new(0.3, 0.55),
		speed = NumberRange.new(6, 14),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, 10, 0),
		drag = 6,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
	-- Flash: the white-hot heart of an explosion.
	flash = {
		texture = PALETTE.FLASH_TEXTURE,
		size = curve({ 4, 9 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.15, 0.25),
		speed = NumberRange.new(0),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = NumberRange.new(-60, 60),
		lightEmission = 1,
		whiten = 0.6,
		locked = false,
	},
	-- Smoke: slow grey puffs that rise and spread.
	smoke = {
		texture = PALETTE.SMOKE_TEXTURE,
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
		texture = PALETTE.SMOKE_TEXTURE,
		size = curve({ 1.5, 4 }),
		transparency = curve({ 0.5, 1 }),
		lifetime = NumberRange.new(0.5, 0.8),
		speed = NumberRange.new(3, 6),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 3,
		rotSpeed = NumberRange.new(-40, 40),
		lightEmission = 0.3,
		whiten = 0.6,
		locked = false,
	},
	-- Motes: sparkles that rise and fade (deaths, heals).
	motes = {
		texture = PALETTE.SPARK_TEXTURE,
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
		texture = PALETTE.SMOKE_TEXTURE,
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
		texture = PALETTE.SPARK_TEXTURE,
		size = curve({ 0.15, 0.7, 0 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(1, 4),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 2,
		rotSpeed = NumberRange.new(-180, 180),
		lightEmission = 1,
		whiten = 0.5,
		locked = false,
	},
	-- Implosion: a ring of light pulled in (a closing state.portal, a cast).
	implosion = {
		texture = PALETTE.IMPLOSION_TEXTURE,
		size = curve({ 5, 1 }),
		transparency = curve({ 0.3, 1 }),
		lifetime = NumberRange.new(0.2, 0.25),
		speed = NumberRange.new(0),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Streams from tracked parts. Flame: a fire bolt's burning core.
	flame = {
		texture = PALETTE.FIRE_TEXTURE,
		size = curve({ 1.8, 0.4 }),
		transparency = curve({ 0.1, 1 }),
		lifetime = NumberRange.new(0.2, 0.35),
		speed = NumberRange.new(0.5, 2),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, 3, 0),
		drag = 0,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
	-- Trail smoke: what a fire bolt leaves in the air behind it.
	trailSmoke = {
		texture = PALETTE.SMOKE_TEXTURE,
		size = curve({ 0.8, 2.6 }),
		transparency = curve({ 0.5, 1 }),
		lifetime = NumberRange.new(0.6, 1),
		speed = NumberRange.new(0.2, 1),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, 2, 0),
		drag = 0,
		rotSpeed = NumberRange.new(-30, 30),
		lightEmission = 0,
		whiten = 0,
		locked = false,
	},
	-- Drips: small sparks falling off an enemy projectile.
	drips = {
		texture = PALETTE.SPARK_TEXTURE,
		size = curve({ 0.45, 0 }),
		transparency = curve({ 0, 1 }),
		lifetime = NumberRange.new(0.25, 0.4),
		speed = NumberRange.new(0.5, 2),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, -8, 0),
		drag = 0,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Halo: a soft glow that stays on a totem, the chest's state.beam or food.
	halo = {
		texture = PALETTE.GLOW_TEXTURE,
		size = curve({ 2.2, 2.8 }),
		transparency = curve({ 1, 0.55, 1 }),
		lifetime = NumberRange.new(0.9, 1.1),
		speed = NumberRange.new(0),
		spread = Vector2.zero,
		acceleration = Vector3.zero,
		drag = 0,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 1,
		whiten = 0,
		locked = true,
	},
	-- Flakes: snow falling through an ice area.
	flakes = {
		texture = PALETTE.SPARK_TEXTURE,
		size = curve({ 0.3, 0.5, 0.2 }),
		transparency = curve({ 1, 0.1, 0.3, 1 }),
		lifetime = NumberRange.new(1.2, 1.6),
		speed = NumberRange.new(0.5, 1.5),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, -6, 0),
		drag = 0.5,
		rotSpeed = NumberRange.new(-90, 90),
		lightEmission = 0.6,
		whiten = 0.6,
		locked = false,
	},
	-- Cinders: burning sparks raining into a fire area.
	cinders = {
		texture = PALETTE.EMBER_TEXTURE,
		size = curve({ 0.6, 0.3 }),
		transparency = curve({ 1, 0, 0.5, 1 }),
		lifetime = NumberRange.new(0.7, 1),
		speed = NumberRange.new(2, 5),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, -16, 0),
		drag = 0.5,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 1,
		whiten = 0.3,
		locked = false,
	},
	-- Bubbles: small, slow globs rising off an enemy's pool and popping.
	bubbles = {
		texture = PALETTE.GLOW_TEXTURE,
		size = curve({ 0.3, 0.8, 0.1 }),
		transparency = curve({ 0.3, 0.2, 1 }),
		lifetime = NumberRange.new(0.6, 1.1),
		speed = NumberRange.new(0.5, 1.5),
		spread = Vector2.new(20, 20),
		acceleration = Vector3.new(0, 1, 0),
		drag = 1,
		rotSpeed = SHAPE.NO_SPIN,
		lightEmission = 0.4,
		whiten = 0.2,
		locked = false,
	},
	-- Swirl: motes circling up the state.portal's face.
	swirl = {
		texture = PALETTE.SPARK_TEXTURE,
		size = curve({ 0.3, 0.7, 0 }),
		transparency = curve({ 0, 0.3, 1 }),
		lifetime = NumberRange.new(0.8, 1.4),
		speed = NumberRange.new(1, 3),
		spread = SHAPE.EVERY_WAY,
		acceleration = Vector3.new(0, 3, 0),
		drag = 1,
		rotSpeed = NumberRange.new(-180, 180),
		lightEmission = 1,
		whiten = 0.4,
		locked = false,
	},
} :: { [string]: Preset }
-- A burst host's size when it throws from a point.
SHAPE.EMIT_POINT = Vector3.new(0.2, 0.2, 0.2)

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
SHAPE.BALL = Enum.PartType.Ball
SHAPE.BLOCK = Enum.PartType.Block
SHAPE.CYLINDER = Enum.PartType.Cylinder
SHAPE.NEON = Enum.Material.Neon
DRAW.PROJECTILE_HEIGHT = 2.5
DRAW.TRAIL_SECONDS = 0.18
DRAW.TRAIL_TRANSPARENCY = 0.15
DRAW.TRACKED_LIGHT_BRIGHTNESS = 2
-- An arrow: a thin bar along its flight; an orb: a ball, bigger with a splash.
DRAW.ARROW_SIZE = Vector3.new(0.3, 0.3, 2.4)
DRAW.ORB_DIAMETER = 1
DRAW.ORB_SPLASH_DIAMETER = 1.6
-- A toughest-first bolt (the big single shot) is drawn this much bigger.
DRAW.TOUGHEST_SHARE = 1.5
DRAW.ENEMY_SHOT_DIAMETER = 1.1
-- Tags whose bolts are arrows rather than orbs.
DATA.ARROW_TAGS = { physical = true, poison = true, bleed = true } :: { [string]: boolean }

local function fromHex(value: number): Color3
	return Color3.fromRGB(bit32.rshift(value, 16) % 256, bit32.rshift(value, 8) % 256, value % 256)
end

local function tintFrom(color: Color3): Tint
	return { color = color, core = color:Lerp(PALETTE.WHITE, 0.6) }
end

-- A skill's tint is its first tag's; a hit named by a status (a dot) takes
-- the status's; anything else is arcane.
PALETTE.SKILL_TINTS = {} :: { [string]: Tint }
for id, skill in Config.skills do
	local tag = skill.tags[1]
	PALETTE.SKILL_TINTS[id] = if tag
		then PALETTE.TAG_TINTS[tag] or PALETTE.ARCANE
		else PALETTE.ARCANE
end

local function tintOf(skill: string?): Tint
	if skill == nil then
		return PALETTE.ARCANE
	end
	return PALETTE.SKILL_TINTS[skill] or PALETTE.DOT_TINTS[skill] or PALETTE.ARCANE
end

-- An enemy kind's tint, from its colour.
PALETTE.KIND_TINTS = {} :: { [string]: Tint }
for id, kind in Config.enemies do
	PALETTE.KIND_TINTS[id] = tintFrom(fromHex(kind.colour))
end

local function kindTint(kind: string?): Tint
	return if kind then PALETTE.KIND_TINTS[kind] or PALETTE.EXPLODER else PALETTE.EXPLODER
end

local function boltStyle(skill: Types.SkillConfig): Style
	local tag = skill.tags[1] or "arcane"
	local tint = PALETTE.TAG_TINTS[tag] or PALETTE.ARCANE
	local grow = if skill.toughest then DRAW.TOUGHEST_SHARE else 1
	if DATA.ARROW_TAGS[tag] then
		return {
			shape = SHAPE.BLOCK,
			size = DRAW.ARROW_SIZE * grow,
			color = tint.core,
			material = SHAPE.NEON,
			transparency = 0,
			glow = tint.color,
			height = DRAW.PROJECTILE_HEIGHT,
			trail = 0.3 * grow,
			streams = if tag == "physical"
				then {}
				else { { preset = "drips", color = tint.color, rate = 14 } },
		}
	end
	local diameter = (if skill.radius > 0 then DRAW.ORB_SPLASH_DIAMETER else DRAW.ORB_DIAMETER)
		* grow
	local streams: { Stream } = {}
	if tag == "fire" then
		streams = {
			{ preset = "flame", color = tint.color, rate = 45 },
			{ preset = "trailSmoke", color = PALETTE.SMOKE_COLOR, rate = 18 },
		}
	elseif tag == "ice" or tag == "arcane" then
		streams = { { preset = "shimmer", color = tint.color, rate = 20 } }
	else
		streams = { { preset = "drips", color = tint.color, rate = 14 } }
	end
	return {
		shape = SHAPE.BALL,
		size = Vector3.one * diameter,
		color = tint.core,
		material = SHAPE.NEON,
		transparency = 0,
		glow = tint.color,
		height = DRAW.PROJECTILE_HEIGHT,
		lightRange = if tag == "fire" then 16 else nil,
		trail = diameter * 0.7,
		streams = streams,
	}
end

local function shotStyle(kind: string): Style
	local tint = kindTint(kind)
	return {
		shape = SHAPE.BALL,
		size = Vector3.one * DRAW.ENEMY_SHOT_DIAMETER,
		color = tint.color,
		material = SHAPE.NEON,
		transparency = 0,
		glow = tint.color,
		height = DRAW.PROJECTILE_HEIGHT,
		trail = 0.7,
		streams = { { preset = "drips", color = tint.color, rate = 16 } },
	}
end

DATA.STYLES = {} :: { [string]: Style }
for id, skill in Config.skills do
	if skill.speed > 0 then
		DATA.STYLES[id] = boltStyle(skill)
	end
end
for id in Config.enemies do
	DATA.STYLES[id] = shotStyle(id)
end
DATA.DEFAULT_PROJECTILE = shotStyle("") :: Style

-- Synergies by id: their name and the tint they flash in (shatter's is ice,
-- the status it breaks; the rest their tag's).
DATA.SYNERGY_NAMES = {} :: { [string]: string }
PALETTE.SYNERGY_TINTS = {} :: { [string]: Tint }
DATA.SYNERGY_CONFIGS = {} :: { [string]: Types.SynergyConfig }
for _, class in Config.classes do
	for _, synergy in class.synergies do
		DATA.SYNERGY_NAMES[synergy.id] = synergy.name
		DATA.SYNERGY_CONFIGS[synergy.id] = synergy
		PALETTE.SYNERGY_TINTS[synergy.id] = if synergy.status == "chilled"
			then PALETTE.ICE
			else PALETTE.TAG_TINTS[synergy.tag] or PALETTE.ARCANE
	end
end

-- Utilities by id.
DATA.UTILITIES = {} :: { [string]: Types.UtilityConfig }
for _, utility in Config.utilities do
	DATA.UTILITIES[utility.id] = utility
end
state.random = Random.new()
SHAPE.UP = Vector3.yAxis

local function easeOut(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

-- Made here so its type is known; named and placed in the workspace by start.
state.folder = Instance.new("Folder")

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = SHAPE.NEON
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
	part.Size = Vector3.new(1, DRAW.RING_THICKNESS, 1)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = DRAW.RING_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Brightness = DRAW.RING_BRIGHTNESS
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
	local density =
		math.min(DRAW.RING_PIXELS_PER_STUD, DRAW.RING_MAX_CANVAS / math.max(diameter, 1))
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

state.pools = {} :: { Pool }

local function newPool(size: number, build: () -> Built, animate: (Slot, number) -> ()): Pool
	local pool: Pool = {
		size = size,
		cursor = 0,
		live = 0,
		slots = {},
		build = build,
		animate = animate,
	}
	table.insert(state.pools, pool)
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
	slot.part.Parent = state.folder
	return slot
end

local function step()
	local now = os.clock()
	for _, pool in state.pools do
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

-- Streaks: a bar from origin to target that thins and state.fades. A travelling one
-- shoots its head to the target, then pulls its tail after it; a flickering
-- one jumps in brightness.
local function animateStreak(slot: Slot, alpha: number)
	local part = slot.part
	local width = slot.from + (slot.to - slot.from) * alpha
	local head, tail = slot.target, slot.origin
	if slot.mode == "travel" then
		head = slot.origin:Lerp(slot.target, math.min(1, alpha / DRAW.TRAVEL_HEAD))
		tail = slot.origin:Lerp(slot.target, alpha * alpha)
	end
	local length = (head - tail).Magnitude
	if length < DRAW.MIN_STREAK then
		part.Transparency = 1
		return
	end
	part.Size = Vector3.new(width, width, length)
	if slot.mode == "travel" then
		part.CFrame = CFrame.lookAt((tail + head) / 2, head)
	end
	local transparency = slot.fade + (1 - slot.fade) * alpha
	if slot.mode == "flicker" then
		transparency += state.random:NextNumber(0, DRAW.FLICKER)
	end
	part.Transparency = math.min(transparency, 1)
end

state.streaks = newPool(DRAW.STREAK_POOL, buildBlock, animateStreak)
state.lightning = newPool(DRAW.LIGHTNING_POOL, buildBlock, animateStreak)

-- Glows: neon balls that swell and fade (flashes).
state.glows = newPool(DRAW.GLOW_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Ball
	return { part = part }
end, function(slot, alpha)
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	slot.part.Size = Vector3.new(diameter, diameter, diameter)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Rings: a thin line on the ground that widens, state.fades and may rise.
state.rings = newPool(DRAW.RING_POOL, function()
	local ring = newRing()
	return { part = ring.part, ring = ring }
end, function(slot, alpha)
	local ring = slot.ring
	if ring == nil then
		return
	end
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	ring.part.Size = Vector3.new(diameter, DRAW.RING_THICKNESS, diameter)
	if slot.drift ~= 0 then
		ring.part.CFrame = slot.frame + SHAPE.UP * (slot.drift * easeOut(alpha))
	end
	ring.stroke.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Discs lie flat, so the cylinder's axis (X) points up. They widen and fade.
state.discs = newPool(DRAW.DISC_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	return { part = part }
end, function(slot, alpha)
	local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha)
	slot.part.Size = Vector3.new(0.2, diameter, diameter)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- Ground marks (scorch, frost): a disc that spreads in the first part of its
-- life, holds, then state.fades.
state.grounds = newPool(DRAW.GROUND_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	return { part = part }
end, function(slot, alpha)
	if alpha < DRAW.GROUND_SPREAD then
		local diameter = slot.from + (slot.to - slot.from) * easeOut(alpha / DRAW.GROUND_SPREAD)
		slot.part.Size = Vector3.new(0.1, diameter, diameter)
	end
	local fading = math.max(0, (alpha - DRAW.GROUND_HOLD) / (1 - DRAW.GROUND_HOLD))
	slot.part.Transparency = slot.fade + (1 - slot.fade) * fading
end)

-- Shards: wedges that fly out from the centre along `target`, lift, tilt and spin.
state.shards = newPool(DRAW.SHARD_POOL, function()
	return { part = newWedge() }
end, function(slot, alpha)
	local radius = slot.from + (slot.to - slot.from) * easeOut(alpha)
	local direction = slot.target
	local position = slot.origin
		+ direction * radius
		+ SHAPE.UP * (SKILL.SHARD_LIFT * math.sin(alpha * math.pi))
	slot.part.CFrame = CFrame.lookAt(position, position + direction)
		* CFrame.Angles(-SKILL.SHARD_TILT * alpha, 0, slot.drift * alpha)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha * alpha
end)

-- Lights: a capped few PointLights that flash and die out.
state.lights = newPool(DRAW.LIGHT_POOL, function()
	local part = newEffectPart()
	part.Transparency = 1
	part.Size = SHAPE.EMIT_POINT
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

-- Afterimages: blocks the size of a hero that fade from `fade` to clear.
state.afterimages = newPool(DRAW.AFTERIMAGE_POOL, function()
	local part = newEffectPart()
	part.Size = OBJECT.DASH_IMAGE_SIZE
	return { part = part }
end, function(slot, alpha)
	slot.part.Transparency = slot.fade + (1 - slot.fade) * alpha
end)

-- The pop of a damage number: up past its size, then back.
local function pop(alpha: number): number
	if alpha < DRAW.NUMBER_POP_SHARE then
		return DRAW.NUMBER_POP_FROM
			+ (DRAW.NUMBER_POP_PEAK - DRAW.NUMBER_POP_FROM) * alpha / DRAW.NUMBER_POP_SHARE
	end
	local settle = math.min(1, (alpha - DRAW.NUMBER_POP_SHARE) / DRAW.NUMBER_POP_SHARE)
	return DRAW.NUMBER_POP_PEAK + (1 - DRAW.NUMBER_POP_PEAK) * settle
end

-- Damage state.numbers: text on a billboard that pops, rises and state.fades.
state.numbers = newPool(DRAW.NUMBER_POOL, function()
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
	slot.part.Position = slot.origin + SHAPE.UP * (DRAW.NUMBER_RISE * easeOut(alpha))
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

-- Particle state.bursts: one hidden host part per preset and colour, moved to where
-- the burst is and told to `Emit`. The particles stay where they were thrown.
type Burst = { host: Part, emitter: ParticleEmitter }
state.bursts = {} :: { [string]: Burst }

local function configureEmitter(emitter: ParticleEmitter, preset: Preset, color: Color3)
	emitter.Texture = preset.texture
	emitter.Color = ColorSequence.new(color:Lerp(PALETTE.WHITE, preset.whiten), color)
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
	local existing = state.bursts[key]
	if existing then
		return existing
	end
	local host = newEffectPart()
	host.Name = "Burst_" .. key
	host.Transparency = 1
	host.Size = SHAPE.EMIT_POINT
	host.Parent = state.folder
	local emitter = Instance.new("ParticleEmitter")
	configureEmitter(emitter, DATA.PRESETS[name], color)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = host
	local made = { host = host, emitter = emitter }
	state.bursts[key] = made
	return made
end

-- Throws `count` particles of preset `name` from `at`, spread through a box
-- `area` wide (a point when nil).
local function emit(name: string, color: Color3, at: Vector3, count: number, area: Vector3?)
	if count < 1 then
		return
	end
	local burst = burstFor(name, color)
	burst.host.Size = area or SHAPE.EMIT_POINT
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
	return (camera.CFrame.Position - at).Magnitude <= DRAW.VIEW_RANGE
end

-- Where the hero's middle is: its character's root, or (x, z) before it has one.
local function heroAt(userId: number, x: number, z: number): Vector3
	local root = characterRoot(userId)
	if root then
		return root.Position
	end
	return Vector3.new(x, Net.groundY() + SKILL.HERO_RISE, z)
end

-- Where a hand of a hero standing at `at` is, reaching towards `toward`.
local function handOf(at: Vector3, toward: Vector3?): Vector3
	local position = at + SHAPE.UP * SKILL.HAND_RISE
	if toward then
		local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
		if flat.Magnitude > 1e-3 then
			position += flat.Unit * SKILL.HAND_REACH
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
	return dx * dx + dz * dz <= DRAW.SHAKE_RANGE * DRAW.SHAKE_RANGE
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
	if (to - from).Magnitude < DRAW.MIN_STREAK then
		return
	end
	local slot = start(pool, seconds, from)
	slot.target = to
	slot.from = width
	slot.to = width * DRAW.STREAK_THIN
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
	local slot = start(state.glows, seconds, at)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Color = color
	slot.part.CFrame = CFrame.new(at)
	state.glows.animate(slot, 0)
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
	local frame = groundFrame(x, z, DRAW.DISC_HEIGHT)
	local slot = start(state.rings, seconds, frame.Position)
	slot.frame = frame
	local ring = slot.ring
	if ring == nil then
		return
	end
	-- Never narrower than its own line, which would turn the canvas inside out.
	slot.from = math.max(from, studs * 2 + DRAW.RING_MIN_HOLE)
	slot.to = math.max(to, slot.from)
	slot.fade = fade
	slot.drift = rise
	setRingLine(ring, studs, color, slot.to)
	ring.part.CFrame = frame
	state.rings.animate(slot, 0)
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
	local frame = groundFrame(x, z, DRAW.DISC_HEIGHT)
	local slot = start(state.discs, seconds, frame.Position)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Color = color
	slot.part.CFrame = frame * SHAPE.LIE
	state.discs.animate(slot, 0)
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
	local frame = groundFrame(x, z, DRAW.DISC_HEIGHT * 0.5)
	local slot = start(state.grounds, seconds, frame.Position)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Material = material
	slot.part.Color = color
	slot.part.Size = Vector3.new(0.1, from, from)
	slot.part.CFrame = frame * SHAPE.LIE
	state.grounds.animate(slot, 0)
end

-- `count` state.shards flying out from `centre` to `reach` studs, `scale` times the
-- full size, alternating the tint's colour and core.
local function showShards(
	centre: Vector3,
	count: number,
	reach: number,
	tint: Tint,
	scale: number,
	seconds: number
)
	local offset = state.random:NextNumber(0, 2 * math.pi)
	for index = 1, count do
		local angle = offset + (index + state.random:NextNumber(-0.3, 0.3)) * 2 * math.pi / count
		local slot = start(state.shards, seconds, centre)
		slot.target = Vector3.new(math.cos(angle), 0, math.sin(angle))
		slot.from = 0.5
		slot.to = reach
		slot.fade = SKILL.SHARD_FADE
		slot.drift = state.random:NextNumber(-SKILL.SHARD_SPIN, SKILL.SHARD_SPIN)
		slot.part.Size = SKILL.SHARD_SIZE * scale
		slot.part.Color = if index % 2 == 0 then tint.core else tint.color
		state.shards.animate(slot, 0)
	end
end

local function showLight(
	at: Vector3,
	color: Color3,
	brightness: number,
	range: number,
	seconds: number
)
	local slot = start(state.lights, seconds, at)
	slot.from = brightness
	slot.part.CFrame = CFrame.new(at)
	local light = slot.light
	if light then
		light.Color = color
		light.Range = range
	end
	state.lights.animate(slot, 0)
end

-- A number or word popping up over `at`.
local function showNumber(at: Vector3, text: string, color: Color3, size: number)
	local origin = at
		+ Vector3.new(state.random:NextNumber(-1.5, 1.5), 3, state.random:NextNumber(-1.5, 1.5))
	local slot = start(state.numbers, DRAW.NUMBER_SECONDS, origin)
	slot.part.Position = origin
	local label = slot.label
	if label then
		label.Text = text
		label.TextColor3 = color
		label.TextSize = size
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.4
	end
	state.numbers.animate(slot, 0)
end

-- The latest snapshot's enemies: which way each faces and what kind it is.
state.enemyFacing = {} :: { [number]: number }
state.enemyKind = {} :: { [number]: string }
-- Bosses announced before a snapshot drew them, and when.
state.pendingBosses = {} :: { [number]: number }

local function forwardOf(enemyId: number): Vector3
	local facing = state.enemyFacing[enemyId] or 0
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
state.markers = {} :: { [number]: Marker }
state.freeMarkers = {} :: { Marker }

local function newDisc(name: string): Part
	local part = newEffectPart()
	part.Name = name
	part.Shape = SHAPE.CYLINDER
	return part
end

local function newMarker(): Marker
	local rim = newRing()
	rim.part.Name = "TelegraphRim"
	local orb = newEffectPart()
	orb.Name = "TelegraphOrb"
	orb.Shape = SHAPE.BALL
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
		orbTint = PALETTE.EXPLODER,
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
	local marker = state.markers[enemyId]
	if marker then
		state.markers[enemyId] = nil
		marker.base.Parent = nil
		marker.fill.Parent = nil
		marker.rim.part.Parent = nil
		marker.orb.Parent = nil
		marker.strip.Parent = nil
		marker.stripFill.Parent = nil
		hideSector(marker.sector)
		hideSector(marker.sectorFill)
		table.insert(state.freeMarkers, marker)
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
	first.Size = Vector3.new(TELEGRAPH.SECTOR_THICKNESS, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	second.Size = Vector3.new(TELEGRAPH.SECTOR_THICKNESS, height, math.abs(ac:Dot(back)))
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
	radius = math.max(radius, TELEGRAPH.SECTOR_MIN_RADIUS)
	local centre = frame.Position
	for slice = 0, TELEGRAPH.SECTOR_SLICES - 1 do
		local from = facing - arc / 2 + arc * slice / TELEGRAPH.SECTOR_SLICES
		local to = from + arc / TELEGRAPH.SECTOR_SLICES
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
		for index = 1, TELEGRAPH.SECTOR_SLICES * 2 do
			wedges[index] = newWedge()
		end
	end
	for _, wedge in wedges do
		wedge.Color = color
		wedge.Transparency = transparency
		wedge.Parent = state.folder
	end
end

function fx.telegraphLook(
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
function fx.placeStrip(part: Part, from: Vector3, direction: Vector3, length: number, width: number)
	local shown = math.max(length, TELEGRAPH.TELEGRAPH_MIN_FILL)
	local middle = from + direction * (shown / 2)
	part.Size = Vector3.new(width, TELEGRAPH.TELEGRAPH_THICKNESS, shown)
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

function fx.showTelegraph(event: TelegraphEvent)
	local enemyId = event.enemyId
	removeMarker(enemyId)
	EnemyView.telegraph(enemyId, event.seconds)
	local kindId = state.enemyKind[enemyId]
	local attack = attackOf(kindId, event.attackKind)
	local look = fx.telegraphLook(event.attackKind, attack, kindId)
	local x, z, radius = event.x, event.z, event.radius

	local marker = table.remove(state.freeMarkers) or newMarker()
	local now = os.clock()
	marker.look = look
	marker.radius = radius
	marker.startedAt = now
	marker.endsAt = now + math.max(event.seconds, 0.05)
	marker.motesAt = now
	marker.frame = groundFrame(x, z, DRAW.DISC_HEIGHT)
	marker.facing = state.enemyFacing[enemyId] or 0
	marker.arc = math.rad(if attack then attack.arcDegrees or 360 else 360)
	marker.orbTint = kindTint(kindId)
	state.markers[enemyId] = marker

	if look == "wedge" then
		showSector(
			marker.sector,
			PALETTE.TELEGRAPH_BASE_COLOR,
			TELEGRAPH.TELEGRAPH_BASE_TRANSPARENCY
		)
		showSector(
			marker.sectorFill,
			PALETTE.TELEGRAPH_FILL_COLOR,
			TELEGRAPH.TELEGRAPH_FILL_TRANSPARENCY
		)
		local below = layer(marker.frame, -TELEGRAPH.TELEGRAPH_LAYER)
		drawSector(marker.sector, below, marker.facing, marker.arc, radius)
		local above = layer(marker.frame, TELEGRAPH.TELEGRAPH_LAYER)
		drawSector(marker.sectorFill, above, marker.facing, marker.arc, 0)
		return
	end

	if look == "strip" then
		local endX, endZ = event.endX or x, event.endZ or z
		local from = groundAt(x, z, DRAW.DISC_HEIGHT)
		local along = Vector3.new(endX - x, 0, endZ - z)
		local length = along.Magnitude
		marker.lineFrom = from
		marker.lineDirection = if length > 1e-3 then along / length else forwardOf(enemyId)
		marker.lineLength = length
		local width = math.max(radius * 2, TELEGRAPH.TELEGRAPH_MIN_FILL)
		marker.strip.Color = PALETTE.TELEGRAPH_BASE_COLOR
		marker.strip.Transparency = TELEGRAPH.TELEGRAPH_BASE_TRANSPARENCY
		fx.placeStrip(
			marker.strip,
			from - SHAPE.UP * TELEGRAPH.TELEGRAPH_LAYER,
			marker.lineDirection,
			length,
			width
		)
		marker.stripFill.Color = PALETTE.TELEGRAPH_FILL_COLOR
		marker.stripFill.Transparency = TELEGRAPH.TELEGRAPH_FILL_TRANSPARENCY
		fx.placeStrip(marker.stripFill, from, marker.lineDirection, 0, width)
		marker.strip.Parent = state.folder
		marker.stripFill.Parent = state.folder
		return
	end

	if look == "summon" then
		marker.radius = math.max(radius, TELEGRAPH.SUMMON_MIN_RADIUS)
	end
	-- The fill sits a hair above the base, the rim above both. A shot that
	-- strikes only what it hits has no area to mark.
	if look ~= "spit" or radius > 0 then
		local heal = look == "heal"
		local tint = if heal
			then PALETTE.HEAL
			elseif look == "summon" then PALETTE.SUMMON_TINT
			else nil
		local diameter = marker.radius * 2
		marker.base.Color = if tint then tint.color else PALETTE.TELEGRAPH_BASE_COLOR
		marker.base.Transparency = if tint
			then TELEGRAPH.HEAL_BASE_TRANSPARENCY
			else TELEGRAPH.TELEGRAPH_BASE_TRANSPARENCY
		marker.base.Size = Vector3.new(TELEGRAPH.TELEGRAPH_THICKNESS, diameter, diameter)
		marker.base.CFrame = layer(marker.frame, -TELEGRAPH.TELEGRAPH_LAYER) * SHAPE.LIE
		marker.fill.Color = if tint then tint.color else PALETTE.TELEGRAPH_FILL_COLOR
		marker.fill.Transparency = if tint
			then TELEGRAPH.HEAL_FILL_TRANSPARENCY
			else TELEGRAPH.TELEGRAPH_FILL_TRANSPARENCY
		marker.fill.Size = Vector3.new(
			TELEGRAPH.TELEGRAPH_THICKNESS,
			TELEGRAPH.TELEGRAPH_MIN_FILL,
			TELEGRAPH.TELEGRAPH_MIN_FILL
		)
		marker.fill.CFrame = layer(marker.frame, TELEGRAPH.TELEGRAPH_LAYER) * SHAPE.LIE
		setRingLine(
			marker.rim,
			TELEGRAPH.TELEGRAPH_RIM_STUDS,
			if tint then tint.core else PALETTE.TELEGRAPH_RIM_COLOR,
			diameter
		)
		marker.rim.stroke.Transparency = TELEGRAPH.TELEGRAPH_RIM_FADE
		marker.rim.part.Size = Vector3.new(diameter, DRAW.RING_THICKNESS, diameter)
		marker.rim.part.CFrame = layer(marker.frame, 2 * TELEGRAPH.TELEGRAPH_LAYER)
		marker.base.Parent = state.folder
		marker.fill.Parent = state.folder
		marker.rim.part.Parent = state.folder
	end

	if look == "swell" then
		marker.orb.Material = Enum.Material.ForceField
		marker.orb.Color = PALETTE.EXPLODER.color
		marker.orb.Size = Vector3.one * TELEGRAPH.SWELL_FROM
		marker.orb.Transparency = TELEGRAPH.SWELL_FADE
	elseif look == "spit" then
		marker.orb.Material = SHAPE.NEON
		marker.orb.Color = marker.orbTint.color
		marker.orb.Size = Vector3.one * TELEGRAPH.ORB_FROM
		marker.orb.Transparency = 0
	end
	if look == "swell" or look == "spit" then
		local at = EnemyView.position(enemyId)
		if at then
			marker.orb.CFrame = CFrame.new(at)
		end
		marker.orb.Parent = state.folder
	end
end

function fx.stepMarkers()
	local now = os.clock()
	for enemyId, marker in state.markers do
		local alpha = (now - marker.startedAt) / (marker.endsAt - marker.startedAt)
		if alpha >= 1 then
			removeMarker(enemyId)
			continue
		end
		local look = marker.look
		if look == "wedge" then
			-- The facing comes with snapshots; the event may have come first.
			local facing = state.enemyFacing[enemyId]
			if facing and facing ~= marker.facing then
				marker.facing = facing
				local below = layer(marker.frame, -TELEGRAPH.TELEGRAPH_LAYER)
				drawSector(marker.sector, below, facing, marker.arc, marker.radius)
			end
			local above = layer(marker.frame, TELEGRAPH.TELEGRAPH_LAYER)
			drawSector(marker.sectorFill, above, marker.facing, marker.arc, marker.radius * alpha)
			continue
		elseif look == "strip" then
			fx.placeStrip(
				marker.stripFill,
				marker.lineFrom,
				marker.lineDirection,
				marker.lineLength * alpha,
				marker.stripFill.Size.X
			)
			continue
		end

		local diameter = math.max(marker.radius * 2 * alpha, TELEGRAPH.TELEGRAPH_MIN_FILL)
		marker.fill.Size = Vector3.new(TELEGRAPH.TELEGRAPH_THICKNESS, diameter, diameter)
		marker.rim.stroke.Transparency = TELEGRAPH.TELEGRAPH_RIM_FADE * (1 - alpha)

		if look == "swell" or look == "spit" then
			local at = EnemyView.position(enemyId)
			if at then
				if look == "spit" then
					at += forwardOf(enemyId) * TELEGRAPH.MOUTH_FORWARD + SHAPE.UP * TELEGRAPH.MOUTH_RISE
				end
				marker.orb.CFrame = CFrame.new(at)
			end
			if look == "swell" then
				local pulse = 1
					+ TELEGRAPH.SWELL_PULSE
						* math.sin(now * TELEGRAPH.SWELL_HERTZ * 2 * math.pi)
				local size = (
					TELEGRAPH.SWELL_FROM + (TELEGRAPH.SWELL_TO - TELEGRAPH.SWELL_FROM) * alpha
				) * pulse
				marker.orb.Size = Vector3.one * size
				marker.orb.Transparency = TELEGRAPH.SWELL_FADE * (1 - alpha)
			else
				marker.orb.Size = Vector3.one
					* (
						TELEGRAPH.ORB_FROM
						+ (TELEGRAPH.ORB_TO - TELEGRAPH.ORB_FROM) * easeOut(alpha)
					)
			end
		elseif (look == "heal" or look == "summon") and now >= marker.motesAt then
			marker.motesAt = now + TELEGRAPH.MOTE_SECONDS
			local at = EnemyView.position(enemyId)
			if at and onScreen(at) then
				if look == "heal" then
					emit(
						"motes",
						PALETTE.HEAL.color,
						at,
						TELEGRAPH.WIND_UP_MOTES,
						Vector3.new(4, 1, 4)
					)
				else
					local offset = state.random:NextNumber(0, 2 * math.pi)
					local ground = groundAt(at.X, at.Z, 1)
					for index = 1, TELEGRAPH.SUMMON_POINTS do
						local angle = offset + index * 2 * math.pi / TELEGRAPH.SUMMON_POINTS
						local point = ground
							+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * marker.radius
						showGlow(
							point,
							PALETTE.SUMMON_TINT.color,
							0.3,
							TELEGRAPH.SUMMON_PULSE_DIAMETER,
							0.3,
							TELEGRAPH.MOTE_SECONDS
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

function fx.newTracker(): Tracker
	return { free = {}, live = {}, stamps = {} }
end

state.projectileTracker = fx.newTracker()
state.trackGeneration = 0
-- The previous snapshot's projectiles by id.
state.previousProjectiles = {} :: { [number]: Protocol.ProjectileView }
-- Reused every frame for the bulk move.
state.moveParts = {} :: { BasePart }
state.moveFrames = {} :: { CFrame }

function fx.buildTracked(style: Style): Tracked
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
		lamp.Brightness = DRAW.TRACKED_LIGHT_BRIGHTNESS
		lamp.Shadows = false
		lamp.Enabled = false
		lamp.Parent = part
		light = lamp
	end

	local trail: Trail? = nil
	if style.trail > 0 then
		local top = Instance.new("Attachment")
		top.Position = SHAPE.UP * (style.trail / 2)
		top.Parent = part
		local bottom = Instance.new("Attachment")
		bottom.Position = -SHAPE.UP * (style.trail / 2)
		bottom.Parent = part
		local ribbon = Instance.new("Trail")
		ribbon.Attachment0 = top
		ribbon.Attachment1 = bottom
		ribbon.FaceCamera = true
		ribbon.Lifetime = DRAW.TRAIL_SECONDS
		ribbon.LightEmission = 1
		ribbon.LightInfluence = 0
		ribbon.Color = ColorSequence.new(style.glow)
		ribbon.Transparency = curve({ DRAW.TRAIL_TRANSPARENCY, 1 })
		ribbon.WidthScale = curve({ 1, 0.2 })
		ribbon.Enabled = false
		ribbon.Parent = part
		trail = ribbon
	end

	local streams = {}
	for _, stream in style.streams do
		local emitter = Instance.new("ParticleEmitter")
		configureEmitter(emitter, DATA.PRESETS[stream.preset], stream.color)
		emitter.Rate = stream.rate
		emitter.Enabled = false
		emitter.Parent = part
		table.insert(streams, emitter)
	end

	return { part = part, style = style, light = light, trail = trail, streams = streams }
end

-- Hides a part let go and hands it back to its style's pool.
function fx.release(tracker: Tracker, id: number, tracked: Tracked)
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
function fx.trackPart(tracker: Tracker, id: number, style: Style, x: number, z: number)
	tracker.stamps[id] = state.trackGeneration
	local live = tracker.live[id]
	if live then
		if live.style == style then
			return
		end
		fx.release(tracker, id, live)
		tracker.stamps[id] = state.trackGeneration
	end
	local free = tracker.free[style]
	local tracked = (if free then table.remove(free) else nil) or fx.buildTracked(style)
	tracked.part.CFrame = CFrame.new(x, Net.groundY() + style.height, z)
	tracked.part.Transparency = style.transparency
	tracked.part.Parent = state.folder
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

function fx.sweep(tracker: Tracker)
	for id, tracked in tracker.live do
		if tracker.stamps[id] ~= state.trackGeneration then
			fx.release(tracker, id, tracked)
		end
	end
end

-- Lights the first live parts that carry a light, up to the cap; returns how
-- many are lit so far.
function fx.lightTracked(tracker: Tracker, lit: number): number
	for _, tracked in tracker.live do
		local light = tracked.light
		if light then
			light.Enabled = lit < DRAW.TRACKED_LIGHTS
			if light.Enabled then
				lit += 1
			end
		end
	end
	return lit
end

-- Where the culling measures from: the local character, or the camera.
function fx.viewCenter(): Vector3?
	local root = localRoot()
	if root then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

function fx.inView(center: Vector3?, x: number, z: number): boolean
	if center == nil then
		return true
	end
	local dx, dz = x - center.X, z - center.Z
	return dx * dx + dz * dz <= DRAW.VIEW_RANGE * DRAW.VIEW_RANGE
end

-- Crystals: one pooled gem per id, parked while out of view. A state.collected
-- one leaves the set and flies; a crystal the snapshot dropped is
-- remembered a moment for the event that collects it.
type Gem = { part: Part, x: number, z: number, xp: number, phase: number, parked: boolean }
type Flight = { part: Part, from: Vector3, player: number, startedAt: number, color: Color3 }
state.gems = {} :: { [number]: Gem }
state.gemStamps = {} :: { [number]: number }
state.freeGems = {} :: { Part }
state.lostGems = {} :: { [number]: { x: number, z: number, xp: number, at: number } }
-- Collected crystals a late snapshot may still list, and when.
state.collected = {} :: { [number]: number }
state.flights = {} :: { Flight }
SHAPE.PARKED = CFrame.new(0, -10000, 0)
-- Turns a cube onto a corner: a gem.
SHAPE.GEM_TURN = CFrame.Angles(math.pi / 4, 0, math.pi / 4)

function fx.newGemPart(): Part
	local part = newEffectPart()
	part.Name = "Crystal"
	part.Size = OBJECT.GEM_SIZE
	return part
end

function fx.gemColor(xp: number): Color3
	if xp <= OBJECT.SMALL_XP then
		return PALETTE.GEM_SMALL
	elseif xp <= OBJECT.MEDIUM_XP then
		return PALETTE.GEM_MEDIUM
	end
	return PALETTE.GEM_LARGE
end

function fx.takeGem(xp: number): Part
	local part = table.remove(state.freeGems) or fx.newGemPart()
	part.Color = fx.gemColor(xp)
	part.Size = if xp > OBJECT.MEDIUM_XP then OBJECT.GEM_SIZE * OBJECT.GEM_BIG else OBJECT.GEM_SIZE
	part.Transparency = 0
	part.Parent = state.folder
	return part
end

function fx.giveGem(part: Part)
	part.Parent = nil
	table.insert(state.freeGems, part)
end

function fx.syncCrystals(crystals: { Protocol.CrystalView })
	local now = os.clock()
	for _, crystal in crystals do
		local id = crystal.id
		state.gemStamps[id] = state.trackGeneration
		local gem = state.gems[id]
		if gem == nil and state.collected[id] == nil then
			gem = {
				part = fx.takeGem(crystal.xp),
				x = crystal.x,
				z = crystal.z,
				xp = crystal.xp,
				phase = (id * 0.618) % 1,
				parked = false,
			}
			state.gems[id] = gem
		end
		if gem then
			gem.x = crystal.x
			gem.z = crystal.z
		end
	end
	for id, gem in state.gems do
		if state.gemStamps[id] ~= state.trackGeneration then
			state.lostGems[id] = { x = gem.x, z = gem.z, xp = gem.xp, at = now }
			fx.giveGem(gem.part)
			state.gems[id] = nil
			state.gemStamps[id] = nil
		end
	end
	for id, lost in state.lostGems do
		if now - lost.at > OBJECT.GEM_MEMORY then
			state.lostGems[id] = nil
		end
	end
	for id, at in state.collected do
		if now - at > OBJECT.GEM_MEMORY then
			state.collected[id] = nil
		end
	end
end

-- Crystal `id` was state.collected by `player`: it flies to them.
function fx.collectGem(id: number, player: number)
	local now = os.clock()
	state.collected[id] = now
	local part: Part
	local from: Vector3
	local xp: number
	local gem = state.gems[id]
	if gem then
		state.gems[id] = nil
		state.gemStamps[id] = nil
		part = gem.part
		xp = gem.xp
		from = if gem.parked then groundAt(gem.x, gem.z, OBJECT.GEM_RISE) else part.Position
	else
		local lost = state.lostGems[id]
		if lost == nil then
			return
		end
		state.lostGems[id] = nil
		xp = lost.xp
		from = groundAt(lost.x, lost.z, OBJECT.GEM_RISE)
		part = fx.takeGem(xp)
	end
	if not onScreen(from) then
		fx.giveGem(part)
		return
	end
	table.insert(
		state.flights,
		{ part = part, from = from, player = player, startedAt = now, color = fx.gemColor(xp) }
	)
end

-- Food: a meat leg per id, placed once.
type Meal = { meat: Part, bone: Part }
state.meals = {} :: { [number]: Meal }
state.mealStamps = {} :: { [number]: number }
state.freeMeals = {} :: { Meal }

function fx.newMeal(): Meal
	local meat = newEffectPart()
	meat.Name = "Food"
	meat.Shape = SHAPE.BALL
	meat.Size = OBJECT.MEAT_SIZE
	meat.Material = Enum.Material.SmoothPlastic
	meat.Color = PALETTE.MEAT_COLOR
	local halo = Instance.new("ParticleEmitter")
	configureEmitter(halo, DATA.PRESETS.halo, PALETTE.HEAL.color)
	halo.Rate = 2
	halo.Parent = meat
	local bone = newEffectPart()
	bone.Name = "FoodBone"
	bone.Shape = SHAPE.CYLINDER
	bone.Size = OBJECT.BONE_SIZE
	bone.Material = Enum.Material.SmoothPlastic
	bone.Color = PALETTE.BONE_COLOR
	return { meat = meat, bone = bone }
end

function fx.syncFoods(foods: { Protocol.FoodView })
	for _, food in foods do
		state.mealStamps[food.id] = state.trackGeneration
		if state.meals[food.id] == nil then
			local meal = table.remove(state.freeMeals) or fx.newMeal()
			local turn = CFrame.Angles(0, (food.id * 0.618 % 1) * 2 * math.pi, 0)
			local at = groundFrame(food.x, food.z, OBJECT.MEAT_RISE) * turn
			meal.meat.CFrame = at
			meal.bone.CFrame = at * CFrame.new(OBJECT.MEAT_SIZE.X * 0.55, 0, 0)
			meal.meat.Parent = state.folder
			meal.bone.Parent = state.folder
			state.meals[food.id] = meal
		end
	end
	for id, meal in state.meals do
		if state.mealStamps[id] ~= state.trackGeneration then
			meal.meat.Parent = nil
			meal.bone.Parent = nil
			state.meals[id] = nil
			state.mealStamps[id] = nil
			table.insert(state.freeMeals, meal)
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
state.areaVisuals = {} :: { [number]: AreaVisual }
state.freeAreas = {} :: { AreaVisual }
state.areaCount = 0

function fx.newAreaVisual(): AreaVisual
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
		baseTransparency = OBJECT.AREA_TRANSPARENCY,
		startedAt = 0,
		endsAt = 0,
		firstTick = 0,
		tick = 1,
		seen = 0,
	}
end

function fx.removeArea(id: number)
	local visual = state.areaVisuals[id]
	if visual == nil then
		return
	end
	state.areaVisuals[id] = nil
	state.areaCount -= 1
	visual.disc.Parent = nil
	visual.rim.part.Parent = nil
	visual.emitter.Enabled = false
	visual.host.Parent = nil
	table.insert(state.freeAreas, visual)
end

-- The oldest area drawn, to make room past the cap.
function fx.oldestArea(): number?
	local oldest: number? = nil
	local at = math.huge
	for id, visual in state.areaVisuals do
		if visual.startedAt < at then
			at = visual.startedAt
			oldest = id
		end
	end
	return oldest
end

function fx.placeArea(
	id: number,
	owner: "player" | "enemy",
	areaKind: string,
	x: number,
	z: number,
	radius: number,
	seconds: number
)
	if state.areaVisuals[id] or seconds <= 0 or radius <= 0 then
		return
	end
	if state.areaCount >= DRAW.AREA_CAP then
		local oldest = fx.oldestArea()
		if oldest then
			fx.removeArea(oldest)
		end
	end
	local visual = table.remove(state.freeAreas) or fx.newAreaVisual()
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
			rise = OBJECT.AREA_FALL_HEIGHT
		elseif tag == "fire" then
			preset = "cinders"
			rise = OBJECT.AREA_FALL_HEIGHT
		else
			preset = "shimmer"
		end
		visual.disc.Material = SHAPE.NEON
		visual.disc.Color = tint.color
		visual.baseTransparency = OBJECT.AREA_TRANSPARENCY
		visual.firstTick = Config.ranks.areaFirstTickSeconds
		visual.tick = Config.ranks.areaTickSeconds
	else
		tint = kindTint(areaKind)
		preset = "bubbles"
		visual.disc.Material = Enum.Material.SmoothPlastic
		visual.disc.Color = tint.color:Lerp(Color3.new(0, 0, 0), OBJECT.AREA_POOL_DARKEN)
		visual.baseTransparency = OBJECT.AREA_POOL_TRANSPARENCY
		local attack = attackOf(areaKind, "ground")
		visual.tick = if attack then attack.groundTickSeconds or 0.5 else 0.5
		visual.firstTick = visual.tick
	end
	visual.startedAt = now
	visual.endsAt = now + seconds
	visual.seen = now

	visual.disc.Size = Vector3.new(OBJECT.AREA_HEIGHT, diameter, diameter)
	visual.disc.CFrame = groundFrame(x, z, OBJECT.AREA_HEIGHT / 2) * SHAPE.LIE
	visual.disc.Transparency = 1
	setRingLine(visual.rim, OBJECT.AREA_RIM_STUDS, tint.core, diameter)
	visual.rim.stroke.Transparency = 1
	visual.rim.part.Size = Vector3.new(diameter, DRAW.RING_THICKNESS, diameter)
	visual.rim.part.CFrame = groundFrame(x, z, OBJECT.AREA_HEIGHT + TELEGRAPH.TELEGRAPH_LAYER)
	configureEmitter(visual.emitter, DATA.PRESETS[preset], tint.color)
	visual.emitter.Rate =
		math.clamp(OBJECT.AREA_PARTICLE_DENSITY * math.pi * radius * radius, 4, 60)
	visual.host.Size = Vector3.new(diameter * 0.9, 0.5, diameter * 0.9)
	visual.host.CFrame = groundFrame(x, z, rise)
	visual.emitter.Enabled = true
	visual.disc.Parent = state.folder
	visual.rim.part.Parent = state.folder
	visual.host.Parent = state.folder
	state.areaVisuals[id] = visual
	state.areaCount += 1
end

function fx.syncAreas(areas: { Protocol.AreaView })
	local now = os.clock()
	for _, area in areas do
		local visual = state.areaVisuals[area.id]
		if visual == nil then
			fx.placeArea(
				area.id,
				area.owner,
				area.areaKind,
				area.x,
				area.z,
				area.radius,
				area.secondsLeft
			)
			visual = state.areaVisuals[area.id]
		end
		if visual then
			visual.seen = now
			visual.endsAt = now + area.secondsLeft
		end
	end
	for id, visual in state.areaVisuals do
		if now - visual.seen > OBJECT.AREA_GRACE then
			fx.removeArea(id)
		end
	end
end

-- Fades areas in and out and pulses each with its ticks.
function fx.stepAreas(now: number)
	for id, visual in state.areaVisuals do
		if now >= visual.endsAt then
			fx.removeArea(id)
			continue
		end
		local shown = math.min(
			1,
			(now - visual.startedAt) / OBJECT.AREA_FADE_IN,
			(visual.endsAt - now) / OBJECT.AREA_FADE_OUT
		)
		local flash = 0
		local since = now - visual.startedAt - visual.firstTick
		if since >= 0 and visual.tick > 0 then
			local phase = (since % visual.tick) / visual.tick
			flash = (1 - phase) ^ 3
		end
		local opaque = (1 - visual.baseTransparency) * shown + OBJECT.AREA_PULSE * flash * shown
		visual.disc.Transparency = math.clamp(1 - opaque, 0, 1)
		visual.rim.stroke.Transparency = 1 - (1 - OBJECT.AREA_RIM_FADE) * shown
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
state.totemVisuals = {} :: { [number]: TotemVisual }
state.freeTotems = {} :: { TotemVisual }

function fx.newTotemVisual(): TotemVisual
	local pole = newEffectPart()
	pole.Name = "TotemPole"
	pole.Shape = SHAPE.CYLINDER
	pole.Size = OBJECT.TOTEM_POLE
	pole.Material = Enum.Material.Wood
	pole.Color = PALETTE.WOOD_COLOR
	local body = newEffectPart()
	body.Name = "TotemBird"
	body.Size = OBJECT.TOTEM_BODY
	local wings = {}
	for index = 1, 2 do
		local wing = newEffectPart()
		wing.Name = "TotemWing"
		wing.Size = OBJECT.TOTEM_WING
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

function fx.removeTotem(id: number)
	local visual = state.totemVisuals[id]
	if visual == nil then
		return
	end
	state.totemVisuals[id] = nil
	visual.pole.Parent = nil
	visual.body.Parent = nil
	for _, wing in visual.wings do
		wing.Parent = nil
	end
	visual.halo.Enabled = false
	table.insert(state.freeTotems, visual)
end

function fx.placeTotem(id: number, skill: string, x: number, z: number, seconds: number)
	local now = os.clock()
	local existing = state.totemVisuals[id]
	if existing then
		existing.endsAt = now + seconds
		existing.seen = now
		return
	end
	local visual = table.remove(state.freeTotems) or fx.newTotemVisual()
	local tint = tintOf(skill)
	visual.x = x
	visual.z = z
	visual.phase = (id * 0.618) % 1
	visual.endsAt = now + seconds
	visual.seen = now
	visual.pole.CFrame = groundFrame(x, z, OBJECT.TOTEM_POLE.X / 2) * SHAPE.LIE
	visual.body.Color = tint.color
	for _, wing in visual.wings do
		wing.Color = tint.core
		wing.Parent = state.folder
	end
	configureEmitter(visual.halo, DATA.PRESETS.halo, tint.color)
	visual.halo.Rate = 2
	visual.halo.Enabled = true
	visual.pole.Parent = state.folder
	visual.body.Parent = state.folder
	state.totemVisuals[id] = visual
end

function fx.syncTotems(totems: { Protocol.TotemView })
	local now = os.clock()
	for _, totem in totems do
		fx.placeTotem(totem.id, totem.skill, totem.x, totem.z, totem.secondsLeft)
	end
	for id, visual in state.totemVisuals do
		if now - visual.seen > OBJECT.AREA_GRACE then
			fx.removeTotem(id)
		end
	end
end

-- The bird idles: it state.glows in and out, turns its head and flaps.
function fx.stepTotems(now: number)
	for id, visual in state.totemVisuals do
		if now >= visual.endsAt then
			fx.removeTotem(id)
			continue
		end
		local wave = math.sin((now * OBJECT.TOTEM_GLOW_HZ + visual.phase) * 2 * math.pi)
		visual.body.Transparency = OBJECT.TOTEM_GLOW_MIN
			+ (OBJECT.TOTEM_GLOW_MAX - OBJECT.TOTEM_GLOW_MIN) * (0.5 + 0.5 * wave)
		local turn = OBJECT.TOTEM_TURN * math.sin((now * 0.3 + visual.phase) * 2 * math.pi)
		local bird = groundFrame(visual.x, visual.z, OBJECT.TOTEM_BIRD_RISE)
			* CFrame.Angles(0, turn, 0)
		visual.body.CFrame = bird
		local flap = OBJECT.TOTEM_FLAP
			* math.sin((now * OBJECT.TOTEM_FLAP_HZ + visual.phase) * 2 * math.pi)
		local reach = (OBJECT.TOTEM_BODY.X + OBJECT.TOTEM_WING.X) / 2
		visual.wings[1].CFrame = bird * CFrame.Angles(0, 0, flap) * CFrame.new(-reach, 0, 0)
		visual.wings[2].CFrame = bird * CFrame.Angles(0, 0, -flap) * CFrame.new(reach, 0, 0)
	end
end

-- The state.portal: built the first time it opens, then reused.
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
state.portal = nil :: PortalVisual?

function fx.buildPortal(): PortalVisual
	local segments = {}
	for index = 1, OBJECT.PORTAL_SEGMENTS do
		local segment = newEffectPart()
		segment.Name = "PortalSegment"
		segment.Size = OBJECT.PORTAL_SEGMENT
		segment.Color = if index % 2 == 0
			then PALETTE.PORTAL_TINT.core
			else PALETTE.PORTAL_TINT.color
		segments[index] = segment
	end
	local face = newDisc("PortalFace")
	face.Material = Enum.Material.ForceField
	face.Color = PALETTE.PORTAL_TINT.color
	face.Transparency = OBJECT.PORTAL_FACE_TRANSPARENCY
	local light = Instance.new("PointLight")
	light.Color = PALETTE.PORTAL_TINT.color
	light.Shadows = false
	light.Parent = face
	local emitter = Instance.new("ParticleEmitter")
	configureEmitter(emitter, DATA.PRESETS.swirl, PALETTE.PORTAL_TINT.color)
	emitter.Rate = OBJECT.PORTAL_MOTE_RATE
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

function fx.openPortal(x: number, z: number, seconds: number)
	local visual = state.portal or fx.buildPortal()
	state.portal = visual
	local now = os.clock()
	visual.endsAt = now + seconds
	if visual.active and visual.x == x and visual.z == z then
		-- A snapshot of the state.portal already standing: only its time left.
		return
	end
	if not visual.active then
		visual.openedAt = now
	end
	visual.active = true
	visual.x = x
	visual.z = z
	local diameter = Config.extraction.portalRadius * 2
	setRingLine(visual.rim, OBJECT.CAST_RING_STUDS * 2, PALETTE.PORTAL_TINT.core, diameter)
	visual.rim.stroke.Transparency = 0.2
	visual.rim.part.Size = Vector3.new(diameter, DRAW.RING_THICKNESS, diameter)
	visual.rim.part.CFrame = groundFrame(x, z, DRAW.DISC_HEIGHT)
	visual.rim.part.Parent = state.folder
	for _, segment in visual.segments do
		segment.Parent = state.folder
	end
	visual.face.Parent = state.folder
	visual.emitter.Enabled = true
end

function fx.closePortal()
	local visual = state.portal
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
		emit("implosion", PALETTE.PORTAL_TINT.color, centre, 1)
		emit("shimmer", PALETTE.PORTAL_TINT.core, centre, 20, Vector3.new(4, 4, 4))
	end
end

-- Spins the ring, grows it in and shrinks it before it closes.
function fx.renderPortal(now: number)
	local visual = state.portal
	if visual == nil or not visual.active then
		return
	end
	local grow = math.min(1, (now - visual.openedAt) / OBJECT.PORTAL_GROW)
	local shrink = math.clamp((visual.endsAt - now) / OBJECT.PORTAL_SHRINK, 0, 1)
	local scale = easeOut(math.min(grow, shrink))
	local full = Config.extraction.portalRadius
	local radius = math.max(full * scale, 0.05)
	local basis = groundFrame(visual.x, visual.z, full + 0.5)
		* CFrame.Angles(-OBJECT.PORTAL_TILT, 0, 0)
	local spin = now * OBJECT.PORTAL_SPIN
	for index, segment in visual.segments do
		local angle = spin + index * 2 * math.pi / OBJECT.PORTAL_SEGMENTS
		segment.CFrame = basis
			* CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			* CFrame.Angles(0, 0, angle + math.pi / 2)
	end
	local face = radius * 2 * 0.95
	visual.face.Size = Vector3.new(0.2, face, face)
	visual.face.CFrame = basis * CFrame.Angles(0, math.pi / 2, 0)
	visual.light.Brightness = OBJECT.PORTAL_LIGHT_BRIGHTNESS * scale
	visual.light.Range = full * 4
end

function fx.syncPortal(view: Protocol.PortalView?)
	if view then
		fx.openPortal(view.x, view.z, view.secondsLeft)
		return
	end
	local visual = state.portal
	if visual and visual.active and os.clock() - visual.openedAt > OBJECT.AREA_GRACE then
		fx.closePortal()
	end
end

-- The chest's state.beam, while the compass points at an unopened chest.
state.beam = nil :: Part?
state.beamHost = nil :: Part?

function fx.syncChest(world: Protocol.WorldView)
	local want = world.compassOn and not world.chest.opened
	local part = state.beam
	local host = state.beamHost
	if want and part == nil then
		local made = newEffectPart()
		made.Name = "ChestBeam"
		made.Shape = SHAPE.CYLINDER
		made.Size = Vector3.new(OBJECT.BEAM_HEIGHT, OBJECT.BEAM_WIDTH, OBJECT.BEAM_WIDTH)
		made.Color = PALETTE.GOLD.color
		made.Transparency = OBJECT.BEAM_TRANSPARENCY
		local light = Instance.new("PointLight")
		light.Color = PALETTE.GOLD.color
		light.Range = 16
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = made
		local glow = newEffectPart()
		glow.Name = "ChestGlints"
		glow.Transparency = 1
		glow.Size = Vector3.new(OBJECT.BEAM_WIDTH, OBJECT.BEAM_HEIGHT / 3, OBJECT.BEAM_WIDTH)
		local glints = Instance.new("ParticleEmitter")
		configureEmitter(glints, DATA.PRESETS.shimmer, PALETTE.GOLD.color)
		glints.Rate = 8
		glints.Parent = glow
		part = made
		host = glow
		state.beam = made
		state.beamHost = glow
	end
	if part and host then
		if want then
			local x, z = world.chest.x, world.chest.z
			part.CFrame = groundFrame(x, z, OBJECT.BEAM_HEIGHT / 2) * SHAPE.LIE
			host.CFrame = groundFrame(x, z, OBJECT.BEAM_HEIGHT / 6)
			part.Parent = state.folder
			host.Parent = state.folder
		else
			part.Parent = nil
			host.Parent = nil
		end
	end
end

function fx.renderBeam(now: number)
	local part = state.beam
	if part and part.Parent then
		local wave = math.sin(now * OBJECT.BEAM_HZ * 2 * math.pi)
		part.Transparency = OBJECT.BEAM_TRANSPARENCY + OBJECT.BEAM_PULSE * wave
	end
end

-- Barrier spheres by player, while the barrier holds; who is state.sprinting.
state.shields = {} :: { [number]: Part }
state.freeShields = {} :: { Part }
state.sprinting = {} :: { [number]: number }

function fx.newShield(): Part
	local sphere = newEffectPart()
	sphere.Name = "Barrier"
	sphere.Shape = SHAPE.BALL
	sphere.Size = Vector3.one * OBJECT.SHIELD_DIAMETER
	sphere.Material = Enum.Material.ForceField
	sphere.Color = PALETTE.BARRIER.color
	sphere.Transparency = OBJECT.SHIELD_TRANSPARENCY
	return sphere
end

function fx.syncPlayers(players: { Protocol.PlayerView })
	local holding: { [number]: boolean } = {}
	local running: { [number]: boolean } = {}
	for _, player in players do
		if player.state == "alive" and player.barrier > 0 then
			holding[player.id] = true
			if not state.shields[player.id] then
				state.shields[player.id] = table.remove(state.freeShields) or fx.newShield()
			end
		end
		if player.state == "alive" and player.sprinting then
			running[player.id] = true
			state.sprinting[player.id] = state.sprinting[player.id] or 0
		end
	end
	for id, sphere in state.shields do
		if not holding[id] then
			sphere.Parent = nil
			state.shields[id] = nil
			table.insert(state.freeShields, sphere)
		end
	end
	for id in state.sprinting do
		if not running[id] then
			state.sprinting[id] = nil
		end
	end
end

function fx.followShields()
	for id, sphere in state.shields do
		local root = characterRoot(id)
		if root then
			sphere.CFrame = CFrame.new(root.Position)
			sphere.Parent = state.folder
		else
			sphere.Parent = nil
		end
	end
end

-- Speed lines behind each state.sprinting hero, along the way it runs.
function fx.stepSprint(now: number)
	for id, nextAt in state.sprinting do
		if now < nextAt then
			continue
		end
		state.sprinting[id] = now + OBJECT.SPRINT_LINE_SECONDS
		local root = characterRoot(id)
		if root == nil or not onScreen(root.Position) then
			continue
		end
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		if flat.Magnitude < OBJECT.SPRINT_MIN_SPEED then
			continue
		end
		local back = -flat.Unit
		local side = Vector3.new(-back.Z, 0, back.X)
		for _ = 1, OBJECT.SPRINT_LINES do
			local from = root.Position
				+ back
				+ side * state.random:NextNumber(-1.2, 1.2)
				+ SHAPE.UP * state.random:NextNumber(-1.5, 1.2)
			showStreak(
				state.streaks,
				from,
				from + back * OBJECT.SPRINT_LINE_LENGTH,
				PALETTE.WHITE,
				OBJECT.SPRINT_LINE_WIDTH,
				0.3,
				OBJECT.SPRINT_LINE_SECONDS_LIVE,
				"fade"
			)
		end
	end
end

-- The extraction spell's cast circle, by player.
type CastCircle = { rim: Ring, motes: { Part }, startedAt: number, endsAt: number }
state.castCircles = {} :: { [number]: CastCircle }
state.freeCircles = {} :: { CastCircle }

function fx.endCast(player: number)
	local circle = state.castCircles[player]
	if circle == nil then
		return
	end
	state.castCircles[player] = nil
	circle.rim.part.Parent = nil
	for _, mote in circle.motes do
		mote.Parent = nil
	end
	table.insert(state.freeCircles, circle)
end

function fx.newCastCircle(): CastCircle
	local rim = newRing()
	rim.part.Name = "CastCircle"
	local motes = {}
	for index = 1, OBJECT.CAST_MOTES do
		local mote = newEffectPart()
		mote.Name = "CastMote"
		mote.Shape = SHAPE.BALL
		mote.Size = Vector3.one * OBJECT.CAST_MOTE_SIZE
		mote.Color = if index % 2 == 0 then PALETTE.PORTAL_TINT.core else PALETTE.PORTAL_TINT.color
		motes[index] = mote
	end
	return { rim = rim, motes = motes, startedAt = 0, endsAt = 0 }
end

function fx.startCast(player: number, seconds: number)
	fx.endCast(player)
	local circle = table.remove(state.freeCircles) or fx.newCastCircle()
	local now = os.clock()
	circle.startedAt = now
	circle.endsAt = now + seconds
	setRingLine(
		circle.rim,
		OBJECT.CAST_RING_STUDS,
		PALETTE.PORTAL_TINT.core,
		OBJECT.CAST_RING_DIAMETER
	)
	circle.rim.stroke.Transparency = 0.1
	circle.rim.part.Size =
		Vector3.new(OBJECT.CAST_RING_DIAMETER, DRAW.RING_THICKNESS, OBJECT.CAST_RING_DIAMETER)
	state.castCircles[player] = circle
end

-- The circle follows its caster; its motes swirl round and climb as the cast nears its end.
function fx.stepCasts(now: number)
	for player, circle in state.castCircles do
		if now >= circle.endsAt then
			fx.endCast(player)
			continue
		end
		local root = characterRoot(player)
		if root == nil then
			circle.rim.part.Parent = nil
			continue
		end
		local position = root.Position
		local progress = (now - circle.startedAt) / (circle.endsAt - circle.startedAt)
		local ground = groundFrame(position.X, position.Z, DRAW.DISC_HEIGHT)
		circle.rim.part.CFrame = ground * CFrame.Angles(0, now * OBJECT.CAST_SWIRL, 0)
		circle.rim.part.Parent = state.folder
		local radius = OBJECT.CAST_RING_DIAMETER / 2 * (1 - 0.35 * progress)
		for index, mote in circle.motes do
			local angle = now * OBJECT.CAST_SWIRL + index * 2 * math.pi / OBJECT.CAST_MOTES
			mote.CFrame = ground
				* CFrame.new(
					math.cos(angle) * radius,
					0.5 + progress * 3 + 0.3 * math.sin(angle * 2),
					math.sin(angle) * radius
				)
			mote.Parent = state.folder
		end
	end
end

-- Heroes fading out as they extract.
type Fade = { parts: { BasePart }, startedAt: number }
state.fades = {} :: { Fade }

function fx.stepFades(now: number)
	for index = #state.fades, 1, -1 do
		local fade = state.fades[index]
		local alpha = math.min(1, (now - fade.startedAt) / WORLD.EXTRACT_SECONDS)
		for _, part in fade.parts do
			part.LocalTransparencyModifier = alpha
		end
		if alpha >= 1 then
			state.fades[index] = state.fades[#state.fades]
			state.fades[#state.fades] = nil
		end
	end
end

function fx.syncTracked(snapshot: Net.Snapshot)
	state.trackGeneration += 1
	table.clear(state.previousProjectiles)
	local previous = Net.previous
	if previous then
		for _, projectile in previous.projectiles do
			state.previousProjectiles[projectile.id] = projectile
		end
	end
	for _, projectile in snapshot.projectiles do
		local style = DATA.STYLES[projectile.kind] or DATA.DEFAULT_PROJECTILE
		fx.trackPart(state.projectileTracker, projectile.id, style, projectile.x, projectile.z)
	end
	fx.sweep(state.projectileTracker)
	fx.lightTracked(state.projectileTracker, 0)
	fx.syncCrystals(snapshot.crystals)
end

-- Moves the projectiles (glided like enemies), the crystals (spinning and
-- bobbing, parked out of view) and the state.collected crystals in flight.
function fx.renderTracked(now: number)
	local latest = Net.latest
	if latest == nil then
		return
	end
	local alpha = EnemyView.interpolation()
	local count = 0
	local ground = Net.groundY()

	for _, projectile in latest.projectiles do
		local tracked = state.projectileTracker.live[projectile.id]
		if tracked then
			local x, z = projectile.x, projectile.z
			local before = state.previousProjectiles[projectile.id]
			if before then
				x = before.x + (x - before.x) * alpha
				z = before.z + (z - before.z) * alpha
			end
			count += 1
			state.moveParts[count] = tracked.part
			state.moveFrames[count] = CFrame.new(x, ground + tracked.style.height, z)
				* CFrame.Angles(0, -projectile.angle - math.pi / 2, 0)
		end
	end

	local center = fx.viewCenter()
	for _, gem in state.gems do
		if not fx.inView(center, gem.x, gem.z) then
			if not gem.parked then
				gem.parked = true
				count += 1
				state.moveParts[count] = gem.part
				state.moveFrames[count] = SHAPE.PARKED
			end
			continue
		end
		gem.parked = false
		local bob = OBJECT.GEM_BOB * math.sin((now * OBJECT.GEM_BOB_HZ + gem.phase) * 2 * math.pi)
		count += 1
		state.moveParts[count] = gem.part
		state.moveFrames[count] = CFrame.new(gem.x, ground + OBJECT.GEM_RISE + bob, gem.z)
			* CFrame.Angles(0, now * OBJECT.GEM_SPIN + gem.phase * 6, 0)
			* SHAPE.GEM_TURN
	end

	for index = #state.flights, 1, -1 do
		local flight = state.flights[index]
		local progress = (now - flight.startedAt) / OBJECT.GEM_FLY_SECONDS
		local target = heroAt(flight.player, flight.from.X, flight.from.Z)
		if progress >= 1 then
			emit("shimmer", flight.color, target, OBJECT.GEM_SPARKLE)
			fx.giveGem(flight.part)
			state.flights[index] = state.flights[#state.flights]
			state.flights[#state.flights] = nil
		else
			local position = flight.from:Lerp(target, progress * progress)
				+ SHAPE.UP * (math.sin(progress * math.pi) * 1.5)
			count += 1
			state.moveParts[count] = flight.part
			state.moveFrames[count] = CFrame.new(position) * SHAPE.GEM_TURN
		end
	end

	for index = #state.moveParts, count + 1, -1 do
		state.moveParts[index] = nil
		state.moveFrames[index] = nil
	end
	if count > 0 then
		workspace:BulkMoveTo(state.moveParts, state.moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- A jagged bolt in `tint`: segments with kinks pushed off the straight
-- line, a white core in a halo, and a fork or two off the side.
state.boltPoints = {} :: { Vector3 }

function fx.showLightning(from: Vector3, to: Vector3, tint: Tint)
	local along = to - from
	local length = along.Magnitude
	if length < 0.1 then
		return
	end
	local direction = along / length
	local sideA = direction:Cross(SHAPE.UP)
	sideA = if sideA.Magnitude < 1e-3 then Vector3.xAxis else sideA.Unit
	local sideB = direction:Cross(sideA).Unit
	local segments =
		math.clamp(math.ceil(length / SKILL.LIGHTNING_STEP), 2, SKILL.LIGHTNING_MAX_SEGMENTS)

	local previous = from
	for index = 1, segments do
		local point = to
		if index < segments then
			point = from
				+ along * (index / segments)
				+ sideA * state.random:NextNumber(-SKILL.LIGHTNING_KINK, SKILL.LIGHTNING_KINK)
				+ sideB
					* state.random:NextNumber(-SKILL.LIGHTNING_KINK, SKILL.LIGHTNING_KINK)
					* 0.5
		end
		showStreak(
			state.lightning,
			previous,
			point,
			tint.core,
			SKILL.LIGHTNING_CORE_WIDTH,
			0,
			SKILL.LIGHTNING_SECONDS,
			"flicker"
		)
		showStreak(
			state.lightning,
			previous,
			point,
			tint.color,
			SKILL.LIGHTNING_HALO_WIDTH,
			SKILL.LIGHTNING_HALO_FADE,
			SKILL.LIGHTNING_SECONDS,
			"flicker"
		)
		state.boltPoints[index] = point
		previous = point
	end

	for _ = 1, state.random:NextInteger(SKILL.FORK_MIN, SKILL.FORK_MAX) do
		local base = state.boltPoints[state.random:NextInteger(1, segments - 1)]
		local spread = sideA * state.random:NextNumber(-SKILL.FORK_SPREAD, SKILL.FORK_SPREAD)
			+ sideB * state.random:NextNumber(-SKILL.FORK_SPREAD, SKILL.FORK_SPREAD) * 0.5
		local tip = base
			+ (direction + spread).Unit
				* state.random:NextNumber(SKILL.FORK_MIN_LENGTH, SKILL.FORK_MAX_LENGTH)
		local kink = (base + tip) / 2
			+ sideA * state.random:NextNumber(-SKILL.LIGHTNING_KINK, SKILL.LIGHTNING_KINK) * 0.5
		showStreak(
			state.lightning,
			base,
			kink,
			tint.core,
			SKILL.FORK_WIDTH,
			0,
			SKILL.LIGHTNING_SECONDS,
			"flicker"
		)
		showStreak(
			state.lightning,
			kink,
			tip,
			tint.core,
			SKILL.FORK_WIDTH,
			0,
			SKILL.LIGHTNING_SECONDS,
			"flicker"
		)
	end
	table.clear(state.boltPoints)
end

-- An explosion of `radius` studs in `tint`, its counts `scale` times the full.
function fx.showExplosion(x: number, z: number, radius: number, tint: Tint, scale: number)
	local centre = groundAt(x, z, SKILL.EXPLOSION_RISE)
	if not onScreen(centre) then
		return
	end
	local diameter = radius * 2
	showGlow(centre, tint.core, 1, diameter * 0.6, 0, SKILL.EXPLOSION_CORE_SECONDS)
	showGlow(
		centre,
		tint.color,
		radius,
		diameter * 1.1,
		SKILL.EXPLOSION_GLOW_FADE,
		SKILL.EXPLOSION_GLOW_SECONDS
	)
	showRing(
		x,
		z,
		tint.color,
		1,
		diameter * 1.15,
		SKILL.EXPLOSION_RING_STUDS,
		0,
		0,
		SKILL.EXPLOSION_RING_SECONDS
	)
	local area = Vector3.new(radius, 1, radius)
	emit("flash", tint.core, centre, SKILL.EXPLOSION_FLASHES * scale)
	emit("blaze", tint.color, centre, SKILL.EXPLOSION_FLAMES * scale, area)
	emit("embers", tint.color, centre, SKILL.EXPLOSION_EMBERS * scale)
	emit("smoke", PALETTE.SMOKE_COLOR, centre, SKILL.EXPLOSION_SMOKE * scale, area)
	showGround(
		x,
		z,
		Enum.Material.CrackedLava,
		PALETTE.SCORCH_COLOR,
		1,
		diameter * 0.8,
		SKILL.SCORCH_FADE,
		SKILL.SCORCH_SECONDS
	)
	showLight(
		centre,
		tint.color,
		SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
		diameter * 1.5,
		SKILL.EXPLOSION_LIGHT_SECONDS
	)
end

-- A burst that is not fire: a disc and a ring of the radius in the tint, sparks.
function fx.showBurstDisc(x: number, z: number, radius: number, tint: Tint)
	local ground = groundAt(x, z, DRAW.DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(x, z, tint.color, 1, diameter, WORLD.SLAM_STUDS, 0, 0, WORLD.SPLASH_SECONDS)
	showDisc(x, z, 1, diameter, WORLD.SPLASH_SECONDS, tint.color, 0.5)
	emit("sparks", tint.color, ground + SHAPE.UP, WORLD.SPLASH_SPARKS * SKILL.BURST_SCALE * 2)
end

-- A nova from (x, z) in `tint`: a ring sweeping out to the radius, sparks and a light.
function fx.showNova(x: number, z: number, radius: number, tint: Tint)
	local ground = groundAt(x, z, DRAW.DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(x, z, tint.color, 1, diameter, SKILL.NOVA_RING_STUDS, 0, 0, SKILL.NOVA_RING_SECONDS)
	showDisc(x, z, 1, diameter, SKILL.NOVA_SWEEP_SECONDS, tint.core, SKILL.NOVA_SWEEP_FADE)
	local area = Vector3.new(diameter * 0.9, 1, diameter * 0.9)
	emit("sparks", tint.color, ground + SHAPE.UP, SKILL.NOVA_SPARKS, area)
	showLight(
		ground + SHAPE.UP * 2,
		tint.color,
		SKILL.NOVA_LIGHT_BRIGHTNESS,
		diameter,
		SKILL.NOVA_LIGHT_SECONDS
	)
end

-- An ice nova: the nova with spinning state.shards, mist, glints and frost left behind.
function fx.showFrostNova(x: number, z: number, radius: number)
	local ground = groundAt(x, z, DRAW.DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(
		x,
		z,
		PALETTE.ICE.color,
		1,
		diameter,
		SKILL.NOVA_RING_STUDS,
		0,
		0,
		SKILL.NOVA_RING_SECONDS
	)
	showDisc(x, z, 1, diameter, SKILL.NOVA_SWEEP_SECONDS, PALETTE.ICE.core, SKILL.NOVA_SWEEP_FADE)
	showShards(
		ground + SHAPE.UP * 1,
		SKILL.NOVA_SHARDS,
		radius,
		PALETTE.ICE,
		1,
		SKILL.NOVA_SHARD_SECONDS
	)
	local area = Vector3.new(diameter * 0.9, 1, diameter * 0.9)
	emit("mist", PALETTE.ICE.color, ground + SHAPE.UP * 0.5, SKILL.NOVA_MIST, area)
	emit("shimmer", PALETTE.ICE.core, ground + SHAPE.UP * 1, SKILL.NOVA_GLINTS, area)
	showGround(
		x,
		z,
		Enum.Material.Ice,
		PALETTE.FROST_COLOR,
		2,
		diameter,
		SKILL.FROST_FADE,
		SKILL.FROST_SECONDS
	)
	showLight(
		ground + SHAPE.UP * 2,
		PALETTE.ICE.color,
		SKILL.NOVA_LIGHT_BRIGHTNESS,
		diameter,
		SKILL.NOVA_LIGHT_SECONDS
	)
end

-- What a synergy looks like on the enemy it fired on, besides its name.
function fx.showSynergy(synergy: string, at: Vector3)
	local tint = PALETTE.SYNERGY_TINTS[synergy]
	local config = DATA.SYNERGY_CONFIGS[synergy]
	if tint == nil or config == nil then
		return
	end
	if config.kind == "spread" then
		-- The status spreads this far: a ring as wide as the reach.
		local reach = (config.radius or SKILL.SYNERGY_RING_DIAMETER / 2) * 2
		showRing(
			at.X,
			at.Z,
			tint.color,
			1,
			reach,
			SKILL.SYNERGY_RING_STUDS,
			0,
			0,
			SKILL.SYNERGY_RING_SECONDS
		)
		emit("embers", tint.color, at, SKILL.SYNERGY_SPARKS)
		return
	end
	showRing(
		at.X,
		at.Z,
		tint.color,
		1,
		SKILL.SYNERGY_RING_DIAMETER,
		SKILL.SYNERGY_RING_STUDS,
		0,
		0,
		SKILL.SYNERGY_RING_SECONDS
	)
	if config.status == "chilled" then
		showShards(
			at,
			SKILL.SHATTER_SHARDS,
			SKILL.SHATTER_REACH,
			tint,
			SKILL.SHATTER_SCALE,
			SKILL.NOVA_SHARD_SECONDS
		)
	else
		emit("shimmer", tint.color, at, SKILL.SYNERGY_GLINTS, Vector3.new(3, 3, 3))
	end
end

function fx.showImpact(at: Vector3, tint: Tint, synergy: string?)
	if synergy then
		showGlow(at, tint.core, 0.5, SKILL.SYNERGY_IMPACT_DIAMETER, 0.1, SKILL.IMPACT_SECONDS * 1.5)
		emit("sparks", tint.color, at, SKILL.SYNERGY_SPARKS)
		fx.showSynergy(synergy, at)
	else
		showGlow(at, tint.core, 0.4, SKILL.IMPACT_DIAMETER, 0.2, SKILL.IMPACT_SECONDS)
		emit("sparks", tint.color, at, SKILL.IMPACT_SPARKS)
	end
end

-- A slash: a tapered arc of state.streaks across the front of `at`, facing `facing`.
function fx.showSlash(at: Vector3, facing: number, radius: number, arc: number, color: Color3)
	local reach = radius * WORLD.SLASH_REACH
	local half = arc / 2 * WORLD.SLASH_ARC_SHARE
	local previous: Vector3? = nil
	for index = 0, WORLD.SLASH_SEGMENTS do
		local angle = facing - half + 2 * half * index / WORLD.SLASH_SEGMENTS
		local point = at + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
		if previous then
			local taper = math.sin(math.pi * (index - 0.5) / WORLD.SLASH_SEGMENTS)
			showStreak(
				state.streaks,
				previous,
				point,
				color,
				WORLD.SLASH_WIDTH * taper,
				0,
				WORLD.SLASH_SECONDS,
				"fade"
			)
		end
		previous = point
	end
	local middle = at + Vector3.new(math.cos(facing), 0, math.sin(facing)) * reach
	emit("sparks", color, middle, WORLD.SLASH_SPARKS)
end

-- A strike: a bar of light falling onto `at`, a flash and sparks.
function fx.showStrike(at: Vector3, tint: Tint)
	local top = at + SHAPE.UP * SKILL.STRIKE_HEIGHT
	showStreak(
		state.streaks,
		top,
		at,
		tint.core,
		SKILL.STRIKE_CORE_WIDTH,
		0,
		SKILL.STRIKE_SECONDS,
		"travel"
	)
	showStreak(
		state.streaks,
		top,
		at,
		tint.color,
		SKILL.STRIKE_SLEEVE_WIDTH,
		0.5,
		SKILL.STRIKE_SECONDS,
		"travel"
	)
	showGlow(at, tint.core, 0.5, SKILL.STRIKE_DIAMETER, 0.2, SKILL.STRIKE_SECONDS)
	emit("sparks", tint.color, at, SKILL.STRIKE_SPARKS)
end

-- A cone from `from` toward `facing`, `radius` long: state.streaks fanned across it.
function fx.showCone(from: Vector3, facing: number, radius: number, tint: Tint)
	local half = math.rad(Config.ranks.coneHalfAngleDegrees)
	local reach = radius * SKILL.CONE_REACH
	local preset = if tint == PALETTE.ICE
		then "mist"
		elseif tint == PALETTE.FIRE then "blaze"
		else "sparks"
	for index = 0, SKILL.CONE_STREAKS - 1 do
		local angle = facing - half + 2 * half * index / (SKILL.CONE_STREAKS - 1)
		local tip = from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
		showStreak(
			state.streaks,
			from,
			tip,
			if index % 2 == 0 then tint.color else tint.core,
			SKILL.CONE_WIDTH,
			SKILL.CONE_FADE,
			SKILL.CONE_SECONDS,
			"travel"
		)
		emit(preset, tint.color, tip, SKILL.CONE_PARTICLES)
	end
end

-- A heal on the hero at `at`: a ring rising round it and motes.
function fx.showHeroHeal(at: Vector3, motes: number)
	showRing(
		at.X,
		at.Z,
		PALETTE.HEAL.color,
		SKILL.HEAL_RING_FROM,
		SKILL.HEAL_RING_TO,
		0.35,
		0,
		SKILL.HEAL_RING_RISE,
		SKILL.HEAL_SECONDS
	)
	emit("motes", PALETTE.HEAL.color, at, motes, Vector3.new(2, 3, 2))
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
-- areas, totems and state.bursts have their own events; the barrier is drawn while
-- the snapshot shows it.
function fx.onCast(event: CastEvent)
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
				showGlow(hand, tint.core, 0.3, SKILL.MUZZLE_DIAMETER, 0.2, SKILL.MUZZLE_SECONDS)
				local along = at - hand
				local tip = if skill.speed > 0 and along.Magnitude > SKILL.BOLT_LEAD
					then hand + along.Unit * SKILL.BOLT_LEAD
					else at
				showStreak(
					state.streaks,
					hand,
					tip,
					tint.core,
					SKILL.BOLT_CORE_WIDTH,
					0,
					SKILL.BOLT_SECONDS,
					"travel"
				)
				showStreak(
					state.streaks,
					hand,
					tip,
					tint.color,
					SKILL.BOLT_SLEEVE_WIDTH,
					SKILL.BOLT_SLEEVE_FADE,
					SKILL.BOLT_SECONDS,
					"travel"
				)
			elseif targeting == "scatter" then
				showStreak(
					state.streaks,
					hand,
					at,
					tint.color,
					SKILL.SCATTER_WIDTH,
					0.2,
					SKILL.SCATTER_SECONDS,
					"travel"
				)
				showGlow(at, tint.core, 0.3, SKILL.SCATTER_DIAMETER, 0.2, SKILL.SCATTER_SECONDS)
			else
				showStreak(
					state.lightning,
					from,
					at,
					tint.core,
					SKILL.ZAP_WIDTH,
					0,
					SKILL.ZAP_SECONDS,
					"flicker"
				)
			end
		end
	elseif targeting == "strike" then
		for _, id in event.targets do
			local at = EnemyView.position(id)
			if at then
				fx.showStrike(at, tint)
			end
		end
	elseif targeting == "melee" then
		fx.showSlash(from, facing, skill.range, SKILL.MELEE_ARC, tint.core)
	elseif targeting == "nova" then
		if skill.tags[1] == "ice" then
			fx.showFrostNova(event.x, event.z, event.radius)
		else
			fx.showNova(event.x, event.z, event.radius, tint)
		end
	elseif targeting == "cone" then
		fx.showCone(from, facing, event.radius, tint)
	elseif targeting == "chain" then
		local previous = handOf(from, nil)
		for index, id in event.targets do
			local at = EnemyView.position(id)
			if at == nil then
				continue
			end
			fx.showLightning(previous, at, tint)
			if index == 1 then
				showLight(
					at,
					tint.color,
					SKILL.LIGHTNING_LIGHT_BRIGHTNESS,
					SKILL.LIGHTNING_LIGHT_RANGE,
					SKILL.LIGHTNING_SECONDS
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
			diameter * SKILL.AURA_FROM,
			diameter,
			SKILL.AURA_STUDS,
			SKILL.AURA_FADE,
			0,
			SKILL.AURA_SECONDS
		)
	elseif targeting == "shield" then
		showGlow(from, PALETTE.BARRIER.core, 1, OBJECT.SHIELD_DIAMETER, 0.3, SKILL.BOLT_SECONDS * 2)
		emit("shimmer", PALETTE.BARRIER.color, from, WORLD.ABSORB_GLINTS, Vector3.new(4, 4, 4))
	elseif targeting == "heal" then
		fx.showHeroHeal(from, SKILL.HEAL_MOTES)
	elseif targeting == "thorns" then
		showShards(
			from,
			SKILL.THORN_SHARDS,
			SKILL.THORN_REACH,
			tint,
			SKILL.THORN_SCALE,
			SKILL.THORN_SECONDS
		)
		local ground = groundAt(from.X, from.Z, 0)
		showRing(
			ground.X,
			ground.Z,
			tint.color,
			1,
			SKILL.THORN_RING_DIAMETER,
			WORLD.SLAM_STUDS,
			0,
			0,
			SKILL.THORN_SECONDS
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

function fx.onHit(event: HitEvent)
	local enemyId = event.enemyId
	local at = EnemyView.position(enemyId)
	if at == nil then
		return
	end
	local visible = onScreen(at)
	local dot = PALETTE.DOT_TINTS[event.skill]
	local skill = Config.skills[event.skill]

	if event.blocked then
		if visible then
			local shield = at + forwardOf(enemyId) * SKILL.BLOCK_REACH
			showGlow(
				shield,
				PALETTE.SHIELD_COLOR,
				0.3,
				SKILL.BLOCK_DIAMETER,
				0.3,
				SKILL.BLOCK_SECONDS
			)
			emit("sparks", PALETTE.SHIELD_COLOR, shield, SKILL.BLOCK_SPARKS)
			showShards(
				shield,
				SKILL.BLOCK_SHARDS,
				SKILL.SHATTER_REACH * 0.5,
				tintFrom(PALETTE.SHIELD_COLOR),
				SKILL.BLOCK_SHARD_SCALE,
				SKILL.SYNERGY_RING_SECONDS
			)
			showNumber(at, "Blocked", PALETTE.BLOCKED_COLOR, DRAW.NUMBER_TEXT_SIZE)
		end
		return
	end

	if dot then
		if visible then
			showNumber(at, tostring(math.round(event.amount)), dot.color, DRAW.DOT_TEXT_SIZE)
		end
		return
	end
	EnemyView.flash(enemyId)
	if skill == nil or not DATA.NO_HIT_STOP[skill.targeting] then
		EnemyView.hitStop(enemyId, SKILL.HIT_STOP_SECONDS)
	end
	if not visible then
		return
	end
	local synergy = event.synergy
	fx.showImpact(at, tintOf(event.skill), synergy)
	local amount = tostring(math.round(event.amount))
	if synergy then
		local name = DATA.SYNERGY_NAMES[synergy] or synergy
		showNumber(at, name .. "! " .. amount, PALETTE.SYNERGY_COLOR, SKILL.SYNERGY_TEXT_SIZE)
	elseif event.crit then
		showNumber(at, amount .. "!", PALETTE.CRIT_COLOR, DRAW.CRIT_TEXT_SIZE)
	else
		showNumber(at, amount, PALETTE.NUMBER_COLOR, DRAW.NUMBER_TEXT_SIZE)
	end
end

function fx.onBurst(x: number, z: number, radius: number, source: string)
	local skill = Config.skills[source]
	if skill == nil then
		-- An enemy's shot landing with a splash, in the kind's colour.
		fx.showBurstDisc(x, z, radius, kindTint(source))
		return
	end
	local tag = skill.tags[1]
	local tint = tintOf(source)
	if tag == "fire" then
		fx.showExplosion(
			x,
			z,
			radius,
			tint,
			if skill.targeting == "bolt" then SKILL.BURST_SCALE else 1
		)
	elseif tag == "ice" then
		fx.showFrostNova(x, z, radius)
	else
		fx.showBurstDisc(x, z, radius, tint)
	end
	if tag == "fire" and skill.targeting ~= "bolt" and nearLocal(x, z) then
		Camera.shake(WORLD.BURST_SHAKE)
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

function fx.onEnemyAttack(event: EnemyAttackEvent)
	local enemyId = event.enemyId
	local x, z, radius = event.x, event.z, event.radius
	local at = EnemyView.position(enemyId) or groundAt(x, z, 1)
	if not onScreen(at) then
		return
	end
	local tint = kindTint(event.enemyKind)
	local kind = event.attackKind
	local ground = groundAt(x, z, DRAW.DISC_HEIGHT)
	if kind == "melee" then
		local attack = attackOf(event.enemyKind, "melee")
		local arc = if attack then attack.arcDegrees or 360 else 360
		if arc < 360 then
			fx.showSlash(at, state.enemyFacing[enemyId] or 0, radius, math.rad(arc), PALETTE.WHITE)
		else
			showRing(x, z, PALETTE.WHITE, 1, radius * 2, WORLD.SLAM_STUDS, 0, 0, WORLD.SLAM_SECONDS)
			emit(
				"puff",
				PALETTE.PUFF_COLOR,
				ground + SHAPE.UP,
				WORLD.SLAM_PUFFS,
				Vector3.new(radius, 1, radius)
			)
		end
	elseif kind == "projectile" then
		local mouth = at
			+ forwardOf(enemyId) * TELEGRAPH.MOUTH_FORWARD
			+ SHAPE.UP * TELEGRAPH.MOUTH_RISE
		emit("sparks", tint.color, mouth, WORLD.MUZZLE_PUFFS)
	elseif kind == "burst" or kind == "leap" then
		showRing(x, z, tint.color, 1, radius * 2, WORLD.SLAM_STUDS, 0, 0, WORLD.SLAM_SECONDS)
		showDisc(x, z, 1, radius * 2, WORLD.SLAM_SECONDS, tint.color, 0.5)
		emit(
			"puff",
			PALETTE.DUST_COLOR,
			ground + SHAPE.UP,
			WORLD.SLAM_PUFFS,
			Vector3.new(radius, 1, radius)
		)
		if kind == "leap" and nearLocal(x, z) then
			Camera.shake(WORLD.BURST_SHAKE)
		end
	elseif kind == "charge" then
		emit(
			"puff",
			PALETTE.DUST_COLOR,
			ground + SHAPE.UP,
			WORLD.CHARGE_PUFFS,
			Vector3.new(3, 1, 3)
		)
	elseif kind == "summon" then
		local reach = math.max(radius, TELEGRAPH.SUMMON_MIN_RADIUS) * 2
		showRing(
			x,
			z,
			PALETTE.SUMMON_TINT.color,
			1,
			reach,
			WORLD.SLAM_STUDS,
			0,
			0,
			WORLD.SLAM_SECONDS
		)
		emit(
			"motes",
			PALETTE.SUMMON_TINT.color,
			ground + SHAPE.UP,
			WORLD.SUMMON_MOTES,
			Vector3.new(reach, 1, reach)
		)
	end
end

-- A kill: the body dissolves (EnemyView), a puff and motes in the kind's colour.
function fx.onKill(enemyId: number, kindId: string, x: number, z: number)
	local at = EnemyView.position(enemyId) or groundAt(x, z, 1)
	if not onScreen(at) then
		return
	end
	local tint = kindTint(kindId)
	emit("puff", tint.color, at, WORLD.KILL_PUFFS)
	emit("motes", tint.color, at, WORLD.KILL_MOTES, Vector3.new(2, 2, 2))
	showGlow(at, tint.core, 1, WORLD.KILL_FLASH_DIAMETER, 0.5, WORLD.KILL_FLASH_SECONDS)
end

-- A boss arriving: a column of light on it and a shockwave on the ground.
function fx.showBossArrival(enemyId: number): boolean
	local at = EnemyView.position(enemyId)
	if at == nil then
		return false
	end
	local ground = groundAt(at.X, at.Z, 0)
	if onScreen(ground) then
		local top = ground + SHAPE.UP * WORLD.BOSS_COLUMN_HEIGHT
		showStreak(
			state.streaks,
			ground,
			top,
			PALETTE.DANGER.color,
			WORLD.BOSS_COLUMN_WIDTH,
			WORLD.COLUMN_FADE,
			WORLD.COLUMN_SECONDS,
			"fade"
		)
		showStreak(
			state.streaks,
			ground,
			top,
			PALETTE.DANGER.core,
			WORLD.COLUMN_CORE_WIDTH,
			0,
			WORLD.COLUMN_SECONDS,
			"fade"
		)
		showRing(
			at.X,
			at.Z,
			PALETTE.DANGER.color,
			2,
			WORLD.BOSS_WAVE_DIAMETER,
			WORLD.BOSS_WAVE_STUDS,
			0,
			0,
			WORLD.BOSS_WAVE_SECONDS
		)
		emit(
			"smoke",
			PALETTE.SMOKE_COLOR,
			ground + SHAPE.UP,
			WORLD.DEATH_SMOKE,
			Vector3.new(8, 1, 8)
		)
		showLight(
			ground + SHAPE.UP * 4,
			PALETTE.DANGER.color,
			SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
			40,
			WORLD.COLUMN_SECONDS
		)
	end
	if nearLocal(at.X, at.Z) then
		Camera.shake(WORLD.BOSS_SHAKE)
	end
	return true
end

function fx.onBossPhase(enemyId: number)
	local at = EnemyView.position(enemyId)
	if at == nil or not onScreen(at) then
		return
	end
	local size = (EnemyView.height(enemyId) or 6) * WORLD.PHASE_FLASH_SHARE
	showGlow(at, PALETTE.DANGER.color, size * 0.5, size, 0.3, WORLD.PHASE_SECONDS)
	showRing(
		at.X,
		at.Z,
		PALETTE.DANGER.color,
		2,
		WORLD.BOSS_WAVE_DIAMETER,
		WORLD.BOSS_WAVE_STUDS,
		0,
		0,
		WORLD.PHASE_SECONDS
	)
	emit("embers", PALETTE.DANGER.color, at, SKILL.EXPLOSION_EMBERS)
	showLight(
		at,
		PALETTE.DANGER.color,
		SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
		size * 3,
		WORLD.PHASE_SECONDS
	)
	if nearLocal(at.X, at.Z) then
		Camera.shake(WORLD.BOSS_SHAKE)
	end
end

function fx.onExtracted(player: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	local ground = groundAt(position.X, position.Z, 0)
	local top = ground + SHAPE.UP * WORLD.COLUMN_HEIGHT
	showStreak(
		state.streaks,
		ground,
		top,
		PALETTE.PORTAL_TINT.color,
		WORLD.COLUMN_WIDTH,
		WORLD.COLUMN_FADE,
		WORLD.COLUMN_SECONDS,
		"fade"
	)
	showStreak(
		state.streaks,
		ground,
		top,
		PALETTE.WHITE,
		WORLD.COLUMN_CORE_WIDTH,
		0,
		WORLD.COLUMN_SECONDS,
		"fade"
	)
	emit("motes", PALETTE.PORTAL_TINT.core, position, WORLD.COLUMN_MOTES, Vector3.new(3, 5, 3))
	showLight(
		position,
		PALETTE.PORTAL_TINT.color,
		SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
		30,
		WORLD.COLUMN_SECONDS
	)
	local character = root.Parent
	if character then
		local parts: { BasePart } = {}
		for _, item in character:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
			end
		end
		table.insert(state.fades, { parts = parts, startedAt = os.clock() })
	end
end

function fx.onDied(player: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	if onScreen(position) then
		showGlow(position, PALETTE.SHADOW.color, 1, WORLD.DEATH_DIAMETER, 0.2, WORLD.DEATH_SECONDS)
		showRing(
			position.X,
			position.Z,
			PALETTE.DANGER.color,
			1,
			WORLD.DEATH_DIAMETER * 2,
			WORLD.SLAM_STUDS,
			0,
			0,
			WORLD.DEATH_SECONDS
		)
		emit("smoke", PALETTE.SHADOW.color, position, WORLD.DEATH_SMOKE, Vector3.new(3, 3, 3))
		emit("embers", PALETTE.DANGER.color, position, WORLD.KILL_MOTES)
	end
	if player == Players.LocalPlayer.UserId then
		Camera.shake(WORLD.EXPLOSION_SHAKE)
	end
end

function fx.onPlayerHurt(player: number, amount: number, absorbed: number)
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local position = root.Position
	if absorbed > 0 then
		showGlow(
			position,
			PALETTE.BARRIER.core,
			1,
			WORLD.ABSORB_DIAMETER,
			0.6,
			SKILL.BLOCK_SECONDS * 2
		)
		emit("shimmer", PALETTE.BARRIER.color, position, WORLD.ABSORB_GLINTS, Vector3.new(4, 4, 4))
	end
	if amount > 0 then
		if onScreen(position) then
			showShards(
				position,
				WORLD.HURT_SHARDS,
				3,
				PALETTE.DANGER,
				WORLD.HURT_SHARD_SCALE,
				WORLD.HURT_SHARD_SECONDS
			)
		end
		if player == Players.LocalPlayer.UserId then
			Camera.shake(
				math.min(
					WORLD.HURT_SHAKE + amount * WORLD.HURT_SHAKE_PER_DAMAGE,
					WORLD.HURT_SHAKE_MAX
				)
			)
		end
	end
end

-- Puts a hero-centred effect at the player's character: motes, a heal.
function fx.atHero(player: number): Vector3?
	local root = characterRoot(player)
	if root and onScreen(root.Position) then
		return root.Position
	end
	return nil
end

function fx.onUtility(player: number, utilityId: string)
	local utility = DATA.UTILITIES[utilityId]
	local at = fx.atHero(player)
	if utility == nil or at == nil then
		return
	end
	if utility.kind == "sprint" then
		local ground = groundAt(at.X, at.Z, 0)
		emit("puff", PALETTE.DUST_COLOR, ground + SHAPE.UP, WORLD.KNOCK_PUFFS, Vector3.new(2, 1, 2))
		showRing(
			ground.X,
			ground.Z,
			PALETTE.WHITE,
			1,
			OBJECT.SHIELD_DIAMETER,
			WORLD.SLAM_STUDS * 0.5,
			0.3,
			0,
			SKILL.AURA_SECONDS
		)
		state.sprinting[player] = state.sprinting[player] or 0
	elseif utility.kind == "barrier" then
		showGlow(at, PALETTE.BARRIER.core, 1, OBJECT.SHIELD_DIAMETER, 0.3, SKILL.BOLT_SECONDS * 2)
		emit("shimmer", PALETTE.BARRIER.color, at, WORLD.ABSORB_GLINTS, Vector3.new(4, 4, 4))
	else
		fx.showHeroHeal(at, SKILL.HEAL_MOTES)
	end
end

-- A player's view in the latest snapshot.
function fx.playerView(player: number): Protocol.PlayerView?
	local latest = Net.latest
	if latest == nil then
		return nil
	end
	for _, view in latest.world.players do
		if view.id == player then
			return view
		end
	end
	return nil
end

-- Afterimages left along a dash, one every share of its time: where the
-- character stands then (so a wall that stops it stops them), or along
-- (dx, dz) from the snapshot's position without a character.
function fx.onDash(player: number, dx: number, dz: number)
	local view = fx.playerView(player)
	local root = characterRoot(player)
	local from = if root
		then root.Position
		elseif view then groundAt(view.x, view.z, SKILL.HERO_RISE)
		else nil
	if from == nil or not onScreen(from) then
		return
	end
	local class = if view then Config.classes[view.class] else nil
	local color = if class then fromHex(class.colour) else PALETTE.WHITE
	local delta = Vector3.new(dx, 0, dz)
	if delta.Magnitude < 1e-3 then
		return
	end
	local facing = CFrame.lookAt(Vector3.zero, delta).Rotation
	emit("puff", PALETTE.DUST_COLOR, from - SHAPE.UP * 2, WORLD.KNOCK_PUFFS, Vector3.new(2, 1, 2))
	local images = OBJECT.DASH_IMAGES
	for index = 0, images - 1 do
		task.delay(Config.player.dashSeconds * index / images, function()
			local now = characterRoot(player)
			local at = if now then now.Position else from + delta * (index / images)
			local slot = start(state.afterimages, OBJECT.DASH_IMAGE_SECONDS, at)
			slot.fade = OBJECT.DASH_IMAGE_FADE
			slot.part.Color = color
			slot.part.CFrame = CFrame.new(at) * facing
			state.afterimages.animate(slot, 0)
		end)
	end
end

-- Where a shrine stands: its view in the latest snapshot, or the model the
-- server drew for it.
function fx.shrinePosition(shrineId: number): Vector3?
	local latest = Net.latest
	local shrines = if latest then latest.world.shrines else nil
	if type(shrines) == "table" then
		for _, shrine in shrines do
			if shrine.id == shrineId then
				return groundAt(shrine.x, shrine.z, 0)
			end
		end
	end
	local world = workspace:FindFirstChild("World")
	local folder = if world then world:FindFirstChild("Shrines") else nil
	local model = if folder then folder:FindFirstChild("Shrine_" .. shrineId) else nil
	if model and model:IsA("PVInstance") then
		local position = model:GetPivot().Position
		return groundAt(position.X, position.Z, 0)
	end
	return nil
end

-- A burst of the shrine's kind's colour where it stands.
function fx.onShrineActivated(shrineId: number, kind: string)
	local ground = fx.shrinePosition(shrineId)
	if ground == nil or not onScreen(ground) then
		return
	end
	local tint = PALETTE.SHRINE_TINTS[kind] or PALETTE.GOLD
	local seconds = OBJECT.SHRINE_SECONDS
	showStreak(
		state.streaks,
		ground,
		ground + SHAPE.UP * OBJECT.SHRINE_COLUMN_HEIGHT,
		tint.color,
		OBJECT.SHRINE_COLUMN_WIDTH,
		OBJECT.SHRINE_COLUMN_FADE,
		seconds,
		"fade"
	)
	showRing(
		ground.X,
		ground.Z,
		tint.color,
		2,
		OBJECT.SHRINE_RING_DIAMETER,
		OBJECT.SHRINE_RING_STUDS,
		0.2,
		0,
		seconds
	)
	showGlow(
		ground + SHAPE.UP * 2,
		tint.core,
		1,
		OBJECT.SHRINE_RING_DIAMETER * 0.4,
		0.3,
		seconds * 0.4
	)
	emit("motes", tint.core, ground + SHAPE.UP * 3, OBJECT.SHRINE_MOTES, Vector3.new(4, 4, 4))
	showLight(
		ground + SHAPE.UP * 4,
		tint.color,
		SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
		OBJECT.SHRINE_LIGHT_RANGE,
		seconds
	)
end

function fx.chestPosition(): Vector3?
	local latest = Net.latest
	if latest == nil then
		return nil
	end
	local chest = latest.world.chest
	return groundAt(chest.x, chest.z, 1)
end

function fx.onEvents(events: { Types.Event }, _self: Protocol.SelfView?)
	for _, event in events do
		if event.kind == "cast" then
			fx.onCast(event)
		elseif event.kind == "hit" then
			fx.onHit(event)
		elseif event.kind == "burst" then
			fx.onBurst(event.x, event.z, event.radius, event.skill)
		elseif event.kind == "areaPlaced" then
			fx.placeArea(
				event.id,
				event.owner,
				event.areaKind,
				event.x,
				event.z,
				event.radius,
				event.seconds
			)
		elseif event.kind == "totemPlaced" then
			fx.placeTotem(event.id, event.skill, event.x, event.z, event.seconds)
			local ground = groundAt(event.x, event.z, 1)
			if onScreen(ground) then
				local tint = tintOf(event.skill)
				showRing(
					event.x,
					event.z,
					tint.color,
					1,
					6,
					WORLD.SLAM_STUDS,
					0,
					0,
					WORLD.SLAM_SECONDS
				)
				emit("motes", tint.color, ground, TELEGRAPH.WIND_UP_MOTES * 2, Vector3.new(2, 4, 2))
			end
		elseif event.kind == "statusApplied" then
			EnemyView.markStatus(event.enemyId, event.status, event.seconds)
			local at = EnemyView.position(event.enemyId)
			local tint = PALETTE.STATUS_TINTS[event.status]
			if at and tint and onScreen(at) then
				showGlow(
					at,
					tint.color,
					0.5,
					SKILL.STATUS_DIAMETER,
					SKILL.STATUS_FADE,
					SKILL.STATUS_SECONDS
				)
			end
		elseif event.kind == "kill" then
			removeMarker(event.enemyId)
			fx.onKill(event.enemyId, event.enemyKind, event.x, event.z)
		elseif event.kind == "playerHurt" then
			fx.onPlayerHurt(event.player, event.amount, event.absorbed)
		elseif event.kind == "knockback" then
			local at = fx.atHero(event.player)
			if at then
				emit(
					"puff",
					PALETTE.DUST_COLOR,
					at - SHAPE.UP * 2,
					WORLD.KNOCK_PUFFS,
					Vector3.new(2, 1, 2)
				)
			end
		elseif event.kind == "dash" then
			fx.onDash(event.player, event.dx, event.dz)
		elseif event.kind == "shrineActivated" then
			fx.onShrineActivated(event.shrineId, event.shrineKind)
		elseif event.kind == "healed" then
			local at = fx.atHero(event.player)
			if at then
				emit("motes", PALETTE.HEAL.color, at, WORLD.HERO_HEALED_MOTES, Vector3.new(2, 3, 2))
			end
		elseif event.kind == "utility" then
			fx.onUtility(event.player, event.utility)
		elseif event.kind == "telegraph" then
			fx.showTelegraph(event)
		elseif event.kind == "enemyAttack" then
			removeMarker(event.enemyId)
			fx.onEnemyAttack(event)
		elseif event.kind == "exploded" then
			removeMarker(event.enemyId)
			fx.showExplosion(event.x, event.z, event.radius, PALETTE.EXPLODER, SKILL.EXPLODER_SCALE)
			if nearLocal(event.x, event.z) then
				Camera.shake(WORLD.EXPLOSION_SHAKE)
			end
		elseif event.kind == "enemyHealed" then
			local at = EnemyView.position(event.enemyId)
			if at and onScreen(at) then
				emit("motes", PALETTE.HEAL.color, at, WORLD.HEALED_MOTES, Vector3.new(2, 2, 2))
			end
		elseif event.kind == "bossSpawned" then
			if not fx.showBossArrival(event.enemyId) then
				state.pendingBosses[event.enemyId] = os.clock()
			end
		elseif event.kind == "bossPhase" then
			fx.onBossPhase(event.enemyId)
		elseif event.kind == "closingRing" then
			local root = localRoot()
			if root then
				local diameter = Config.horde.ringRadius * 2
				local position = root.Position
				showRing(
					position.X,
					position.Z,
					PALETTE.DANGER.color,
					diameter * WORLD.CLOSING_FROM,
					diameter,
					WORLD.CLOSING_STUDS,
					0.1,
					0,
					WORLD.CLOSING_SECONDS
				)
			end
		elseif event.kind == "crystalCollected" then
			fx.collectGem(event.id, event.player)
		elseif event.kind == "foodEaten" then
			local at = fx.atHero(event.player)
			if at then
				emit("motes", PALETTE.HEAL.color, at, WORLD.FOOD_MOTES, Vector3.new(2, 3, 2))
			end
		elseif event.kind == "chestOpened" then
			local at = fx.chestPosition()
			if at and onScreen(at) then
				emit("sparks", PALETTE.GOLD.color, at, OBJECT.CHEST_SPARKS, Vector3.new(2, 1, 2))
				emit("embers", PALETTE.GOLD.color, at, OBJECT.CHEST_EMBERS)
				showGlow(at, PALETTE.GOLD.core, 1, 6, 0.3, WORLD.KILL_FLASH_SECONDS * 2)
				showLight(
					at,
					PALETTE.GOLD.color,
					SKILL.EXPLOSION_LIGHT_BRIGHTNESS,
					24,
					SKILL.EXPLOSION_LIGHT_SECONDS
				)
			end
		elseif event.kind == "castStarted" then
			fx.startCast(event.player, event.seconds)
		elseif event.kind == "castInterrupted" then
			local at = fx.atHero(event.player)
			fx.endCast(event.player)
			if at then
				showShards(
					at - SHAPE.UP * 2,
					OBJECT.CAST_SHARDS,
					4,
					PALETTE.PORTAL_TINT,
					SKILL.THORN_SCALE,
					SKILL.THORN_SECONDS
				)
				emit("implosion", PALETTE.PORTAL_TINT.color, at, 1)
			end
		elseif event.kind == "portalOpened" then
			fx.openPortal(event.x, event.z, event.seconds)
			local ground = groundAt(event.x, event.z, 1)
			if onScreen(ground) then
				showRing(
					event.x,
					event.z,
					PALETTE.PORTAL_TINT.color,
					1,
					WORLD.BOSS_WAVE_DIAMETER * 0.5,
					WORLD.BOSS_WAVE_STUDS,
					0,
					0,
					WORLD.BOSS_WAVE_SECONDS
				)
				emit(
					"motes",
					PALETTE.PORTAL_TINT.core,
					ground,
					WORLD.COLUMN_MOTES,
					Vector3.new(6, 2, 6)
				)
			end
		elseif event.kind == "portalClosed" then
			fx.closePortal()
		elseif event.kind == "extracted" then
			fx.endCast(event.player)
			fx.onExtracted(event.player)
		elseif event.kind == "died" then
			fx.endCast(event.player)
			fx.onDied(event.player)
		elseif event.kind == "levelUp" then
			local at = fx.atHero(event.player)
			if at then
				showRing(
					at.X,
					at.Z,
					PALETTE.GOLD.color,
					2,
					6,
					0.4,
					0,
					SKILL.HEAL_RING_RISE,
					WORLD.LEVEL_SECONDS
				)
				emit("motes", PALETTE.GOLD.color, at, WORLD.LEVEL_MOTES, Vector3.new(2, 3, 2))
			end
		end
		-- The rest is the Hud's: offers, cards, the compass, the timers, the end.
	end
end

function fx.syncEnemies(snapshot: Net.Snapshot)
	table.clear(state.enemyFacing)
	table.clear(state.enemyKind)
	for _, enemy in snapshot.enemies do
		state.enemyFacing[enemy.id] = enemy.facing
		state.enemyKind[enemy.id] = enemy.kind
	end
	local now = os.clock()
	for id, at in state.pendingBosses do
		if fx.showBossArrival(id) or now - at > WORLD.BOSS_WAIT then
			state.pendingBosses[id] = nil
		end
	end
end

function fx.onWorld(snapshot: Net.Snapshot)
	fx.syncEnemies(snapshot)
	fx.syncTracked(snapshot)
	local world = snapshot.world
	fx.syncFoods(world.foods)
	fx.syncAreas(world.areas)
	fx.syncTotems(world.totems)
	fx.syncPortal(world.portal)
	fx.syncChest(world)
	fx.syncPlayers(world.players)
end

function Effects.start()
	state.folder.Name = "ClientEffects"
	state.folder.Parent = workspace

	for _ = 1, DRAW.PREWARM_GEMS do
		table.insert(state.freeGems, fx.newGemPart())
	end
	Net.onEvents(fx.onEvents)
	Net.onWorld(fx.onWorld)
	local latest = Net.latest
	if latest then
		fx.onWorld(latest)
	end
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		step()
		fx.stepMarkers()
		fx.renderTracked(now)
		fx.stepAreas(now)
		fx.stepTotems(now)
		fx.renderPortal(now)
		fx.renderBeam(now)
		fx.followShields()
		fx.stepSprint(now)
		fx.stepCasts(now)
		fx.stepFades(now)
	end)
end

return Effects
