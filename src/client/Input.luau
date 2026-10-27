--!strict
-- Raw input: the character faces the aim (the server reads the facing from the
-- root part, so facing the aim is sending it), the basic attack fires while held,
-- three active skills, the dash, drinking, interacting and the map screen. PC, touch (an aim pad on
-- the right of the screen) and gamepad. The client only sends intents and moves its
-- own character; the server decides what happens (AGENTS.md rule 1). The Hud's
-- on-screen buttons call the exported functions. The local player's Blink and
-- Arcane Bolts are drawn from here, as they happen, rather than from the
-- server's events, which come a snapshot later and say nothing of a miss.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)
local MapScreen = require(script.Parent.MapScreen)
local Net = require(script.Parent.Net)

local Input = {}

-- A dash or knockback stops this far before a wall.
local WALL_MARGIN = 1.5
-- The aim is sent at most this often, and only once it has turned this much.
local AIM_INTERVAL = 0.1
local AIM_EPSILON = math.rad(2)
-- The aim pad is the right part of the screen; a drag longer than this aims and fires.
local PAD_REGION = 0.45
local PAD_DEADZONE = 12
-- The gamepad's right stick below this deflection gives no aim.
local STICK_DEADZONE = 0.25
-- Below this the move direction counts as standing still.
local MOVE_EPSILON = 0.1
-- How far the mouse's ray looks for something to aim at, in studs.
local AIM_RAY_LENGTH = 1000
-- The basic attack as the server fires it while held: once per cooldown, out
-- to its range. Perks that change either are not reflected in the drawing.
local BASIC = Config.classes.elementalist.basic

local SKILL_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Q] = 1,
	[Enum.KeyCode.E] = 2,
	[Enum.KeyCode.R] = 3,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
}
local DASH_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonR1] = true,
}
local DRINK_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.C] = true,
	[Enum.KeyCode.DPadDown] = true,
}
local INTERACT_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.F] = true,
	[Enum.KeyCode.ButtonA] = true,
}
-- Open or close the map screen (the same as Hud.toggleMap, which requires this module).
local MAP_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.M] = true,
	[Enum.KeyCode.DPadUp] = true,
}
-- The last input type that makes the mouse the aim source.
local MOUSE_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Keyboard] = true,
}

-- A displacement of the character, spread over `duration` seconds.
type Shift = {
	character: Model,
	delta: Vector3,
	duration: number,
	elapsed: number,
	applied: number,
}

local lastAim: Vector3? = nil
local mouseAim = UserInputService.MouseEnabled
-- The right stick's deflection (x right, y up).
local stick = Vector2.zero
-- The touch that is the aim pad, where it began and the aim it gives once past the dead zone.
local padTouch: InputObject? = nil
local padStart = Vector2.zero
local padAim: Vector3? = nil

local firing = false
-- When the next local Arcane Bolt may be drawn.
local nextBoltAt = 0
-- The walk speed the server set, restored after a backpedal; nil while not backpedaling.
local speedBeforeBackpedal: number? = nil
-- The last aim angle sent to the server and when.
local sentAim: number? = nil
local sentAimAt = 0
local shifts: { Shift } = {}
local dashShift: Shift? = nil
local trackedCharacter: Model? = nil

-- Where the mouse points: the first terrain, water, prop or enemy under it, so
-- a target up or down a slope is read where it is drawn. With nothing under
-- the mouse (past the map's edge), the level plane through the ground under
-- the character. The invisible barriers and the bushes are not targets.
local function groundPoint(root: BasePart): Vector3?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	local targets: { Instance } = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	local props = if world then world:FindFirstChild("Props") else nil
	if props then
		table.insert(targets, props)
	end
	local enemies = workspace:FindFirstChild("ClientEnemies")
	if enemies then
		table.insert(targets, enemies)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	local hit = workspace:Raycast(ray.Origin, ray.Direction * AIM_RAY_LENGTH, params)
	if hit then
		return hit.Position
	end
	if ray.Direction.Y >= -1e-4 then
		return nil
	end
	local planeY = Net.heightAt(root.Position.X, root.Position.Z)
	return ray.Origin + ray.Direction * ((planeY - ray.Origin.Y) / ray.Direction.Y)
end

-- Clicking a button of the Hud (a perk offer, say) must not fire.
local function overButton(position: Vector3): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end
	for _, object in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if object:IsA("GuiButton") then
			return true
		end
	end
	return false
end

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

local function flat(vector: Vector3): Vector3?
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < 1e-3 then
		return nil
	end
	return horizontal.Unit
end

-- The direction the character is aiming along the ground, if it has aimed yet.
function Input.aimDirection(): Vector3?
	return lastAim
end

-- The aim as the core's angle: radians from +x toward +z.
local function aimAngle(): number?
	local aim = lastAim
	if aim == nil then
		return nil
	end
	return math.atan2(aim.Z, aim.X)
end

-- Tells the server the aim, throttled, once it has turned enough. Every skill
-- carries its own aim, so this only has to keep the basic attack honest.
local function sendAim(force: boolean)
	local angle = aimAngle()
	if angle == nil then
		return
	end
	local now = os.clock()
	local turned = sentAim == nil
		or math.abs((angle - sentAim + math.pi) % (2 * math.pi) - math.pi) > AIM_EPSILON
	if force or (turned and now - sentAimAt >= AIM_INTERVAL) then
		sentAim = angle
		sentAimAt = now
		Net.setAim(angle)
	end
end

-- How far the mouse's ground point is from the character: only a mouse aims at a point.
local function aimDistance(): number?
	if not mouseAim then
		return nil
	end
	local _, _, root = localParts()
	if root == nil then
		return nil
	end
	local point = groundPoint(root)
	if point == nil then
		return nil
	end
	return Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z).Magnitude
end

local function setFiring(held: boolean)
	if firing == held then
		return
	end
	firing = held
	Net.setFiring(held)
end

-- Fires active skill `index` (1..3) along the current aim.
function Input.useSkill(index: number)
	Net.useSkill(index, aimAngle(), aimDistance())
end

function Input.drink()
	Net.drink()
end

function Input.interact(held: boolean)
	Net.interact(held)
end

-- Shortens `delta` so that a move from `origin` stops before a prop or a barrier
-- of the map. Only the solid parts in workspace.World stop it: hills are
-- walkable, and the shift climbs them in `stepShifts`.
local function limitByWalls(origin: Vector3, delta: Vector3): Vector3
	local distance = delta.Magnitude
	local world = workspace:FindFirstChild("World")
	if distance < 1e-3 or world == nil then
		return delta
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	-- Bushes and other walk-through dressing do not stop a dash.
	params.RespectCanCollide = true
	local hit = workspace:Raycast(origin, delta, params)
	if hit == nil then
		return delta
	end
	return delta.Unit * math.max(0, hit.Distance - WALL_MARGIN)
end

local function addShift(character: Model, root: BasePart, delta: Vector3, duration: number): Shift
	local shift = {
		character = character,
		delta = limitByWalls(root.Position, delta),
		duration = duration,
		elapsed = 0,
		applied = 0,
	}
	table.insert(shifts, shift)
	return shift
end

-- Lifts the character onto the ground when a shift has pushed its feet under a
-- hill; physics settles it from there. The root's centre stands HipHeight plus
-- half its own height above the feet (R15).
local function keepAboveGround(character: Model, humanoid: Humanoid, root: BasePart)
	local position = root.Position
	local standing = Net.heightAt(position.X, position.Z) + humanoid.HipHeight + root.Size.Y / 2
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
			if shift == dashShift then
				dashShift = nil
			end
			continue
		end
		shift.elapsed += deltaTime
		local fraction = math.min(shift.elapsed / shift.duration, 1)
		character:PivotTo(character:GetPivot() + shift.delta * (fraction - shift.applied))
		keepAboveGround(character, humanoid, root)
		shift.applied = fraction
		if fraction >= 1 then
			table.remove(shifts, index)
			if shift == dashShift then
				dashShift = nil
			end
		end
	end
end

-- Asks for a dash and moves the character along the move direction (or the facing)
-- by the distance the server last said a dash carries, over the dash's time.
function Input.dash()
	if dashShift ~= nil then
		return
	end
	local dashSelf = Net.self
	if dashSelf and dashSelf.dashCharges <= 0 then
		return
	end
	Net.dash()
	local character, humanoid, root = localParts()
	if character == nil or humanoid == nil or root == nil then
		return
	end
	local direction = if humanoid.MoveDirection.Magnitude > MOVE_EPSILON
		then flat(humanoid.MoveDirection)
		else nil
	direction = direction or lastAim or flat(root.CFrame.LookVector)
	if direction == nil then
		return
	end
	local dash = Config.classes.elementalist.dash
	local distance = if dashSelf then dashSelf.dashDistance else dash.distance
	local from = root.Position
	local shift = addShift(character, root, direction * distance, dash.seconds)
	dashShift = shift
	Effects.showLocalBlink(from, from + shift.delta)
end

local function knocked(dx: number, dz: number)
	local character, _, root = localParts()
	if character == nil or root == nil then
		return
	end
	addShift(character, root, Vector3.new(dx, 0, dz), Config.player.knockbackSeconds)
end

-- Where the character aims this frame: the aim pad, the right stick or the mouse; with
-- none of them the last aim stays.
local function updateAim(root: BasePart)
	if padAim then
		lastAim = padAim
	elseif stick.Magnitude > STICK_DEADZONE then
		lastAim = flat(Vector3.new(stick.X, 0, -stick.Y)) or lastAim
	elseif mouseAim then
		local point = groundPoint(root)
		if point then
			lastAim = flat(point - root.Position) or lastAim
		end
	end
end

local function face(root: BasePart)
	local aim = lastAim
	if aim == nil then
		return
	end
	local position = root.Position
	root.CFrame = CFrame.lookAt(position, position + aim)
end

-- Walking away from the aim while firing is slower. The server holds the budget
-- to the same rule; this only keeps the character from running ahead of it. The
-- speed the server set (perks included) comes back afterwards.
local function updateBackpedal(humanoid: Humanoid)
	local move = humanoid.MoveDirection
	local aim = lastAim
	local backwards = firing
		and aim ~= nil
		and move.Magnitude > MOVE_EPSILON
		and move.Unit:Dot(aim) < Config.player.backpedalDot
	local before = speedBeforeBackpedal
	if backwards and before == nil then
		speedBeforeBackpedal = humanoid.WalkSpeed
		humanoid.WalkSpeed = humanoid.WalkSpeed * Config.player.backpedalFactor
	elseif not backwards and before ~= nil then
		humanoid.WalkSpeed = before
		speedBeforeBackpedal = nil
	end
end

-- Whether the server would fire the basic attack for the local player now:
-- alive and not drinking, as the latest snapshot has it.
local function ableToFire(): boolean
	local latest = Net.latest
	if latest == nil then
		return false
	end
	local userId = Players.LocalPlayer.UserId
	for _, player in latest.world.players do
		if player.id == userId then
			return player.state == "alive" and player.drinkingFor <= 0
		end
	end
	return false
end

-- Draws a local Arcane Bolt each time the basic attack fires while held, at
-- the server's cadence, so a miss shows as well as a hit.
local function updateBolt(root: BasePart)
	local aim = lastAim
	local now = os.clock()
	if not firing or aim == nil or now < nextBoltAt or not ableToFire() then
		return
	end
	nextBoltAt = now + BASIC.cooldownSeconds
	Effects.showLocalBolt(root.Position, aim, BASIC.range)
end

local function update(deltaTime: number)
	local character, humanoid, root = localParts()
	if character == nil or humanoid == nil or root == nil then
		return
	end
	if character ~= trackedCharacter then
		trackedCharacter = character
		speedBeforeBackpedal = nil
		humanoid.AutoRotate = false
	end
	if humanoid.Health <= 0 then
		return
	end
	stepShifts(character, humanoid, root, deltaTime)
	updateAim(root)
	face(root)
	sendAim(false)
	updateBackpedal(humanoid)
	updateBolt(root)
end

-- Assist follows what the player last aimed with: a stick or a touch gets the
-- cone, a mouse does not, so a controller merely plugged in changes nothing.
local assisting: boolean? = nil
local function refreshAssist()
	local wanted = not mouseAim
	if wanted ~= assisting then
		assisting = wanted
		Net.setAssist(wanted)
	end
end

local function onInputBegan(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.Touch then
		if padTouch ~= nil or overButton(input.Position) then
			return
		end
		local camera = workspace.CurrentCamera
		if camera == nil or input.Position.X < camera.ViewportSize.X * (1 - PAD_REGION) then
			return
		end
		padTouch = input
		padStart = Vector2.new(input.Position.X, input.Position.Y)
		return
	end
	if typing() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not overButton(input.Position) then
			sendAim(true)
			setFiring(true)
		end
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonR2 then
		sendAim(true)
		setFiring(true)
	elseif SKILL_KEYS[key] then
		Input.useSkill(SKILL_KEYS[key])
	elseif DASH_KEYS[key] then
		Input.dash()
	elseif DRINK_KEYS[key] then
		Input.drink()
	elseif INTERACT_KEYS[key] then
		Input.interact(true)
	elseif MAP_KEYS[key] then
		MapScreen.toggle()
	end
end

local function onInputChanged(input: InputObject, _gameProcessed: boolean)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	elseif input == padTouch then
		-- Screen right is world +x and screen up is world -z, as the camera sees it.
		local drag = Vector2.new(input.Position.X, input.Position.Y) - padStart
		if drag.Magnitude > PAD_DEADZONE then
			padAim = flat(Vector3.new(drag.X, 0, drag.Y))
			lastAim = padAim or lastAim
			sendAim(not firing)
			setFiring(true)
		end
	end
end

-- Releases are handled whatever the focus: a key let go while typing must not stick.
local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input == padTouch then
		padTouch = nil
		padAim = nil
		setFiring(false)
	elseif
		input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
	then
		setFiring(false)
	elseif INTERACT_KEYS[input.KeyCode] then
		Input.interact(false)
	end
end

function Input.start()
	refreshAssist()
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if MOUSE_TYPES[inputType] then
			mouseAim = UserInputService.MouseEnabled
		elseif inputType == Enum.UserInputType.Touch or inputType.Name:sub(1, 7) == "Gamepad" then
			mouseAim = false
		end
		refreshAssist()
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	-- A key released while the window is in the background never arrives.
	UserInputService.WindowFocusReleased:Connect(function()
		firing = false
		Net.setFiring(false)
		Net.interact(false)
	end)
	Net.onEvents(function(events)
		for _, event in events do
			if event.kind == "knockback" and event.player == Players.LocalPlayer.UserId then
				knocked(event.dx, event.dz)
			end
		end
	end)
	-- After the camera, so the facing is the last word each frame.
	RunService:BindToRenderStep("InputFacing", Enum.RenderPriority.Camera.Value + 2, update)
end

return Input
