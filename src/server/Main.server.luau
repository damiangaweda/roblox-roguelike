--!strict
-- The server adapter (ADR-0002): builds the arena, owns the run lifecycle and
-- drives the pure core in fixed steps. The only things it reads from the world
-- are character positions and parsed intents (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Core.Progression)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Run = require(ReplicatedStorage.Shared.Core.Run)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Arena = require(script.Parent.Arena)
local Characters = require(script.Parent.Characters)
local Network = require(script.Parent.Network)

local STEP_SECONDS = 1 / Config.net.stepHz
local SNAPSHOT_SECONDS = 1 / Config.net.snapshotHz
-- A slow frame catches up with at most this many steps; the rest is dropped.
local MAX_STEPS_PER_FRAME = 5

local kindNames = Protocol.kindNames(Config)

local run: Types.Run? = nil
-- True while a run is being set up, which can yield on respawning characters.
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

-- Studio only: a heavy run for the performance check (plan, criterion 7).
local function perfConfig(): Types.Config
	local config = deepCopy(Config) :: Types.Config
	config.horde.spawnPerSecondAtStart = 100
	config.player.maxHealth = 1e6
	return config
end

local function perfRequested(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("PerfTest") == true
end

local function joinRun(current: Types.Run, player: Player)
	local position = Characters.position(player)
	Run.addPlayer(
		current,
		player.UserId,
		if position then position.x else 0,
		if position then position.z else 0
	)
	members[player.UserId] = player
	seen[player.UserId] = true
end

-- Starts a run with everyone present, respawning them first if asked to.
local function startRun(respawn: boolean)
	if starting then
		return
	end
	starting = true
	run = nil
	members = {}
	seen = {}
	pending = {}

	if respawn then
		for _, player in Players:GetPlayers() do
			pcall(player.LoadCharacter, player)
		end
	end

	local present = {}
	for _, player in Players:GetPlayers() do
		if player.Parent == Players then
			table.insert(present, player)
		end
	end
	if #present > 0 then
		perfRun = perfRequested()
		local config = if perfRun then perfConfig() else Config
		local fresh = Run.new(config, Random.new():NextInteger(1, 2 ^ 31 - 2))
		for _, player in present do
			joinRun(fresh, player)
		end
		stepAccumulator = 0
		snapshotAccumulator = 0
		summaryLeft = config.run.summarySeconds
		run = fresh
	end
	starting = false
end

local function onPlayerAdded(player: Player)
	if starting then
		-- The run being set up picks the player up.
		return
	end
	local current = run
	if current == nil then
		startRun(false)
	elseif
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
		views[id] = {
			level = player.level,
			xp = player.xp,
			xpToNext = Progression.xpToNext(current.config, player.level),
			activeSkillReadyIn = math.max(0, player.activeSkillReadyAt - current.time),
			activeSkillCooldown = current.config.activeSkill.cooldownSeconds,
			kills = player.kills,
			offer = player.offers[1],
		}
	end
	return views
end

local function gatherInputs(): { [number]: Types.PlayerInput }
	local inputs = {}
	for id, player in members do
		local position = Characters.position(player)
		if position then
			inputs[id] = position
		end
	end
	return inputs
end

local function onIntent(player: Player, intent: Protocol.Intent)
	local current = run
	if current == nil then
		return
	end
	if intent.kind == "activeSkill" then
		Run.useActiveSkill(current, player.UserId, intent.aim)
	elseif intent.kind == "perk" then
		Run.choosePerk(current, player.UserId, intent.index)
	elseif intent.kind == "interact" then
		Run.setInteracting(current, player.UserId, intent.held)
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
			Characters.apply(player, core.state)
			Characters.hold(player, core.x, core.z)
		end
	end

	snapshotAccumulator += dt
	if snapshotAccumulator >= SNAPSHOT_SECONDS then
		snapshotAccumulator %= SNAPSHOT_SECONDS
		Network.sendWorld(current, kindNames)
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
Arena.build(Config)
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
