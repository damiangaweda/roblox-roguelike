--!strict
-- Skill aim on PC: the left mouse button or Q fires the skill at the point
-- where the mouse ray meets the ground. The server decides what happens.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Net)

local Input = {}

-- The ground plane is y = 0.
local function groundPoint(): Vector3?
	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	if ray.Direction.Y >= -1e-4 then
		return nil
	end
	return ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)
end

-- Clicking a button of the Hud (a perk offer, say) must not fire the skill.
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

local function onInputBegan(input: InputObject, _gameProcessed: boolean)
	-- Touch devices fire through the Hud's own button, which auto-aims.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return
	end
	local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
	local isKey = input.KeyCode == Enum.KeyCode.Q
	if not (isMouse or isKey) then
		return
	end
	-- Typing in the chat is not aiming.
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if isMouse and overButton(input.Position) then
		return
	end
	local point = groundPoint()
	if point then
		Net.useActiveSkill(point)
	end
end

function Input.start()
	UserInputService.InputBegan:Connect(onInputBegan)
end

return Input
