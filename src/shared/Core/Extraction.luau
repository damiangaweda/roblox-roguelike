--!strict
-- The way out of a run (ADR-0015): the compass that starts pointing at the
-- extraction chest, the hold that opens it and hands its opener the
-- extraction spell, the cast that opens the portal and the portal itself.
-- A hit interrupting a cast or an opening is Hero.damage's; ending the run
-- once everyone has left is Run's.

local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Extraction = {}

-- Whether the player holds the open button; the hold advances in update.
function Extraction.setOpening(run: Types.Run, playerId: number, held: boolean)
	local player = run.players[playerId]
	if player then
		player.opening = held
	end
end

-- Starts casting the extraction spell. Only an alive holder of the spell who
-- is not already casting may, and only while no portal stands.
function Extraction.castSpell(run: Types.Run, playerId: number): boolean
	local player = run.players[playerId]
	if
		not player
		or player.state ~= "alive"
		or not player.hasSpell
		or run.portal ~= nil
		or player.castingUntil ~= nil
	then
		return false
	end
	local seconds = run.config.extraction.castSeconds
	player.castingUntil = run.time + seconds
	table.insert(run.events, { kind = "castStarted", player = player.id, seconds = seconds })
	return true
end

-- Leaves the run through the open portal, when the player stands within reach.
function Extraction.enterPortal(run: Types.Run, playerId: number): boolean
	local player = run.players[playerId]
	local portal = run.portal
	if not player or player.state ~= "alive" or not portal then
		return false
	end
	if
		Geometry.distance(player.x, player.z, portal.x, portal.z)
		> run.config.extraction.portalRadius
	then
		return false
	end
	player.state = "extracted"
	player.opening = false
	player.openProgress = 0
	player.castingUntil = nil
	table.insert(run.events, { kind = "extracted", player = player.id })
	return true
end

function Extraction.update(run: Types.Run, dt: number)
	local config = run.config.extraction
	local arena = run.arena

	if not run.compassOn and run.time >= config.compassMinute * 60 then
		run.compassOn = true
		table.insert(run.events, { kind = "compass", x = arena.chestX, z = arena.chestZ })
	end

	for _, player in State.sortedPlayers(run) do
		local alive = player.state == "alive"

		-- The hold at the chest: one opener gets the spell, once per run.
		local holding = alive
			and player.opening
			and not run.chestOpened
			and Geometry.distance(player.x, player.z, arena.chestX, arena.chestZ)
				<= config.openRadius
		if holding then
			player.openProgress += dt
			if player.openProgress >= config.openSeconds then
				run.chestOpened = true
				player.hasSpell = true
				player.openProgress = 0
				table.insert(run.events, { kind = "chestOpened", player = player.id })
			end
		else
			player.openProgress = 0
		end

		-- The cast: the portal opens where the caster stands.
		local castingUntil = player.castingUntil
		if castingUntil ~= nil then
			if not alive then
				player.castingUntil = nil
			elseif run.time >= castingUntil then
				player.castingUntil = nil
				run.portal = {
					x = player.x,
					z = player.z,
					until_ = run.time + config.portalSeconds,
				}
				table.insert(run.events, {
					kind = "portalOpened",
					x = player.x,
					z = player.z,
					seconds = config.portalSeconds,
				})
			end
		end
	end

	local portal = run.portal
	if portal and run.time >= portal.until_ then
		run.portal = nil
		table.insert(run.events, { kind = "portalClosed" })
	end
end

return Extraction
