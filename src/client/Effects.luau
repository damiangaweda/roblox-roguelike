--!strict
-- Hit and zone effects. Everything here is drawn from events and snapshots the
-- server sent; nothing is decided on the client (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local EnemyView = require(script.Parent.EnemyView)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Effects = {}

local TRACER_SECONDS = 0.08
local TRACER_WIDTH = 0.25
local TRACER_COLOR = Color3.fromRGB(255, 240, 160)
local TRACER_POOL = 30

local RING_SECONDS = 0.3
local RING_START_DIAMETER = 2
local RING_END_DIAMETER = 9
local RING_COLOR = Color3.fromRGB(255, 170, 70)
local RING_POOL = 40

local NUMBER_SECONDS = 0.8
local NUMBER_RISE = 5
local NUMBER_POOL = 40
local NUMBER_COLOR = Color3.fromRGB(255, 255, 255)
local SYNERGY_COLOR = Color3.fromRGB(255, 220, 40)
local NUMBER_TEXT_SIZE = 22
local SYNERGY_TEXT_SIZE = 36

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

-- Tracers: a thin neon bar from the shooter to the enemy.
local tracers = newPool(TRACER_POOL, function()
	local part = newEffectPart()
	part.Color = TRACER_COLOR
	return part, nil
end, function(slot, alpha)
	slot.part.Transparency = alpha
end)

-- Skill hits: a disc that widens at the enemy and fades. It lies flat, so the
-- cylinder's axis (X) points up.
local rings = newPool(RING_POOL, function()
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	part.Color = RING_COLOR
	return part, nil
end, function(slot, alpha)
	local diameter = RING_START_DIAMETER + (RING_END_DIAMETER - RING_START_DIAMETER) * alpha
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

local function showTracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local slot = start(tracers, TRACER_SECONDS, from)
	slot.part.Size = Vector3.new(TRACER_WIDTH, TRACER_WIDTH, length)
	slot.part.CFrame = CFrame.lookAt((from + to) / 2, to)
	slot.part.Transparency = 0
end

local function showRing(at: Vector3)
	local slot = start(rings, RING_SECONDS, at)
	-- Lie flat on the ground.
	slot.part.CFrame = CFrame.new(at.X, 0.15, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
	slot.part.Size = Vector3.new(0.2, RING_START_DIAMETER, RING_START_DIAMETER)
	slot.part.Transparency = 0.3
end

local function showNumber(at: Vector3, amount: number, synergy: boolean)
	local origin = at + Vector3.new(random:NextNumber(-1.5, 1.5), 3, random:NextNumber(-1.5, 1.5))
	local slot = start(numbers, NUMBER_SECONDS, origin)
	slot.part.Position = origin
	local label = slot.label
	if label then
		local text = tostring(math.round(amount))
		label.Text = if synergy then "SHATTER! " .. text else text
		label.TextColor3 = if synergy then SYNERGY_COLOR else NUMBER_COLOR
		label.TextSize = if synergy then SYNERGY_TEXT_SIZE else NUMBER_TEXT_SIZE
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.4
	end
end

local function onEvents(events: { Types.Event })
	for _, event in events do
		if event.kind == "hit" then
			local at = EnemyView.position(event.enemyId)
			if at then
				if event.skill then
					showRing(at)
				else
					local root = characterRoot(event.source)
					if root then
						showTracer(root.Position, at)
					end
				end
				showNumber(at, event.amount, event.synergy)
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

local function onWorld(snapshot: Net.Snapshot)
	syncZones(snapshot.world.zones)
	syncDowned(snapshot.world.players)
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
	RunService.RenderStepped:Connect(function()
		step()
		followDowned()
	end)
end

return Effects
