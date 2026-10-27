--!strict
-- Every boss's every telegraphed attack, driven from the configuration: a
-- boss alone on open ground with one hero in reach, the attack chosen, the
-- telegraph read, then the effect of the kind when it lands.
local Assert = require("./Assert")
local Enemies = require("../src/shared/Core/Enemies")
local Fixtures = require("./Fixtures")
local Horde = require("../src/shared/Core/Horde")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

local DT = 0.05
-- Steps a boss gets to start its telegraph, and a charge to end.
local MAX_STEPS = 60

local function tick(run: Types.Run, dt: number)
	run.time += dt
	Enemies.step(run, dt)
end

local function bossIds(): { string }
	local ids = {}
	for id, kind in Fixtures.config().enemies do
		if State.isBoss(kind) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function eventsOf(run: Types.Run, kind: string): { any }
	local found = {}
	for _, event in run.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

-- A run on open ground whose hero cannot die, the boss at the centre and the
-- hero on +x at the attack's trigger distance.
local function setUp(
	kindId: string,
	index: number
): (Types.Run, Types.Enemy, Types.Player, Types.AttackConfig)
	local config = Fixtures.config()
	for _, class in config.classes do
		class.maxHealth = 1e6
	end
	local run = Fixtures.run(1, config)
	Fixtures.clearObstacles(run)
	local kind = run.config.enemies[kindId]
	local attack = kind.attacks[index]
	local distance = attack.range * run.config.horde.approachFactor * 0.9
	-- Outside the boss's body, so the hero is not stood inside it.
	distance = math.max(distance, kind.radius + run.config.player.radius + 0.5)
	local player = run.players[1]
	Fixtures.place(run, 1, distance, 0)
	local boss = Fixtures.enemy(run, kindId, 0, 0)
	boss.attack = index
	boss.attackReadyAt = 0
	if kind.phaseAttackIndex and index >= kind.phaseAttackIndex then
		boss.phase = 2
	end
	return run, boss, player, attack
end

-- Steps until the boss winds up; returns the telegraph event.
local function telegraph(run: Types.Run, boss: Types.Enemy, label: string): any
	for _ = 1, MAX_STEPS do
		tick(run, DT)
		local event = Assert.findEvent(run.events, "telegraph")
		if event then
			Assert.equal(boss.state, "telegraph", label .. " state")
			return event
		end
	end
	error(label .. ": no telegraph")
end

local function checkAttack(kindId: string, index: number)
	local run, boss, player, attack = setUp(kindId, index)
	local label = string.format("%s attack %d (%s)", kindId, index, attack.kind)
	local event = telegraph(run, boss, label)
	Assert.equal(event.attackKind, attack.kind, label .. " telegraph kind")
	Assert.equal(event.enemyId, boss.id, label .. " telegraph enemy")
	Assert.near(event.seconds, attack.telegraphSeconds, 1e-6, label .. " telegraph seconds")
	Assert.truthy(event.radius > 0, label .. " telegraph radius")
	Assert.truthy(event.x == event.x and event.z == event.z, label .. " telegraph position")
	local aimed = attack.kind == "projectile" or attack.kind == "leap" or attack.kind == "ground"
	if aimed then
		Assert.near(event.x, player.x, 1e-6, label .. " telegraph at the aim")
		Assert.near(event.z, player.z, 1e-6, label .. " telegraph at the aim")
	else
		Assert.near(event.x, boss.x, 1e-6, label .. " telegraph at the boss")
		Assert.near(event.z, boss.z, 1e-6, label .. " telegraph at the boss")
	end
	if attack.kind == "charge" then
		Assert.truthy(event.endX ~= nil and event.endZ ~= nil, label .. " charge end")
		Assert.truthy((event.endX :: number) > player.x, label .. " the rush runs past the aim")
	end

	local enemiesBefore = #run.enemies
	local aliveBefore = Horde.aliveCount(run)
	run.time = boss.stateUntil
	Enemies.step(run, 0)
	local attacked = Assert.findEvent(run.events, "enemyAttack")
	Assert.truthy(attacked, label .. " no enemyAttack")
	Assert.equal(attacked.attackKind, attack.kind, label .. " enemyAttack kind")

	local kind = attack.kind
	if kind == "melee" or kind == "burst" or kind == "leap" then
		Assert.truthy(#eventsOf(run, "playerHurt") >= 1, label .. " no playerHurt")
		Assert.truthy(player.health < 1e6, label .. " no damage")
	elseif kind == "projectile" then
		local shots = 0
		for _, shot in run.projectiles do
			if shot.owner == "enemy" and shot.source == boss.id then
				shots += 1
			end
		end
		Assert.equal(shots, attack.projectileCount or 1, label .. " shots")
	elseif kind == "charge" then
		Assert.equal(boss.state, "charge", label .. " rushing")
		for _ = 1, MAX_STEPS do
			tick(run, DT)
			if boss.state ~= "charge" then
				break
			end
		end
		Assert.equal(boss.state, "recover", label .. " recovered")
		Assert.equal(#eventsOf(run, "playerHurt"), 1, label .. " hit once")
	elseif kind == "summon" then
		local expected = if aliveBefore < run.config.horde.maxAlive
			then attack.summonCount or 0
			else 0
		Assert.equal(#run.enemies - enemiesBefore, expected, label .. " summoned")
	elseif kind == "ground" then
		local area: Types.Area? = nil
		for _, candidate in run.areas do
			if candidate.owner == "enemy" and candidate.source == boss.id then
				area = candidate
			end
		end
		Assert.truthy(area, label .. " no area")
		local placed = area :: Types.Area
		Assert.near(
			placed.until_,
			run.time + (attack.groundSeconds or 0),
			1e-6,
			label .. " lifetime"
		)
		Assert.equal(placed.radius, attack.radius, label .. " area radius")
	else
		error(label .. ": a boss attack kind with no check")
	end
end

local spec: { [string]: () -> () } = {}

for _, kindId in bossIds() do
	spec["every attack of " .. kindId .. " telegraphs and lands"] = function()
		local kind = Fixtures.config().enemies[kindId]
		Assert.truthy(#kind.attacks > 0, kindId .. " has no attacks")
		for index = 1, #kind.attacks do
			checkAttack(kindId, index)
		end
	end
end

spec["the final boss enters its second phase at its health share"] = function()
	for _, kindId in bossIds() do
		local kind = Fixtures.config().enemies[kindId]
		if kind.role ~= "finalBoss" then
			continue
		end
		local share = kind.phaseHealthShare
		Assert.truthy(share ~= nil, kindId .. " has no second phase")
		local run = Fixtures.run(1)
		Fixtures.clearObstacles(run)
		-- Far off, so nothing but the phase happens.
		Fixtures.place(run, 1, 150, 0)
		local boss = Fixtures.enemy(run, kindId, 0, 0)
		boss.health = boss.maxHealth * (share :: number) + 1
		tick(run, DT)
		Assert.equal(boss.phase, 1, kindId .. " early phase")
		Assert.falsy(Assert.findEvent(run.events, "bossPhase"), kindId .. " early event")
		boss.health = boss.maxHealth * (share :: number)
		tick(run, DT)
		Assert.equal(boss.phase, 2, kindId .. " phase")
		local event = Assert.findEvent(run.events, "bossPhase")
		Assert.truthy(event, kindId .. " no bossPhase")
		Assert.equal(event.enemyId, boss.id)
		Assert.equal(event.phase, 2)
		tick(run, DT)
		Assert.equal(#eventsOf(run, "bossPhase"), 1, kindId .. " once")
	end
end

return spec
