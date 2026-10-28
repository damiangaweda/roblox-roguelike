--!strict
-- The world's light, as the client wants it. `default.project.json` sets the
-- same values on Lighting for the built place; a live Rojo session does not
-- always push service properties, so the client applies them again at start.
-- Lighting changes on the client are local, which is all a look needs. Every
-- number here is presentation; keep it in step with the project file.
--
-- Two looks lie over the day (ADR-0021): doom, a dark violet sky with the
-- haze drawn in, which stays until the next run; and the final boss's rise,
-- a darkening the effects ramp in and out, with a flash when it stands.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Net = require(script.Parent.Net)

local Atmosphere = {}

-- The sun: late afternoon, fairly high, long but readable shadows.
local CLOCK_TIME = 15.5
local LATITUDE = 20
local BRIGHTNESS = 2.6
local EXPOSURE = -0.1
local AMBIENT = Color3.new(0.33, 0.33, 0.36)
local OUTDOOR_AMBIENT = Color3.new(0.5, 0.49, 0.53)
local SHIFT_TOP = Color3.new(1, 0.93, 0.82)
local SHIFT_BOTTOM = Color3.new(0, 0, 0)
local DIFFUSE_SCALE = 0.5
local SPECULAR_SCALE = 0.35
local SHADOW_SOFTNESS = 0.3

-- Distance haze.
local ATMOSPHERE_DENSITY = 0.28
local ATMOSPHERE_OFFSET = 0.15
local ATMOSPHERE_COLOR = Color3.new(0.82, 0.75, 0.63)
local ATMOSPHERE_DECAY = Color3.new(0.43, 0.39, 0.35)
local ATMOSPHERE_GLARE = 0.1
local ATMOSPHERE_HAZE = 1

-- The sky that ships with the engine.
local SKY_FACES = {
	SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
	SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
	SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
	SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
	SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
	SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
}

-- Post effects: a touch of contrast and saturation, subtle rays, a bloom so
-- neon effects glow.
local CONTRAST = 0.08
local SATURATION = 0.1
local TINT = Color3.new(1, 0.98, 0.95)
local SUN_RAYS_INTENSITY = 0.05
local SUN_RAYS_SPREAD = 0.5
local BLOOM_INTENSITY = 0.5
local BLOOM_SIZE = 24
local BLOOM_THRESHOLD = 1.6

-- Doom: the light falls, the ambient turns dark violet, the haze closes in.
local DOOM_BRIGHTNESS = 0.9
local DOOM_EXPOSURE = -0.6
local DOOM_AMBIENT = Color3.fromRGB(46, 22, 64)
local DOOM_OUTDOOR_AMBIENT = Color3.fromRGB(70, 34, 92)
local DOOM_SHIFT_TOP = Color3.fromRGB(150, 90, 200)
local DOOM_DENSITY = 0.5
local DOOM_OFFSET = 0
local DOOM_HAZE_COLOR = Color3.fromRGB(60, 30, 80)
local DOOM_HAZE_DECAY = Color3.fromRGB(30, 12, 44)
local DOOM_TINT = Color3.fromRGB(200, 170, 230)
local DOOM_SATURATION = -0.2

-- The rise at its darkest: the light lower still and a violet tint.
local RISE_BRIGHTNESS = 0.6
local RISE_EXPOSURE = -0.8
local RISE_AMBIENT = Color3.fromRGB(40, 20, 60)
local RISE_OUTDOOR_AMBIENT = Color3.fromRGB(60, 30, 90)
local RISE_TINT = Color3.fromRGB(190, 150, 255)
-- The flash when the final boss stands: the picture's brightness, then back.
local FLASH_BRIGHTNESS = 0.7
local FLASH_SECONDS = 0.6

-- The child of Lighting with this name and class, made when missing.
local function ensure(name: string, className: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

-- What lies over the day: doom, and the rise's darkness from 0 to 1.
local doom = false
local rise = 0
local flashTween: Tween? = nil

local function mix(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

-- Sets the light that doom and the rise change, from the day's.
local function apply()
	local d = if doom then 1 else 0
	local brightness = mix(BRIGHTNESS, DOOM_BRIGHTNESS, d)
	local exposure = mix(EXPOSURE, DOOM_EXPOSURE, d)
	local ambient = AMBIENT:Lerp(DOOM_AMBIENT, d)
	local outdoor = OUTDOOR_AMBIENT:Lerp(DOOM_OUTDOOR_AMBIENT, d)
	local tint = TINT:Lerp(DOOM_TINT, d)
	Lighting.Brightness = mix(brightness, RISE_BRIGHTNESS, rise)
	Lighting.ExposureCompensation = mix(exposure, RISE_EXPOSURE, rise)
	Lighting.Ambient = ambient:Lerp(RISE_AMBIENT, rise)
	Lighting.OutdoorAmbient = outdoor:Lerp(RISE_OUTDOOR_AMBIENT, rise)
	Lighting.ColorShift_Top = SHIFT_TOP:Lerp(DOOM_SHIFT_TOP, d)

	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	if atmosphere and atmosphere:IsA("Atmosphere") then
		atmosphere.Density = mix(ATMOSPHERE_DENSITY, DOOM_DENSITY, d)
		atmosphere.Offset = mix(ATMOSPHERE_OFFSET, DOOM_OFFSET, d)
		atmosphere.Color = ATMOSPHERE_COLOR:Lerp(DOOM_HAZE_COLOR, d)
		atmosphere.Decay = ATMOSPHERE_DECAY:Lerp(DOOM_HAZE_DECAY, d)
	end
	local correction = Lighting:FindFirstChild("ColorCorrection")
	if correction and correction:IsA("ColorCorrectionEffect") then
		correction.TintColor = tint:Lerp(RISE_TINT, rise)
		correction.Saturation = mix(SATURATION, DOOM_SATURATION, d)
	end
end

-- Doom's look on or off; it stays until the next run.
function Atmosphere.setDoom(on: boolean)
	if on == doom then
		return
	end
	doom = on
	apply()
end

-- The final boss's rise: 0 is no darkening, 1 the darkest.
function Atmosphere.setRise(share: number)
	local clamped = math.clamp(share, 0, 1)
	if clamped == rise then
		return
	end
	rise = clamped
	apply()
end

-- A flash of the whole picture, fading back.
function Atmosphere.flash()
	local correction = Lighting:FindFirstChild("ColorCorrection")
	if correction == nil or not correction:IsA("ColorCorrectionEffect") then
		return
	end
	if flashTween then
		flashTween:Cancel()
	end
	correction.Brightness = FLASH_BRIGHTNESS
	local tween = TweenService:Create(
		correction,
		TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	)
	flashTween = tween
	tween:Play()
end

-- The day back, as at the start.
function Atmosphere.restore()
	doom = false
	rise = 0
	apply()
end

function Atmosphere.start()
	Lighting.ClockTime = CLOCK_TIME
	Lighting.GeographicLatitude = LATITUDE
	Lighting.Brightness = BRIGHTNESS
	Lighting.ExposureCompensation = EXPOSURE
	Lighting.Ambient = AMBIENT
	Lighting.OutdoorAmbient = OUTDOOR_AMBIENT
	Lighting.ColorShift_Top = SHIFT_TOP
	Lighting.ColorShift_Bottom = SHIFT_BOTTOM
	Lighting.EnvironmentDiffuseScale = DIFFUSE_SCALE
	Lighting.EnvironmentSpecularScale = SPECULAR_SCALE
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = SHADOW_SOFTNESS

	local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = ATMOSPHERE_DENSITY
	atmosphere.Offset = ATMOSPHERE_OFFSET
	atmosphere.Color = ATMOSPHERE_COLOR
	atmosphere.Decay = ATMOSPHERE_DECAY
	atmosphere.Glare = ATMOSPHERE_GLARE
	atmosphere.Haze = ATMOSPHERE_HAZE

	local sky = ensure("Sky", "Sky") :: Sky
	for property, id in SKY_FACES do
		(sky :: any)[property] = id
	end
	sky.CelestialBodiesShown = true

	local correction = ensure("ColorCorrection", "ColorCorrectionEffect") :: ColorCorrectionEffect
	correction.Brightness = 0
	correction.Contrast = CONTRAST
	correction.Saturation = SATURATION
	correction.TintColor = TINT

	local rays = ensure("SunRays", "SunRaysEffect") :: SunRaysEffect
	rays.Intensity = SUN_RAYS_INTENSITY
	rays.Spread = SUN_RAYS_SPREAD

	local bloom = ensure("Bloom", "BloomEffect") :: BloomEffect
	bloom.Intensity = BLOOM_INTENSITY
	bloom.Size = BLOOM_SIZE
	bloom.Threshold = BLOOM_THRESHOLD

	-- A place's default depth of field blurs the top-down view.
	local depth = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if depth then
		depth.Enabled = false
	end

	doom = false
	rise = 0
	apply()
	-- A new run, or the pick before it, begins under the day's light.
	Net.onPhase(function(phase)
		if phase ~= "summary" then
			Atmosphere.restore()
		end
	end)
end

return Atmosphere
