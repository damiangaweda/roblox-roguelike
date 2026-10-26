--!strict
-- The client end of every remote: sends intents, keeps the latest world and
-- hands events to whoever listens. The client only asks (AGENTS.md rule 1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Net = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local intentRemote = remotes:WaitForChild(Protocol.remotes.intent) :: RemoteEvent
local worldRemote = remotes:WaitForChild(Protocol.remotes.world) :: RemoteEvent
local eventsRemote = remotes:WaitForChild(Protocol.remotes.events) :: RemoteEvent

local kindNames = Protocol.kindNames(Config)

export type Snapshot = {
	-- os.clock() when it arrived, for interpolation.
	receivedAt: number,
	world: Protocol.WorldView,
	enemies: { Protocol.EnemyView },
}

-- The two latest snapshots, newest last.
Net.previous = nil :: Snapshot?
Net.latest = nil :: Snapshot?
-- The local player's own state from the latest event batch.
Net.self = nil :: Protocol.SelfView?

local worldListeners: { (Snapshot) -> () } = {}
local eventListeners: { ({ Types.Event }) -> () } = {}

function Net.onWorld(listener: (Snapshot) -> ())
	table.insert(worldListeners, listener)
end

function Net.onEvents(listener: ({ Types.Event }) -> ())
	table.insert(eventListeners, listener)
end

-- Fires the skill at a ground point, or lets the server pick the nearest
-- enemy when `aim` is nil (touch).
function Net.useSkill(aim: Vector3?)
	if aim then
		intentRemote:FireServer("skill", aim.X, aim.Z)
	else
		intentRemote:FireServer("skill")
	end
end

function Net.choosePerk(index: number)
	intentRemote:FireServer("perk", index)
end

worldRemote.OnClientEvent:Connect(function(world: Protocol.WorldView, data: buffer)
	local enemies = Protocol.decodeEnemies(data, kindNames)
	if enemies == nil then
		return
	end
	local snapshot = { receivedAt = os.clock(), world = world, enemies = enemies }
	Net.previous = Net.latest
	Net.latest = snapshot
	for _, listener in worldListeners do
		listener(snapshot)
	end
end)

eventsRemote.OnClientEvent:Connect(function(events: { Types.Event }, selfView: Protocol.SelfView?)
	Net.self = selfView
	for _, listener in eventListeners do
		listener(events)
	end
end)

return Net
