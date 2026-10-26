--!strict
-- Combat and world effects: hits, bursts, telegraphs, projectiles, pickups,
-- zones. Everything here is drawn from events and snapshots the server sent;
-- nothing is decided on the client (AGENTS.md rule 1).

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

local TRACER_SECONDS = 0.08
local TRACER_WIDTH = 0.25
local TRACER_COLOR = Color3.fromRGB(255, 240, 160)
local TRACER_POOL = 60
-- Chain Lightning: a jagged bar, two segments with a kink in the middle.
local BOLT_SECONDS = 0.18
local BOLT_WIDTH = 0.35
local BOLT_COLOR = Color3.fromRGB(150, 200, 255)
local BOLT_KINK = 1.2
-- Dash: a few bars side by side along the way the player came.
local DASH_SECONDS = 0.25
local DASH_WIDTH = 0.3
local DASH_COLOR = Color3.fromRGB(200, 240, 255)
local DASH_SPREAD = 0.8
-- Where a player was this long ago is where a dash trail starts.
local SAMPLE_SECONDS = 0.1

-- Flat discs on the ground: skill bursts, explosions, enemy attacks.
local DISC_HEIGHT = 0.15
local DISC_POOL = 60
local DISC_START_DIAMETER = 1
local BURST_SECONDS = 0.3
local BURST_DEFAULT_COLOR = Color3.fromRGB(255, 170, 70)
local BURST_COLORS: { [string]: Color3 } = {
	fireball = Color3.fromRGB(255, 140, 30),
	frostNova = Color3.fromRGB(150, 210, 255),
	spitter = Color3.fromRGB(150, 220, 60),
	campLeader = Color3.fromRGB(170, 60, 200),
}
-- Chain Lightning has no burst; the bolts are its picture.
local NO_BURST = "chainLightning"
local EXPLOSION_SECONDS = 0.4
local EXPLOSION_COLOR = Color3.fromRGB(255, 120, 20)
local ATTACK_SECONDS = 0.15
local ATTACK_COLOR = Color3.fromRGB(255, 255, 255)
local ATTACK_DEFAULT_RADIUS = 4
local ATTACK_MAX_RADIUS = 10

-- Camera shake: how hard, and how near the local character a burst must be.
local SHAKE_RANGE = 30
local BURST_SHAKE = 0.6
local EXPLOSION_SHAKE = 1
local HURT_SHAKE = 0.3
local SHAKEN_BURSTS: { [string]: boolean } = { fireball = true, frostNova = true }

-- A telegraph: a translucent disc with a brighter one filling it.
local TELEGRAPH_BASE_COLOR = Color3.fromRGB(200, 30, 30)
local TELEGRAPH_FILL_COLOR = Color3.fromRGB(255, 70, 50)
local TELEGRAPH_BASE_TRANSPARENCY = 0.65
local TELEGRAPH_FILL_TRANSPARENCY = 0.4
local TELEGRAPH_THICKNESS = 0.1
local TELEGRAPH_MIN_FILL = 0.1

local NUMBER_SECONDS = 0.8
local NUMBER_RISE = 5
local NUMBER_POOL = 40
local NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
local BLOCKED_COLOR = Color3.fromRGB(160, 160, 160)
local SYNERGY_COLOR = Color3.fromRGB(255, 200, 40)
local NUMBER_TEXT_SIZE = 22
local SYNERGY_TEXT_SIZE = 36

-- Projectiles and pickups: one pooled part per id, by what it is.
type Style = {
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	-- Height of the centre above the ground.
	height: number,
	-- Whether it carries a light, and how far it reaches.
	lightRange: number?,
	-- A cylinder stood on its end instead of lying along X.
	upright: boolean,
	-- Studs a pickup bobs up and down.
	bob: number,
}
local BALL = Enum.PartType.Ball
local PROJECTILE_HEIGHT = 2.5
local DEFAULT_PROJECTILE: Style = {
	shape = BALL,
	size = Vector3.new(1, 1, 1),
	color = Color3.fromRGB(255, 255, 255),
	height = PROJECTILE_HEIGHT,
	upright = false,
	bob = 0,
}
local STYLES: { [string]: Style } = {
	fireball = {
		shape = BALL,
		size = Vector3.new(1.5, 1.5, 1.5),
		color = Color3.fromRGB(255, 130, 30),
		height = PROJECTILE_HEIGHT,
		lightRange = 14,
		upright = false,
		bob = 0,
	},
	spitter = {
		shape = BALL,
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(130, 230, 60),
		height = PROJECTILE_HEIGHT,
		upright = false,
		bob = 0,
	},
	campLeader = {
		shape = BALL,
		size = Vector3.new(1.2, 1.2, 1.2),
		color = Color3.fromRGB(170, 60, 220),
		height = PROJECTILE_HEIGHT,
		upright = false,
		bob = 0,
	},
	potion = {
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(1.6, 0.8, 0.8),
		color = Color3.fromRGB(255, 40, 60),
		height = 1.6,
		lightRange = 8,
		upright = true,
		bob = 0.3,
	},
}
local BOB_HERTZ = 0.5

local ZONE_COLOR = Color3.fromRGB(80, 255, 140)
local ZONE_HEIGHT = 0.4
local ZONE_TRANSPARENCY = 0.6
local DOWNED_COLOR = Color3.fromRGB(255, 50, 50)
-- Pixels of the square canvas the downed ring is drawn on.
local DOWNED_CANVAS = 256

local random = Random.new()

-- An effect that lives for a moment. A pool is a ring of slots: a new effect
-- takes the next slot, so when all are alive the oldest is reused.
type Slot = {
	part: Part,
	label: TextLabel?,
	active: boolean,
	startedAt: number,
	endsAt: number,
	origin: Vector3,
	-- A disc's diameter at the start and at the end.
	from: number,
	to: number,
}

type Pool = {
	size: number,
	cursor: number,
	slots: { Slot },
	build: () -> (Part, TextLabel?),
	animate: (slot: Slot, alpha: number) -> (),
}

local folder: Folder
local pools: { Pool } = {}

local function newEffectPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	return part
end

local function newPool(
	size: number,
	build: () -> (Part, TextLabel?),
	animate: (Slot, number) -> ()
): Pool
	local pool: Pool = { size = size, cursor = 0, slots = {}, build = build, animate = animate }
	table.insert(pools, pool)
	return pool
end

-- Takes the next slot, parented and live for `seconds`.
local function start(pool: Pool, seconds: number, origin: Vector3): Slot
	pool.cursor = pool.cursor % pool.size + 1
	local slot = pool.slots[pool.cursor]
	if slot == nil then
		local part, label = pool.build()
		slot = {
			part = part,
			label = label,
			active = false,
			startedAt = 0,
			endsAt = 0,
			origin = origin,
			from = 0,
			to = 0,
		}
		pool.slots[pool.cursor] = slot
	end
	local now = os.clock()
	slot.active = true
	slot.startedAt = now
	slot.endsAt = now + seconds
	slot.origin = origin
	slot.part.Parent = folder
	return slot
end

local function step()
	local now = os.clock()
	for _, pool in pools do
		for _, slot in pool.slots do
			if slot.active then
				local alpha = (now - slot.startedAt) / (slot.endsAt - slot.startedAt)
				if alpha >= 1 then
					slot.active = false
					slot.part.Parent = nil
				else
					pool.animate(slot, alpha)
				end
			end
		end
	end
end

-- Tracers: a thin neon bar between two points that fades.
local tracers = newPool(TRACER_POOL, function()
	return newEffectPart(), nil
end, function(slot, alpha)
	slot.part.Transparency = alpha
end)

-- Discs lie flat, so the cylinder's axis (X) points up. They widen and fade.
local discs = newPool(DISC_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	return part, nil
end, function(slot, alpha)
	local diameter = slot.from + (slot.to - slot.from) * alpha
	slot.part.Size = Vector3.new(0.2, diameter, diameter)
	slot.part.Transparency = 0.3 + 0.7 * alpha
end)

-- Damage numbers: text on a billboard that rises and fades.
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
	return part, label
end, function(slot, alpha)
	slot.part.Position = slot.origin + Vector3.new(0, NUMBER_RISE * alpha, 0)
	local label = slot.label
	if label then
		label.TextTransparency = alpha * alpha
		label.TextStrokeTransparency = 0.4 + 0.6 * alpha * alpha
	end
end)

local function characterRoot(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function showTracer(from: Vector3, to: Vector3, color: Color3, width: number, seconds: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local slot = start(tracers, seconds, from)
	slot.part.Color = color
	slot.part.Size = Vector3.new(width, width, length)
	slot.part.CFrame = CFrame.lookAt((from + to) / 2, to)
	slot.part.Transparency = 0
end

-- A jagged bolt: two bars meeting at a point pushed off the straight line.
local function showBolt(from: Vector3, to: Vector3)
	local kink = (from + to) / 2
		+ Vector3.new(
			random:NextNumber(-BOLT_KINK, BOLT_KINK),
			random:NextNumber(-BOLT_KINK, BOLT_KINK) / 2,
			random:NextNumber(-BOLT_KINK, BOLT_KINK)
		)
	showTracer(from, kink, BOLT_COLOR, BOLT_WIDTH, BOLT_SECONDS)
	showTracer(kink, to, BOLT_COLOR, BOLT_WIDTH, BOLT_SECONDS)
end

-- A flat disc on the ground at (x, z) growing from `from` to `to` studs wide.
local function showDisc(
	x: number,
	z: number,
	from: number,
	to: number,
	seconds: number,
	color: Color3
)
	local slot = start(discs, seconds, Vector3.new(x, DISC_HEIGHT, z))
	slot.from = from
	slot.to = to
	slot.part.Color = color
	slot.part.CFrame = CFrame.new(x, DISC_HEIGHT, z) * CFrame.Angles(0, 0, math.pi / 2)
	slot.part.Size = Vector3.new(0.2, from, from)
	slot.part.Transparency = 0.3
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
end

-- Telegraphs: the ground marker of a wind-up, one per enemy so that a second
-- telegraph replaces the first.
type Marker = { base: Part, fill: Part, radius: number, startedAt: number, endsAt: number }
local markers: { [number]: Marker } = {}
local freeMarkers: { Marker } = {}

local function newMarker(): Marker
	local base = newEffectPart()
	base.Name = "TelegraphBase"
	base.Shape = Enum.PartType.Cylinder
	base.Color = TELEGRAPH_BASE_COLOR
	base.Transparency = TELEGRAPH_BASE_TRANSPARENCY
	local fill = newEffectPart()
	fill.Name = "TelegraphFill"
	fill.Shape = Enum.PartType.Cylinder
	fill.Color = TELEGRAPH_FILL_COLOR
	fill.Transparency = TELEGRAPH_FILL_TRANSPARENCY
	return { base = base, fill = fill, radius = 0, startedAt = 0, endsAt = 0 }
end

local function removeMarker(enemyId: number)
	local marker = markers[enemyId]
	if marker then
		markers[enemyId] = nil
		marker.base.Parent = nil
		marker.fill.Parent = nil
		table.insert(freeMarkers, marker)
	end
end

local function showTelegraph(enemyId: number, x: number, z: number, radius: number, seconds: number)
	removeMarker(enemyId)
	local marker = table.remove(freeMarkers) or newMarker()
	local now = os.clock()
	marker.radius = radius
	marker.startedAt = now
	marker.endsAt = now + seconds
	local diameter = radius * 2
	-- The cylinders' axis (X) points up; the fill sits a hair above the base.
	local lie = CFrame.Angles(0, 0, math.pi / 2)
	marker.base.Size = Vector3.new(TELEGRAPH_THICKNESS, diameter, diameter)
	marker.base.CFrame = CFrame.new(x, DISC_HEIGHT - 0.03, z) * lie
	marker.fill.Size = Vector3.new(TELEGRAPH_THICKNESS, TELEGRAPH_MIN_FILL, TELEGRAPH_MIN_FILL)
	marker.fill.CFrame = CFrame.new(x, DISC_HEIGHT + 0.03, z) * lie
	marker.base.Parent = folder
	marker.fill.Parent = folder
	markers[enemyId] = marker
end

-- Projectiles and pickups: pooled parts, one per id, drawn from the snapshots.
type Tracker = {
	free: { Part },
	live: { [number]: Part },
	stamps: { [number]: number },
}

local function newTracker(): Tracker
	return { free = {}, live = {}, stamps = {} }
end

local projectileTracker = newTracker()
local pickupTracker = newTracker()
local styleOf: { [Part]: Style } = {}
local lightOf: { [Part]: PointLight } = {}
local trackGeneration = 0
-- The previous snapshot's projectiles by id.
local previousProjectiles: { [number]: Protocol.ProjectileView } = {}
-- Reused every frame for the bulk move.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function applyStyle(part: Part, style: Style)
	part.Shape = style.shape
	part.Size = style.size
	part.Color = style.color
	local light: PointLight? = lightOf[part]
	if style.lightRange then
		local lamp = light or Instance.new("PointLight")
		if light == nil then
			lamp.Parent = part
			lightOf[part] = lamp
		end
		lamp.Color = style.color
		lamp.Range = style.lightRange
		lamp.Brightness = 2
		lamp.Enabled = true
	elseif light then
		light.Enabled = false
	end
	styleOf[part] = style
end

-- The part drawing `id`, taken from the pool the first time it is seen.
local function trackPart(tracker: Tracker, id: number, style: Style, x: number, z: number): Part
	tracker.stamps[id] = trackGeneration
	local existing: Part? = tracker.live[id]
	if existing then
		return existing
	end
	local fresh = table.remove(tracker.free) or newEffectPart()
	applyStyle(fresh, style)
	fresh.CFrame = CFrame.new(x, style.height, z)
	fresh.Parent = folder
	tracker.live[id] = fresh
	return fresh
end

local function sweep(tracker: Tracker)
	for id, part in tracker.live do
		if tracker.stamps[id] ~= trackGeneration then
			tracker.live[id] = nil
			tracker.stamps[id] = nil
			part.Parent = nil
			table.insert(tracker.free, part)
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
	for _, pickup in snapshot.world.pickups do
		local style = STYLES[pickup.kind] or DEFAULT_PROJECTILE
		trackPart(pickupTracker, pickup.id, style, pickup.x, pickup.z)
	end
	sweep(projectileTracker)
	sweep(pickupTracker)
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
		local part = projectileTracker.live[projectile.id]
		local style = if part then styleOf[part] else nil
		if part and style then
			local x, z = projectile.x, projectile.z
			local before = previousProjectiles[projectile.id]
			if before then
				x = before.x + (x - before.x) * alpha
				z = before.z + (z - before.z) * alpha
			end
			count += 1
			moveParts[count] = part
			moveFrames[count] = CFrame.new(x, style.height, z)
				* CFrame.Angles(0, -projectile.facing - math.pi / 2, 0)
		end
	end

	for _, pickup in latest.world.pickups do
		local part = pickupTracker.live[pickup.id]
		local style = if part then styleOf[part] else nil
		if part and style then
			local bob = math.sin((now * BOB_HERTZ + pickup.id * 0.37) * 2 * math.pi) * style.bob
			count += 1
			moveParts[count] = part
			moveFrames[count] = CFrame.new(pickup.x, style.height + bob, pickup.z)
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

-- Dash trails start where the player was a moment ago: each player's position
-- is sampled every SAMPLE_SECONDS, keeping the sample before the latest.
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

local function showDash(userId: number)
	local root = characterRoot(userId)
	local sample = samples[userId]
	local from = if sample then sample.previous else nil
	if root == nil or from == nil then
		return
	end
	local to = root.Position
	local along = to - from
	if along.Magnitude < 0.5 then
		return
	end
	local side = Vector3.new(-along.Z, 0, along.X).Unit * DASH_SPREAD
	for _, offset in { -side, Vector3.zero, side } do
		showTracer(from + offset, to + offset, DASH_COLOR, DASH_WIDTH, DASH_SECONDS)
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

local BASIC_SKILL = Config.classes.elementalist.basic.id
local CHAIN_SKILL = "chainLightning"
-- Where each caster's chain last ended, within one event batch.
local chainEnds: { [number]: Vector3 } = {}

local function onHit(event: Types.Event)
	if event.kind ~= "hit" then
		return
	end
	local at = EnemyView.position(event.enemyId)
	if at == nil then
		return
	end
	if not event.blocked then
		EnemyView.flash(event.enemyId)
	end
	if event.skill == BASIC_SKILL then
		local root = characterRoot(event.source)
		if root then
			showTracer(root.Position, at, TRACER_COLOR, TRACER_WIDTH, TRACER_SECONDS)
		end
	elseif event.skill == CHAIN_SKILL then
		-- Hits arrive in jump order: the first bolt leaves the caster.
		local from: Vector3? = chainEnds[event.source]
		if from == nil then
			local root = characterRoot(event.source)
			from = if root then root.Position else nil
		end
		if from then
			showBolt(from, at)
		end
		chainEnds[event.source] = at
	end
	showNumber(at, event.amount, event.synergy, event.blocked)
end

local function onBurst(x: number, z: number, radius: number, skill: string)
	if skill == NO_BURST then
		return
	end
	local color = BURST_COLORS[skill] or BURST_DEFAULT_COLOR
	showDisc(x, z, DISC_START_DIAMETER, radius * 2, BURST_SECONDS, color)
	if SHAKEN_BURSTS[skill] and nearLocal(x, z) then
		Camera.shake(BURST_SHAKE)
	end
end

local function onEnemyAttack(archetype: string, attack: number, x: number, z: number)
	local config = Config.enemies.archetypes[archetype]
	local attackConfig = if config then config.attacks[attack] else nil
	local radius = if attackConfig then attackConfig.radius else ATTACK_DEFAULT_RADIUS
	radius = math.min(radius, ATTACK_MAX_RADIUS)
	showDisc(x, z, DISC_START_DIAMETER, radius * 2, ATTACK_SECONDS, ATTACK_COLOR)
end

local function onEvents(events: { Types.Event })
	table.clear(chainEnds)
	local localId = Players.LocalPlayer.UserId
	for _, event in events do
		if event.kind == "hit" then
			onHit(event)
		elseif event.kind == "burst" then
			onBurst(event.x, event.z, event.radius, event.skill)
		elseif event.kind == "exploded" then
			showDisc(
				event.x,
				event.z,
				DISC_START_DIAMETER,
				event.radius * 2,
				EXPLOSION_SECONDS,
				EXPLOSION_COLOR
			)
			if nearLocal(event.x, event.z) then
				Camera.shake(EXPLOSION_SHAKE)
			end
		elseif event.kind == "telegraph" then
			showTelegraph(event.enemyId, event.x, event.z, event.radius, event.seconds)
		elseif event.kind == "enemyAttack" then
			onEnemyAttack(event.archetype, event.attack, event.x, event.z)
		elseif event.kind == "kill" then
			removeMarker(event.enemyId)
		elseif event.kind == "dashed" then
			showDash(event.player)
		elseif event.kind == "playerHurt" then
			if event.player == localId then
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

local function buildZone(zone: Types.Zone): ZoneVisual
	local part = newEffectPart()
	part.Name = "ExtractionZone"
	part.Shape = Enum.PartType.Cylinder
	part.Color = ZONE_COLOR
	part.Transparency = ZONE_TRANSPARENCY
	part.Size = Vector3.new(ZONE_HEIGHT, zone.radius * 2, zone.radius * 2)
	-- The cylinder's axis (X) points up.
	part.CFrame = CFrame.new(zone.x, ZONE_HEIGHT / 2, zone.z) * CFrame.Angles(0, 0, math.pi / 2)

	local light = Instance.new("PointLight")
	light.Color = ZONE_COLOR
	light.Range = zone.radius * 2
	light.Brightness = 2
	light.Parent = part

	part.Parent = folder
	return { zone = zone, part = part }
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
			ring.Position = Vector3.new(position.X, 0.15, position.Z)
		else
			ring.Parent = nil
		end
	end
end

local function stepMarkers()
	local now = os.clock()
	for enemyId, marker in markers do
		local alpha = (now - marker.startedAt) / (marker.endsAt - marker.startedAt)
		if alpha >= 1 then
			removeMarker(enemyId)
		else
			local diameter = math.max(marker.radius * 2 * alpha, TELEGRAPH_MIN_FILL)
			marker.fill.Size = Vector3.new(TELEGRAPH_THICKNESS, diameter, diameter)
		end
	end
end

local function onWorld(snapshot: Net.Snapshot)
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
