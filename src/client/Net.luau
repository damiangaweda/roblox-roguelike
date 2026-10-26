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

local archetypeNames = Protocol.archetypeNames(Config)
local projectileKinds = Protocol.projectileKinds(Config)

export type Snapshot = {
	-- os.clock() when it arrived, for interpolation.
	receivedAt: number,
	world: Protocol.WorldView,
	enemies: { Protocol.EnemyView },
	projectiles: { Protocol.ProjectileView },
}

-- The two latest snapshots, newest last.
Net.previous = nil :: Snapshot?
Net.latest = nil :: Snapshot?
-- The local player's own state from the latest event batch, and when it came.
Net.self = nil :: Protocol.SelfView?
Net.selfAt = 0

local worldListeners: { (Snapshot) -> () } = {}
local eventListeners: { ({ Types.Event }) -> () } = {}

function Net.onWorld(listener: (Snapshot) -> ())
	table.insert(worldListeners, listener)
end

function Net.onEvents(listener: ({ Types.Event }) -> ())
	table.insert(eventListeners, listener)
end

-- The basic attack's input went down (`held`) or up.
function Net.setFiring(held: boolean)
	intentRemote:FireServer("fire", held)
end

-- Fires active skill `index` (1..3). `aimDistance` is how far the aim point is
-- from the character, which shortens a projectile's flight; nil for full range.
function Net.useSkill(index: number, aimDistance: number?)
	if aimDistance then
		intentRemote:FireServer("skill", index, aimDistance)
	else
		intentRemote:FireServer("skill", index)
	end
end

function Net.dash()
	intentRemote:FireServer("dash")
end

function Net.drink()
	intentRemote:FireServer("drink")
end

-- The interact button went down (`held`) or up: reviving or extracting.
function Net.interact(held: boolean)
	intentRemote:FireServer("interact", held)
end

function Net.choosePerk(index: number)
	intentRemote:FireServer("perk", index)
end

-- Whether the aim should snap to enemies in the assist cone (touch, gamepad).
function Net.setAssist(enabled: boolean)
	intentRemote:FireServer("assist", enabled)
end

worldRemote.OnClientEvent:Connect(
	function(world: Protocol.WorldView, enemyData: buffer, projectileData: buffer)
		local enemies = Protocol.decodeEnemies(enemyData, archetypeNames)
		local projectiles = Protocol.decodeProjectiles(projectileData, projectileKinds)
		if enemies == nil or projectiles == nil then
			return
		end
		local snapshot = {
			receivedAt = os.clock(),
			world = world,
			enemies = enemies,
			projectiles = projectiles,
		}
		Net.previous = Net.latest
		Net.latest = snapshot
		for _, listener in worldListeners do
			listener(snapshot)
		end
	end
)

eventsRemote.OnClientEvent:Connect(function(events: { Types.Event }, selfView: Protocol.SelfView?)
	Net.self = selfView
	Net.selfAt = os.clock()
	for _, listener in eventListeners do
		listener(events)
	end
end)

return Net
