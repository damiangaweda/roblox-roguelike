--!strict
-- The server adapter (ADR-0002): owns the run lifecycle (the class pick, the
-- run, the summary) and drives the pure core in fixed steps. The only things
-- it reads from the world are character positions and parsed intents
-- (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Damage = require(ReplicatedStorage.Shared.Core.Damage)
local Hero = require(ReplicatedStorage.Shared.Core.Hero)
local Run = require(ReplicatedStorage.Shared.Core.Run)
local State = require(ReplicatedStorage.Shared.Core.State)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local Characters = require(script.Parent.Characters)
local Network = require(script.Parent.Network)

local STEP_SECONDS = 1 / Config.net.stepHz
local SNAPSHOT_SECONDS = 1 / Config.net.snapshotHz
-- A slow frame catches up with at most this many steps; the rest is dropped.
local MAX_STEPS_PER_FRAME = 5
-- The seed, the run's clock and the core's view of each player are
-- Studio-only diagnostics: attributes replicate to every client, and the seed
-- with the shared core would let a client replay the run's rolls.
local IS_STUDIO = RunService:IsStudio()

local enemyKinds = Protocol.enemyKinds(Config)
local projectileKinds = Protocol.projectileKinds(Config)

type Phase = "pick" | "run" | "summary"

local run: Types.Run? = nil
-- True while a run is being set up, which yields on building the map and on
-- respawning characters.
local starting = false
-- Players who picked a class while the run was being set up, and the class.
local waiting: { [Player]: string } = {}
-- Real seconds left of the summary once the run ended; nil before.
local summaryLeft: number? = nil
-- Why the run ended, from its `ended` event.
local endReason: string? = nil
-- Whether the current run was started with the Studio perf test config.
local perfRun = false
-- Each present player's phase.
local phases: { [Player]: Phase } = {}
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

-- Studio only: a heavy run for the performance check (plan, stage 3
-- criterion 5): every lair releasing full batches at once from the start,
-- so the horde reaches its cap quickly, and an unkillable hero.
local function perfConfig(): Types.Config
	local config = deepCopy(Config) :: Types.Config
	config.lairs.batchStart = config.lairs.batchEnd
	for _, kind in config.lairs.kinds do
		kind.intervalSeconds = 1
	end
	for _, class in config.classes do
		class.maxHealth = 1e6
	end
	return config
end

local function perfRequested(): boolean
	return IS_STUDIO and workspace:GetAttribute("PerfTest") == true
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

local function setPhase(player: Player, phase: Phase, summary: Protocol.SummaryView?)
	phases[player] = phase
	Network.sendPhase(player, phase, summary)
end

-- Forgets the run; the world stays until the next one is built.
local function dropRun()
	run = nil
	members = {}
	seen = {}
	pending = {}
	summaryLeft = nil
	endReason = nil
end

-- Adds a player to the run as `class`, respawns their character, puts it
-- where the run says they are and dresses it for the class.
local function joinRun(current: Types.Run, player: Player, class: string)
	local core = Run.addPlayer(current, player.UserId, class)
	seen[player.UserId] = true
	-- A dead or extracted character from the last run comes back whole.
	pcall(player.LoadCharacterAsync, player)
	if player.Parent ~= Players then
		Run.removePlayer(current, player.UserId)
		return
	end
	Characters.teleport(player, core.x, core.z, ArenaBuilder.groundHeight(core.x, core.z))
	Characters.dress(player, current.config.classes[core.class])
	members[player.UserId] = player
	setPhase(player, "run")
end

-- Starts a run for the players waiting in `waiting`: builds its map, which
-- takes some frames, then lets them in. Whoever picks during the build is let
-- in with the rest.
local function startRun()
	if starting then
		return
	end
	starting = true
	dropRun()

	perfRun = perfRequested()
	local config = if perfRun then perfConfig() else Config
	local seed = Random.new():NextInteger(1, 2 ^ 31 - 2)
	local fresh = Run.new(config, seed)
	if IS_STUDIO then
		workspace:SetAttribute("RunSeed", seed)
	end
	-- The old map goes away under the characters while the new one is built.
	for _, player in present() do
		Characters.freeze(player)
	end
	ArenaBuilder.build(fresh.arena)
	ArenaBuilder.buildShrines(fresh.shrines)
	ArenaBuilder.buildLairs(fresh.lairs)

	while true do
		local player, class = next(waiting)
		if player == nil then
			break
		end
		waiting[player] = nil
		if player.Parent == Players and phases[player] == "pick" then
			joinRun(fresh, player, class)
		end
	end
	-- Everyone else waits on the new map, out of the run.
	for _, player in present() do
		if not members[player.UserId] then
			Characters.teleport(
				player,
				fresh.arena.startX,
				fresh.arena.startZ,
				ArenaBuilder.groundHeight(fresh.arena.startX, fresh.arena.startZ)
			)
		end
	end
	if next(fresh.players) ~= nil then
		stepAccumulator = 0
		snapshotAccumulator = 0
		run = fresh
	end
	starting = false
end

-- A player in the pick phase chose `class`: they start a run, join the one
-- that has just begun, or wait for the next one.
local function pickClass(player: Player, class: string)
	if phases[player] ~= "pick" then
		return
	end
	if starting then
		waiting[player] = class
		return
	end
	local current = run
	if current == nil then
		waiting[player] = class
		startRun()
		return
	end
	if
		not current.ended
		and not seen[player.UserId]
		and current.time <= current.config.run.lateJoinSeconds
	then
		joinRun(current, player, class)
	end
	-- Anyone else waits for the next run on the pick screen.
end

-- Studio only: the perf switch changed, so the run restarts with the same
-- players in the same classes.
local function restartRun()
	local current = run
	if current == nil or starting then
		return
	end
	for id, player in members do
		local core = current.players[id]
		if core and player.Parent == Players then
			waiting[player] = core.class
			phases[player] = "pick"
		end
	end
	startRun()
end

local function onPlayerAdded(player: Player)
	-- A respawned character appears at a spawn; the run says where it belongs.
	player.CharacterAdded:Connect(function()
		task.defer(function()
			local current = run
			local core = if current then current.players[player.UserId] else nil
			if current and core and members[player.UserId] then
				Characters.teleport(
					player,
					core.x,
					core.z,
					ArenaBuilder.groundHeight(core.x, core.z)
				)
			elseif members[player.UserId] then
				-- Already put in place by its join.
				return
			elseif starting then
				-- Nothing holds a character that spawns while the map is built;
				-- the run's teleport lets it go.
				Characters.freeze(player)
			elseif current then
				-- A player out of the run waits at the start.
				Characters.teleport(
					player,
					current.arena.startX,
					current.arena.startZ,
					ArenaBuilder.groundHeight(current.arena.startX, current.arena.startZ)
				)
			end
		end)
	end)
	setPhase(player, "pick")
end

local function onPlayerRemoving(player: Player)
	Characters.forget(player)
	phases[player] = nil
	waiting[player] = nil
	members[player.UserId] = nil
	local current = run
	if current then
		Run.removePlayer(current, player.UserId)
		if next(current.players) == nil then
			dropRun()
		end
	end
end

local function selfViews(current: Types.Run): { [number]: Protocol.SelfView }
	local views = {}
	for id in members do
		local core = current.players[id]
		if core then
			views[id] = Protocol.selfView(current, core)
		end
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
	if intent.kind == "pickClass" then
		pickClass(player, intent.class)
		return
	end
	local current = run
	local id = player.UserId
	if current == nil or not members[id] or current.players[id] == nil then
		return
	end
	if intent.kind == "card" then
		Run.chooseCard(current, id, intent.index)
	elseif intent.kind == "utility" then
		Run.useUtility(current, id, intent.index)
	elseif intent.kind == "interact" then
		Run.setInteracting(current, id, intent.held)
	elseif intent.kind == "dash" then
		Run.dash(current, id, intent.dx, intent.dz)
	elseif intent.kind == "cast" then
		Run.castSpell(current, id)
	elseif intent.kind == "enter" then
		Run.enterPortal(current, id)
	end
end

local function sendSnapshot(current: Types.Run)
	-- The builder redraws a shrine only when its state changed.
	for _, shrine in current.shrines do
		ArenaBuilder.setShrineState(shrine.id, shrine.used, shrine.readyAt <= current.time)
	end
	-- And a lair's column only when it woke, slept or was silenced.
	for _, lair in current.lairs do
		ArenaBuilder.setLairState(lair.id, lair.asleep, lair.silenced)
	end
	Network.sendWorld(current, enemyKinds, projectileKinds)
	Network.sendEvents(pending, selfViews(current))
	pending = {}
end

-- The run ended: everyone in it sees how it went.
local function beginSummary(current: Types.Run)
	-- The last events (the death, the extraction, the end) go out first.
	sendSnapshot(current)
	snapshotAccumulator = 0
	local seconds = current.config.run.summarySeconds
	summaryLeft = seconds
	for id, player in members do
		local core = current.players[id]
		if core then
			setPhase(player, "summary", {
				reason = endReason or "ended",
				extracted = core.state == "extracted",
				time = current.time,
				level = core.level,
				kills = core.kills,
				damageDone = core.damageDone,
				class = core.class,
				nextIn = seconds,
			})
		end
	end
end

-- The summary is over: the run is forgotten and everyone picks a class again.
local function endSummary()
	local finished = members
	dropRun()
	for _, player in finished do
		if player.Parent == Players then
			Characters.dress(player, nil)
			-- The faded character of a dead or extracted hero comes back whole.
			task.spawn(function()
				pcall(player.LoadCharacterAsync, player)
			end)
		end
	end
	for _, player in present() do
		setPhase(player, "pick")
	end
end

local function drain(current: Types.Run)
	for _, event in Run.drainEvents(current) do
		if event.kind == "chestOpened" then
			ArenaBuilder.setChestOpened(true)
		elseif event.kind == "portalOpened" then
			ArenaBuilder.setPortal(event.x, event.z)
		elseif event.kind == "portalClosed" then
			ArenaBuilder.clearPortal()
		elseif event.kind == "finalRising" then
			ArenaBuilder.setFinalRise(event.x, event.z)
		elseif event.kind == "bossSpawned" and event.final then
			ArenaBuilder.clearFinalRise()
		elseif event.kind == "ended" then
			endReason = event.reason
			ArenaBuilder.clearFinalRise()
		end
		table.insert(pending, event)
	end
end

local heartbeatFrames = 0
local heartbeatClock = 0

local function measure(dt: number)
	heartbeatFrames += 1
	heartbeatClock += dt
	if heartbeatClock < 1 then
		return
	end
	if IS_STUDIO then
		local current = run
		workspace:SetAttribute("ServerHeartbeatHz", heartbeatFrames / heartbeatClock)
		workspace:SetAttribute("EnemyCount", if current then #current.enemies else 0)
		workspace:SetAttribute("RunTime", if current then current.time else 0)
		-- Where the core thinks each player stands, for the lead to compare with
		-- the character in Studio.
		if current then
			for id, core in current.players do
				local player = members[id]
				if player then
					player:SetAttribute("CoreX", core.x)
					player:SetAttribute("CoreZ", core.z)
				end
			end
		end
	end
	heartbeatFrames = 0
	heartbeatClock = 0
end

-- Studio only: the lead's shortcuts for the playtest (plan, criterion 4).
-- Setting the workspace attribute DebugSkipTo moves the run's clock there;
-- DebugSpell gives every member the extraction spell; DebugAutoCards picks
-- cards for them; DebugGoToChest, DebugGoToShrine and DebugGoToLair move
-- them. Attributes never reach a live server's rules: the guard is
-- RunService:IsStudio().
local function applyDebug(current: Types.Run)
	if not IS_STUDIO then
		return
	end
	local skipTo = workspace:GetAttribute("DebugSkipTo")
	if type(skipTo) == "number" and skipTo > current.time then
		current.time = skipTo
		workspace:SetAttribute("DebugSkipTo", nil)
	end
	-- DebugAutoCards takes the first card of every offer, so a long test
	-- run never waits for a choice.
	if workspace:GetAttribute("DebugAutoCards") == true then
		for _, core in current.players do
			if #core.offers > 0 then
				Run.chooseCard(current, core.id, 1)
			end
		end
	end
	-- DebugGoToChest puts every member beside the chest.
	if workspace:GetAttribute("DebugGoToChest") == true then
		for _, core in current.players do
			core.x = current.arena.chestX + 4
			core.z = current.arena.chestZ
		end
		workspace:SetAttribute("DebugGoToChest", nil)
	end
	-- DebugGoToShrine (a shrine's id) puts every member beside that shrine.
	local shrineId = workspace:GetAttribute("DebugGoToShrine")
	if type(shrineId) == "number" then
		for _, shrine in current.shrines do
			if shrine.id == shrineId then
				for _, core in current.players do
					core.x = shrine.x + 4
					core.z = shrine.z
				end
			end
		end
		workspace:SetAttribute("DebugGoToShrine", nil)
	end
	-- DebugGoToLair (a lair's id) puts every member just outside the radius
	-- that wakes that lair, so the hero can walk in.
	local lairId = workspace:GetAttribute("DebugGoToLair")
	if type(lairId) == "number" then
		for _, lair in current.lairs do
			if lair.id == lairId then
				for _, core in current.players do
					core.x = lair.x + lair.radius + 12
					core.z = lair.z
				end
			end
		end
		workspace:SetAttribute("DebugGoToLair", nil)
	end
	-- DebugInvulnerable keeps every member at full health while set.
	if workspace:GetAttribute("DebugInvulnerable") == true then
		for _, core in current.players do
			if core.state == "alive" then
				core.health = Hero.stats(current, core).maxHealth
			end
		end
	end
	-- DebugKillBosses kills every lair's boss through the core's own kill, so
	-- silencing, the great offer and the final rise can be watched.
	if workspace:GetAttribute("DebugKillBosses") == true then
		for _, lair in current.lairs do
			local bossId = lair.bossId
			local boss = if bossId then State.enemyById(current, bossId) else nil
			if boss then
				local killer = next(current.players)
				Damage.kill(current, boss, killer or 0)
			end
		end
		workspace:SetAttribute("DebugKillBosses", nil)
	end
	-- DebugNoHorde (perf runs only, whose config is a private copy) stops the
	-- horde and removes its grunts and elites, so a boss can be watched alone.
	if workspace:GetAttribute("DebugNoHorde") == true and perfRun then
		current.config.horde.maxAlive = 0
		for index = #current.enemies, 1, -1 do
			local kind = current.config.enemies[current.enemies[index].kind]
			if kind.role ~= "boss" and kind.role ~= "finalBoss" then
				table.remove(current.enemies, index)
			end
		end
		workspace:SetAttribute("DebugNoHorde", nil)
	end
	if workspace:GetAttribute("DebugSpell") == true then
		for _, core in current.players do
			core.hasSpell = true
		end
		workspace:SetAttribute("DebugSpell", nil)
	end
end

local function onHeartbeat(dt: number)
	-- Measurements for the performance check, once per second.
	measure(dt)

	local current = run
	if current == nil then
		return
	end

	if not current.ended then
		applyDebug(current)
		stepAccumulator += dt
		local steps = 0
		while
			stepAccumulator >= STEP_SECONDS
			and steps < MAX_STEPS_PER_FRAME
			and not current.ended
		do
			Run.step(current, STEP_SECONDS, gatherInputs())
			drain(current)
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
			local walkSpeed = if current.paused or core.state ~= "alive"
				then 0
				else Run.walkSpeed(current, core)
			Characters.apply(player, core.state, walkSpeed)
			Characters.hold(player, core.x, core.z, ArenaBuilder.groundHeight(core.x, core.z))
		end
	end

	local left = summaryLeft
	if current.ended and left == nil then
		beginSummary(current)
		return
	end

	snapshotAccumulator += dt
	if snapshotAccumulator >= SNAPSHOT_SECONDS then
		snapshotAccumulator %= SNAPSHOT_SECONDS
		sendSnapshot(current)
	end

	if left then
		left -= dt
		summaryLeft = left
		if left <= 0 then
			endSummary()
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
		task.spawn(restartRun)
	end
end)

-- Players who joined before this script ran.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
