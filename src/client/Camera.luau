--!strict
-- A top-down camera that follows the local character, close enough for a room
-- to fill the screen, with a shake that big hits ask for. Purely presentation:
-- it never feeds anything back to the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Camera = {}

-- Where the camera sits relative to what it looks at, in studs.
local OFFSET = Vector3.new(0, 44, 20)
-- How quickly the camera catches up with the character, per second.
local FOLLOW_RATE = 8
-- How quickly a shake dies out, per second.
local SHAKE_DECAY = 6

local focus: Vector3? = nil
local trackedCharacter: Model? = nil
local shake = 0
local random = Random.new()

local function update(deltaTime: number)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character and root and root:IsA("BasePart") then
		local current = focus
		if current == nil or character ~= trackedCharacter then
			-- First frame or a respawn: jump instead of gliding across the map.
			focus = root.Position
			trackedCharacter = character
		else
			focus = current:Lerp(root.Position, 1 - math.exp(-FOLLOW_RATE * deltaTime))
		end
	end

	local target = focus
	if target then
		local jitter = Vector3.zero
		if shake > 0.01 then
			jitter = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * shake
			shake *= math.exp(-SHAKE_DECAY * deltaTime)
		else
			shake = 0
		end
		camera.CFrame = CFrame.lookAt(target + OFFSET + jitter, target + jitter)
	end
end

-- Shakes the camera by up to `magnitude` studs, fading out.
function Camera.shake(magnitude: number)
	shake = math.max(shake, magnitude)
end

function Camera.start()
	-- Just after Roblox's own camera, so ours is the last word each frame.
	RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return Camera
