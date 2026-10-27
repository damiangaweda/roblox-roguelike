-- Smoke simulation of a whole run with an idle hero that takes the first card.
local Run = require("../../src/shared/Core/Run")
local Config = require("../../src/shared/Config")
local Hero = require("../../src/shared/Core/Hero")
local run = Run.new(Config, 12)
Run.addPlayer(run, 1, "mage")

local dt = 1 / 30
local counts = {}
local hurtBy = {}
local t0 = os.clock()
local steps = 0
local maxEnemies = 0
while not run.ended and run.time < 900 and steps < 900 * 30 * 2 do
	-- Kite: walk away from the enemies' centre of mass, at walking speed.
	local p = run.players[1]
	local ax, az, n = 0, 0, 0
	for _, e in run.enemies do
		local d = math.sqrt((e.x - p.x) ^ 2 + (e.z - p.z) ^ 2)
		if d < 40 then
			local w = 1 / math.max(d * d, 1)
			ax += (p.x - e.x) / math.max(d, 1) * w
			az += (p.z - e.z) / math.max(d, 1) * w
			n += 1
		end
	end
	local tx, tz = p.x, p.z
	if n > 0 then
		local len = math.sqrt(ax * ax + az * az)
		if len > 1e-6 then
			local speed = 16 * dt
			tx, tz = p.x + ax / len * speed, p.z + az / len * speed
		end
	end
	-- Drift toward the centre when near the edge.
	if math.sqrt(tx * tx + tz * tz) > 300 then
		tx, tz = tx * 0.98, tz * 0.98
	end
	Run.step(run, dt, { [1] = { x = tx, z = tz } })
	steps += 1
	maxEnemies = math.max(maxEnemies, #run.enemies)
	for _, e in Run.drainEvents(run) do
		counts[e.kind] = (counts[e.kind] or 0) + 1
		if e.kind == "playerHurt" then
			local en = e.enemyId
					and (function()
						for _, x in run.enemies do
							if x.id == e.enemyId then
								return x.kind
							end
						end
						return "gone"
					end)()
				or "?"
			hurtBy[en] = (hurtBy[en] or 0) + e.amount
		end
	end
	if steps % 150 == 0 then
		print(
			string.format(
				"t=%.0f pos=(%.0f,%.0f) hp=%.0f near=%d enemies=%d budget=%.1f",
				run.time,
				p.x,
				p.z,
				p.health,
				n,
				#run.enemies,
				p.moveBudget
			)
		)
	end
	if run.paused then
		-- Prefer a new skill, then a skill rank, then anything.
		local offer = run.players[1].offers[1]
		local pick = 1
		for index, card in offer do
			if card.kind == "newSkill" then
				pick = index
				break
			elseif card.kind == "skillRank" then
				pick = index
			end
		end
		Run.chooseCard(run, 1, pick)
	end
	do
		local hero = run.players[1]
		local stats = Hero.stats(run, hero)
		if n >= 6 then
			Run.useUtility(run, 1, 1)
		end
		if hero.health < stats.maxHealth * 0.6 then
			Run.useUtility(run, 1, 2)
		end
		if hero.health < stats.maxHealth * 0.45 then
			Run.useUtility(run, 1, 3)
		end
	end
end
local p = run.players[1]
local keys = {}
for k in counts do
	table.insert(keys, k)
end
table.sort(keys)
local out = {}
for _, k in keys do
	table.insert(out, k .. "=" .. counts[k])
end
print(
	string.format(
		"time=%.0f ended=%s state=%s level=%d health=%.0f kills=%d maxEnemies=%d steps=%d wall=%.1fs",
		run.time,
		tostring(run.ended),
		p.state,
		p.level,
		p.health,
		p.kills,
		maxEnemies,
		steps,
		os.clock() - t0
	)
)
print(table.concat(out, " "))
local skills = {}
for _, s in p.skills do
	table.insert(skills, s.id .. ":" .. s.rank)
end
if hurtBy then
	local t = {}
	for k, v in hurtBy do
		table.insert(t, k .. "=" .. math.floor(v))
	end
	print("hurtBy " .. table.concat(t, " "))
end
print("skills " .. table.concat(skills, " "))
