--!strict
-- Draws the horde. The server owns the enemies as data (ADR-0004); this keeps
-- one pooled, anchored part per enemy id and glides it between snapshots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Net = require(script.Parent.Net)

local EnemyView = {}

type Look = { size: Vector3, color: Color3 }

local GRUNT: Look = { size = Vector3.new(3, 3, 3), color = Color3.fromRGB(205, 50, 50) }
local LOOKS: { [string]: Look } = {
	grunt = GRUNT,
	brute = { size = Vector3.new(5, 5, 5), color = Color3.fromRGB(105, 15, 15) },
}
local CHILLED_COLOR = Color3.fromRGB(150, 210, 255)
local BURNING_COLOR = Color3.fromRGB(255, 140, 30)
-- How long the last drawn position of a vanished enemy stays answerable, so
-- the hit that killed it can still find it.
local DEPARTED_SECONDS = 1

-- Enemies are drawn one snapshot interval behind the newest data, so there is
-- always a next position to glide to.
local interval = 1 / Config.net.snapshotHz

local folder: Folder
local free: { Part } = {}
local parts: { [number]: Part } = {}
local heights: { [number]: number } = {}
local stamps: { [number]: number } = {}
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
	part.CanQuery = false
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
	heights[id] = nil
	stamps[id] = nil
end

-- Chilled wins over burning.
local function tint(look: Look, chilled: boolean, burning: boolean): Color3
	if chilled then
		return CHILLED_COLOR
	elseif burning then
		return BURNING_COLOR
	end
	return look.color
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
		local look = LOOKS[enemy.kind] or GRUNT
		local existing: Part? = parts[id]
		local part: Part
		if existing then
			part = existing
		else
			part = acquire()
			parts[id] = part
			-- Appears where it is, not where a stale pooled part was.
			part.Position = Vector3.new(enemy.x, look.size.Y / 2, enemy.z)
			departed[id] = nil
			departedAt[id] = nil
		end
		stamps[id] = generation
		heights[id] = look.size.Y / 2
		if part.Size ~= look.size then
			part.Size = look.size
		end
		local color = tint(look, enemy.chilled, enemy.burning)
		if part.Color ~= color then
			part.Color = color
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

local function render()
	local latest = Net.latest
	if latest == nil then
		return
	end
	local alpha = 1
	local previous = Net.previous
	if previous then
		local span = latest.receivedAt - previous.receivedAt
		if span > 1e-3 then
			alpha = math.clamp((os.clock() - interval - previous.receivedAt) / span, 0, 1)
		end
	end

	local count = 0
	for _, enemy in latest.enemies do
		local part = parts[enemy.id]
		if part then
			local x, z = enemy.x, enemy.z
			local before = previousById[enemy.id]
			if before then
				x = before.x + (x - before.x) * alpha
				z = before.z + (z - before.z) * alpha
			end
			count += 1
			moveParts[count] = part
			moveFrames[count] = CFrame.new(x, heights[enemy.id], z)
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
