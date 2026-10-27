--!strict
-- Dresses a hero's character for its class: the class colour on the torso
-- and limbs, a sash, a soft glow and a weapon built from parts in the right
-- hand (a staff, a sword or a bow). The default R15 rig stays (simplification
-- register); this only makes the class read from the top-down camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Core.Types)

local HeroLook = {}

local LOOK_FOLDER = "ClassLook"
local TORSO_PARTS = { "UpperTorso", "LowerTorso" }
local LIMB_PARTS = {
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}
local HEAD_COLOR = Color3.fromRGB(234, 200, 170)
local DARKEN = 0.35
local LIGHTEN = 0.25

local function colour(hex: number): Color3
	return Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
end

local function part(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.Color = color
	piece.Material = material
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
	piece.Parent = parent
	return piece
end

-- Welds `piece` to `to` so that it sits at `offset` in `to`'s frame.
local function attach(piece: BasePart, to: BasePart, offset: CFrame)
	piece.CFrame = to.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = piece
	weld.Parent = piece
end

local function tint(character: Model, names: { string }, color: Color3)
	for _, name in names do
		local piece = character:FindFirstChild(name)
		if piece and piece:IsA("BasePart") then
			piece.Color = color
			piece.Material = Enum.Material.SmoothPlastic
		end
	end
end

local function buildStaff(hand: BasePart, base: Color3, folder: Folder)
	local shaft = part(
		"Shaft",
		Vector3.new(0.3, 5.2, 0.3),
		Color3.fromRGB(96, 66, 42),
		Enum.Material.Wood,
		folder
	)
	attach(shaft, hand, CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(10), 0, 0))
	local orb = part(
		"Orb",
		Vector3.new(0.9, 0.9, 0.9),
		base:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.Neon,
		folder
	)
	orb.Shape = Enum.PartType.Ball
	attach(orb, shaft, CFrame.new(0, 2.9, 0))
	local light = Instance.new("PointLight")
	light.Color = base
	light.Brightness = 1.5
	light.Range = 10
	light.Parent = orb
end

local function buildSword(hand: BasePart, base: Color3, folder: Folder)
	local blade = part(
		"Blade",
		Vector3.new(0.25, 3.4, 0.7),
		Color3.fromRGB(210, 214, 222),
		Enum.Material.Metal,
		folder
	)
	attach(blade, hand, CFrame.new(0, -0.4, -2.2) * CFrame.Angles(math.rad(90), 0, 0))
	local guard = part("Guard", Vector3.new(1.4, 0.25, 0.3), base, Enum.Material.Metal, folder)
	attach(guard, hand, CFrame.new(0, -0.4, -0.5) * CFrame.Angles(math.rad(90), 0, 0))
	local grip = part(
		"Grip",
		Vector3.new(0.3, 0.9, 0.3),
		Color3.fromRGB(60, 40, 30),
		Enum.Material.Fabric,
		folder
	)
	attach(grip, hand, CFrame.new(0, 0, 0))
	local shield = part(
		"Shield",
		Vector3.new(0.3, 2.2, 1.8),
		base:Lerp(Color3.new(0, 0, 0), DARKEN),
		Enum.Material.Metal,
		folder
	)
	local leftArm = (hand.Parent :: Model):FindFirstChild("LeftLowerArm")
	if leftArm and leftArm:IsA("BasePart") then
		attach(shield, leftArm, CFrame.new(-0.5, 0, 0))
	end
end

local function buildBow(hand: BasePart, base: Color3, folder: Folder)
	local upper = part(
		"BowUpper",
		Vector3.new(0.25, 2, 0.25),
		Color3.fromRGB(110, 78, 46),
		Enum.Material.Wood,
		folder
	)
	attach(upper, hand, CFrame.new(0, 1, -0.2) * CFrame.Angles(math.rad(-15), 0, 0))
	local lower = part(
		"BowLower",
		Vector3.new(0.25, 2, 0.25),
		Color3.fromRGB(110, 78, 46),
		Enum.Material.Wood,
		folder
	)
	attach(lower, hand, CFrame.new(0, -1, -0.2) * CFrame.Angles(math.rad(15), 0, 0))
	local string = part(
		"BowString",
		Vector3.new(0.06, 3.8, 0.06),
		base:Lerp(Color3.new(1, 1, 1), 0.5),
		Enum.Material.Neon,
		folder
	)
	attach(string, hand, CFrame.new(0, 0, 0.3))
	local quiver = part(
		"Quiver",
		Vector3.new(0.7, 2, 0.7),
		base:Lerp(Color3.new(0, 0, 0), DARKEN),
		Enum.Material.Fabric,
		folder
	)
	local torso = (hand.Parent :: Model):FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		attach(quiver, torso, CFrame.new(-0.6, 0.4, 0.8) * CFrame.Angles(0, 0, math.rad(-20)))
	end
end

-- Applies the class look to `character`; call it after the character loads.
function HeroLook.apply(character: Model, class: Types.ClassConfig)
	local existing = character:FindFirstChild(LOOK_FOLDER)
	if existing then
		existing:Destroy()
	end
	local base = colour(class.colour)
	tint(character, TORSO_PARTS, base)
	tint(character, LIMB_PARTS, base:Lerp(Color3.new(0, 0, 0), DARKEN))
	tint(character, { "Head" }, HEAD_COLOR)
	for _, child in character:GetChildren() do
		if
			child:IsA("Accessory")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
		then
			child:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = LOOK_FOLDER
	folder.Parent = character

	local torso = character:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		local sash = part(
			"Sash",
			Vector3.new(2.2, 0.5, 1.2),
			base:Lerp(Color3.new(1, 1, 1), LIGHTEN),
			Enum.Material.Fabric,
			folder
		)
		attach(sash, torso, CFrame.new(0, -0.6, 0))
		local glow = part(
			"Glow",
			Vector3.new(0.6, 0.6, 0.2),
			base:Lerp(Color3.new(1, 1, 1), 0.4),
			Enum.Material.Neon,
			folder
		)
		attach(glow, torso, CFrame.new(0, 0.3, -0.6))
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local ring = part("Ring", Vector3.new(4, 0.1, 4), base, Enum.Material.Neon, folder)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.6
		ring.Size = Vector3.new(0.1, 4.2, 4.2)
		attach(ring, root, CFrame.new(0, -2.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local light = Instance.new("PointLight")
		light.Color = base
		light.Brightness = 0.8
		light.Range = 14
		light.Parent = root
	end

	local hand = character:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") then
		if class.weapon == "staff" then
			buildStaff(hand, base, folder)
		elseif class.weapon == "sword" then
			buildSword(hand, base, folder)
		else
			buildBow(hand, base, folder)
		end
	end
end

return HeroLook
