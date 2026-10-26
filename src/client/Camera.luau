--!strict
-- A fixed top-down camera that follows the local character. Purely
-- presentation: it never feeds anything back to the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Camera = {}

-- Where the camera sits relative to what it looks at, in studs.
local OFFSET = Vector3.new(0, 70, 35)
-- How quickly the camera catches up with the character, per second.
local FOLLOW_RATE = 8

local focus: Vector3? = nil
local trackedCharacter: Model? = nil

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
		camera.CFrame = CFrame.lookAt(target + OFFSET, target)
	end
end

function Camera.start()
	-- Just after Roblox's own camera, so ours is the last word each frame.
	RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return Camera
