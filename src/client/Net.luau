--!strict
-- The client end of every remote: sends intents, keeps the latest world, the
-- local player's own state and phase, and hands them to whoever listens. The
-- client only asks (AGENTS.md rule 1; stage 3, criterion 3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Net = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local intentRemote = remotes:WaitForChild(Protocol.remotes.intent) :: RemoteEvent
local worldRemote = remotes:WaitForChild(Protocol.remotes.world) :: RemoteEvent
local eventsRemote = remotes:WaitForChild(Protocol.remotes.events) :: RemoteEvent
local phaseRemote = remotes:WaitForChild(Protocol.remotes.phase) :: RemoteEvent

local enemyKinds = Protocol.enemyKinds(Config)
local projectileKinds = Protocol.projectileKinds(Config)

export type Snapshot = {
	-- os.clock() when it arrived, for interpolation.
	receivedAt: number,
	world: Protocol.WorldView,
	enemies: { Protocol.EnemyView },
	projectiles: { Protocol.ProjectileView },
	crystals: { Protocol.CrystalView },
}

export type Phase = "pick" | "run" | "summary"

local PHASES: { [string]: Phase } = { pick = "pick", run = "run", summary = "summary" }

-- The two latest snapshots, newest last.
Net.previous = nil :: Snapshot?
Net.latest = nil :: Snapshot?
-- The local player's own state from the latest event batch, and when it came.
Net.self = nil :: Protocol.SelfView?
Net.selfAt = 0
-- Where the local player is: choosing a class, in the run, or reading how it went.
Net.phase = "pick" :: Phase
Net.summary = nil :: Protocol.SummaryView?

local worldListeners: { (Snapshot) -> () } = {}
local eventListeners: { ({ Types.Event }, Protocol.SelfView?) -> () } = {}
local phaseListeners: { (Phase, Protocol.SummaryView?) -> () } = {}

function Net.onWorld(listener: (Snapshot) -> ())
	table.insert(worldListeners, listener)
end

function Net.onEvents(listener: ({ Types.Event }, Protocol.SelfView?) -> ())
	table.insert(eventListeners, listener)
end

function Net.onPhase(listener: (Phase, Protocol.SummaryView?) -> ())
	table.insert(phaseListeners, listener)
end

-- The ground's height where nothing is sculpted, and without a point.
local FLAT_GROUND = 0
-- The ground's height is sampled once per cell this many studs wide.
local GROUND_CELL = 4
-- A height query casts down from this high, this far.
local GROUND_RAY_TOP = 80
local GROUND_RAY_LENGTH = 200
-- Cells per row of the cache's key; a cell index sits within half of it.
local GROUND_KEY_SPAN = 2 ^ 20

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
-- Shallows are waded: things stand on the bed, not on the water.
groundParams.IgnoreWater = true

-- The ground's height per cell, keyed by the cell; cleared on every phase,
-- since every run sculpts its own terrain (ADR-0023).
local groundHeights: { [number]: number } = {}

-- The terrain's surface right under (x, z), or the flat height where no
-- terrain is.
local function castGround(x: number, z: number): number
	local origin = Vector3.new(x, GROUND_RAY_TOP, z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), groundParams)
	return if hit then hit.Position.Y else FLAT_GROUND
end

-- The ground's height under (x, z): the terrain's surface at the middle of
-- the cell around the point, cached. Without a point, the flat height.
function Net.groundY(x: number?, z: number?): number
	if x == nil or z == nil then
		return FLAT_GROUND
	end
	local cellX = math.floor(x / GROUND_CELL)
	local cellZ = math.floor(z / GROUND_CELL)
	local key = (cellX + GROUND_KEY_SPAN / 2) * GROUND_KEY_SPAN + cellZ
	local known = groundHeights[key]
	if known then
		return known
	end
	local height = castGround((cellX + 0.5) * GROUND_CELL, (cellZ + 0.5) * GROUND_CELL)
	groundHeights[key] = height
	return height
end

-- The ground's height right under (x, z), uncached: for the few queries a
-- cell's sample would mislead, such as a hero beside a cliff.
function Net.groundYExact(x: number, z: number): number
	return castGround(x, z)
end

function Net.pickClass(class: string)
	intentRemote:FireServer("pickClass", class)
end

-- Takes card `index` of the offer on screen.
function Net.chooseCard(index: number)
	intentRemote:FireServer("card", index)
end

-- Fires utility skill `index` (the button, 1..3).
function Net.useUtility(index: number)
	intentRemote:FireServer("utility", index)
end

-- The interact button went down (`held`) or up: holding it at the chest
-- opens it, beside a shrine activates it.
function Net.setInteracting(held: boolean)
	intentRemote:FireServer("interact", held)
end

-- Dashes towards (dx, dz), not both zero; the run normalises it.
function Net.dash(dx: number, dz: number)
	intentRemote:FireServer("dash", dx, dz)
end

-- Starts casting the extraction spell.
function Net.castSpell()
	intentRemote:FireServer("cast")
end

function Net.enterPortal()
	intentRemote:FireServer("enter")
end

worldRemote.OnClientEvent:Connect(
	function(
		world: Protocol.WorldView,
		enemyData: buffer,
		projectileData: buffer,
		crystalData: buffer
	)
		if type(world) ~= "table" then
			return
		end
		local enemies = Protocol.decodeEnemies(enemyData, enemyKinds)
		local projectiles = Protocol.decodeProjectiles(projectileData, projectileKinds)
		local crystals = Protocol.decodeCrystals(crystalData)
		if enemies == nil or projectiles == nil or crystals == nil then
			return
		end
		local snapshot = {
			receivedAt = os.clock(),
			world = world,
			enemies = enemies,
			projectiles = projectiles,
			crystals = crystals,
		}
		Net.previous = Net.latest
		Net.latest = snapshot
		for _, listener in worldListeners do
			listener(snapshot)
		end
	end
)

eventsRemote.OnClientEvent:Connect(function(events: { Types.Event }, selfView: Protocol.SelfView?)
	if type(events) ~= "table" then
		return
	end
	Net.self = selfView
	Net.selfAt = os.clock()
	for _, listener in eventListeners do
		listener(events, selfView)
	end
end)

local function notifyPhase(phase: Phase, summary: Protocol.SummaryView?)
	for _, listener in phaseListeners do
		listener(phase, summary)
	end
end

phaseRemote.OnClientEvent:Connect(function(phase: any, summary: Protocol.SummaryView?)
	if type(phase) ~= "string" then
		return
	end
	if PHASES[phase] == nil then
		return
	end
	local current: Phase = PHASES[phase]
	Net.phase = current
	table.clear(groundHeights)
	Net.summary = if phase == "summary" and type(summary) == "table" then summary else nil
	notifyPhase(current, Net.summary)
end)

return Net
