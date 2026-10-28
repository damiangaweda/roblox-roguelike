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

-- The ground's height under any point: the map is flat (ADR-0014).
function Net.groundY(): number
	return 0
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

-- The open button went down (`held`) or up: holding it at the chest opens it.
function Net.setInteracting(held: boolean)
	intentRemote:FireServer("interact", held)
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
	Net.summary = if phase == "summary" and type(summary) == "table" then summary else nil
	notifyPhase(current, Net.summary)
end)

return Net
