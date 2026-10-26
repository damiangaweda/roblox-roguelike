--!strict
-- Keeps each player's character in line with the player the core tracks. The
-- core's health is the truth: the Humanoid's own health never kills anyone
-- (AGENTS.md rule 1), and the character only shows what the core decided. The
-- server reads two things from a character: where it stands and which way it
-- faces, which is the aim (ADR-0009).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Characters = {}

-- Presentation constants, not gameplay numbers.
local DEAD_TRANSPARENCY = 0.7
local EXTRACTED_TRANSPARENCY = 1
-- Where a teleported character's feet land above the floor.
local TELEPORT_HEIGHT = 3.5

type Entry = {
	character: Model,
	humanoid: Humanoid,
	-- The state and walk speed last applied, so they are applied on change only.
	state: Types.PlayerState?,
	walkSpeed: number?,
}

local entries: { [Player]: Entry } = {}

-- The entry for the player's current character; a new character (a respawn)
-- gets a fresh one, which is what restores everything.
local function entryFor(player: Player): Entry?
	local character = player.Character
	if character == nil then
		entries[player] = nil
		return nil
	end
	local existing = entries[player]
	if existing and existing.character == character then
		return existing
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	humanoid.BreakJointsOnDeath = false
	-- A top-down run has no jumping: the dash is the burst of movement.
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = false
	local entry: Entry = {
		character = character,
		humanoid = humanoid,
		state = nil,
		walkSpeed = nil,
	}
	entries[player] = entry
	return entry
end

local function root(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local part = character:FindFirstChild("HumanoidRootPart")
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	return part
end

-- The character's position on the ground plane and its facing, or nil while it
-- has no body.
function Characters.input(player: Player): Types.PlayerInput?
	local part = root(player)
	if part == nil then
		return nil
	end
	local look = part.CFrame.LookVector
	return { x = part.Position.X, z = part.Position.Z, facing = math.atan2(look.Z, look.X) }
end

-- Puts the character where the run says the player is, keeping its facing.
function Characters.teleport(player: Player, x: number, z: number)
	local character = player.Character
	local part = root(player)
	if character == nil or part == nil then
		return
	end
	local pivot = character:GetPivot()
	character:PivotTo(pivot.Rotation + Vector3.new(x, TELEPORT_HEIGHT, z))
end

-- Hides the character and lets others walk through it.
local function fade(entry: Entry, transparency: number)
	for _, descendant in entry.character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			-- The root part is invisible already and stays so.
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Transparency = transparency
			end
		elseif descendant:IsA("Decal") then
			descendant.Transparency = transparency
		end
	end
end

-- Puts a character back where the run says the player is, once it has drifted
-- further than walking allows: a teleport, a speed hack, or a downed player
-- trying to crawl away (rule 1).
function Characters.hold(player: Player, x: number, z: number)
	local character = player.Character
	local part = root(player)
	if character == nil or part == nil then
		return
	end
	local position = part.Position
	local dx, dz = position.X - x, position.Z - z
	if dx * dx + dz * dz > Config.player.correctionDistance ^ 2 then
		character:PivotTo(character:GetPivot() + Vector3.new(-dx, 0, -dz))
	end
end

-- Makes the player's character match `state` and `walkSpeed`. Call it every
-- frame; it acts on a change and keeps the Humanoid's health full.
function Characters.apply(player: Player, state: Types.PlayerState, walkSpeed: number)
	local entry = entryFor(player)
	if entry == nil then
		return
	end
	local humanoid = entry.humanoid
	if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
	if entry.state == state and entry.walkSpeed == walkSpeed then
		return
	end
	entry.state = state
	entry.walkSpeed = walkSpeed

	if state == "alive" then
		humanoid.WalkSpeed = walkSpeed
		return
	end
	humanoid.WalkSpeed = 0
	if state == "dead" then
		fade(entry, DEAD_TRANSPARENCY)
	elseif state == "extracted" then
		fade(entry, EXTRACTED_TRANSPARENCY)
	end
end

function Characters.forget(player: Player)
	entries[player] = nil
end

return Characters
