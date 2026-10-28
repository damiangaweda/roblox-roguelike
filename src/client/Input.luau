--!strict
-- Raw input for the solo run (ADR-0013): Roblox's own character movement
-- walks the hero (WASD, the thumbstick on touch); keys fire the three utility
-- skills or, while an offer is up, choose a card; the interact key opens the
-- chest or enters the portal; the cast key casts the extraction spell. The
-- client only sends intents and moves its own character; the server decides
-- what happens (AGENTS.md rule 1). The Hud's touch buttons call the exported
-- functions. A knockback the server reports is played here at once, so the
-- character does not wait a snapshot to be pushed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

local Input = {}

-- A knockback stops this far before an obstacle.
local WALL_MARGIN = 1.5

-- The three buttons: a utility skill, or a card while an offer is up.
local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
}
local INTERACT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.ButtonL1] = true,
}
local CAST_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.F] = true,
	[Enum.KeyCode.ButtonR1] = true,
}

-- A displacement of the character, spread over `duration` seconds.
type Shift = {
	character: Model,
	delta: Vector3,
	duration: number,
	elapsed: number,
	applied: number,
}

local shifts: { Shift } = {}
-- Whether the open intent was last sent held, so a release follows it.
local opening = false

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

-- Whether the local hero stands within the portal's reach, as the latest
-- snapshot places the portal.
local function nearPortal(): boolean
	local latest = Net.latest
	local portal = if latest then latest.world.portal else nil
	local _, _, root = localParts()
	if portal == nil or root == nil then
		return false
	end
	local dx, dz = portal.x - root.Position.X, portal.z - root.Position.Z
	local reach = Config.extraction.portalRadius
	return dx * dx + dz * dz <= reach * reach
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

-- The interact button went down (`held`) or up: by the portal it enters, else
-- holding it opens the chest.
function Input.interact(held: boolean)
	if held then
		if Net.phase ~= "run" then
			return
		end
		if nearPortal() then
			Net.enterPortal()
		elseif not opening then
			opening = true
			Net.setInteracting(true)
		end
	elseif opening then
		opening = false
		Net.setInteracting(false)
	end
end

-- Casts the extraction spell.
function Input.cast()
	if Net.phase == "run" then
		Net.castSpell()
	end
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
	local standing = Net.groundY() + humanoid.HipHeight + root.Size.Y / 2
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

local function knocked(dx: number, dz: number)
	local character, _, root = localParts()
	if character == nil or root == nil then
		return
	end
	addShift(character, root, Vector3.new(dx, 0, dz), Config.player.knockbackSeconds)
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
	local slot = SLOT_KEYS[key]
	if slot then
		local selfView = Net.self
		local offer = if selfView then selfView.offer else nil
		if offerUp() and offer then
			if slot <= #offer then
				Net.chooseCard(slot)
			end
		else
			Input.useUtility(slot)
		end
	elseif INTERACT_KEYS[key] then
		Input.interact(true)
	elseif CAST_KEYS[key] then
		Input.cast()
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
			if event.kind == "knockback" and event.player == Players.LocalPlayer.UserId then
				knocked(event.dx, event.dz)
			end
		end
	end)
	RunService:BindToRenderStep("InputShifts", Enum.RenderPriority.Character.Value + 1, update)
end

return Input
