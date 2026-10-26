--!strict
-- The server adapter (ADR-0002): builds the map, owns the run lifecycle and
-- drives the pure core in fixed steps. The only things it reads from the world
-- are character positions and parsed intents (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Life = require(ReplicatedStorage.Shared.Core.Life)
local Map = require(ReplicatedStorage.Shared.Core.Map)
local Progression = require(ReplicatedStorage.Shared.Core.Progression)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Run = require(ReplicatedStorage.Shared.Core.Run)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Characters = require(script.Parent.Characters)
local MapBuilder = require(script.Parent.MapBuilder)
local Network = require(script.Parent.Network)

local STEP_SECONDS = 1 / Config.net.stepHz
local SNAPSHOT_SECONDS = 1 / Config.net.snapshotHz
-- A slow frame catches up with at most this many steps; the rest is dropped.
local MAX_STEPS_PER_FRAME = 5

local archetypeNames = Protocol.archetypeNames(Config)
local projectileKinds = Protocol.projectileKinds(Config)

local run: Types.Run? = nil
-- True while a run is being set up, which yields on building the map and on
-- respawning characters.
local starting = false
-- Real seconds left of the summary after the run ended.
local summaryLeft = 0
-- Whether the current run was started with the Studio perf test config.
local perfRun = false
-- The players in the current run, by core id.
local members: { [number]: Player } = {}
-- Everyone who has been in the current run, so leaving and rejoining does not
-- bring a dead or extracted player back.
local seen: { [number]: boolean } = {}
-- Events drained from the run and not yet sent.
local pending: { Types.Event } = {}
local stepAccumulator = 0
local snapshotAccumulator = 0

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: { [any]: any } do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- Studio only: a heavy run for the performance check (plan, criterion 6): a
-- world full of patrols and an unkillable player.
local function perfConfig(): Types.Config
	local config = deepCopy(Config) :: Types.Config
	config.enemies.patrols.groupsAtStart = 25
	config.enemies.patrols.sizeAtStart = 8
	config.player.maxHealth = 1e6
	return config
end

local function perfRequested(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("PerfTest") == true
end

-- Moves the character onto the map's ground at (x, z).
local function teleport(current: Types.Run, player: Player, x: number, z: number)
	Characters.teleport(player, x, z, Map.heightAt(current.map, x, z))
end

-- Adds a player to the run and moves their character to its entry.
local function joinRun(current: Types.Run, player: Player)
	local core = Run.addPlayer(current, player.UserId)
	members[player.UserId] = player
	seen[player.UserId] = true
	teleport(current, player, core.x, core.z)
end

local function present(): { Player }
	local players = {}
	for _, player in Players:GetPlayers() do
		if player.Parent == Players then
			table.insert(players, player)
		end
	end
	return players
end

-- Starts a run with everyone present: builds its map, which takes some
-- frames, then respawns everyone if asked to and lets them in. Whoever joins
-- during the build is let in with the rest.
local function startRun(respawn: boolean)
	if starting then
		return
	end
	starting = true
	run = nil
	members = {}
	seen = {}
	pending = {}

	local count = #present()
	if count > 0 then
		-- The old map goes away under the characters while the new one is built.
		for _, player in present() do
			Characters.freeze(player)
		end
		perfRun = perfRequested()
		local config = if perfRun then perfConfig() else Config
		local fresh = Run.new(config, Random.new():NextInteger(1, 2 ^ 31 - 2), count)
		MapBuilder.build(fresh.map, config)

		if respawn then
			for _, player in present() do
				pcall(player.LoadCharacter, player)
			end
		end
		local joined = present()
		for _, player in joined do
			joinRun(fresh, player)
		end
		if #joined > 0 then
			Network.sendMapToAll(fresh)
			stepAccumulator = 0
			snapshotAccumulator = 0
			summaryLeft = config.run.summarySeconds
			run = fresh
		end
	end
	starting = false
end

local function onPlayerAdded(player: Player)
	-- A respawned character appears at the origin; the run says where it belongs.
	player.CharacterAdded:Connect(function()
		local current = run
		local core = if current then current.players[player.UserId] else nil
		if current and core then
			task.defer(teleport, current, player, core.x, core.z)
		elseif current and #current.map.entries > 0 then
			-- A spectator waits at an entry, out of the camps' way.
			local entry = current.map.points[current.map.entries[1]]
			task.defer(teleport, current, player, entry.x, entry.z)
		end
	end)

	if starting then
		-- The run being set up picks the player up.
		return
	end
	local current = run
	if current == nil then
		startRun(false)
		return
	end
	-- Everyone sees the map, spectators included.
	Network.sendMap(player, current)
	if
		not current.ended
		and not seen[player.UserId]
		and current.time <= current.config.run.lateJoinSeconds
	then
		joinRun(current, player)
	end
	-- Anyone else waits for the next run.
end

local function onPlayerRemoving(player: Player)
	Characters.forget(player)
	members[player.UserId] = nil
	local current = run
	if current then
		Run.removePlayer(current, player.UserId)
		if next(current.players) == nil then
			run = nil
			pending = {}
		end
	end
end

local function selfViews(current: Types.Run): { [number]: Protocol.SelfView }
	local views = {}
	for id, player in current.players do
		local class = Run.class(current, player)
		local skills: { Protocol.SkillView } = {}
		for index, active in class.actives do
			table.insert(skills, {
				id = active.id,
				name = active.name,
				readyIn = math.max(0, (player.skillReadyAt[index] or 0) - current.time),
				cooldown = active.cooldownSeconds,
			})
		end
		local maxCharges = Run.dashMaxCharges(current, player)
		views[id] = {
			level = player.level,
			xp = player.xp,
			xpToNext = Progression.xpToNext(current.config, player.level),
			kills = player.kills,
			offer = player.offers[1],
			perks = player.perks,
			skills = skills,
			dashCharges = player.dashCharges,
			dashMaxCharges = maxCharges,
			dashRechargeIn = if player.dashCharges < maxCharges
				then math.max(0, player.dashRechargeAt - current.time)
				else 0,
			dashDistance = Run.dashDistance(current, player),
			potions = player.potions,
			potionCapacity = Life.potionCapacity(current, player),
		}
	end
	return views
end

local function gatherInputs(): { [number]: Types.PlayerInput }
	local inputs = {}
	for id, player in members do
		local input = Characters.input(player)
		if input then
			inputs[id] = input
		end
	end
	return inputs
end

local function onIntent(player: Player, intent: Protocol.Intent)
	local current = run
	if current == nil then
		return
	end
	local id = player.UserId
	if intent.kind == "aim" then
		Run.setAim(current, id, intent.angle)
	elseif intent.kind == "fire" then
		Run.setFiring(current, id, intent.held)
	elseif intent.kind == "skill" then
		Run.useSkill(current, id, intent.index, intent.aim, intent.aimDistance)
	elseif intent.kind == "dash" then
		Run.dash(current, id)
	elseif intent.kind == "drink" then
		Run.drink(current, id)
	elseif intent.kind == "interact" then
		Run.setInteracting(current, id, intent.held)
	elseif intent.kind == "perk" then
		Run.choosePerk(current, id, intent.index)
	elseif intent.kind == "assist" then
		Run.setAssist(current, id, intent.enabled)
	end
end

local heartbeatFrames = 0
local heartbeatClock = 0

local function onHeartbeat(dt: number)
	-- Measurements for the performance check, once per second.
	heartbeatFrames += 1
	heartbeatClock += dt
	if heartbeatClock >= 1 then
		local current = run
		workspace:SetAttribute("ServerHeartbeatHz", heartbeatFrames / heartbeatClock)
		workspace:SetAttribute("EnemyCount", if current then #current.enemies else 0)
		heartbeatFrames = 0
		heartbeatClock = 0
	end

	local current = run
	if current == nil then
		return
	end

	if not current.ended then
		stepAccumulator += dt
		local steps = 0
		while
			stepAccumulator >= STEP_SECONDS
			and steps < MAX_STEPS_PER_FRAME
			and not current.ended
		do
			Run.step(current, STEP_SECONDS, gatherInputs())
			for _, event in Run.drainEvents(current) do
				table.insert(pending, event)
			end
			stepAccumulator -= STEP_SECONDS
			steps += 1
		end
		if stepAccumulator >= STEP_SECONDS then
			stepAccumulator %= STEP_SECONDS
		end
	end

	for id, player in members do
		local core = current.players[id]
		if core then
			Characters.apply(player, core.state, Run.walkSpeed(current, core))
			Characters.hold(player, core.x, core.z)
		end
	end

	snapshotAccumulator += dt
	if snapshotAccumulator >= SNAPSHOT_SECONDS then
		snapshotAccumulator %= SNAPSHOT_SECONDS
		Network.sendWorld(current, archetypeNames, projectileKinds)
		Network.sendEvents(pending, selfViews(current))
		pending = {}
	end

	if current.ended then
		summaryLeft -= dt
		if summaryLeft <= 0 then
			task.spawn(startRun, true)
		end
	end
end

Network.init(Config)
Network.onIntent(onIntent)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
RunService.Heartbeat:Connect(onHeartbeat)

-- Changing the perf test switch restarts the run at once.
workspace:GetAttributeChangedSignal("PerfTest"):Connect(function()
	if run ~= nil and perfRequested() ~= perfRun then
		task.spawn(startRun, true)
	end
end)

-- Players who joined before this script ran.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
