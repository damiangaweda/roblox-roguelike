--!strict
-- Combat and world effects: skills, hits, bursts, telegraphs, projectiles,
-- pickups, zones. Everything here is drawn from events and snapshots the server
-- sent; nothing is decided on the client (AGENTS.md rule 1). Every effect comes
-- from a pool with a cap, particles are thrown in bursts from pooled hosts and
-- lights are capped, so the frame budget holds however much fires at once.
-- Nothing here is a gameplay number: every constant is a look.

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

-- The palette: one tint per element, reused by every effect of it. `color` is
-- the element's own; `core` the near-white centre of its flashes.
type Tint = { color: Color3, core: Color3 }
local ARCANE: Tint = { color = Color3.fromRGB(165, 85, 255), core = Color3.fromRGB(240, 225, 255) }
local FIRE: Tint = { color = Color3.fromRGB(255, 115, 25), core = Color3.fromRGB(255, 225, 150) }
local ICE: Tint = { color = Color3.fromRGB(135, 205, 255), core = Color3.fromRGB(230, 248, 255) }
local LIGHTNING: Tint = {
	color = Color3.fromRGB(190, 175, 255),
	core = Color3.fromRGB(250, 248, 255),
}
-- A skill's tint is its first tag's; a skill without tags (the basic attack) is arcane.
local TAG_TINTS: { [string]: Tint } = { fire = FIRE, ice = ICE, lightning = LIGHTNING }
-- The enemies' own: the exploder's blast, the spitter's spit, the leader's
-- bolts, the shaman's heal; and the brittle synergy's pale gold.
local EXPLODER: Tint = { color = Color3.fromRGB(255, 70, 30), core = Color3.fromRGB(255, 210, 160) }
local SPIT: Tint = { color = Color3.fromRGB(140, 225, 50), core = Color3.fromRGB(220, 255, 170) }
local LEADER: Tint = { color = Color3.fromRGB(175, 55, 220), core = Color3.fromRGB(240, 200, 255) }
local HEAL: Tint = { color = Color3.fromRGB(90, 255, 130), core = Color3.fromRGB(215, 255, 225) }
local BRITTLE: Tint =
	{ color = Color3.fromRGB(255, 225, 110), core = Color3.fromRGB(255, 250, 220) }
-- Plain colours: a white hit, a grey block, grey smoke, scorched and frosted ground.
local WHITE = Color3.new(1, 1, 1)
local SHIELD_COLOR = Color3.fromRGB(175, 180, 190)
local SMOKE_COLOR = Color3.fromRGB(70, 66, 62)
local PUFF_COLOR = Color3.fromRGB(220, 215, 225)
local SCORCH_COLOR = Color3.fromRGB(60, 30, 18)
local FROST_COLOR = Color3.fromRGB(205, 235, 255)

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

-- Pool sizes: the most of each kind alive at once; a new one past the cap
-- reuses the oldest.
local STREAK_POOL = 120
local LIGHTNING_POOL = 160
local GLOW_POOL = 48
local RING_POOL = 32
local DISC_POOL = 32
local GROUND_POOL = 16
local SHARD_POOL = 48
local NUMBER_POOL = 40
-- Flash lights at once. With TRACKED_LIGHTS and the zones' (at most
-- Config.map.maxZones) this keeps the PointLights alive near a dozen.
local LIGHT_POOL = 5
local TRACKED_LIGHTS = 4

-- Streaks: neon bars between two points (bolts, slashes, lightning, Blink).
-- They end this share of their width wide; anything shorter is not drawn.
local STREAK_THIN = 0.3
local MIN_STREAK = 0.05
-- A travelling streak's head reaches the end in this share of its life; the
-- tail follows over the whole of it.
local TRAVEL_HEAD = 0.3
-- How much a flickering streak's transparency jumps frame to frame.
local FLICKER = 0.35

-- Character hands: this far above the root and towards the target.
local HAND_RISE = 0.6
local HAND_REACH = 1.2

-- Arcane Bolt: a white core in a violet sleeve, travelling to the hit, with a
-- flash at the hand.
local BOLT_SECONDS = 0.16
local BOLT_CORE_WIDTH = 0.3
local BOLT_SLEEVE_WIDTH = 0.9
local BOLT_SLEEVE_FADE = 0.45
local MUZZLE_SECONDS = 0.1
local MUZZLE_DIAMETER = 1.4

-- Hit impacts: a flash at the enemy and sparks in the skill's tint.
local IMPACT_SECONDS = 0.12
local IMPACT_DIAMETER = 1.8
local IMPACT_SPARKS = 8
local SYNERGY_IMPACT_DIAMETER = 3.6
local SYNERGY_SPARKS = 20
local BLOCK_SECONDS = 0.1
local BLOCK_DIAMETER = 1.2
local BLOCK_SPARKS = 7
-- How far in front of an enemy's centre its shield is.
local BLOCK_REACH = 1.5

-- Synergies: a ring on the ground in the synergy's tint, plus its own extra.
local SYNERGY_TINTS: { [string]: Tint } = { shatter = ICE, conduct = FIRE, brittle = BRITTLE }
local SYNERGY_RING_SECONDS = 0.35
local SYNERGY_RING_DIAMETER = 7
local SYNERGY_RING_STUDS = 0.4
-- Shatter: ice shards thrown off the enemy.
local SHATTER_SHARDS = 6
local SHATTER_REACH = 4
local SHATTER_SCALE = 0.6
-- Brittle: glints hanging round the enemy.
local BRITTLE_GLINTS = 14

-- Chain Lightning: a jagged bolt of short segments, a core in a halo, with
-- forks off it; a flash and a light where it jumps.
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

-- Explosions (Fireball, the exploder): a core flash, a wider glow, a
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
-- The exploder's blast against the Fireball's.
local EXPLODER_SCALE = 0.6

-- Frost Nova: an expanding ring of spinning ice shards, a pale sweep, mist,
-- glints and frost left on the ground.
local NOVA_RING_SECONDS = 0.35
local NOVA_RING_STUDS = 0.55
local NOVA_SWEEP_SECONDS = 0.3
local NOVA_SWEEP_FADE = 0.55
local NOVA_SHARDS = 10
local NOVA_SHARD_SECONDS = 0.45
local NOVA_MIST = 18
local NOVA_GLINTS = 16
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

-- Blink: a streak from where the player was to where they are, two thin
-- streaks beside it and a shimmer at both ends.
local BLINK_SECONDS = 0.28
local BLINK_CORE_WIDTH = 1.2
local BLINK_SLEEVE_WIDTH = 2.6
local BLINK_SLEEVE_FADE = 0.6
local BLINK_SIDE_WIDTH = 0.2
local BLINK_SPREAD = 0.9
local BLINK_SHIMMER = 14
local BLINK_FLASH_DIAMETER = 3
-- Where a player was this long ago is where a Blink streak starts.
local SAMPLE_SECONDS = 0.1

-- Kills: motes in the killing skill's tint, a soft puff and a small flash.
local KILL_MOTES = 14
local KILL_PUFFS = 5
local KILL_FLASH_DIAMETER = 3
local KILL_FLASH_SECONDS = 0.25
-- How long the skill that last hit an enemy is remembered after it is gone.
local HIT_MEMORY_SECONDS = 2

-- The local player hurt: white sparks at the character.
local HURT_SPARKS = 10

-- A potion drunk: a green ring rising round the character, and motes.
local DRANK_SECONDS = 0.7
local DRANK_FROM = 2
local DRANK_TO = 5
local DRANK_RISE = 4
local DRANK_MOTES = 12
-- The shaman's heal landing on an enemy.
local HEALED_MOTES = 6

-- Enemy attacks landing. A melee hit is a slash: a tapered arc of streaks in
-- front of the enemy; an all-round slam is a ring. A shot is a puff at the mouth.
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
-- Splashes of enemy projectiles that land with a radius (the leader's).
local SPLASH_SECONDS = 0.3
local SPLASH_SPARKS = 10
local BURST_TINTS: { [string]: Tint } = { spitter = SPIT, campLeader = LEADER }

-- Discs: flat neon cylinders on the ground. Heights here are above the
-- ground, which Net.heightAt gives.
local DISC_HEIGHT = 0.15
-- Rings: a thin line on a flat SurfaceGui, this many canvas pixels per stud.
local RING_THICKNESS = 0.05
local RING_PIXELS_PER_STUD = 16
local RING_BRIGHTNESS = 2.5
-- Studs of open middle a ring keeps at its narrowest.
local RING_MIN_HOLE = 0.5

-- Camera shake: how hard, and how near the local character a burst must be.
local SHAKE_RANGE = 30
local BURST_SHAKE = 0.6
local EXPLOSION_SHAKE = 1
local HURT_SHAKE = 0.3
local SHAKEN_BURSTS: { [string]: boolean } = { fireball = true, frostNova = true }

-- Telegraphs: a translucent base, a brighter fill growing from the centre and
-- a rim at the edge that brightens as the attack nears.
local TELEGRAPH_BASE_COLOR = Color3.fromRGB(200, 30, 30)
local TELEGRAPH_FILL_COLOR = Color3.fromRGB(255, 70, 50)
local TELEGRAPH_RIM_COLOR = Color3.fromRGB(255, 150, 120)
local TELEGRAPH_BASE_TRANSPARENCY = 0.72
local TELEGRAPH_FILL_TRANSPARENCY = 0.4
local TELEGRAPH_RIM_STUDS = 0.3
local TELEGRAPH_RIM_FADE = 0.5
local TELEGRAPH_THICKNESS = 0.1
local TELEGRAPH_MIN_FILL = 0.1
-- The brute's hammer arc: a wedge on the ground drawn from triangle slices.
local WEDGE_ARCHETYPES: { [string]: boolean } = { brute = true }
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
local ORB_TINTS: { [string]: Tint } = { spitter = SPIT, campLeader = LEADER }
-- The shaman's heal: motes rise round it this often while it winds up.
local HEAL_MOTE_SECONDS = 0.25
local HEAL_MOTES = 6
local HEAL_BASE_TRANSPARENCY = 0.85
local HEAL_FILL_TRANSPARENCY = 0.7

local NUMBER_SECONDS = 0.8
local NUMBER_RISE = 5
local NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
local BLOCKED_COLOR = Color3.fromRGB(160, 160, 160)
local SYNERGY_COLOR = Color3.fromRGB(255, 200, 40)
local NUMBER_TEXT_SIZE = 22
local SYNERGY_TEXT_SIZE = 36
-- The pop: a number starts at NUMBER_POP_FROM of its size, overshoots to
-- NUMBER_POP_PEAK, then settles, each over this share of its life.
local NUMBER_POP_SHARE = 0.12
local NUMBER_POP_FROM = 0.5
local NUMBER_POP_PEAK = 1.35

-- Particle presets. Each is thrown in bursts (`Emit`) from a pooled host, or
-- streams at a rate from a tracked projectile or pickup.
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
	-- Mist: low, wide, slow puffs on the ground (Frost Nova).
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
	-- Shimmer: sparkles that hang in the air (Blink, frost glints, brittle).
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
	-- Implosion: a ring of light pulled in (Blink's arrival).
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
	-- Streams from tracked parts. Flame: the Fireball's burning core.
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
	-- Trail smoke: what the Fireball leaves in the air behind it.
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
	-- Halo: a soft glow that stays on a pickup.
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
}
-- A burst host's size when it throws from a point.
local EMIT_POINT = Vector3.new(0.2, 0.2, 0.2)

-- Projectiles and pickups: one pooled part per id, by what it is.
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
	-- A cylinder stood on its end instead of lying along X.
	upright: boolean,
	-- Studs a pickup bobs up and down.
	bob: number,
	-- A trail behind it this many studs wide; 0 for none.
	trail: number,
	-- Particles it gives off while it is live.
	streams: { Stream },
}
local BALL = Enum.PartType.Ball
local NEON = Enum.Material.Neon
local PROJECTILE_HEIGHT = 2.5
local TRAIL_SECONDS = 0.18
local TRAIL_TRANSPARENCY = 0.15
local TRACKED_LIGHT_BRIGHTNESS = 2
local POTION_COLOR = Color3.fromRGB(255, 40, 60)
local DEFAULT_PROJECTILE: Style = {
	shape = BALL,
	size = Vector3.new(1, 1, 1),
	color = WHITE,
	material = NEON,
	transparency = 0,
	glow = WHITE,
	height = PROJECTILE_HEIGHT,
	upright = false,
	bob = 0,
	trail = 0.5,
	streams = {},
}
local STYLES: { [string]: Style } = {
	fireball = {
		shape = BALL,
		size = Vector3.new(1.6, 1.6, 1.6),
		color = FIRE.core,
		material = NEON,
		transparency = 0,
		glow = FIRE.color,
		height = PROJECTILE_HEIGHT,
		lightRange = 16,
		upright = false,
		bob = 0,
		trail = 1.2,
		streams = {
			{ preset = "flame", color = FIRE.color, rate = 45 },
			{ preset = "trailSmoke", color = SMOKE_COLOR, rate = 18 },
		},
	},
	spitter = {
		shape = BALL,
		size = Vector3.new(1, 1, 1),
		color = SPIT.color,
		material = NEON,
		transparency = 0,
		glow = SPIT.color,
		height = PROJECTILE_HEIGHT,
		upright = false,
		bob = 0,
		trail = 0.6,
		streams = { { preset = "drips", color = SPIT.color, rate = 14 } },
	},
	campLeader = {
		shape = BALL,
		size = Vector3.new(1.2, 1.2, 1.2),
		color = LEADER.color,
		material = NEON,
		transparency = 0,
		glow = LEADER.color,
		height = PROJECTILE_HEIGHT,
		upright = false,
		bob = 0,
		trail = 0.8,
		streams = { { preset = "drips", color = LEADER.color, rate = 16 } },
	},
	potion = {
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1.6, 0.8, 0.8),
		color = POTION_COLOR,
		material = NEON,
		transparency = 0,
		glow = POTION_COLOR,
		height = 1.6,
		lightRange = 8,
		upright = true,
		bob = 0.3,
		trail = 0,
		streams = {
			{ preset = "shimmer", color = POTION_COLOR, rate = 4 },
			{ preset = "halo", color = POTION_COLOR, rate = 2 },
		},
	},
}
local BOB_HERTZ = 0.5

local ZONE_COLOR = Color3.fromRGB(80, 255, 140)
local ZONE_HEIGHT = 0.4
local ZONE_TRANSPARENCY = 0.6
local DOWNED_COLOR = Color3.fromRGB(255, 50, 50)
local DOWNED_HEIGHT = 0.15
-- Pixels of the square canvas the downed ring is drawn on.
local DOWNED_CANVAS = 256

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
type Ring = { part: Part, frame: Frame, stroke: UIStroke }

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
	return { part = part, frame = frame, stroke = stroke }
end

-- Sets a ring's line: `studs` thick, in `color`, kept inside the canvas.
local function setRingLine(ring: Ring, studs: number, color: Color3)
	local pixels = math.max(1, studs * RING_PIXELS_PER_STUD)
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
		ring.part.CFrame = CFrame.new(slot.origin + UP * (slot.drift * easeOut(alpha)))
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
local GROUND_SPREAD = 0.12
local GROUND_HOLD = 0.45
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

-- Where a character's hand is, reaching towards `toward`.
local function handOf(userId: number, toward: Vector3?): Vector3?
	local root = characterRoot(userId)
	if root == nil then
		return nil
	end
	local position = root.Position + UP * HAND_RISE
	if toward then
		local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
		if flat.Magnitude > 1e-3 then
			position += flat.Unit * HAND_REACH
		end
	end
	return position
end

local function groundAt(x: number, z: number, rise: number): Vector3
	return Vector3.new(x, Net.heightAt(x, z) + rise, z)
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

-- A ring on the ground (or at `at`) widening from `from` to `to` studs, its
-- line `studs` thick, rising `rise` studs as it goes.
local function showRing(
	at: Vector3,
	color: Color3,
	from: number,
	to: number,
	studs: number,
	fade: number,
	rise: number,
	seconds: number
)
	local slot = start(rings, seconds, at)
	local ring = slot.ring
	if ring == nil then
		return
	end
	-- Never narrower than its own line, which would turn the canvas inside out.
	slot.from = math.max(from, studs * 2 + RING_MIN_HOLE)
	slot.to = math.max(to, slot.from)
	slot.fade = fade
	slot.drift = rise
	setRingLine(ring, studs, color)
	ring.part.CFrame = CFrame.new(at)
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
	local at = groundAt(x, z, DISC_HEIGHT)
	local slot = start(discs, seconds, at)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Color = color
	slot.part.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
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
	local at = groundAt(x, z, DISC_HEIGHT * 0.5)
	local slot = start(grounds, seconds, at)
	slot.from = from
	slot.to = to
	slot.fade = fade
	slot.part.Material = material
	slot.part.Color = color
	slot.part.Size = Vector3.new(0.1, from, from)
	slot.part.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
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

local function showNumber(at: Vector3, amount: number, synergy: string?, blocked: boolean)
	local origin = at + Vector3.new(random:NextNumber(-1.5, 1.5), 3, random:NextNumber(-1.5, 1.5))
	local slot = start(numbers, NUMBER_SECONDS, origin)
	slot.part.Position = origin
	local label = slot.label
	if label then
		local text = tostring(math.round(amount))
		local color = NUMBER_COLOR
		local size = NUMBER_TEXT_SIZE
		if blocked then
			text = "BLOCKED"
			color = BLOCKED_COLOR
		elseif synergy then
			text = string.upper(synergy) .. "! " .. text
			color = SYNERGY_COLOR
			size = SYNERGY_TEXT_SIZE
		end
		label.Text = text
		label.TextColor3 = color
		label.TextSize = size
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.4
	end
	numbers.animate(slot, 0)
end

-- The latest snapshot's enemies: which way each faces and what it is.
local enemyFacing: { [number]: number } = {}
local enemyArchetype: { [number]: string } = {}
-- The skill that last hit each enemy, and when, for the colour of its death.
local lastSkill: { [number]: string } = {}
local lastHitAt: { [number]: number } = {}

local function syncEnemies(snapshot: Net.Snapshot)
	table.clear(enemyFacing)
	table.clear(enemyArchetype)
	for _, enemy in snapshot.enemies do
		enemyFacing[enemy.id] = enemy.facing
		enemyArchetype[enemy.id] = enemy.archetype
	end
	local now = os.clock()
	for id, at in lastHitAt do
		if enemyArchetype[id] == nil and now - at > HIT_MEMORY_SECONDS then
			lastHitAt[id] = nil
			lastSkill[id] = nil
		end
	end
end

local function forwardOf(enemyId: number): Vector3
	local facing = enemyFacing[enemyId] or 0
	return Vector3.new(math.cos(facing), 0, math.sin(facing))
end

-- Telegraphs: the wind-up of an enemy attack, one per enemy so that a second
-- telegraph replaces the first. The look follows the attack's config: a wedge
-- for the brute's arc, a swelling shell for the exploder, an orb at the mouth
-- for shooters, a green ring for the shaman's heal, a disc for the rest.
type Marker = {
	look: string,
	base: Part,
	fill: Part,
	rim: Ring,
	orb: Part,
	-- The wedge's slices, two wedge parts each: the faint base and the fill.
	sector: { WedgePart },
	sectorFill: { WedgePart },
	centre: Vector3,
	radius: number,
	-- The wedge's width in radians and the way it points.
	arc: number,
	facing: number,
	orbTint: Tint,
	startedAt: number,
	endsAt: number,
	-- When the next motes rise (the shaman's heal).
	motesAt: number,
}
local markers: { [number]: Marker } = {}
local freeMarkers: { Marker } = {}

local function newDisc(name: string): Part
	local part = newEffectPart()
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function newMarker(): Marker
	local rim = newRing()
	rim.part.Name = "TelegraphRim"
	local orb = newEffectPart()
	orb.Name = "TelegraphOrb"
	orb.Shape = Enum.PartType.Ball
	return {
		look = "disc",
		base = newDisc("TelegraphBase"),
		fill = newDisc("TelegraphFill"),
		rim = rim,
		orb = orb,
		sector = {},
		sectorFill = {},
		centre = Vector3.zero,
		radius = 0,
		arc = 0,
		facing = 0,
		orbTint = SPIT,
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

-- A wedge of `arc` radians round `facing`, `radius` studs long, from slices.
local function drawSector(
	wedges: { WedgePart },
	centre: Vector3,
	facing: number,
	arc: number,
	radius: number
)
	radius = math.max(radius, SECTOR_MIN_RADIUS)
	for slice = 0, SECTOR_SLICES - 1 do
		local from = facing - arc / 2 + arc * slice / SECTOR_SLICES
		local to = from + arc / SECTOR_SLICES
		local p0 = centre + Vector3.new(math.cos(from), 0, math.sin(from)) * radius
		local p1 = centre + Vector3.new(math.cos(to), 0, math.sin(to)) * radius
		drawTriangle(centre, p0, p1, wedges[slice * 2 + 1], wedges[slice * 2 + 2])
	end
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

local function telegraphLook(archetype: string?, attack: Types.AttackConfig?): string
	if attack == nil then
		return "disc"
	elseif attack.kind == "heal" then
		return "heal"
	elseif attack.kind == "burst" then
		return "swell"
	elseif attack.kind == "projectile" then
		return "spit"
	elseif archetype and WEDGE_ARCHETYPES[archetype] and (attack.arcDegrees or 360) < 360 then
		return "wedge"
	end
	return "disc"
end

local function showTelegraph(
	enemyId: number,
	attackIndex: number,
	x: number,
	z: number,
	radius: number,
	seconds: number
)
	removeMarker(enemyId)
	local archetype = enemyArchetype[enemyId]
	local config = if archetype then Config.enemies.archetypes[archetype] else nil
	local attack = if config then config.attacks[attackIndex] else nil
	local look = telegraphLook(archetype, attack)

	local marker = table.remove(freeMarkers) or newMarker()
	local now = os.clock()
	marker.look = look
	marker.radius = radius
	marker.startedAt = now
	marker.endsAt = now + seconds
	marker.motesAt = now
	marker.centre = groundAt(x, z, DISC_HEIGHT)
	marker.facing = enemyFacing[enemyId] or 0
	marker.arc = math.rad(if attack then attack.arcDegrees or 360 else 360)
	marker.orbTint = if archetype then ORB_TINTS[archetype] or SPIT else SPIT
	markers[enemyId] = marker

	if look == "wedge" then
		showSector(marker.sector, TELEGRAPH_BASE_COLOR, TELEGRAPH_BASE_TRANSPARENCY)
		showSector(marker.sectorFill, TELEGRAPH_FILL_COLOR, TELEGRAPH_FILL_TRANSPARENCY)
		drawSector(marker.sector, marker.centre - UP * 0.03, marker.facing, marker.arc, radius)
		drawSector(marker.sectorFill, marker.centre + UP * 0.03, marker.facing, marker.arc, 0)
		return
	end

	-- The cylinders' axis (X) points up; the fill sits a hair above the base.
	local heal = look == "heal"
	local diameter = radius * 2
	local lie = CFrame.Angles(0, 0, math.pi / 2)
	marker.base.Color = if heal then HEAL.color else TELEGRAPH_BASE_COLOR
	marker.base.Transparency = if heal then HEAL_BASE_TRANSPARENCY else TELEGRAPH_BASE_TRANSPARENCY
	marker.base.Size = Vector3.new(TELEGRAPH_THICKNESS, diameter, diameter)
	marker.base.CFrame = CFrame.new(marker.centre - UP * 0.03) * lie
	marker.fill.Color = if heal then HEAL.color else TELEGRAPH_FILL_COLOR
	marker.fill.Transparency = if heal then HEAL_FILL_TRANSPARENCY else TELEGRAPH_FILL_TRANSPARENCY
	marker.fill.Size = Vector3.new(TELEGRAPH_THICKNESS, TELEGRAPH_MIN_FILL, TELEGRAPH_MIN_FILL)
	marker.fill.CFrame = CFrame.new(marker.centre + UP * 0.03) * lie
	setRingLine(marker.rim, TELEGRAPH_RIM_STUDS, if heal then HEAL.core else TELEGRAPH_RIM_COLOR)
	marker.rim.stroke.Transparency = TELEGRAPH_RIM_FADE
	marker.rim.part.Size = Vector3.new(diameter, RING_THICKNESS, diameter)
	marker.rim.part.CFrame = CFrame.new(marker.centre + UP * 0.06)
	marker.base.Parent = folder
	marker.fill.Parent = folder
	marker.rim.part.Parent = folder

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
				local below = marker.centre - UP * 0.03
				drawSector(marker.sector, below, facing, marker.arc, marker.radius)
			end
			local above = marker.centre + UP * 0.03
			drawSector(marker.sectorFill, above, marker.facing, marker.arc, marker.radius * alpha)
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
		elseif look == "heal" and now >= marker.motesAt then
			marker.motesAt = now + HEAL_MOTE_SECONDS
			local at = EnemyView.position(enemyId)
			if at and onScreen(at) then
				emit("motes", HEAL.color, at, HEAL_MOTES, Vector3.new(4, 1, 4))
			end
		end
	end
end

-- Projectiles and pickups: pooled parts, one per id, drawn from the
-- snapshots. A part keeps its style for life, so its trail and particles are
-- built once; a part let go is hidden in place so its smoke can die out.
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
local pickupTracker = newTracker()
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

-- The part drawing `id`, taken from the pool the first time it is seen.
local function trackPart(tracker: Tracker, id: number, style: Style, x: number, z: number)
	tracker.stamps[id] = trackGeneration
	if tracker.live[id] then
		return
	end
	local free = tracker.free[style]
	local tracked = (if free then table.remove(free) else nil) or buildTracked(style)
	tracked.part.CFrame = CFrame.new(x, Net.heightAt(x, z) + style.height, z)
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
	for _, pickup in snapshot.world.pickups do
		local style = STYLES[pickup.kind] or DEFAULT_PROJECTILE
		trackPart(pickupTracker, pickup.id, style, pickup.x, pickup.z)
	end
	sweep(projectileTracker)
	sweep(pickupTracker)
	lightTracked(pickupTracker, lightTracked(projectileTracker, 0))
end

-- Moves the projectiles (glided like enemies) and the pickups (bobbing).
local function renderTracked()
	local latest = Net.latest
	if latest == nil then
		return
	end
	local alpha = EnemyView.interpolation()
	local now = os.clock()
	local count = 0

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
			moveFrames[count] = CFrame.new(x, Net.heightAt(x, z) + tracked.style.height, z)
				* CFrame.Angles(0, -projectile.facing - math.pi / 2, 0)
		end
	end

	for _, pickup in latest.world.pickups do
		local tracked = pickupTracker.live[pickup.id]
		if tracked then
			local style = tracked.style
			local bob = math.sin((now * BOB_HERTZ + pickup.id * 0.37) * 2 * math.pi) * style.bob
			count += 1
			moveParts[count] = tracked.part
			local ground = Net.heightAt(pickup.x, pickup.z)
			moveFrames[count] = CFrame.new(pickup.x, ground + style.height + bob, pickup.z)
				* (if style.upright then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity)
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

-- Blink streaks start where the player was a moment ago: each player's
-- position is sampled every SAMPLE_SECONDS, keeping the sample before the latest.
type Sample = { current: Vector3, previous: Vector3?, at: number }
local samples: { [number]: Sample } = {}

local function sampleRoots()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = characterRoot(player.UserId)
		if root then
			local sample = samples[player.UserId]
			if sample == nil then
				samples[player.UserId] = { current = root.Position, previous = nil, at = now }
			elseif now - sample.at >= SAMPLE_SECONDS then
				sample.previous = sample.current
				sample.current = root.Position
				sample.at = now
			end
		end
	end
end

-- Whether a point on the ground is close to the local character.
local function nearLocal(x: number, z: number): boolean
	local root = characterRoot(Players.LocalPlayer.UserId)
	if root == nil then
		return false
	end
	local position = root.Position
	local dx, dz = position.X - x, position.Z - z
	return dx * dx + dz * dz <= SHAKE_RANGE * SHAKE_RANGE
end

local function showBlink(userId: number)
	local root = characterRoot(userId)
	local sample = samples[userId]
	local from = if sample then sample.previous else nil
	if root == nil or from == nil then
		return
	end
	local to = root.Position
	local along = to - from
	if along.Magnitude < 0.5 or not onScreen(to) then
		return
	end
	showStreak(streaks, from, to, ARCANE.core, BLINK_CORE_WIDTH, 0, BLINK_SECONDS, "travel")
	showStreak(
		streaks,
		from,
		to,
		ARCANE.color,
		BLINK_SLEEVE_WIDTH,
		BLINK_SLEEVE_FADE,
		BLINK_SECONDS,
		"travel"
	)
	local side = Vector3.new(-along.Z, 0, along.X).Unit * BLINK_SPREAD
	for _, offset in { -side, side } do
		showStreak(
			streaks,
			from + offset,
			to + offset,
			ARCANE.color,
			BLINK_SIDE_WIDTH,
			0,
			BLINK_SECONDS,
			"fade"
		)
	end
	local body = Vector3.new(2, 4, 2)
	emit("shimmer", ARCANE.color, from, BLINK_SHIMMER, body)
	emit("shimmer", ARCANE.core, to, BLINK_SHIMMER, body)
	emit("implosion", ARCANE.color, to, 1)
	showGlow(to, ARCANE.core, 0.5, BLINK_FLASH_DIAMETER, 0.4, BLINK_SECONDS)
end

-- A jagged bolt: segments with kinks pushed off the straight line, a white
-- core in a halo, and a fork or two off the side.
local boltPoints: { Vector3 } = {}

local function showLightning(from: Vector3, to: Vector3)
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
			LIGHTNING.core,
			LIGHTNING_CORE_WIDTH,
			0,
			LIGHTNING_SECONDS,
			"flicker"
		)
		showStreak(
			lightning,
			previous,
			point,
			LIGHTNING.color,
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
		showStreak(
			lightning,
			base,
			kink,
			LIGHTNING.core,
			FORK_WIDTH,
			0,
			LIGHTNING_SECONDS,
			"flicker"
		)
		showStreak(
			lightning,
			kink,
			tip,
			LIGHTNING.core,
			FORK_WIDTH,
			0,
			LIGHTNING_SECONDS,
			"flicker"
		)
	end
	table.clear(boltPoints)
end

local function showArcaneBolt(source: number, at: Vector3)
	local hand = handOf(source, at)
	if hand == nil then
		return
	end
	showStreak(streaks, hand, at, ARCANE.core, BOLT_CORE_WIDTH, 0, BOLT_SECONDS, "travel")
	showStreak(
		streaks,
		hand,
		at,
		ARCANE.color,
		BOLT_SLEEVE_WIDTH,
		BOLT_SLEEVE_FADE,
		BOLT_SECONDS,
		"travel"
	)
	showGlow(hand, ARCANE.core, 0.3, MUZZLE_DIAMETER, 0.2, MUZZLE_SECONDS)
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
		groundAt(x, z, DISC_HEIGHT),
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

local function showFrostNova(x: number, z: number, radius: number)
	local ground = groundAt(x, z, DISC_HEIGHT)
	if not onScreen(ground) then
		return
	end
	local diameter = radius * 2
	showRing(ground, ICE.color, 1, diameter, NOVA_RING_STUDS, 0, 0, NOVA_RING_SECONDS)
	showDisc(x, z, 1, diameter, NOVA_SWEEP_SECONDS, ICE.core, NOVA_SWEEP_FADE)
	showShards(ground + UP * 1, NOVA_SHARDS, radius, ICE, 1, NOVA_SHARD_SECONDS)
	local area = Vector3.new(diameter * 0.9, 1, diameter * 0.9)
	emit("mist", ICE.color, ground + UP * 0.5, NOVA_MIST, area)
	emit("shimmer", ICE.core, ground + UP * 1, NOVA_GLINTS, area)
	showGround(x, z, Enum.Material.Ice, FROST_COLOR, 2, diameter, FROST_FADE, FROST_SECONDS)
	showLight(ground + UP * 2, ICE.color, NOVA_LIGHT_BRIGHTNESS, diameter, NOVA_LIGHT_SECONDS)
end

-- What a synergy looks like on the enemy it fired on, besides its word.
local function showSynergy(synergy: string, at: Vector3)
	local tint = SYNERGY_TINTS[synergy]
	if tint == nil then
		return
	end
	local ground = groundAt(at.X, at.Z, DISC_HEIGHT)
	if synergy == "conduct" then
		-- The burn spreads this far: a fire ring as wide as the reach.
		local reach = Config.statuses.conductRadius * 2
		showRing(ground, tint.color, 1, reach, SYNERGY_RING_STUDS, 0, 0, SYNERGY_RING_SECONDS)
		emit("embers", tint.color, at, SYNERGY_SPARKS)
		return
	end
	showRing(
		ground,
		tint.color,
		1,
		SYNERGY_RING_DIAMETER,
		SYNERGY_RING_STUDS,
		0,
		0,
		SYNERGY_RING_SECONDS
	)
	if synergy == "shatter" then
		showShards(at, SHATTER_SHARDS, SHATTER_REACH, tint, SHATTER_SCALE, NOVA_SHARD_SECONDS)
	else
		emit("shimmer", tint.color, at, BRITTLE_GLINTS, Vector3.new(3, 3, 3))
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

local BASIC_SKILL = Config.classes.elementalist.basic.id
local CHAIN_SKILL = "chainLightning"
local SKILL_TINTS: { [string]: Tint } = {}
for _, class in Config.classes do
	SKILL_TINTS[class.basic.id] = ARCANE
	for _, active in class.actives do
		local tag = active.tags[1]
		SKILL_TINTS[active.id] = if tag then TAG_TINTS[tag] or ARCANE else ARCANE
	end
end

local function tintOf(skill: string?): Tint
	return if skill then SKILL_TINTS[skill] or ARCANE else ARCANE
end

-- Where each caster's chain last ended, within one event batch.
local chainEnds: { [number]: Vector3 } = {}

local function onHit(
	source: number,
	enemyId: number,
	amount: number,
	synergy: string?,
	skill: string,
	blocked: boolean
)
	local at = EnemyView.position(enemyId)
	if at == nil then
		return
	end
	lastSkill[enemyId] = skill
	lastHitAt[enemyId] = os.clock()
	local visible = onScreen(at)

	if blocked then
		if visible then
			local shield = at + forwardOf(enemyId) * BLOCK_REACH
			showGlow(shield, SHIELD_COLOR, 0.3, BLOCK_DIAMETER, 0.3, BLOCK_SECONDS)
			emit("sparks", SHIELD_COLOR, shield, BLOCK_SPARKS)
		end
	else
		EnemyView.flash(enemyId)
		if skill ~= BASIC_SKILL then
			EnemyView.hitStop(enemyId, HIT_STOP_SECONDS)
		end
	end

	if skill == CHAIN_SKILL then
		-- Hits arrive in jump order: the first bolt leaves the caster.
		local from: Vector3? = chainEnds[source]
		local first = from == nil
		if from == nil then
			from = handOf(source, at)
		end
		if from and visible then
			showLightning(from, at)
			if first then
				showLight(
					at,
					LIGHTNING.color,
					LIGHTNING_LIGHT_BRIGHTNESS,
					LIGHTNING_LIGHT_RANGE,
					LIGHTNING_SECONDS
				)
			end
		end
		chainEnds[source] = at
	elseif skill == BASIC_SKILL and visible then
		showArcaneBolt(source, at)
	end

	if visible then
		if not blocked then
			showImpact(at, tintOf(skill), synergy)
		end
		showNumber(at, amount, synergy, blocked)
	end
end

local function onBurst(x: number, z: number, radius: number, skill: string)
	if skill == CHAIN_SKILL then
		-- Chain Lightning has no burst; the bolts are its picture.
		return
	end
	if skill == "frostNova" then
		showFrostNova(x, z, radius)
	elseif skill == "fireball" then
		showExplosion(x, z, radius, FIRE, 1)
	else
		local ground = groundAt(x, z, DISC_HEIGHT)
		if onScreen(ground) then
			local tint = BURST_TINTS[skill] or tintOf(skill)
			showRing(ground, tint.color, 1, radius * 2, SLAM_STUDS, 0, 0, SPLASH_SECONDS)
			showDisc(x, z, 1, radius * 2, SPLASH_SECONDS, tint.color, 0.5)
			emit("sparks", tint.color, ground + UP, SPLASH_SPARKS)
		end
	end
	if SHAKEN_BURSTS[skill] and nearLocal(x, z) then
		Camera.shake(BURST_SHAKE)
	end
end

-- A slash: a tapered arc of streaks across the front of the enemy.
local function showSlash(at: Vector3, facing: number, radius: number, arc: number)
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
				WHITE,
				SLASH_WIDTH * taper,
				0,
				SLASH_SECONDS,
				"fade"
			)
		end
		previous = point
	end
	local middle = at + Vector3.new(math.cos(facing), 0, math.sin(facing)) * reach
	emit("sparks", WHITE, middle, SLASH_SPARKS)
end

local function onEnemyAttack(
	enemyId: number,
	archetype: string,
	attackIndex: number,
	x: number,
	z: number
)
	local config = Config.enemies.archetypes[archetype]
	local attack = if config then config.attacks[attackIndex] else nil
	local at = EnemyView.position(enemyId) or groundAt(x, z, 1)
	if attack == nil or not onScreen(at) then
		return
	end
	if attack.kind == "melee" then
		local arc = attack.arcDegrees or 360
		if arc < 360 then
			showSlash(at, enemyFacing[enemyId] or 0, attack.radius, math.rad(arc))
		else
			local ground = groundAt(x, z, DISC_HEIGHT)
			showRing(ground, WHITE, 1, attack.radius * 2, SLAM_STUDS, 0, 0, SLAM_SECONDS)
			emit(
				"puff",
				PUFF_COLOR,
				ground + UP,
				SLAM_PUFFS,
				Vector3.new(attack.radius, 1, attack.radius)
			)
		end
	elseif attack.kind == "projectile" then
		local tint = ORB_TINTS[archetype] or SPIT
		local mouth = at + forwardOf(enemyId) * MOUTH_FORWARD + UP * MOUTH_RISE
		emit("sparks", tint.color, mouth, MUZZLE_PUFFS)
	end
end

local function onKill(enemyId: number)
	local at = EnemyView.position(enemyId)
	local tint = tintOf(lastSkill[enemyId])
	lastSkill[enemyId] = nil
	lastHitAt[enemyId] = nil
	if at == nil or not onScreen(at) then
		return
	end
	emit("motes", tint.color, at, KILL_MOTES, Vector3.new(2, 2, 2))
	emit("puff", PUFF_COLOR, at, KILL_PUFFS)
	showGlow(at, tint.core, 1, KILL_FLASH_DIAMETER, 0.5, KILL_FLASH_SECONDS)
end

local function onDrank(userId: number)
	local root = characterRoot(userId)
	if root == nil then
		return
	end
	local position = root.Position
	if not onScreen(position) then
		return
	end
	local ground = groundAt(position.X, position.Z, DISC_HEIGHT)
	showRing(ground, HEAL.color, DRANK_FROM, DRANK_TO, 0.35, 0, DRANK_RISE, DRANK_SECONDS)
	emit("motes", HEAL.color, position, DRANK_MOTES, Vector3.new(2, 3, 2))
end

local function onHealed(enemyId: number)
	local at = EnemyView.position(enemyId)
	if at and onScreen(at) then
		emit("motes", HEAL.color, at, HEALED_MOTES, Vector3.new(2, 2, 2))
	end
end

local function onEvents(events: { Types.Event })
	table.clear(chainEnds)
	local localId = Players.LocalPlayer.UserId
	for _, event in events do
		if event.kind == "hit" then
			onHit(
				event.source,
				event.enemyId,
				event.amount,
				event.synergy,
				event.skill,
				event.blocked
			)
		elseif event.kind == "burst" then
			onBurst(event.x, event.z, event.radius, event.skill)
		elseif event.kind == "exploded" then
			removeMarker(event.enemyId)
			showExplosion(event.x, event.z, event.radius, EXPLODER, EXPLODER_SCALE)
			if nearLocal(event.x, event.z) then
				Camera.shake(EXPLOSION_SHAKE)
			end
		elseif event.kind == "telegraph" then
			showTelegraph(
				event.enemyId,
				event.attack,
				event.x,
				event.z,
				event.radius,
				event.seconds
			)
		elseif event.kind == "enemyAttack" then
			removeMarker(event.enemyId)
			onEnemyAttack(event.enemyId, event.archetype, event.attack, event.x, event.z)
		elseif event.kind == "healed" then
			onHealed(event.enemyId)
		elseif event.kind == "kill" then
			removeMarker(event.enemyId)
			onKill(event.enemyId)
		elseif event.kind == "dashed" then
			showBlink(event.player)
		elseif event.kind == "drank" then
			onDrank(event.player)
		elseif event.kind == "playerHurt" then
			if event.player == localId then
				local root = characterRoot(localId)
				if root then
					emit("sparks", WHITE, root.Position, HURT_SPARKS)
				end
				Camera.shake(HURT_SHAKE)
			end
		end
	end
end

-- Zones: one neon cylinder with a light per open zone.
type ZoneVisual = { zone: Types.Zone, part: Part }
local zoneVisuals: { ZoneVisual } = {}

local function sameZone(a: Types.Zone, b: Types.Zone): boolean
	return a.x == b.x and a.z == b.z and a.radius == b.radius
end

-- Stands the zone's cylinder on the ground at its centre; its axis (X) points up.
local function placeZone(visual: ZoneVisual)
	local zone = visual.zone
	local y = Net.heightAt(zone.x, zone.z) + ZONE_HEIGHT / 2
	visual.part.CFrame = CFrame.new(zone.x, y, zone.z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function buildZone(zone: Types.Zone): ZoneVisual
	local part = newEffectPart()
	part.Name = "ExtractionZone"
	part.Shape = Enum.PartType.Cylinder
	part.Color = ZONE_COLOR
	part.Transparency = ZONE_TRANSPARENCY
	part.Size = Vector3.new(ZONE_HEIGHT, zone.radius * 2, zone.radius * 2)

	local light = Instance.new("PointLight")
	light.Color = ZONE_COLOR
	light.Range = zone.radius * 2
	light.Brightness = 2
	light.Parent = part

	local visual = { zone = zone, part = part }
	placeZone(visual)
	part.Parent = folder
	return visual
end

local function syncZones(zones: { Types.Zone })
	local unchanged = #zones == #zoneVisuals
	if unchanged then
		for index, zone in zones do
			if not sameZone(zone, zoneVisuals[index].zone) then
				unchanged = false
				break
			end
		end
	end
	if unchanged then
		return
	end
	for _, visual in zoneVisuals do
		visual.part:Destroy()
	end
	table.clear(zoneVisuals)
	for _, zone in zones do
		table.insert(zoneVisuals, buildZone(zone))
	end
end

-- Downed players: a red ring as wide as the revive reach, under the player.
local downedRings: { [number]: Part } = {}

local function buildDownedRing(): Part
	local diameter = Config.player.reviveRadius * 2
	local part = newEffectPart()
	part.Name = "DownedRing"
	part.Size = Vector3.new(diameter, 0.2, diameter)
	part.Transparency = 1

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(DOWNED_CANVAS, DOWNED_CANVAS)
	gui.LightInfluence = 0
	gui.Parent = part

	local circle = Instance.new("Frame")
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundTransparency = 1
	circle.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local stroke = Instance.new("UIStroke")
	stroke.Color = DOWNED_COLOR
	stroke.Thickness = 8
	stroke.Parent = circle

	part.Parent = folder
	return part
end

local function syncDowned(players: { Protocol.PlayerView })
	local downed: { [number]: boolean } = {}
	for _, player in players do
		if player.state == "downed" then
			downed[player.id] = true
			if not downedRings[player.id] then
				downedRings[player.id] = buildDownedRing()
			end
		end
	end
	for id, ring in downedRings do
		if not downed[id] then
			ring:Destroy()
			downedRings[id] = nil
		end
	end
end

local function followDowned()
	for id, ring in downedRings do
		local root = characterRoot(id)
		if root then
			local position = root.Position
			ring.Parent = folder
			ring.Position = Vector3.new(
				position.X,
				Net.heightAt(position.X, position.Z) + DOWNED_HEIGHT,
				position.Z
			)
		else
			ring.Parent = nil
		end
	end
end

local function onWorld(snapshot: Net.Snapshot)
	syncEnemies(snapshot)
	syncZones(snapshot.world.zones)
	syncDowned(snapshot.world.players)
	syncTracked(snapshot)
end

function Effects.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace

	Net.onEvents(onEvents)
	Net.onWorld(onWorld)
	-- Zones drawn before the map came stand at 0; the map puts them on the ground.
	Net.onMap(function()
		for _, visual in zoneVisuals do
			placeZone(visual)
		end
	end)
	local latest = Net.latest
	if latest then
		onWorld(latest)
	end
	Players.PlayerRemoving:Connect(function(player)
		samples[player.UserId] = nil
	end)
	RunService.RenderStepped:Connect(function()
		step()
		stepMarkers()
		followDowned()
		renderTracked()
		sampleRoots()
	end)
end

return Effects
