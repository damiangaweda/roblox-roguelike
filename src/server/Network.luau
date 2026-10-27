--!strict
-- The server end of every remote. Intents are rate limited and parsed by
-- Protocol before the run sees them (AGENTS.md rule 1); the world and events
-- go out at the configured rate, each player's phase when it changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Network = {}

local intentRemote: RemoteEvent
local worldRemote: RemoteEvent
local eventsRemote: RemoteEvent
local phaseRemote: RemoteEvent

-- A token bucket per player: `intentsPerSecond` tokens, refilled continuously.
local buckets: { [Player]: { tokens: number, at: number } } = {}
local intentsPerSecond = 0
local intentConfig: Types.Config

function Network.init(config: Types.Config)
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	intentRemote = Instance.new("RemoteEvent")
	intentRemote.Name = Protocol.remotes.intent
	intentRemote.Parent = folder
	worldRemote = Instance.new("RemoteEvent")
	worldRemote.Name = Protocol.remotes.world
	worldRemote.Parent = folder
	eventsRemote = Instance.new("RemoteEvent")
	eventsRemote.Name = Protocol.remotes.events
	eventsRemote.Parent = folder
	phaseRemote = Instance.new("RemoteEvent")
	phaseRemote.Name = Protocol.remotes.phase
	phaseRemote.Parent = folder
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
	intentsPerSecond = config.net.intentsPerSecond
	intentConfig = config
end

local function allow(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if bucket == nil then
		bucket = { tokens = intentsPerSecond, at = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(intentsPerSecond, bucket.tokens + (now - bucket.at) * intentsPerSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Calls `handler` for every well-formed intent within the rate limit; the
-- rest are dropped silently.
function Network.onIntent(handler: (player: Player, intent: Protocol.Intent) -> ())
	intentRemote.OnServerEvent:Connect(function(player, kind, a, b)
		if not allow(player) then
			return
		end
		local intent = Protocol.parseIntent(intentConfig, kind, a, b)
		if intent then
			handler(player, intent)
		end
	end)
end

function Network.sendWorld(run: Types.Run, enemyKinds: { string }, projectileKinds: { string })
	worldRemote:FireAllClients(
		Protocol.worldView(run),
		Protocol.encodeEnemies(run, enemyKinds),
		Protocol.encodeProjectiles(run, projectileKinds),
		Protocol.encodeCrystals(run)
	)
end

-- Tells one player its phase; the summary phase carries how its run went.
function Network.sendPhase(
	player: Player,
	phase: "pick" | "run" | "summary",
	summary: Protocol.SummaryView?
)
	phaseRemote:FireClient(player, phase, summary)
end

-- Sends each player the public events and its own private ones, with its
-- own state. `selfViews` is keyed by player id.
function Network.sendEvents(events: { Types.Event }, selfViews: { [number]: Protocol.SelfView })
	for _, player in Players:GetPlayers() do
		local id = player.UserId
		local mine = {}
		for _, event in events do
			if not Protocol.isPrivate(event) or Protocol.eventPlayer(event) == id then
				table.insert(mine, event)
			end
		end
		eventsRemote:FireClient(player, mine, selfViews[id])
	end
end

return Network
