--!strict
-- Draws the enemies. The server owns them as data (ADR-0004); this keeps one
-- pooled, anchored part per enemy id and glides it between snapshots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Net = require(script.Parent.Net)

local EnemyView = {}

-- Greybox stand-in (ADR-0010): one plain part per enemy. The rigged store pack
-- replaces the part where `acquire` and `LOOKS` are used; nothing else here
-- cares what an enemy looks like. Sizes are about twice the archetype radius,
-- deeper than wide (Z is the front) so the facing reads.
type Look = { size: Vector3, color: Color3, shape: Enum.PartType }

local BLOCK = Enum.PartType.Block
local GRUNT: Look = {
	size = Vector3.new(2.6, 3, 3.4),
	color = Color3.fromRGB(205, 50, 50),
	shape = BLOCK,
}
local LOOKS: { [string]: Look } = {
	grunt = GRUNT,
	brute = {
		size = Vector3.new(4.4, 5, 5.6),
		color = Color3.fromRGB(105, 15, 15),
		shape = BLOCK,
	},
	spitter = {
		size = Vector3.new(2.2, 3, 2.8),
		color = Color3.fromRGB(150, 70, 200),
		shape = BLOCK,
	},
	exploder = {
		size = Vector3.new(2.5, 2.5, 2.5),
		color = Color3.fromRGB(255, 140, 20),
		shape = Enum.PartType.Ball,
	},
	-- Wider than deep: the broad side is the shield.
	shieldbearer = {
		size = Vector3.new(4, 4, 2.5),
		color = Color3.fromRGB(70, 130, 180),
		shape = BLOCK,
	},
	shaman = {
		size = Vector3.new(2.6, 4, 3.4),
		color = Color3.fromRGB(30, 160, 150),
		shape = BLOCK,
	},
	campLeader = {
		size = Vector3.new(5.2, 6, 6.8),
		color = Color3.fromRGB(190, 20, 60),
		shape = BLOCK,
	},
}

local CHILLED_COLOR = Color3.fromRGB(150, 210, 255)
local BURNING_COLOR = Color3.fromRGB(255, 140, 30)
local BRITTLE_COLOR = Color3.fromRGB(255, 235, 120)
local BUFFED_COLOR = Color3.fromRGB(120, 255, 130)
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
local HIT_FLASH_SECONDS = 0.08
-- How long the last drawn position of a vanished enemy stays answerable, so
-- the hit that killed it can still find it.
local DEPARTED_SECONDS = 1

-- Enemies are drawn one snapshot interval behind the newest data, so there is
-- always a next position to glide to.
local interval = 1 / Config.net.snapshotHz

local folder: Folder
local free: { Part } = {}
local parts: { [number]: Part } = {}
-- Half of each part's height: its centre stands this far above the ground.
local halfHeights: { [number]: number } = {}
local stamps: { [number]: number } = {}
-- The colour an enemy has apart from flashes, and what key it was built from.
local baseColors: { [number]: Color3 } = {}
local colorKeys: { [number]: number } = {}
-- The colour last written to the part.
local shown: { [number]: Color3 } = {}
local flashUntil: { [number]: number } = {}
-- Enemies held still for a moment by a skill hit (the hit-stop), by id.
local holdUntil: { [number]: number } = {}
local generation = 0
-- The previous snapshot's enemies by id.
local previousById: { [number]: Protocol.EnemyView } = {}
local departed: { [number]: Vector3 } = {}
local departedAt: { [number]: number } = {}
-- Reused every frame for the bulk move.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function newPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	-- Queryable so the mouse aim lands on an enemy (Input).
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function acquire(): Part
	local part = table.remove(free) or newPart()
	part.Parent = folder
	return part
end

local function release(id: number, part: Part)
	departed[id] = part.Position
	departedAt[id] = os.clock()
	part.Parent = nil
	table.insert(free, part)
	parts[id] = nil
	halfHeights[id] = nil
	stamps[id] = nil
	baseColors[id] = nil
	colorKeys[id] = nil
	shown[id] = nil
	flashUntil[id] = nil
	holdUntil[id] = nil
end

local function shade(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

-- The colour of an enemy at rest: its archetype's, shaded by level, tinted by
-- the status it carries (chilled > burning > brittle > buffed), darker as its
-- health falls.
local function baseColor(look: Look, enemy: Protocol.EnemyView): Color3
	local color = shade(look.color, LEVEL_SHADE[math.min(enemy.level, #LEVEL_SHADE)] or 1)
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

-- Runs once per snapshot: pairs parts with enemies and sets how they look.
local function sync(snapshot: Net.Snapshot)
	generation += 1
	table.clear(previousById)
	local previous = Net.previous
	if previous then
		for _, enemy in previous.enemies do
			previousById[enemy.id] = enemy
		end
	end

	for _, enemy in snapshot.enemies do
		local id = enemy.id
		local look = LOOKS[enemy.archetype] or GRUNT
		local part: Part? = parts[id]
		if part == nil then
			local fresh = acquire()
			parts[id] = fresh
			part = fresh
			-- Appears where it is, not where a stale pooled part was.
			fresh.Shape = look.shape
			fresh.Size = look.size
			fresh.CFrame = CFrame.new(
				enemy.x,
				Net.heightAt(enemy.x, enemy.z) + look.size.Y / 2,
				enemy.z
			) * CFrame.Angles(0, -enemy.facing - math.pi / 2, 0)
			halfHeights[id] = look.size.Y / 2
			departed[id] = nil
			departedAt[id] = nil
			colorKeys[id] = nil
			shown[id] = nil
		end
		stamps[id] = generation

		local key = colorKey(enemy)
		if colorKeys[id] ~= key then
			colorKeys[id] = key
			baseColors[id] = baseColor(look, enemy)
		end
	end

	for id, part in parts do
		if stamps[id] ~= generation then
			release(id, part)
		end
	end

	local now = os.clock()
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

local function render()
	local latest = Net.latest
	if latest == nil then
		return
	end
	local alpha = EnemyView.interpolation()
	local now = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(now * TELEGRAPH_HZ * 2 * math.pi)

	local count = 0
	for _, enemy in latest.enemies do
		local id = enemy.id
		local part = parts[id]
		if part then
			local x, z, facing = enemy.x, enemy.z, enemy.facing
			local before = previousById[id]
			if before then
				x = before.x + (x - before.x) * alpha
				z = before.z + (z - before.z) * alpha
				facing = before.facing + angleDelta(before.facing, facing) * alpha
			end
			count += 1
			moveParts[count] = part
			if (holdUntil[id] or 0) > now then
				-- The hit-stop: the enemy freezes where it was drawn.
				moveFrames[count] = part.CFrame
			else
				-- The part's front is -Z; the facing is measured from +X toward +Z.
				moveFrames[count] = CFrame.new(x, Net.heightAt(x, z) + halfHeights[id], z)
					* CFrame.Angles(0, -facing - math.pi / 2, 0)
			end

			local color = baseColors[id]
			if (flashUntil[id] or 0) > now then
				color = WHITE
			elseif enemy.state == "telegraph" then
				color = color:Lerp(WHITE, TELEGRAPH_FLASH * pulse)
			end
			if shown[id] ~= color then
				shown[id] = color
				part.Color = color
			end
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

-- Turns the enemy white for a moment: a hit landed on it.
function EnemyView.flash(id: number)
	if parts[id] then
		flashUntil[id] = os.clock() + HIT_FLASH_SECONDS
	end
end

-- Holds the enemy still for `seconds`: the hit-stop of a skill.
function EnemyView.hitStop(id: number, seconds: number)
	if parts[id] then
		holdUntil[id] = math.max(holdUntil[id] or 0, os.clock() + seconds)
	end
end

-- Where the enemy is drawn now, or was drawn just before it vanished.
function EnemyView.position(id: number): Vector3?
	local part = parts[id]
	if part then
		return part.Position
	end
	return departed[id]
end

function EnemyView.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEnemies"
	folder.Parent = workspace

	Net.onWorld(sync)
	local latest = Net.latest
	if latest then
		sync(latest)
	end
	RunService.RenderStepped:Connect(render)
end

return EnemyView
