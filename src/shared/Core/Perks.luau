--!strict
-- Perk offers at level-up, taking a perk, and the modifiers a player's perks
-- add up to. A perk changes one property; Skills applies it to the skills that
-- carry the property, the player's own numbers read it through Perks.value.

local Types = require("./Types")

local Perks = {}

local function copy(list: { string }): { string }
	return table.clone(list)
end

-- Draws up to `offerSize` distinct perks the player can still take, or nil
-- when none is left.
local function draw(run: Types.Run, player: Types.Player): { string }?
	local perks = run.config.perks

	-- Sorted so that the same seed picks the same perks.
	local candidates: { string } = {}
	for id, perk in perks.pool do
		if (player.perks[id] or 0) < perk.maxStacks then
			table.insert(candidates, id)
		end
	end
	table.sort(candidates)
	if #candidates == 0 then
		return nil
	end

	-- A partial shuffle: the first `size` slots end up holding the picks.
	local size = math.min(perks.offerSize, #candidates)
	local offer: { string } = {}
	for slot = 1, size do
		local pick = run.rng:integer(slot, #candidates)
		candidates[slot], candidates[pick] = candidates[pick], candidates[slot]
		table.insert(offer, candidates[slot])
	end
	return offer
end

-- Whether an offer holds a perk the player has taken as often as it allows.
local function isStale(run: Types.Run, player: Types.Player, offer: { string }): boolean
	for _, id in offer do
		if (player.perks[id] or 0) >= run.config.perks.pool[id].maxStacks then
			return true
		end
	end
	return false
end

-- Queues an offer of up to `offerSize` distinct perks the player can still take.
function Perks.offer(run: Types.Run, player: Types.Player)
	local offer = draw(run, player)
	if offer == nil then
		return
	end
	table.insert(player.offers, offer)
	if #player.offers == 1 then
		table.insert(run.events, { kind = "offer", player = player.id, perks = copy(offer) })
	end
end

-- The multiplier and addend the player's perks give every property.
function Perks.modifiers(config: Types.Config, player: Types.Player): Types.Modifiers
	local modifiers: Types.Modifiers = {}
	for id, stacks in player.perks do
		local perk = config.perks.pool[id]
		if perk == nil or stacks <= 0 then
			continue
		end
		local entry = modifiers[perk.property]
		if entry == nil then
			entry = { mul = 1, add = 0 }
			modifiers[perk.property] = entry
		end
		entry.mul *= (perk.mul or 1) ^ stacks
		entry.add += (perk.add or 0) * stacks
	end
	return modifiers
end

-- `base` with the property's modifiers applied: multiplied, then added to.
function Perks.value(modifiers: Types.Modifiers, property: Types.Property, base: number): number
	local entry = modifiers[property]
	if entry == nil then
		return base
	end
	return base * entry.mul + entry.add
end

-- A player's number for `property` after their perks.
function Perks.playerValue(
	config: Types.Config,
	player: Types.Player,
	property: Types.Property,
	base: number
): number
	return Perks.value(Perks.modifiers(config, player), property, base)
end

-- Takes perk number `index` of the player's oldest offer. Returns false when
-- there is no such offer or the player cannot choose now.
function Perks.choose(run: Types.Run, playerId: number, index: number): boolean
	local player = run.players[playerId]
	if player == nil or (player.state ~= "alive" and player.state ~= "downed") then
		return false
	end
	local offer = player.offers[1]
	if offer == nil or index < 1 or index > #offer or index % 1 ~= 0 then
		return false
	end

	local perk = offer[index]
	player.perks[perk] = (player.perks[perk] or 0) + 1
	local perkConfig = run.config.perks.pool[perk]
	if perkConfig.property == "maxHealth" then
		-- Health grows with the maximum at once, so the perk heals by its bonus.
		local before = player.maxHealth
		player.maxHealth =
			Perks.playerValue(run.config, player, "maxHealth", run.config.player.maxHealth)
		player.health += player.maxHealth - before
	elseif perkConfig.property == "dashCharges" then
		player.dashCharges += perkConfig.add or 0
	end
	table.insert(run.events, { kind = "perkTaken", player = player.id, perk = perk })

	table.remove(player.offers, 1)
	-- Offers queued by several level-ups at once were drawn before this choice,
	-- so the next one is drawn again if this choice maxed out one of its perks.
	local following: { string }? = player.offers[1]
	if following and isStale(run, player, following) then
		following = draw(run, player)
		if following ~= nil then
			player.offers[1] = following :: { string }
		else
			table.clear(player.offers)
		end
	end
	if following then
		table.insert(run.events, { kind = "offer", player = player.id, perks = copy(following) })
	end
	return true
end

return Perks
