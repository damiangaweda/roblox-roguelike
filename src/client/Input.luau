--!strict
-- Raw input for the solo run (ADR-0013, stage 3b): Roblox's own character
-- movement walks the hero (WASD, the thumbstick on touch); Q, E and R fire the
-- three utility skills; 1, 2 and 3 choose a card while an offer is up; F does
-- every world interaction: it enters the portal, is held at the chest or a
-- shrine, and otherwise casts the extraction spell; space dashes. On a gamepad
-- the face buttons X, Y and B are the utilities (or the cards while an offer
-- is up), R1 is F and A dashes. The client only sends intents and moves its
-- own character; the server decides what happens (AGENTS.md rule 1). The Hud's
-- touch buttons call the exported functions. A knockback or a dash the server
-- reports is played here at once, so the character does not wait a snapshot
-- to be moved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Net = require(script.Parent.Net)

local Input = {}

-- A knockback stops this far before an obstacle.
local WALL_MARGIN = 0.1

-- A move direction shorter than this counts as standing.
local STANDING = 0.1

-- The utility skills.
local UTILITY_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Q] = 1,
	[Enum.KeyCode.E] = 2,
	[Enum.KeyCode.R] = 3,
}
-- The cards, only while an offer is up.
local CARD_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}
-- The gamepad's face buttons: a card while an offer is up, else a utility skill.
local PAD_SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
}
local INTERACT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.F] = true,
	[Enum.KeyCode.ButtonR1] = true,
}
local DASH_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}

-- What the interact button does where the hero stands; nil casts the spell.
export type Target = "portal" | "chest" | "shrine"

-- A displacement of the character, spread over `duration` seconds.
type Shift = {
	character: Model,
	delta: Vector3,
	duration: number,
	elapsed: number,
	applied: number,
}

local shifts: { Shift } = {}
-- Whether the interact intent was last sent held, so a release follows it.
local holding = false

local function typing(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function localParts(): (Model?, Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function within(here: Vector3, x: number, z: number, reach: number): boolean
	local dx, dz = x - here.X, z - here.Z
	return dx * dx + dz * dz <= reach * reach
end

-- Whether a shrine can be activated now, as the run judges it: unused, not
-- fighting its trial and, for a spring, back.
function Input.shrineUsable(shrine: Protocol.ShrineView): boolean
	return not shrine.used and not shrine.trial and shrine.readyIn <= 0
end

-- The nearest shrine within reach of `here` worth naming: a usable one, or a
-- spring still recharging; usable ones first.
function Input.shrineNear(here: Vector3): Protocol.ShrineView?
	local latest = Net.latest
	local shrines = if latest then latest.world.shrines else nil
	if type(shrines) ~= "table" then
		return nil
	end
	local reach = Config.shrines.reach
	local best: Protocol.ShrineView? = nil
	local bestUsable = false
	local bestDistance = math.huge
	for _, shrine in shrines do
		local usable = Input.shrineUsable(shrine)
		if not usable and not (shrine.kind == "spring" and not shrine.used) then
			continue
		end
		local dx, dz = shrine.x - here.X, shrine.z - here.Z
		local distance = dx * dx + dz * dz
		if distance > reach * reach then
			continue
		end
		if (usable and not bestUsable) or (usable == bestUsable and distance < bestDistance) then
			best = shrine
			bestUsable = usable
			bestDistance = distance
		end
	end
	return best
end

-- What the interact button does for a hero at `here`, as the latest snapshot
-- places things: the portal wins over the chest, the chest over a usable
-- shrine; nil means it casts the spell.
function Input.target(here: Vector3?): (Target?, Protocol.ShrineView?)
	local latest = Net.latest
	if latest == nil or here == nil then
		return nil, nil
	end
	local world = latest.world
	local portal = world.portal
	if portal and within(here, portal.x, portal.z, Config.extraction.portalRadius) then
		return "portal", nil
	end
	local chest = world.chest
	if
		chest
		and not chest.opened
		and within(here, chest.x, chest.z, Config.extraction.openRadius)
	then
		return "chest", nil
	end
	local shrine = Input.shrineNear(here)
	if shrine and Input.shrineUsable(shrine) then
		return "shrine", shrine
	end
	return nil, nil
end

-- Whether the local player has an offer of cards waiting.
local function offerUp(): boolean
	local selfView = Net.self
	return Net.phase == "run" and selfView ~= nil and selfView.offer ~= nil
end

-- Fires utility skill `index` (1..3).
function Input.useUtility(index: number)
	if Net.phase == "run" then
		Net.useUtility(index)
	end
end

-- Casts the extraction spell.
function Input.cast()
	if Net.phase == "run" then
		Net.castSpell()
	end
end

-- The interact button went down (`held`) or up: by the portal it enters, at
-- the chest or a shrine it is held, anywhere else it casts the spell.
function Input.interact(held: boolean)
	if held then
		if Net.phase ~= "run" then
			return
		end
		local _, _, root = localParts()
		local target = Input.target(if root then root.Position else nil)
		if target == "portal" then
			Net.enterPortal()
		elseif target == "chest" or target == "shrine" then
			if not holding then
				holding = true
				Net.setInteracting(true)
			end
		else
			Input.cast()
		end
	elseif holding then
		holding = false
		Net.setInteracting(false)
	end
end

-- Dashes the way the hero moves, or the way it faces when standing.
function Input.dash()
	if Net.phase ~= "run" then
		return
	end
	local _, humanoid, root = localParts()
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	local move = humanoid.MoveDirection
	local direction = Vector3.new(move.X, 0, move.Z)
	if direction.Magnitude < STANDING then
		local look = root.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < STANDING then
		return
	end
	direction = direction.Unit
	Net.dash(direction.X, direction.Z)
end

-- Shortens `delta` so that a move from `origin` stops before an obstacle or
-- the map's wall: only the solid parts in workspace.World stop it.
local function limitByWalls(origin: Vector3, delta: Vector3): Vector3
	local distance = delta.Magnitude
	local world = workspace:FindFirstChild("World")
	if distance < 1e-3 or world == nil then
		return delta
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	-- Walk-through dressing does not stop it.
	params.RespectCanCollide = true
	local hit = workspace:Raycast(origin, delta, params)
	if hit == nil then
		return delta
	end
	return delta.Unit * math.max(0, hit.Distance - WALL_MARGIN)
end

local function addShift(character: Model, root: BasePart, delta: Vector3, duration: number)
	table.insert(shifts, {
		character = character,
		delta = limitByWalls(root.Position, delta),
		duration = duration,
		elapsed = 0,
		applied = 0,
	})
end

-- Lifts the character onto the ground when a shift has pushed its feet under
-- it; physics settles it from there. The root's centre stands HipHeight plus
-- half its own height above the feet (R15).
local function keepAboveGround(character: Model, humanoid: Humanoid, root: BasePart)
	local position = root.Position
	local standing = Net.groundYExact(position.X, position.Z) + humanoid.HipHeight + root.Size.Y / 2
	if standing > position.Y then
		character:PivotTo(character:GetPivot() + Vector3.new(0, standing - position.Y, 0))
	end
end

-- Carries the character along its shifts; a shift of another character is dropped.
local function stepShifts(character: Model, humanoid: Humanoid, root: BasePart, deltaTime: number)
	for index = #shifts, 1, -1 do
		local shift = shifts[index]
		if shift.character ~= character then
			table.remove(shifts, index)
			continue
		end
		shift.elapsed += deltaTime
		local fraction = math.min(shift.elapsed / shift.duration, 1)
		character:PivotTo(character:GetPivot() + shift.delta * (fraction - shift.applied))
		keepAboveGround(character, humanoid, root)
		shift.applied = fraction
		if fraction >= 1 then
			table.remove(shifts, index)
		end
	end
end

-- Plays a knockback or a dash of the local character: (dx, dz) over `seconds`.
local function shifted(dx: number, dz: number, seconds: number)
	local character, _, root = localParts()
	if character == nil or root == nil then
		return
	end
	addShift(character, root, Vector3.new(dx, 0, dz), seconds)
end

local function update(deltaTime: number)
	local character, humanoid, root = localParts()
	if character == nil or humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	stepShifts(character, humanoid, root, deltaTime)
end

local function onInputBegan(input: InputObject, _gameProcessed: boolean)
	if typing() then
		return
	end
	local key = input.KeyCode
	local selfView = Net.self
	local offer = if offerUp() and selfView then selfView.offer else nil
	local card = CARD_KEYS[key] or PAD_SLOT_KEYS[key]
	if offer and card then
		if card <= #offer then
			Net.chooseCard(card)
		end
	elseif UTILITY_KEYS[key] or PAD_SLOT_KEYS[key] then
		Input.useUtility(UTILITY_KEYS[key] or PAD_SLOT_KEYS[key])
	elseif INTERACT_KEYS[key] then
		Input.interact(true)
	elseif DASH_KEYS[key] then
		Input.dash()
	end
end

-- Releases are handled whatever the focus: a key let go while typing must not stick.
local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if INTERACT_KEYS[input.KeyCode] then
		Input.interact(false)
	end
end

function Input.start()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	-- A key released while the window is in the background never arrives.
	UserInputService.WindowFocusReleased:Connect(function()
		Input.interact(false)
	end)
	Net.onPhase(function()
		Input.interact(false)
	end)
	Net.onEvents(function(events)
		for _, event in events do
			local userId = Players.LocalPlayer.UserId
			if event.kind == "knockback" and event.player == userId then
				shifted(event.dx, event.dz, Config.player.knockbackSeconds)
			elseif event.kind == "dash" and event.player == userId then
				shifted(event.dx, event.dz, Config.player.dashSeconds)
			end
		end
	end)
	RunService:BindToRenderStep("InputShifts", Enum.RenderPriority.Character.Value + 1, update)
end

return Input
