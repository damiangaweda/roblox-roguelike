--!strict
-- The world's light, as the client wants it. `default.project.json` sets the
-- same values on Lighting for the built place; a live Rojo session does not
-- always push service properties, so the client applies them again at start.
-- Lighting changes on the client are local, which is all a look needs. Every
-- number here is presentation; keep it in step with the project file.

local Lighting = game:GetService("Lighting")

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
end

return Atmosphere
