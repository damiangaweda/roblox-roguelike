--!strict
-- Keeps each player's character in line with the player the core tracks. The
-- core's health is the truth: the Humanoid's own health never kills anyone
-- (AGENTS.md rule 1), and the character only shows what the core decided.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Core.Types)

local Characters = {}

-- Presentation constants, not gameplay numbers.
local DEAD_TRANSPARENCY = 0.7
local EXTRACTED_TRANSPARENCY = 1

type Entry = {
	character: Model,
	humanoid: Humanoid,
	-- The jump values of a fresh character, restored when the player is alive.
	jumpHeight: number,
	jumpPower: number,
	-- The state last applied, so a state is applied once, not every frame.
	state: Types.PlayerState?,
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
	local entry: Entry = {
		character = character,
		humanoid = humanoid,
		jumpHeight = humanoid.JumpHeight,
		jumpPower = humanoid.JumpPower,
		state = nil,
	}
	entries[player] = entry
	return entry
end

-- The character's position on the ground plane, or nil while it has none.
function Characters.position(player: Player): Types.PlayerInput?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return { x = root.Position.X, z = root.Position.Z }
end

local function setJumping(entry: Entry, enabled: boolean)
	entry.humanoid.JumpHeight = if enabled then entry.jumpHeight else 0
	entry.humanoid.JumpPower = if enabled then entry.jumpPower else 0
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

-- Makes the player's character match `state`. Call it every frame; it acts
-- on a change of state and keeps the Humanoid's health full.
function Characters.apply(player: Player, state: Types.PlayerState)
	local entry = entryFor(player)
	if entry == nil then
		return
	end
	local humanoid = entry.humanoid
	if humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
	if entry.state == state then
		return
	end
	entry.state = state

	if state == "alive" then
		humanoid.WalkSpeed = Config.player.walkSpeed
		setJumping(entry, true)
		return
	end
	humanoid.WalkSpeed = 0
	setJumping(entry, false)
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
