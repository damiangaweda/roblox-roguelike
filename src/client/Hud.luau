--!strict
-- The HUD, built in code: health, potions, level and experience, the three
-- active skills and the dash, the run clock, the zone compass, banners, notices
-- and announcements, the perk choice and list, the downed, extraction and
-- end-of-run panels, and the touch buttons; the map screen is MapScreen's. It
-- only shows state and sends intents through Net or Input (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Input = require(script.Parent.Input)
local MapScreen = require(script.Parent.MapScreen)
local Net = require(script.Parent.Net)

local Hud = {}

-- Presentation constants; gameplay numbers come from Config.
local DESIGN_HEIGHT = 720
local MIN_SCALE = 0.55
local MAX_SCALE = 1.25
local BANNER_SECONDS = 4
-- A label's text stroke and a bar's track, as built.
local STROKE_TRANSPARENCY = 0.6
local TRACK_TRANSPARENCY = 0.15
-- The vignette's rims reach this far in: a share of the screen's width at the
-- sides and of its height at the top and the bottom.
local VIGNETTE_SIDE_DEPTH = 0.16
local VIGNETTE_END_DEPTH = 0.22
-- Hurt flash: a red rim that pops on a hit and fades out over this long.
local HURT_FLASH_SECONDS = 0.4
-- The rim's opacity for the lightest hit, the opacity each share of max health
-- a hit takes adds, and the most it reaches; a hit during a flash keeps the stronger.
local HURT_FLASH_MIN = 0.3
local HURT_FLASH_PER_SHARE = 2
local HURT_FLASH_MAX = 0.85
-- Low health: below this share of max health a slow pulse, below the second a fast one.
local LOW_HEALTH_SHARE = 0.35
local CRITICAL_HEALTH_SHARE = 0.15
-- Seconds per pulse, slow and fast.
local LOW_HEALTH_PERIOD = 1.4
local CRITICAL_HEALTH_PERIOD = 0.7
-- The dark rim's opacity at the bottom and the top of a pulse, slow and fast.
local LOW_HEALTH_ALPHA_MIN = 0.2
local LOW_HEALTH_ALPHA_MAX = 0.45
local CRITICAL_HEALTH_ALPHA_MIN = 0.35
local CRITICAL_HEALTH_ALPHA_MAX = 0.7
-- How quickly (per second) the low-health state eases in and out, so healing does not snap it off.
local LOW_HEALTH_EASE = 4
-- The health number's text stroke at full low health, darker so it reads on the pulse.
local LOW_HEALTH_STROKE_TRANSPARENCY = 0.1
-- Drinking: the bar sits this far right of the potion hint, and flashes this long when
-- a drink lands or is interrupted.
local DRINK_BAR_GAP = 26
local DRINK_BAR_WIDTH = 96
local DRINK_FLASH_SECONDS = 0.5
-- Level-up: the popup's life, how much it grows over it, the share of its life
-- before it starts to fade, and how long the experience bar flashes gold.
local LEVEL_POPUP_SECONDS = 1.2
local LEVEL_POPUP_GROWTH = 0.5
local LEVEL_POPUP_HOLD = 0.35
local LEVEL_FLASH_SECONDS = 0.6
-- Camp notices: how long a line stays, the fade at its end, and how many show at once.
local NOTICE_SECONDS = 2
local NOTICE_FADE_SECONDS = 0.5
local MAX_NOTICES = 3
-- Announcements of the run (zones, the flood, events, clues, chests) share the
-- notice lines and stay longer.
local ANNOUNCEMENT_SECONDS = 4
-- The first notice line's top, clear of the flood note above it, and the step between lines.
local NOTICE_TOP = 72
local NOTICE_STEP = 20
-- "A camp has noticed you" shows only when an enemy this close to the local
-- character (on the ground plane) woke from idle to chase in the same snapshot.
local NOTICED_RANGE = 40
-- "A clue is nearby" shows only when a clue was found this close to the local character.
local CLUE_NEARBY_RANGE = 40
-- Downed, dead and extracted screens fade in over this long, to these tint opacities.
local STATE_FADE_SECONDS = 0.6
local DOWNED_TINT_ALPHA = 0.15
local DEAD_TINT_ALPHA = 0.1
local STATE_PANEL_TRANSPARENCY = 0.3
local COMPASS_RADIUS = 110
-- A zone this close (edge to character) is on screen; its arrow is hidden.
local COMPASS_HIDE_STUDS = 25
-- "No zone yet" (or "No zone left") sits where the arrow would point straight up, this faint.
local NO_ZONE_TRANSPARENCY = 0.3
-- The touch Map button, under the stats panel.
local MAP_BUTTON_SIZE = Vector2.new(76, 44)
local MAP_BUTTON_TOP = 144
local MAX_SKILL_SLOTS = 3
local SKILL_KEYS = { "Q", "E", "R" }
local POTION_SLOT_SIZE = 22
local POTION_SLOT_STEP = 26

-- What a perk's property is called on a perk button.
local PROPERTY_LABELS: { [string]: string } = {
	damage = "Damage",
	area = "Area size",
	cooldown = "Cooldowns",
	attackSpeed = "Attack speed",
	range = "Range",
	statusDuration = "Status duration",
	projectileSplit = "Projectiles",
	pierce = "Pierce",
	chainJumps = "Chain jumps",
	knockback = "Knockback",
	maxHealth = "Max health",
	moveSpeed = "Move speed",
	dashCharges = "Dash charges",
	dashDistance = "Dash distance",
	potionCapacity = "Potion slots",
	potionHeal = "Potion healing",
	burnDamage = "Burn damage",
	chillSlow = "Chill slow",
	synergyBonus = "Synergy bonus",
	xpGain = "Experience",
}

local WHITE = Color3.new(1, 1, 1)
local PANEL_COLOR = Color3.fromRGB(20, 22, 28)
local TRACK_COLOR = Color3.fromRGB(45, 48, 58)
local HEALTH_COLOR = Color3.fromRGB(214, 69, 65)
local XP_COLOR = Color3.fromRGB(86, 156, 236)
local SKILL_COLOR = Color3.fromRGB(120, 200, 120)
local SKILL_COOLDOWN_COLOR = Color3.fromRGB(110, 114, 126)
local POTION_COLOR = Color3.fromRGB(214, 69, 65)
local DASH_COLOR = Color3.fromRGB(150, 210, 240)
local EXTRACT_COLOR = Color3.fromRGB(240, 196, 70)
local BLEED_COLOR = Color3.fromRGB(190, 60, 60)
local REVIVE_COLOR = Color3.fromRGB(110, 210, 150)
local HURT_COLOR = Color3.fromRGB(230, 40, 40)
local LOW_HEALTH_COLOR = Color3.fromRGB(110, 0, 0)
-- The health bar's fill at the top of a low-health pulse; dark enough for the white number.
local HEALTH_PULSE_COLOR = Color3.fromRGB(255, 96, 86)
local LEVEL_COLOR = Color3.fromRGB(255, 214, 90)
local DRANK_COLOR = Color3.fromRGB(110, 220, 120)
local NOTICE_COLOR = Color3.fromRGB(225, 225, 232)
local ANNOUNCEMENT_COLOR = Color3.fromRGB(255, 226, 140)
local CLUE_COLOR = Color3.fromRGB(90, 170, 255)
local MAP_COLOR = Color3.fromRGB(70, 90, 80)
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local PERK_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
}

type Bar = {
	root: Frame,
	fill: Frame,
	label: TextLabel,
}

type SkillSlot = {
	root: Frame,
	overlay: Frame,
	name: TextLabel,
	key: TextLabel,
	time: TextLabel,
}

type Pip = {
	root: Frame,
	fill: Frame,
}

type Arrow = {
	root: Frame,
	arrow: TextLabel,
	distance: TextLabel,
}

-- A notice line, the os.clock() it was shown at, how long it stays and its colour.
type Notice = {
	text: string,
	at: number,
	seconds: number,
	color: Color3,
}

-- What each announcement says.
local ANNOUNCEMENTS: { [string]: string } = {
	zoneOpened = "A zone has opened",
	zoneClosed = "A zone was lost to the flood",
	chestDrop = "A chest fell",
	wanderingBoss = "A boss is roaming",
	incursionWave = "An incursion wave begins",
	floodStarted = "The flood begins",
}

local function round(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function newFrame(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	transparency: number
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newLabel(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	textSize: number,
	font: Enum.Font
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = STROKE_TRANSPARENCY
	label.Text = ""
	label.Parent = parent
	return label
end

local function newBar(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	textSize: number
): Bar
	local root = newFrame(parent, name, size, position, TRACK_COLOR, TRACK_TRANSPARENCY)
	round(root, 6)
	local fill = newFrame(root, "Fill", UDim2.fromScale(1, 1), UDim2.new(), color, 0)
	round(fill, 6)
	local label = newLabel(root, "Label", UDim2.fromScale(1, 1), UDim2.new(), textSize, FONT_BOLD)
	return { root = root, fill = fill, label = label }
end

local function setBar(bar: Bar, fraction: number, text: string)
	bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	bar.label.Text = text
end

-- Fades a bar as a whole; 1 is as built, 0 is gone.
local function setBarAlpha(bar: Bar, alpha: number)
	bar.root.BackgroundTransparency = 1 - (1 - TRACK_TRANSPARENCY) * alpha
	bar.fill.BackgroundTransparency = 1 - alpha
	bar.label.TextTransparency = 1 - alpha
	bar.label.TextStrokeTransparency = 1 - (1 - STROKE_TRANSPARENCY) * alpha
end

-- Fades a label's text and stroke; 1 is as built.
local function setTextAlpha(label: TextLabel, alpha: number)
	label.TextTransparency = 1 - alpha
	label.TextStrokeTransparency = 1 - (1 - STROKE_TRANSPARENCY) * alpha
end

-- A vignette: four rims along the screen's edges, each opaque at the edge and
-- clear toward the centre; the corners, where two overlap, read darkest.
local function newVignette(parent: Instance, name: string, color: Color3): { Frame }
	local holder = newFrame(parent, name, UDim2.fromScale(1, 1), UDim2.new(), color, 1)
	local falloff = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	local edges: { Frame } = {}
	-- `rotation` turns the gradient so its opaque end lies on the screen's edge.
	local function addEdge(edgeName: string, size: UDim2, position: UDim2, rotation: number)
		local edge = newFrame(holder, edgeName, size, position, color, 1)
		edge.Visible = false
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = falloff
		gradient.Rotation = rotation
		gradient.Parent = edge
		table.insert(edges, edge)
	end
	addEdge("Left", UDim2.fromScale(VIGNETTE_SIDE_DEPTH, 1), UDim2.new(), 0)
	addEdge(
		"Right",
		UDim2.fromScale(VIGNETTE_SIDE_DEPTH, 1),
		UDim2.fromScale(1 - VIGNETTE_SIDE_DEPTH, 0),
		180
	)
	addEdge("Top", UDim2.fromScale(1, VIGNETTE_END_DEPTH), UDim2.new(), 90)
	addEdge(
		"Bottom",
		UDim2.fromScale(1, VIGNETTE_END_DEPTH),
		UDim2.fromScale(0, 1 - VIGNETTE_END_DEPTH),
		-90
	)
	return edges
end

-- Sets a vignette's opacity, 0 hiding it.
local function setVignette(edges: { Frame }, alpha: number)
	local clamped = math.clamp(alpha, 0, 1)
	for _, edge in edges do
		edge.Visible = clamped > 0
		edge.BackgroundTransparency = 1 - clamped
	end
end

-- Quick at first, slowing to the end; for t in [0, 1].
local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- "1.15" for 1.15, "1.5" for 1.50, "1" for 1.00.
local function trimNumber(value: number): string
	local text = string.format("%.2f", value)
	text = (string.gsub(text, "0+$", ""))
	text = (string.gsub(text, "%.$", ""))
	return text
end

-- What a perk changes, in a plain sentence: "Damage ×1.15" or "Max health +25".
local function describePerk(perk: Types.PerkConfig): string
	local label = PROPERTY_LABELS[perk.property] or perk.property
	local parts: { string } = {}
	if perk.mul then
		table.insert(parts, "×" .. trimNumber(perk.mul))
	end
	if perk.add then
		table.insert(parts, string.format("%+g", perk.add))
	end
	return label .. " " .. table.concat(parts, " ")
end

local started = false

-- Opens or closes the map screen (M, or the touch Map button).
function Hud.toggleMap()
	MapScreen.toggle()
end

function Hud.start()
	if started then
		return
	end
	started = true
	MapScreen.start()

	local player = Players.LocalPlayer
	local userId = player.UserId
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Everything sits in one root, scaled to the screen height so a phone and a
	-- PC both read well.
	local root = newFrame(gui, "Root", UDim2.fromScale(1, 1), UDim2.new(), WHITE, 1)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root

	-- Low health and the hurt flash: rims at the screen's edges, behind every panel.
	local lowHealthRim = newVignette(root, "LowHealth", LOW_HEALTH_COLOR)
	local hurtRim = newVignette(root, "HurtFlash", HURT_COLOR)

	-- Top left: health, potions, experience, kills.
	local stats = newFrame(
		root,
		"Stats",
		UDim2.fromOffset(280, 120),
		UDim2.fromOffset(16, 16),
		PANEL_COLOR,
		1
	)
	local healthBar =
		newBar(stats, "Health", UDim2.fromOffset(280, 28), UDim2.new(), HEALTH_COLOR, 18)
	-- An outline that pulses with low health.
	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = HURT_COLOR
	healthStroke.Thickness = 2
	healthStroke.Transparency = 1
	healthStroke.Parent = healthBar.root

	local potionRow = newFrame(
		stats,
		"Potions",
		UDim2.fromOffset(280, POTION_SLOT_SIZE),
		UDim2.fromOffset(0, 34),
		PANEL_COLOR,
		1
	)
	local potionSlots: { Frame } = {}
	local potionHint = newLabel(
		potionRow,
		"Hint",
		UDim2.fromOffset(20, POTION_SLOT_SIZE),
		UDim2.new(),
		14,
		FONT_BOLD
	)
	potionHint.Text = if touch then "" else "C"
	-- Placed after the potion hint by setPotionCapacity.
	local drinkBar = newBar(
		potionRow,
		"Drinking",
		UDim2.fromOffset(DRINK_BAR_WIDTH, POTION_SLOT_SIZE),
		UDim2.new(),
		POTION_COLOR,
		13
	)
	drinkBar.root.Visible = false
	local shownCapacity = 0

	local xpBar = newBar(
		stats,
		"Experience",
		UDim2.fromOffset(280, 22),
		UDim2.fromOffset(0, 62),
		XP_COLOR,
		15
	)
	local killsLabel =
		newLabel(stats, "Kills", UDim2.fromOffset(280, 22), UDim2.fromOffset(0, 90), 16, FONT)
	killsLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Right edge: the perks taken so far.
	local perkList =
		newLabel(root, "PerkList", UDim2.fromOffset(200, 0), UDim2.new(1, -16, 0, 16), 16, FONT)
	perkList.AnchorPoint = Vector2.new(1, 0)
	perkList.AutomaticSize = Enum.AutomaticSize.Y
	perkList.TextXAlignment = Enum.TextXAlignment.Right
	perkList.TextYAlignment = Enum.TextYAlignment.Top
	local shownPerkList = ""

	-- Top centre: run clock, flood note, banner.
	local clockLabel = newLabel(
		root,
		"Clock",
		UDim2.fromOffset(220, 36),
		UDim2.new(0.5, -110, 0, 12),
		30,
		FONT_BOLD
	)
	local floodLabel = newLabel(
		root,
		"FloodNote",
		UDim2.fromOffset(460, 22),
		UDim2.new(0.5, -230, 0, 48),
		16,
		FONT
	)
	-- Camp notices and announcements: short lines under the flood note, the newest last.
	local noticeLabels: { TextLabel } = {}
	for index = 1, MAX_NOTICES do
		local label = newLabel(
			root,
			"Notice" .. index,
			UDim2.fromOffset(460, NOTICE_STEP),
			UDim2.new(0.5, -230, 0, NOTICE_TOP + (index - 1) * NOTICE_STEP),
			16,
			FONT
		)
		label.TextColor3 = NOTICE_COLOR
		label.Visible = false
		noticeLabels[index] = label
	end
	local bannerLabel = newLabel(
		root,
		"Banner",
		UDim2.fromOffset(560, 48),
		UDim2.new(0.5, -280, 0, NOTICE_TOP + MAX_NOTICES * NOTICE_STEP),
		28,
		FONT_BOLD
	)
	bannerLabel.TextColor3 = EXTRACT_COLOR
	bannerLabel.Visible = false

	-- The zone compass: an arrow toward the nearest open zone on a ring around
	-- the screen centre, or "No zone yet" while none is open ("No zone left"
	-- once the flood has started).
	local compass =
		newFrame(root, "Compass", UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.5), PANEL_COLOR, 1)
	local function newArrow(): Arrow
		local frame =
			newFrame(compass, "Zone", UDim2.fromOffset(56, 48), UDim2.new(), PANEL_COLOR, 1)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		local arrow = newLabel(frame, "Arrow", UDim2.fromOffset(56, 28), UDim2.new(), 26, FONT_BOLD)
		arrow.Text = "▲"
		arrow.TextColor3 = EXTRACT_COLOR
		local distance = newLabel(
			frame,
			"Distance",
			UDim2.fromOffset(56, 18),
			UDim2.fromOffset(0, 28),
			14,
			FONT_BOLD
		)
		distance.TextColor3 = EXTRACT_COLOR
		return { root = frame, arrow = arrow, distance = distance }
	end
	local zoneArrow = newArrow()
	zoneArrow.root.Visible = false
	local noZoneLabel = newLabel(
		compass,
		"NoZone",
		UDim2.fromOffset(160, 22),
		UDim2.fromOffset(0, -COMPASS_RADIUS),
		16,
		FONT_BOLD
	)
	noZoneLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	noZoneLabel.Text = "No zone yet"
	noZoneLabel.TextColor3 = EXTRACT_COLOR
	noZoneLabel.TextTransparency = NO_ZONE_TRANSPARENCY
	noZoneLabel.Visible = false

	-- Extraction, reading a clue or opening a chest: one bar above the middle of the screen.
	local extractBar = newBar(
		root,
		"Extraction",
		UDim2.fromOffset(320, 28),
		UDim2.new(0.5, -160, 0.28, 0),
		EXTRACT_COLOR,
		16
	)
	extractBar.root.Visible = false

	-- Level-up: "Level N" in the upper middle, growing as it fades; below the
	-- banner, clear of its full growth, while the banner shows.
	local levelPopupPosition = UDim2.fromScale(0.5, 0.22)
	local levelPopup =
		newLabel(root, "LevelUp", UDim2.fromOffset(320, 56), levelPopupPosition, 40, FONT_BOLD)
	local levelPopupBelowBanner = UDim2.new(
		0.5,
		0,
		0,
		bannerLabel.Position.Y.Offset
			+ bannerLabel.Size.Y.Offset
			+ levelPopup.Size.Y.Offset * (1 + LEVEL_POPUP_GROWTH) / 2
	)
	levelPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	levelPopup.TextColor3 = LEVEL_COLOR
	levelPopup.Visible = false
	local levelPopupScale = Instance.new("UIScale")
	levelPopupScale.Parent = levelPopup

	-- Bottom centre: the three active skills, then the dash.
	local skillRow = newFrame(
		root,
		"Skills",
		UDim2.fromOffset(376, 60),
		UDim2.new(0.5, -188, 1, -76),
		PANEL_COLOR,
		1
	)
	local skillSlots: { SkillSlot } = {}
	for index = 1, MAX_SKILL_SLOTS do
		local slot = newFrame(
			skillRow,
			"Skill" .. index,
			UDim2.fromOffset(120, 60),
			UDim2.fromOffset((index - 1) * 128, 0),
			SKILL_COLOR,
			0.25
		)
		round(slot, 8)
		-- Drains from full to empty as the cooldown runs out.
		local overlay =
			newFrame(slot, "Cooldown", UDim2.fromScale(0, 1), UDim2.new(), PANEL_COLOR, 0.35)
		round(overlay, 8)
		local name =
			newLabel(slot, "Name", UDim2.new(1, -8, 0, 24), UDim2.fromOffset(4, 6), 17, FONT_BOLD)
		local key =
			newLabel(slot, "Key", UDim2.fromOffset(40, 20), UDim2.new(0, 6, 1, -24), 15, FONT_BOLD)
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Text = if touch then "" else (SKILL_KEYS[index] or "")
		local time = newLabel(
			slot,
			"Time",
			UDim2.fromOffset(60, 20),
			UDim2.new(1, -66, 1, -24),
			15,
			FONT_BOLD
		)
		time.TextXAlignment = Enum.TextXAlignment.Right
		skillSlots[index] = {
			root = slot,
			overlay = overlay,
			name = name,
			key = key,
			time = time,
		}
	end

	local dashPanel = newFrame(
		root,
		"Dash",
		UDim2.fromOffset(120, 60),
		UDim2.new(0.5, 194, 1, -76),
		PANEL_COLOR,
		0.25
	)
	round(dashPanel, 8)
	local pipRow =
		newFrame(dashPanel, "Pips", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 6), PANEL_COLOR, 1)
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 6)
	pipLayout.Parent = pipRow
	local pips: { Pip } = {}
	local dashKey =
		newLabel(dashPanel, "Key", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 1, -24), 15, FONT_BOLD)
	dashKey.Text = if touch then "Dash" else "Space"

	-- Touch: a cluster of large round buttons in the bottom-right corner, kept
	-- clear of the aim pad above it. Skills in the bottom row, dash, potion and
	-- hold above. Held, not tapped, for interact: revive and extraction take seconds.
	local skillButtons: { TextButton } = {}
	local dashButton: TextButton? = nil
	local potionButton: TextButton? = nil
	if touch then
		local function newButton(
			name: string,
			text: string,
			color: Color3,
			column: number,
			row: number
		): TextButton
			local button = Instance.new("TextButton")
			button.Name = name
			button.AnchorPoint = Vector2.new(1, 1)
			button.Position = UDim2.new(1, -16 - column * 84, 1, -16 - row * 84)
			button.Size = UDim2.fromOffset(76, 76)
			button.BackgroundColor3 = color
			button.BackgroundTransparency = 0.15
			button.BorderSizePixel = 0
			button.AutoButtonColor = true
			button.Font = FONT_BOLD
			button.TextSize = 15
			button.TextColor3 = WHITE
			button.TextStrokeTransparency = 0.6
			button.Text = text
			button.Parent = root
			round(button, 38)
			return button
		end

		for index = 1, MAX_SKILL_SLOTS do
			local button =
				newButton("SkillButton" .. index, "SKILL " .. index, SKILL_COLOR, index - 1, 0)
			button.Activated:Connect(function()
				Input.useSkill(index)
			end)
			skillButtons[index] = button
		end

		local dash = newButton("DashButton", "DASH", DASH_COLOR, 0, 1)
		dash.Activated:Connect(function()
			Input.dash()
		end)
		dashButton = dash

		local potion = newButton("PotionButton", "POTION", POTION_COLOR, 1, 1)
		potion.Activated:Connect(function()
			Input.drink()
		end)
		potionButton = potion

		local map = Instance.new("TextButton")
		map.Name = "MapButton"
		map.Position = UDim2.fromOffset(16, MAP_BUTTON_TOP)
		map.Size = UDim2.fromOffset(MAP_BUTTON_SIZE.X, MAP_BUTTON_SIZE.Y)
		map.BackgroundColor3 = MAP_COLOR
		map.BackgroundTransparency = 0.15
		map.BorderSizePixel = 0
		map.AutoButtonColor = true
		map.Font = FONT_BOLD
		map.TextSize = 15
		map.TextColor3 = WHITE
		map.TextStrokeTransparency = 0.6
		map.Text = "Map"
		map.Parent = root
		round(map, 10)
		map.Activated:Connect(function()
			Hud.toggleMap()
		end)

		local interact = newButton("InteractButton", "HOLD", EXTRACT_COLOR, 2, 1)
		interact.MouseButton1Down:Connect(function()
			Input.interact(true)
		end)
		interact.MouseButton1Up:Connect(function()
			Input.interact(false)
		end)
		interact.MouseLeave:Connect(function()
			Input.interact(false)
		end)
	end

	-- What holding interact would do here, if anything.
	local interactPrompt = newLabel(
		root,
		"InteractPrompt",
		UDim2.fromOffset(420, 26),
		UDim2.new(0.5, -210, 1, -112),
		20,
		FONT_BOLD
	)
	interactPrompt.Visible = false
	local holdWord = if touch then "Hold HOLD" else "Hold F"

	-- Perk choice: a row of buttons that leaves the middle and the corners free
	-- for movement.
	local perkPanel = newFrame(
		root,
		"Perks",
		UDim2.fromOffset(660, 170),
		UDim2.new(0.5, -330, 0.6, 0),
		PANEL_COLOR,
		1
	)
	local perkTitle =
		newLabel(perkPanel, "Title", UDim2.new(1, 0, 0, 30), UDim2.new(), 22, FONT_BOLD)
	perkTitle.Text = if touch then "Choose a perk" else "Choose a perk (1 / 2 / 3)"
	local perkRow =
		newFrame(perkPanel, "Row", UDim2.new(1, 0, 1, -36), UDim2.fromOffset(0, 36), PANEL_COLOR, 1)
	local perkLayout = Instance.new("UIListLayout")
	perkLayout.FillDirection = Enum.FillDirection.Horizontal
	perkLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	perkLayout.Padding = UDim.new(0, 10)
	perkLayout.Parent = perkRow
	perkPanel.Visible = false
	local shownOffer = ""

	-- Downed, dead and extracted overlay for the local player.
	local stateTint =
		newFrame(root, "StateTint", UDim2.fromScale(1, 1), UDim2.new(), BLEED_COLOR, 1)
	stateTint.Visible = false
	local statePanel = newFrame(
		stateTint,
		"Panel",
		UDim2.fromOffset(460, 160),
		UDim2.new(0.5, -230, 0.38, 0),
		PANEL_COLOR,
		STATE_PANEL_TRANSPARENCY
	)
	round(statePanel, 10)
	local stateTitle = newLabel(
		statePanel,
		"Title",
		UDim2.new(1, 0, 0, 44),
		UDim2.fromOffset(0, 10),
		26,
		FONT_BOLD
	)
	local stateText =
		newLabel(statePanel, "Text", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 54), 18, FONT)
	local bleedBar = newBar(
		statePanel,
		"Bleed",
		UDim2.fromOffset(400, 22),
		UDim2.new(0.5, -200, 0, 88),
		BLEED_COLOR,
		14
	)
	local reviveBar = newBar(
		statePanel,
		"Revive",
		UDim2.fromOffset(400, 22),
		UDim2.new(0.5, -200, 0, 118),
		REVIVE_COLOR,
		14
	)

	-- End-of-run summary.
	local summary = newFrame(
		root,
		"Summary",
		UDim2.fromOffset(380, 230),
		UDim2.new(0.5, -190, 0.5, -115),
		PANEL_COLOR,
		0.1
	)
	round(summary, 12)
	local summaryTitle =
		newLabel(summary, "Title", UDim2.new(1, 0, 0, 56), UDim2.fromOffset(0, 12), 36, FONT_BOLD)
	local summaryLines =
		newLabel(summary, "Lines", UDim2.new(1, 0, 0, 90), UDim2.fromOffset(0, 74), 22, FONT)
	local summaryHint =
		newLabel(summary, "Hint", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 184), 16, FONT)
	summaryHint.Text = "The next run starts shortly."
	summary.Visible = false

	-- What the HUD remembers between frames.
	local lastWorldTime = -1
	local bannerUntil = 0
	local hurtAt = -math.huge
	-- The hurt flash's opacity when it popped.
	local hurtStrength = 0
	-- How far into the low-health state the HUD is, 0 to 1, and the pulse's phase in turns.
	local lowLevel = 0
	local pulsePhase = 0
	-- os.clock() when the local player started drinking, by the event; nil when not.
	local drinkStartedAt: number? = nil
	-- The drink bar's last fill, and its flash when a drink lands or is interrupted.
	local drinkFraction = 0
	local drinkFlashAt = -math.huge
	local drinkFlashColor = DRANK_COLOR
	local drinkFlashText = ""
	local levelUpAt = -math.huge
	local notices: { Notice } = {}
	-- The local player's state on screen and when it began, for the fade-in.
	local shownState: Types.PlayerState = "alive"
	local stateAt = -math.huge
	local ended = false
	-- The run time when the local player extracted or died, and which.
	local finishedAt: number? = nil
	local outcome: "Extracted" | "Died" | nil = nil

	local function worldTime(): number
		local snapshot = Net.latest
		return if snapshot then snapshot.world.time else 0
	end

	local function showBanner(text: string, seconds: number)
		bannerLabel.Text = text
		bannerLabel.Visible = true
		bannerUntil = os.clock() + seconds
	end

	local function resetRun()
		ended = false
		finishedAt = nil
		outcome = nil
		summary.Visible = false
		bannerLabel.Visible = false
		bannerUntil = 0
		hurtAt = -math.huge
		hurtStrength = 0
		drinkStartedAt = nil
		drinkFlashAt = -math.huge
		levelUpAt = -math.huge
		table.clear(notices)
	end

	-- Adds a notice line, dropping the oldest beyond MAX_NOTICES; the same line
	-- again only refreshes the newest. Announcements stay longer, in their own colour.
	local function pushNotice(text: string, announcement: boolean?)
		local now = os.clock()
		local newest = notices[#notices]
		if newest and newest.text == text then
			newest.at = now
			return
		end
		table.insert(notices, {
			text = text,
			at = now,
			seconds = if announcement then ANNOUNCEMENT_SECONDS else NOTICE_SECONDS,
			color = if announcement then ANNOUNCEMENT_COLOR else NOTICE_COLOR,
		})
		while #notices > MAX_NOTICES do
			table.remove(notices, 1)
		end
	end

	local function hurtAlpha(now: number): number
		local t = (now - hurtAt) / HURT_FLASH_SECONDS
		return if t < 1 then hurtStrength * (1 - t) else 0
	end

	local function flashDrink(color: Color3, text: string)
		drinkStartedAt = nil
		drinkFlashAt = os.clock()
		drinkFlashColor = color
		drinkFlashText = text
	end

	-- Whether an enemy within `NOTICED_RANGE` of the local character went from
	-- idle to chase between the previous and the latest snapshot. The server
	-- sends a tick's snapshot before its events, so the latest one shows the
	-- camp that woke.
	local function nearbyEnemyWoke(): boolean
		local latest = Net.latest
		local previous = Net.previous
		local character = Players.LocalPlayer.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if latest == nil or previous == nil or ownRoot == nil or not ownRoot:IsA("BasePart") then
			return false
		end
		local here = ownRoot.Position
		local idle: { [number]: boolean } = {}
		for _, enemy in previous.enemies do
			if enemy.state == "idle" then
				idle[enemy.id] = true
			end
		end
		for _, enemy in latest.enemies do
			if enemy.state == "chase" and idle[enemy.id] then
				local dx, dz = enemy.x - here.X, enemy.z - here.Z
				if dx * dx + dz * dz <= NOTICED_RANGE * NOTICED_RANGE then
					return true
				end
			end
		end
		return false
	end

	-- Whether a clue just found stands near the local character. The server
	-- sends a tick's snapshot before its events, so the latest one holds the clue.
	local function clueNearby(clueId: number): boolean
		local latest = Net.latest
		local character = Players.LocalPlayer.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if latest == nil or ownRoot == nil or not ownRoot:IsA("BasePart") then
			return false
		end
		local here = ownRoot.Position
		for _, clue in latest.world.clues do
			if clue.id == clueId then
				local dx, dz = clue.x - here.X, clue.z - here.Z
				return dx * dx + dz * dz <= CLUE_NEARBY_RANGE * CLUE_NEARBY_RANGE
			end
		end
		return false
	end

	local function localView(snapshot: Net.Snapshot?): Protocol.PlayerView?
		if snapshot == nil then
			return nil
		end
		for _, view in snapshot.world.players do
			if view.id == userId then
				return view
			end
		end
		return nil
	end

	Net.onWorld(function(snapshot)
		-- The world time dropping means the next run has started.
		if snapshot.world.time < lastWorldTime then
			resetRun()
		end
		lastWorldTime = snapshot.world.time
		local view = localView(snapshot)
		if view and finishedAt == nil then
			if view.state == "dead" then
				finishedAt = snapshot.world.time
				outcome = "Died"
			elseif view.state == "extracted" then
				finishedAt = snapshot.world.time
				outcome = "Extracted"
			end
		end
	end)

	local function showSummary()
		local selfView = Net.self
		local view = localView(Net.latest)
		local result = outcome
		if result == nil then
			result = if view and view.state == "extracted" then "Extracted" else "Died"
		end
		summaryTitle.Text = if result == "Extracted" then "Extracted" else "You died"
		summaryTitle.TextColor3 = if result == "Extracted" then REVIVE_COLOR else HEALTH_COLOR
		summaryLines.Text = string.format(
			"Time survived: %s\nLevel: %d\nKills: %d",
			formatTime(finishedAt or worldTime()),
			if selfView then selfView.level else 1,
			if selfView then selfView.kills else 0
		)
		summary.Visible = true
	end

	Net.onEvents(function(events: { Types.Event })
		for _, event in events do
			if event.kind == "flood" then
				showBanner("The horde floods the map", BANNER_SECONDS)
			elseif event.kind == "campAlerted" then
				-- The event names no player; it is about the local one only when
				-- an enemy close by has just woken.
				if nearbyEnemyWoke() then
					pushNotice("A camp has noticed you")
				end
			elseif event.kind == "campReturned" then
				-- The client does not know where points are, so there is no "nearby" filter.
				pushNotice("A camp has returned")
			elseif event.kind == "announcement" then
				local text = ANNOUNCEMENTS[event.what]
				if text then
					pushNotice(text, true)
				end
			elseif event.kind == "clueFound" then
				-- The clue itself appears on the ground and the map screen once the
				-- world view carries it.
				if clueNearby(event.clueId) then
					pushNotice("A clue is nearby")
				end
			elseif event.kind == "clueRead" then
				pushNotice(
					string.format("A clue narrows the leader's area (%d left)", event.remaining),
					true
				)
			elseif event.kind == "chestOpened" and event.playerId == userId then
				pushNotice(
					if event.reward == "perk" then "Chest: a perk" else "Chest: potions",
					true
				)
			elseif event.kind == "levelUp" and event.player == userId then
				levelUpAt = os.clock()
				levelPopup.Text = "Level " .. event.level
			elseif event.kind == "playerHurt" and event.player == userId then
				-- Scaled by the hit's share of max health; a hit during a flash keeps the stronger.
				local now = os.clock()
				local view = localView(Net.latest)
				local share = if view and view.maxHealth > 0
					then event.amount / view.maxHealth
					else 0
				local strength =
					math.min(HURT_FLASH_MAX, HURT_FLASH_MIN + share * HURT_FLASH_PER_SHARE)
				hurtStrength = math.max(hurtAlpha(now), strength)
				hurtAt = now
			elseif event.kind == "drinking" and event.player == userId then
				drinkStartedAt = os.clock()
				drinkFlashAt = -math.huge
			elseif event.kind == "drank" and event.player == userId then
				drinkFraction = 1
				flashDrink(DRANK_COLOR, string.format("+%d", math.floor(event.amount + 0.5)))
			elseif event.kind == "drinkInterrupted" and event.player == userId then
				flashDrink(SKILL_COOLDOWN_COLOR, "Interrupted")
			elseif event.kind == "died" and event.player == userId then
				finishedAt = finishedAt or worldTime()
				outcome = "Died"
			elseif event.kind == "extracted" and event.player == userId then
				finishedAt = finishedAt or worldTime()
				outcome = "Extracted"
			elseif event.kind == "ended" then
				ended = true
				showSummary()
			end
		end
	end)

	-- Rebuilds the perk buttons when the offer changes.
	local function showOffer(offer: { string }?)
		local key = if offer then table.concat(offer, ",") else ""
		if key == shownOffer then
			return
		end
		shownOffer = key
		for _, child in perkRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		perkPanel.Visible = offer ~= nil
		if offer == nil then
			return
		end
		local taken = if Net.self then Net.self.perks else {}
		for index, id in offer do
			local perk = Config.perks.pool[id]
			local button = Instance.new("TextButton")
			button.Name = "Perk" .. index
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(204, 124)
			button.BackgroundColor3 = PANEL_COLOR
			button.BackgroundTransparency = 0.1
			button.BorderSizePixel = 0
			button.AutoButtonColor = true
			button.Font = FONT_BOLD
			button.TextSize = 18
			button.TextColor3 = WHITE
			button.TextWrapped = true
			local prefix = if touch then "" else index .. ". "
			if perk then
				button.Text = string.format(
					"%s%s\n%s\n(%d/%d)",
					prefix,
					perk.name,
					describePerk(perk),
					taken[id] or 0,
					perk.maxStacks
				)
			else
				button.Text = prefix .. id
			end
			button.Parent = perkRow
			round(button, 8)
			button.Activated:Connect(function()
				Net.choosePerk(index)
			end)
		end
	end

	-- Keys 1/2/3 choose a perk, except while typing in chat or another text box.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local index = PERK_KEYS[input.KeyCode]
		if index == nil or UserInputService:GetFocusedTextBox() then
			return
		end
		local selfView = Net.self
		if selfView and selfView.offer and index <= #selfView.offer then
			Net.choosePerk(index)
		end
	end)

	local function updateScale()
		local camera = workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else DESIGN_HEIGHT
		local scale = math.clamp(height / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
		uiScale.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	end
	updateScale()
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		updateScale()
	end)

	-- Builds or hides potion slots to match the capacity.
	local function setPotionCapacity(capacity: number)
		if capacity == shownCapacity then
			return
		end
		shownCapacity = capacity
		for index = #potionSlots + 1, capacity do
			local slot = newFrame(
				potionRow,
				"Slot" .. index,
				UDim2.fromOffset(POTION_SLOT_SIZE, POTION_SLOT_SIZE),
				UDim2.fromOffset((index - 1) * POTION_SLOT_STEP, 0),
				TRACK_COLOR,
				0.15
			)
			round(slot, 11)
			potionSlots[index] = slot
		end
		for index, slot in potionSlots do
			slot.Visible = index <= capacity
		end
		potionHint.Position = UDim2.fromOffset(capacity * POTION_SLOT_STEP + 2, 0)
		drinkBar.root.Position = UDim2.fromOffset(capacity * POTION_SLOT_STEP + DRINK_BAR_GAP, 0)
	end

	local function updatePotions(
		selfView: Protocol.SelfView?,
		view: Protocol.PlayerView?,
		now: number
	)
		local capacity = if selfView then selfView.potionCapacity else Config.player.potionCapacity
		local potions = if selfView then selfView.potions else 0
		setPotionCapacity(capacity)
		for index, slot in potionSlots do
			slot.BackgroundColor3 = if index <= potions then POTION_COLOR else TRACK_COLOR
		end
		-- Seconds of the drink left, from the snapshot or, until one shows it, the event.
		local snapshot = Net.latest
		local drinking = 0
		if view and snapshot and view.drinkingFor > 0 then
			drinking = math.max(0, view.drinkingFor - (now - snapshot.receivedAt))
		end
		local startedAt = drinkStartedAt
		if startedAt then
			local left = Config.player.drinkSeconds - (now - startedAt)
			if left > 0 then
				drinking = math.max(drinking, left)
			else
				drinkStartedAt = nil
			end
		end
		local sinceFlash = now - drinkFlashAt
		if sinceFlash < DRINK_FLASH_SECONDS then
			-- A landed or interrupted drink: the bar in green or grey, fading out.
			drinkBar.root.Visible = true
			drinkBar.fill.BackgroundColor3 = drinkFlashColor
			setBar(drinkBar, drinkFraction, drinkFlashText)
			setBarAlpha(drinkBar, 1 - sinceFlash / DRINK_FLASH_SECONDS)
		elseif drinking > 0 then
			drinkBar.root.Visible = true
			drinkBar.fill.BackgroundColor3 = POTION_COLOR
			drinkFraction = 1 - drinking / Config.player.drinkSeconds
			setBar(drinkBar, drinkFraction, "Drinking…")
			setBarAlpha(drinkBar, 1)
		else
			drinkBar.root.Visible = false
		end
		if potionButton then
			potionButton.BackgroundColor3 = if potions > 0
				then POTION_COLOR
				else SKILL_COOLDOWN_COLOR
			potionButton.Text = string.format("POTION\n%d", potions)
		end
	end

	local function updateSkills(selfView: Protocol.SelfView?, now: number)
		local elapsed = now - Net.selfAt
		local actives = Config.classes.elementalist.actives
		for index = 1, MAX_SKILL_SLOTS do
			local slot = skillSlots[index]
			local skill = if selfView then selfView.skills[index] else nil
			local remaining = 0
			local fraction = 0
			if skill then
				remaining = skill.readyIn - elapsed
				fraction = if skill.cooldown > 0
					then math.clamp(remaining / skill.cooldown, 0, 1)
					else 0
			end
			local cooling = remaining > 0
			slot.name.Text = if skill
				then skill.name
				else (actives[index] and actives[index].name or "")
			slot.root.BackgroundColor3 = if cooling then SKILL_COOLDOWN_COLOR else SKILL_COLOR
			slot.overlay.Size = UDim2.fromScale(if cooling then fraction else 0, 1)
			slot.time.Text = if cooling then string.format("%.1f", remaining) else ""
			local button = skillButtons[index]
			if button then
				button.BackgroundColor3 = if cooling then SKILL_COOLDOWN_COLOR else SKILL_COLOR
				button.Text = if cooling
					then string.format("%.1f", remaining)
					else "SKILL " .. index
			end
		end
	end

	local function updateDash(selfView: Protocol.SelfView?, now: number)
		local maxCharges = if selfView then selfView.dashMaxCharges else 0
		local charges = if selfView then selfView.dashCharges else 0
		for index = #pips + 1, maxCharges do
			local pip = newFrame(
				pipRow,
				"Pip" .. index,
				UDim2.fromOffset(24, 24),
				UDim2.new(),
				TRACK_COLOR,
				0.15
			)
			pip.LayoutOrder = index
			round(pip, 12)
			local fill =
				newFrame(pip, "Fill", UDim2.fromScale(1, 0), UDim2.fromScale(0, 1), DASH_COLOR, 0)
			fill.AnchorPoint = Vector2.new(0, 1)
			round(fill, 12)
			pips[index] = { root = pip, fill = fill }
		end
		local recharge = Config.classes.elementalist.dash.rechargeSeconds
		local rechargeLeft = if selfView then selfView.dashRechargeIn - (now - Net.selfAt) else 0
		for index, pip in pips do
			pip.root.Visible = index <= maxCharges
			if index <= charges then
				pip.fill.Size = UDim2.fromScale(1, 1)
			elseif index == charges + 1 and recharge > 0 then
				pip.fill.Size = UDim2.fromScale(1, math.clamp(1 - rechargeLeft / recharge, 0, 1))
			else
				pip.fill.Size = UDim2.fromScale(1, 0)
			end
		end
		if dashButton then
			dashButton.BackgroundColor3 = if charges > 0 then DASH_COLOR else SKILL_COOLDOWN_COLOR
			dashButton.Text = string.format("DASH\n%d", charges)
		end
	end

	-- The perks taken, one per line, sorted by name; the text is set only on a change.
	local function updatePerkList(selfView: Protocol.SelfView?)
		local entries: { string } = {}
		if selfView then
			for id, stacks in selfView.perks do
				local perk = Config.perks.pool[id]
				table.insert(
					entries,
					string.format("%s ×%d", if perk then perk.name else id, stacks)
				)
			end
			table.sort(entries)
		end
		local text = table.concat(entries, "\n")
		if text ~= shownPerkList then
			shownPerkList = text
			perkList.Text = text
		end
	end

	-- Points the arrow from the character toward the nearest open zone, hidden
	-- when that zone is already on screen; with none open, "No zone yet", or
	-- "No zone left" once the flood has started and every zone is closed.
	local function updateCompass(
		snapshot: Net.Snapshot?,
		view: Protocol.PlayerView?,
		ownRoot: BasePart?
	)
		local showing = snapshot ~= nil and view ~= nil and view.state == "alive" and ownRoot ~= nil
		local nearest: Types.Zone? = nil
		local nearestDistance = math.huge
		local dx, dz = 0, 0
		if snapshot and ownRoot then
			local here = ownRoot.Position
			for _, zone in snapshot.world.zones do
				if zone.open then
					local zx, zz = zone.x - here.X, zone.z - here.Z
					local distance = math.sqrt(zx * zx + zz * zz)
					if distance < nearestDistance then
						nearest = zone
						nearestDistance = distance
						dx, dz = zx, zz
					end
				end
			end
		end
		noZoneLabel.Visible = showing and nearest == nil
		if snapshot and nearest == nil then
			local map = Net.map
			local flooding = map ~= nil and snapshot.world.floodHalf < map.half
			noZoneLabel.Text = if flooding then "No zone left" else "No zone yet"
		end
		local visible = false
		if showing and nearest and nearestDistance > 0 then
			if nearestDistance - nearest.radius > COMPASS_HIDE_STUDS then
				visible = true
				zoneArrow.root.Position = UDim2.fromOffset(
					dx / nearestDistance * COMPASS_RADIUS,
					dz / nearestDistance * COMPASS_RADIUS
				)
				-- World +x is screen right and +z screen down; the arrow points up at 0.
				zoneArrow.arrow.Rotation = math.deg(math.atan2(dx, -dz))
				zoneArrow.distance.Text = tostring(math.floor(nearestDistance + 0.5))
			end
		end
		zoneArrow.root.Visible = visible
	end

	local function render(deltaTime: number)
		local now = os.clock()
		local snapshot = Net.latest
		local selfView = Net.self
		local view = localView(snapshot)

		-- Health, experience, kills.
		if view then
			setBar(
				healthBar,
				if view.maxHealth > 0 then view.health / view.maxHealth else 0,
				string.format(
					"%d / %d",
					math.ceil(math.max(0, view.health)),
					math.ceil(view.maxHealth)
				)
			)
		else
			setBar(healthBar, 0, "")
		end

		-- Low health: a dark rim and the health bar pulsing, faster when critical;
		-- the state eases in and out.
		local healthShare = if view and view.maxHealth > 0 then view.health / view.maxHealth else 1
		local alive = view ~= nil and view.state == "alive"
		local lowTarget = if alive and healthShare < LOW_HEALTH_SHARE then 1 else 0
		lowLevel += (lowTarget - lowLevel) * math.min(1, deltaTime * LOW_HEALTH_EASE)
		local critical = healthShare < CRITICAL_HEALTH_SHARE
		pulsePhase = (
			pulsePhase
			+ deltaTime / (if critical then CRITICAL_HEALTH_PERIOD else LOW_HEALTH_PERIOD)
		) % 1
		local wave = 0.5 - 0.5 * math.cos(pulsePhase * 2 * math.pi)
		local rimMin = if critical then CRITICAL_HEALTH_ALPHA_MIN else LOW_HEALTH_ALPHA_MIN
		local rimMax = if critical then CRITICAL_HEALTH_ALPHA_MAX else LOW_HEALTH_ALPHA_MAX
		setVignette(lowHealthRim, lowLevel * (rimMin + (rimMax - rimMin) * wave))
		healthBar.fill.BackgroundColor3 = HEALTH_COLOR:Lerp(HEALTH_PULSE_COLOR, lowLevel * wave)
		healthStroke.Transparency = 1 - lowLevel * wave
		healthBar.label.TextStrokeTransparency = STROKE_TRANSPARENCY
			+ (LOW_HEALTH_STROKE_TRANSPARENCY - STROKE_TRANSPARENCY) * lowLevel

		-- Hurt flash.
		setVignette(hurtRim, hurtAlpha(now))

		if selfView then
			setBar(
				xpBar,
				if selfView.xpToNext > 0 then selfView.xp / selfView.xpToNext else 0,
				string.format(
					"Level %d  -  %d / %d XP",
					selfView.level,
					selfView.xp,
					selfView.xpToNext
				)
			)
			killsLabel.Text = "Kills: " .. selfView.kills
		else
			setBar(xpBar, 0, "")
			killsLabel.Text = ""
		end
		-- Level-up: the experience bar flashes gold, and the popup grows and fades.
		local sinceLevel = now - levelUpAt
		local levelFlash = if sinceLevel < LEVEL_FLASH_SECONDS
			then 1 - sinceLevel / LEVEL_FLASH_SECONDS
			else 0
		xpBar.fill.BackgroundColor3 = XP_COLOR:Lerp(LEVEL_COLOR, levelFlash)
		xpBar.label.TextColor3 = WHITE:Lerp(LEVEL_COLOR, levelFlash)
		local popupAge = sinceLevel / LEVEL_POPUP_SECONDS
		levelPopup.Visible = popupAge < 1
		if popupAge < 1 then
			levelPopup.Position = if bannerLabel.Visible
				then levelPopupBelowBanner
				else levelPopupPosition
			levelPopupScale.Scale = 1 + LEVEL_POPUP_GROWTH * easeOut(popupAge)
			setTextAlpha(
				levelPopup,
				1 - math.clamp((popupAge - LEVEL_POPUP_HOLD) / (1 - LEVEL_POPUP_HOLD), 0, 1)
			)
		end

		updatePotions(selfView, view, now)
		updatePerkList(selfView)

		-- Run clock and flood note; the clock runs on between snapshots and
		-- freezes once the run has ended.
		local duration = if snapshot
			then snapshot.world.durationSeconds
			else Config.run.durationSeconds
		local runTime = 0
		if snapshot then
			runTime = snapshot.world.time
			if not ended then
				runTime = math.min(duration, runTime + (now - snapshot.receivedAt))
			end
		end
		clockLabel.Text = formatTime(runTime)
		-- Before the flood: when it begins; while it advances: when it meets
		-- at the centre, in red while the local character stands in it.
		local floodStart = Config.run.arc.flood.startMinute * 60
		-- The flood reaches the centre as the run ends.
		local floodEnd = duration
		local character = Players.LocalPlayer.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local ownPart = if ownRoot and ownRoot:IsA("BasePart") then ownRoot else nil
		local flooded = false
		if snapshot and ownPart and view and view.state == "alive" and runTime >= floodStart then
			local here = ownPart.Position
			flooded = math.max(math.abs(here.X), math.abs(here.Z)) > snapshot.world.floodHalf
		end
		if runTime < floodStart then
			floodLabel.Text = "flood in " .. formatTime(floodStart - runTime)
		elseif runTime < floodEnd then
			floodLabel.Text = (if flooded then "You are in the flood! " else "")
				.. "The flood meets in "
				.. formatTime(floodEnd - runTime)
		else
			floodLabel.Text = ""
		end
		floodLabel.TextColor3 = if flooded then HURT_COLOR else WHITE
		if bannerLabel.Visible and now >= bannerUntil then
			bannerLabel.Visible = false
		end

		-- Notices, fading out at the end of their time.
		for index = #notices, 1, -1 do
			if now - notices[index].at >= notices[index].seconds then
				table.remove(notices, index)
			end
		end
		for index, label in noticeLabels do
			local notice = notices[index]
			label.Visible = notice ~= nil
			if notice then
				label.Text = notice.text
				label.TextColor3 = notice.color
				local left = notice.seconds - (now - notice.at)
				setTextAlpha(label, math.clamp(left / NOTICE_FADE_SECONDS, 0, 1))
			end
		end

		-- Skills and dash, counted down locally between event batches.
		updateSkills(selfView, now)
		updateDash(selfView, now)

		-- Perk choice.
		-- Only a player still in the run can choose; the summary hides the panel.
		local choosing = view ~= nil
			and (view.state == "alive" or view.state == "downed")
			and not summary.Visible
		showOffer(if selfView and choosing then selfView.offer else nil)

		-- The interact prompt and the zone compass, from where the local character
		-- stands. What holding does, as the run decides it: extract in an open
		-- zone, else read a clue, else open a chest; reviving wins over all.
		local prompt: string? = nil
		if view and view.state == "alive" and snapshot and ownPart then
			local here = ownPart.Position
			local function near(x: number, z: number, radius: number): boolean
				local dx, dz = x - here.X, z - here.Z
				return dx * dx + dz * dz <= radius * radius
			end
			for _, zone in snapshot.world.zones do
				if zone.open and near(zone.x, zone.z, zone.radius) then
					prompt = holdWord .. " to extract"
				end
			end
			if prompt == nil then
				for _, clue in snapshot.world.clues do
					if not clue.read and near(clue.x, clue.z, Config.run.arc.clues.readRadius) then
						prompt = holdWord .. " to read the clue"
					end
				end
			end
			if prompt == nil then
				for _, chest in snapshot.world.chests do
					if
						not chest.opened
						and near(chest.x, chest.z, Config.run.arc.events.chest.openRadius)
					then
						prompt = holdWord .. " to open the chest"
					end
				end
			end
			for _, other in snapshot.world.players do
				local otherPlayer = if other.state == "downed"
					then Players:GetPlayerByUserId(other.id)
					else nil
				local otherCharacter = if otherPlayer then otherPlayer.Character else nil
				local otherRoot = if otherCharacter
					then otherCharacter:FindFirstChild("HumanoidRootPart")
					else nil
				if
					otherRoot
					and otherRoot:IsA("BasePart")
					-- On the ground plane, as the server measures it: hills tilt the line.
					and ((otherRoot.Position - here) * Vector3.new(1, 0, 1)).Magnitude
						<= Config.player.reviveRadius
				then
					prompt = holdWord .. " to revive"
				end
			end
		end
		interactPrompt.Visible = prompt ~= nil
		interactPrompt.Text = prompt or ""
		updateCompass(if summary.Visible then nil else snapshot, view, ownPart)

		-- Extracting, reading or opening: the one bar, whichever is held.
		local holding = false
		if view and view.state == "alive" then
			local arc = Config.run.arc
			if view.extractProgress > 0 then
				holding = true
				extractBar.fill.BackgroundColor3 = EXTRACT_COLOR
				setBar(
					extractBar,
					view.extractProgress / Config.run.extractSeconds,
					"Extracting..."
				)
			elseif view.clueProgress > 0 then
				holding = true
				extractBar.fill.BackgroundColor3 = CLUE_COLOR
				setBar(extractBar, view.clueProgress / arc.clues.readSeconds, "Reading...")
			elseif view.chestProgress > 0 then
				holding = true
				extractBar.fill.BackgroundColor3 = EXTRACT_COLOR
				setBar(extractBar, view.chestProgress / arc.events.chest.openSeconds, "Opening...")
			end
		end
		extractBar.root.Visible = holding

		-- Downed, dead, extracted: the tint and the panel fade in when the state begins.
		local state: Types.PlayerState = if view then view.state else "alive"
		if state ~= shownState then
			shownState = state
			stateAt = now
		end
		local fadeIn = easeOut(math.clamp((now - stateAt) / STATE_FADE_SECONDS, 0, 1))
		stateTint.Visible = state ~= "alive" and not summary.Visible
		statePanel.BackgroundTransparency = 1 - (1 - STATE_PANEL_TRANSPARENCY) * fadeIn
		setTextAlpha(stateTitle, fadeIn)
		setTextAlpha(stateText, fadeIn)
		setBarAlpha(bleedBar, fadeIn)
		setBarAlpha(reviveBar, fadeIn)
		bleedBar.root.Visible = false
		reviveBar.root.Visible = false
		if state == "downed" and view then
			stateTint.BackgroundTransparency = 1 - DOWNED_TINT_ALPHA * fadeIn
			stateTitle.Text = "Downed"
			stateText.Text = "Another player can revive you"
			bleedBar.root.Visible = true
			reviveBar.root.Visible = true
			setBar(bleedBar, 1 - view.downedFor / Config.player.downedSeconds, "Bleeding out")
			setBar(reviveBar, view.reviveProgress / Config.player.reviveSeconds, "Being revived")
		elseif state == "dead" then
			stateTint.BackgroundTransparency = 1 - DEAD_TINT_ALPHA * fadeIn
			stateTitle.Text = "You died"
			stateText.Text = "Spectating the rest of the run"
		elseif state == "extracted" then
			stateTint.BackgroundTransparency = 1
			stateTitle.Text = "Extracted"
			stateText.Text = "Waiting for the run to end"
		end
	end

	RunService.RenderStepped:Connect(render)
end

return Hud
