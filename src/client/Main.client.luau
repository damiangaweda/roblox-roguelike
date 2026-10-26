--!strict
-- The client entry point: starts every part of the client world.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Atmosphere = require(script.Parent.Atmosphere)
local Camera = require(script.Parent.Camera)
local Effects = require(script.Parent.Effects)
local EnemyView = require(script.Parent.EnemyView)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)

Atmosphere.start()
EnemyView.start()
Effects.start()
Camera.start()
Input.start()
Hud.start()

-- Roblox's reset would respawn the character at the origin, away from the
-- horde, while the run still holds the player; the run decides deaths.
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
			return
		end
		task.wait(1)
	end
end)

-- Frames per second of this client, written once a second for the lead to
-- read in Studio. The attribute stays on this client.
local frames = 0
local windowStart = os.clock()
RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	local elapsed = now - windowStart
	if elapsed >= 1 then
		workspace:SetAttribute("ClientFps", math.round(frames / elapsed))
		frames = 0
		windowStart = now
	end
end)
