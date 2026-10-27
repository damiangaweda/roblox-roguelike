--!strict
-- The HUD of the solo run, built in code: the class pick screen; in the run
-- health with the barrier, level and experience, kills, the run clock and its
-- timers, banners and notices, the skill bar with ranks and cooldowns, the
-- three utility skills, the passives, the three-card level-up choice, the
-- chest compass, the chest, spell and portal prompts with their bars, the
-- touch buttons and the death and extraction overlay; then the summary. It
-- only shows state and sends intents through Net or Input (AGENTS.md rule 1);
-- every string it shows comes from Strings or Config.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Skills = require(ReplicatedStorage.Shared.Core.Skills)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Input = require(script.Parent.Input)
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
-- Level-up: the popup's life, how much it grows over it, the share of its life
-- before it starts to fade, and how long the experience bar flashes gold.
local LEVEL_POPUP_SECONDS = 1.2
local LEVEL_POPUP_GROWTH = 0.5
local LEVEL_POPUP_HOLD = 0.35
local LEVEL_FLASH_SECONDS = 0.6
-- Notices: how long a line stays, the fade at its end, and how many show at once.
local NOTICE_SECONDS = 2
local NOTICE_FADE_SECONDS = 0.5
local MAX_NOTICES = 3
-- The timer lines under the clock, the first notice line under them, and the step between lines.
local TIMER_TOP = 48
local NOTICE_TOP = 92
local NOTICE_STEP = 20
-- Dead and extracted screens fade in over this long, to this tint opacity.
local STATE_FADE_SECONDS = 0.6
local DEAD_TINT_ALPHA = 0.1
local STATE_PANEL_TRANSPARENCY = 0.3
-- The chest compass keeps this far inside the screen's edge, and hides while
-- the chest itself is this far inside it.
local COMPASS_MARGIN = 70
-- The pick screen's note shows when a pick has not moved the player on in this long.
local PICK_WAIT_SECONDS = 2
-- The world dims behind an offer to this opacity.
local OFFER_DIM_ALPHA = 0.55
-- The skill bar: tiles, their step, the gap before the utilities.
local MAX_SKILLS = Config.cards.maxSkills
local TILE_SIZE = 52
local TILE_STEP = 58
local UTILITY_GAP = 20
local PIP_GAP = 1
-- Up to this many capitals of a skill's name stand on its tile.
local MAX_INITIALS = 2
-- Touch buttons: size and step.
local BUTTON_SIZE = 76
local BUTTON_STEP = 84

-- Targeting kinds whose ranks 3, 5 and 7 add a target (ADR-0013).
local COUNTED: { [string]: boolean } = {
	bolt = true,
	strike = true,
	melee = true,
	chain = true,
	scatter = true,
	orbit = true,
}
-- Kinds whose damage lands per tick of an area or per shot of a totem.
local PER_TICK: { [string]: boolean } = {
	ground = true,
	groundSelf = true,
	totem = true,
}
-- Stats a passive raises by a flat amount rather than a share.
local FLAT_STATS: { [string]: boolean } = {
	regeneration = true,
	armour = true,
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL_COLOR = Color3.fromRGB(20, 22, 28)
local TRACK_COLOR = Color3.fromRGB(45, 48, 58)
local HEALTH_COLOR = Color3.fromRGB(214, 69, 65)
local BARRIER_COLOR = Color3.fromRGB(235, 240, 255)
local XP_COLOR = Color3.fromRGB(86, 156, 236)
local COOLDOWN_COLOR = Color3.fromRGB(110, 114, 126)
local UTILITY_COLOR = Color3.fromRGB(70, 150, 200)
local EXTRACT_COLOR = Color3.fromRGB(240, 196, 70)
local PORTAL_COLOR = Color3.fromRGB(170, 120, 255)
local PIP_EMPTY_COLOR = Color3.fromRGB(30, 32, 40)
local DEAD_COLOR = Color3.fromRGB(190, 60, 60)
local GOOD_COLOR = Color3.fromRGB(110, 210, 150)
local HURT_COLOR = Color3.fromRGB(230, 40, 40)
local LOW_HEALTH_COLOR = Color3.fromRGB(110, 0, 0)
-- The health bar's fill at the top of a low-health pulse; dark enough for the white number.
local HEALTH_PULSE_COLOR = Color3.fromRGB(255, 96, 86)
local LEVEL_COLOR = Color3.fromRGB(255, 214, 90)
local NOTICE_COLOR = Color3.fromRGB(225, 225, 232)
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

-- A skill tile's colour, by the skill's first tag.
local TAG_COLORS: { [string]: Color3 } = {
	fire = Color3.fromRGB(255, 136, 40),
	ice = Color3.fromRGB(140, 210, 255),
	lightning = Color3.fromRGB(255, 226, 60),
	arcane = Color3.fromRGB(160, 100, 240),
	physical = Color3.fromRGB(150, 160, 175),
	bleed = Color3.fromRGB(140, 20, 30),
	poison = Color3.fromRGB(110, 200, 50),
	nature = Color3.fromRGB(70, 160, 60),
}

-- A card's border, by how much it gives (stage 3: the colour changes nothing else).
local RARITY_COLORS = {
	common = Color3.fromRGB(235, 235, 240),
	uncommon = Color3.fromRGB(90, 200, 100),
	rare = Color3.fromRGB(70, 140, 240),
	epic = Color3.fromRGB(175, 90, 235),
	legendary = Color3.fromRGB(255, 150, 20),
}

-- The Strings tables read by a key known only at run time.
local TARGETING_TEXT = Strings.targeting :: { [string]: string }
local EFFECT_TEXT = Strings.effects :: { [string]: string }
local STAT_TEXT = Strings.stats :: { [string]: string }
local OUTCOME_TEXT = Strings.summary.outcomes :: { [string]: string }

type Bar = {
	root: Frame,
	fill: Frame,
	label: TextLabel,
}

-- A tile of the skill bar: a skill with its rank pips, or a utility skill.
type Tile = {
	root: Frame,
	sweep: Frame,
	text: TextLabel,
	time: TextLabel,
	pips: { Frame },
}

-- A notice line and the os.clock() it was shown at.
type Notice = {
	text: string,
	at: number,
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

local function newButton(parent: Instance, name: string, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = FONT_BOLD
	button.TextSize = 15
	button.TextColor3 = WHITE
	button.TextStrokeTransparency = STROKE_TRANSPARENCY
	button.Text = ""
	button.Parent = parent
	return button
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
	label.ZIndex = 2
	return { root = root, fill = fill, label = label }
end

local function setBar(bar: Bar, fraction: number, text: string)
	bar.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	bar.label.Text = text
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

-- 0xRRGGBB as a Color3.
local function hexColor(value: number): Color3
	return Color3.fromRGB(
		bit32.band(bit32.rshift(value, 16), 0xff),
		bit32.band(bit32.rshift(value, 8), 0xff),
		bit32.band(value, 0xff)
	)
end

-- The capitals that start the words of a name: "Rime Dart" is "RD", "Fan of
-- Arrows" is "FA".
local function initials(name: string): string
	local letters: { string } = {}
	for word in string.gmatch(name, "%S+") do
		local first = string.sub(word, 1, 1)
		if string.upper(first) == first and #letters < MAX_INITIALS then
			table.insert(letters, first)
		end
	end
	return if #letters > 0 then table.concat(letters) else string.upper(string.sub(name, 1, 2))
end

local function skillColor(skill: Types.SkillConfig?): Color3
	local tag = if skill then skill.tags[1] else nil
	return if tag then TAG_COLORS[tag] else COOLDOWN_COLOR
end

-- How much a card gives, for its border.
local function rarity(card: Types.Card): Color3
	if card.kind == "skillRank" then
		local skill = Config.skills[card.skill]
		if card.rank >= Config.ranks.maxRank then
			return RARITY_COLORS.legendary
		elseif
			skill
			and COUNTED[skill.targeting]
			and table.find(Config.ranks.extraTargetRanks, card.rank) ~= nil
		then
			return RARITY_COLORS.epic
		end
		return RARITY_COLORS.uncommon
	elseif card.kind == "newSkill" then
		return RARITY_COLORS.rare
	elseif card.kind == "newPassive" then
		return RARITY_COLORS.uncommon
	elseif card.kind == "passiveRank" then
		local passive = Config.passives[card.passive]
		if passive and card.rank >= passive.maxRank then
			return RARITY_COLORS.epic
		end
		return RARITY_COLORS.uncommon
	end
	return RARITY_COLORS.common
end

-- A skill card's lines: what it targets and its numbers at `rank`, after the
-- hero's stats, as the core computes them.
local function describeSkill(id: string, rank: number, stats: Types.HeroStats): string
	local skill = Config.skills[id]
	if skill == nil then
		return ""
	end
	local effective = Skills.effective(Config, skill, rank, stats)
	local targeting = effective.targeting
	local lines: { string } = { TARGETING_TEXT[targeting] or "" }
	if effective.toughest then
		table.insert(lines, Strings.skill.toughest)
	end
	local amount = math.round(effective.damage)
	if targeting == "shield" then
		table.insert(lines, string.format(Strings.skill.absorbs, amount))
	elseif targeting == "heal" then
		table.insert(lines, string.format(Strings.skill.heals, amount))
	elseif targeting == "thorns" then
		table.insert(lines, string.format(Strings.skill.reflects, amount))
	elseif PER_TICK[targeting] and effective.durationSeconds > 0 then
		table.insert(lines, string.format(Strings.skill.damagePerTick, amount))
	else
		table.insert(lines, string.format(Strings.skill.damage, amount))
	end
	if COUNTED[targeting] then
		local gained = rank > 1
			and Skills.extraTargets(Config, rank) > Skills.extraTargets(Config, rank - 1)
		if gained then
			table.insert(lines, Strings.skill.extraTarget)
		end
		-- A chain strikes its first target and then `count` more.
		local targets = effective.count + (if targeting == "chain" then 1 else 0)
		if targets > 1 then
			table.insert(lines, string.format(Strings.skill.targets, targets))
		end
	end
	if (targeting == "bolt" or targeting == "strike") and effective.radius > 0 then
		table.insert(lines, Strings.skill.splash)
	end
	table.insert(lines, string.format(Strings.skill.cooldown, effective.cooldownSeconds))
	local effect = effective.effect
	if effect then
		if effect.kind == "dot" then
			table.insert(lines, EFFECT_TEXT[effect.status or ""] or "")
		elseif effect.kind == "execute" then
			table.insert(
				lines,
				string.format(Strings.effects.execute, math.round((effect.factor or 0) * 100))
			)
		else
			table.insert(lines, EFFECT_TEXT[effect.kind] or "")
		end
	end
	return table.concat(lines, "\n")
end

-- A passive card's line: what one rank adds.
local function describePassive(id: string): string
	local passive = Config.passives[id]
	if passive == nil then
		return ""
	end
	local name = STAT_TEXT[passive.stat] or passive.stat
	if FLAT_STATS[passive.stat] then
		return string.format(Strings.passive.flat, trimNumber(passive.perRank), name)
	end
	return string.format(Strings.passive.percent, trimNumber(passive.perRank * 100), name)
end

-- A card's title, subtitle and description.
local function describeCard(card: Types.Card, stats: Types.HeroStats): (string, string, string)
	if card.kind == "skillRank" then
		local skill = Config.skills[card.skill]
		return if skill then skill.name else card.skill,
			string.format(Strings.cards.skillRank, card.rank),
			describeSkill(card.skill, card.rank, stats)
	elseif card.kind == "newSkill" then
		local skill = Config.skills[card.skill]
		return if skill then skill.name else card.skill,
			Strings.cards.newSkill,
			describeSkill(card.skill, 1, stats)
	elseif card.kind == "passiveRank" then
		local passive = Config.passives[card.passive]
		return if passive then passive.name else card.passive,
			string.format(Strings.cards.passiveRank, card.rank),
			describePassive(card.passive)
	elseif card.kind == "newPassive" then
		local passive = Config.passives[card.passive]
		return if passive then passive.name else card.passive,
			Strings.cards.newPassive,
			describePassive(card.passive)
	end
	return Strings.cards.heal,
		"",
		string.format(Strings.cards.healText, math.round(Config.cards.healShare * 100))
end

-- A stable key for an offer, so its buttons are rebuilt only when it changes.
local function offerKey(offer: { Types.Card }?): string
	if offer == nil then
		return ""
	end
	local parts: { string } = {}
	for _, card in offer do
		local id = (card :: any).skill or (card :: any).passive or ""
		local rank = (card :: any).rank or 0
		table.insert(parts, string.format("%s:%s:%d", card.kind, id, rank))
	end
	return table.concat(parts, ",")
end

-- Classes in the order of their names, for the pick screen.
local function sortedClasses(): { Types.ClassConfig }
	local classes: { Types.ClassConfig } = {}
	for _, class in Config.classes do
		table.insert(classes, class)
	end
	table.sort(classes, function(a, b)
		return a.name < b.name
	end)
	return classes
end

local started = false

function Hud.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local userId = player.UserId
	local touch = UserInputService.TouchEnabled

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

	-- The run's HUD, shown only in the run phase.
	local runLayer = newFrame(root, "Run", UDim2.fromScale(1, 1), UDim2.new(), WHITE, 1)
	runLayer.Visible = false

	-- Top left: health with the barrier, experience, kills.
	local stats =
		newFrame(runLayer, "Stats", UDim2.fromOffset(280, 90), UDim2.fromOffset(16, 16), WHITE, 1)
	local healthBar =
		newBar(stats, "Health", UDim2.fromOffset(280, 28), UDim2.new(), HEALTH_COLOR, 18)
	-- The barrier: a lighter segment after the health, or over its end when full.
	local barrierFill =
		newFrame(healthBar.root, "Barrier", UDim2.new(), UDim2.new(), BARRIER_COLOR, 0.25)
	round(barrierFill, 6)
	-- An outline that pulses with low health.
	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = HURT_COLOR
	healthStroke.Thickness = 2
	healthStroke.Transparency = 1
	healthStroke.Parent = healthBar.root
	local xpBar = newBar(
		stats,
		"Experience",
		UDim2.fromOffset(280, 22),
		UDim2.fromOffset(0, 34),
		XP_COLOR,
		15
	)
	local killsLabel =
		newLabel(stats, "Kills", UDim2.fromOffset(280, 22), UDim2.fromOffset(0, 62), 16, FONT)
	killsLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Right edge: the passives taken, with their ranks.
	local passiveList =
		newLabel(runLayer, "Passives", UDim2.fromOffset(200, 0), UDim2.new(1, -16, 0, 16), 16, FONT)
	passiveList.AnchorPoint = Vector2.new(1, 0)
	passiveList.AutomaticSize = Enum.AutomaticSize.Y
	passiveList.TextXAlignment = Enum.TextXAlignment.Right
	passiveList.TextYAlignment = Enum.TextYAlignment.Top
	local shownPassives = ""

	-- Top centre: the run clock, the final boss's and the portal's timers, the
	-- notices and the banner.
	local clockLabel = newLabel(
		runLayer,
		"Clock",
		UDim2.fromOffset(220, 36),
		UDim2.new(0.5, -110, 0, 12),
		30,
		FONT_BOLD
	)
	local bossTimerLabel = newLabel(
		runLayer,
		"FinalBossTimer",
		UDim2.fromOffset(460, 20),
		UDim2.new(0.5, -230, 0, TIMER_TOP),
		17,
		FONT_BOLD
	)
	bossTimerLabel.TextColor3 = HURT_COLOR
	local portalTimerLabel = newLabel(
		runLayer,
		"PortalTimer",
		UDim2.fromOffset(460, 20),
		UDim2.new(0.5, -230, 0, TIMER_TOP + 20),
		17,
		FONT_BOLD
	)
	portalTimerLabel.TextColor3 = PORTAL_COLOR
	local noticeLabels: { TextLabel } = {}
	for index = 1, MAX_NOTICES do
		local label = newLabel(
			runLayer,
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
		runLayer,
		"Banner",
		UDim2.fromOffset(640, 48),
		UDim2.new(0.5, -320, 0, NOTICE_TOP + MAX_NOTICES * NOTICE_STEP),
		28,
		FONT_BOLD
	)
	bannerLabel.TextColor3 = EXTRACT_COLOR
	bannerLabel.Visible = false

	-- The chest compass: an arrow near the screen's edge pointing at the chest,
	-- with the distance under it, hidden while the chest is on screen.
	local compass =
		newFrame(runLayer, "Compass", UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.5), WHITE, 1)
	local compassArrow = newFrame(compass, "Chest", UDim2.fromOffset(56, 48), UDim2.new(), WHITE, 1)
	compassArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	compassArrow.Visible = false
	local arrowLabel =
		newLabel(compassArrow, "Arrow", UDim2.fromOffset(56, 28), UDim2.new(), 26, FONT_BOLD)
	arrowLabel.Text = "▲"
	arrowLabel.TextColor3 = EXTRACT_COLOR
	local distanceLabel = newLabel(
		compassArrow,
		"Distance",
		UDim2.fromOffset(56, 18),
		UDim2.fromOffset(0, 28),
		14,
		FONT_BOLD
	)
	distanceLabel.TextColor3 = EXTRACT_COLOR

	-- Opening the chest or casting the spell: one bar above the middle of the screen.
	local actionBar = newBar(
		runLayer,
		"Action",
		UDim2.fromOffset(320, 28),
		UDim2.new(0.5, -160, 0.28, 0),
		EXTRACT_COLOR,
		16
	)
	actionBar.root.Visible = false

	-- Level-up: "Level N" in the upper middle, growing as it fades; below the
	-- banner, clear of its full growth, while the banner shows.
	local levelPopupPosition = UDim2.fromScale(0.5, 0.22)
	local levelPopup =
		newLabel(runLayer, "LevelUp", UDim2.fromOffset(320, 56), levelPopupPosition, 40, FONT_BOLD)
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

	-- Bottom centre: up to six skills, then the three utility skills.
	local utilityCount = #Config.utilities
	local skillsWidth = MAX_SKILLS * TILE_STEP - (TILE_STEP - TILE_SIZE)
	local barWidth = skillsWidth + UTILITY_GAP + utilityCount * TILE_STEP - (TILE_STEP - TILE_SIZE)
	local skillBar = newFrame(
		runLayer,
		"SkillBar",
		UDim2.fromOffset(barWidth, TILE_SIZE),
		UDim2.new(0.5, -barWidth / 2, 1, -TILE_SIZE - 16),
		WHITE,
		1
	)

	local function newTile(name: string, x: number, pipCount: number): Tile
		local tile = newFrame(
			skillBar,
			name,
			UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
			UDim2.fromOffset(x, 0),
			COOLDOWN_COLOR,
			0.1
		)
		round(tile, 8)
		-- Covers the tile from the bottom up while the cooldown runs, draining away.
		local sweep = newFrame(tile, "Cooldown", UDim2.new(), UDim2.fromScale(0, 1), BLACK, 0.45)
		sweep.AnchorPoint = Vector2.new(0, 1)
		round(sweep, 8)
		local text = newLabel(
			tile,
			"Text",
			UDim2.new(1, 0, 1, if pipCount > 0 then -10 else 0),
			UDim2.new(),
			18,
			FONT_BOLD
		)
		text.ZIndex = 2
		local time =
			newLabel(tile, "Time", UDim2.new(1, -4, 0, 16), UDim2.new(0, 2, 1, -18), 14, FONT_BOLD)
		time.ZIndex = 2
		local pips: { Frame } = {}
		if pipCount > 0 then
			local pipSize = math.floor((TILE_SIZE - 4 - (pipCount - 1) * PIP_GAP) / pipCount)
			local left = (TILE_SIZE - pipCount * pipSize - (pipCount - 1) * PIP_GAP) / 2
			for index = 1, pipCount do
				local pip = newFrame(
					tile,
					"Pip" .. index,
					UDim2.fromOffset(pipSize, pipSize),
					UDim2.new(0, left + (index - 1) * (pipSize + PIP_GAP), 1, -pipSize - 3),
					PIP_EMPTY_COLOR,
					0
				)
				pip.ZIndex = 2
				pips[index] = pip
			end
		end
		return { root = tile, sweep = sweep, text = text, time = time, pips = pips }
	end

	local skillTiles: { Tile } = {}
	for index = 1, MAX_SKILLS do
		local tile = newTile("Skill" .. index, (index - 1) * TILE_STEP, Config.ranks.maxRank)
		tile.root.Visible = false
		skillTiles[index] = tile
	end
	local utilityTiles: { Tile } = {}
	for index, utility in Config.utilities do
		local tile =
			newTile("Utility" .. index, skillsWidth + UTILITY_GAP + (index - 1) * TILE_STEP, 0)
		-- The name between the key above and the cooldown below.
		tile.text.Size = UDim2.new(1, -4, 0, 18)
		tile.text.Position = UDim2.fromOffset(2, 16)
		tile.text.TextSize = 12
		tile.text.Text = utility.name
		tile.text.TextWrapped = true
		local key = newLabel(
			tile.root,
			"Key",
			UDim2.fromOffset(16, 16),
			UDim2.fromOffset(4, 2),
			13,
			FONT_BOLD
		)
		key.ZIndex = 2
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Text = if touch then "" else (Strings.keys.utilities[index] or "")
		utilityTiles[index] = tile
	end

	-- What the interact or cast key would do here, if anything.
	local prompt = newLabel(
		runLayer,
		"Prompt",
		UDim2.fromOffset(520, 26),
		UDim2.new(0.5, -260, 1, -TILE_SIZE - 52),
		20,
		FONT_BOLD
	)
	prompt.TextColor3 = EXTRACT_COLOR
	prompt.Visible = false
	local interactName = if touch then Strings.buttons.interact else Strings.keys.interact
	local castName = if touch then Strings.buttons.cast else Strings.keys.cast

	-- Touch: large round buttons in the bottom-right corner: the utility skills
	-- in the bottom row, interact and cast above. Interact is held: opening the
	-- chest takes a moment.
	local utilityButtons: { TextButton } = {}
	if touch then
		local function cornerButton(
			name: string,
			text: string,
			color: Color3,
			column: number,
			row: number
		): TextButton
			local button =
				newButton(runLayer, name, UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE), color)
			button.AnchorPoint = Vector2.new(1, 1)
			button.Position = UDim2.new(1, -16 - column * BUTTON_STEP, 1, -16 - row * BUTTON_STEP)
			button.Text = text
			round(button, BUTTON_SIZE / 2)
			return button
		end

		for index, utility in Config.utilities do
			local button = cornerButton(
				"UtilityButton" .. index,
				utility.name,
				UTILITY_COLOR,
				utilityCount - index,
				0
			)
			button.Activated:Connect(function()
				Input.useUtility(index)
			end)
			utilityButtons[index] = button
		end

		local interact =
			cornerButton("InteractButton", Strings.buttons.interact, EXTRACT_COLOR, 1, 1)
		interact.MouseButton1Down:Connect(function()
			Input.interact(true)
		end)
		interact.MouseButton1Up:Connect(function()
			Input.interact(false)
		end)
		interact.MouseLeave:Connect(function()
			Input.interact(false)
		end)

		local cast = cornerButton("CastButton", Strings.buttons.cast, PORTAL_COLOR, 0, 1)
		cast.Activated:Connect(function()
			Input.cast()
		end)
	end

	-- Dead and extracted overlay for the local player.
	local stateTint =
		newFrame(runLayer, "StateTint", UDim2.fromScale(1, 1), UDim2.new(), DEAD_COLOR, 1)
	stateTint.Visible = false
	local statePanel = newFrame(
		stateTint,
		"Panel",
		UDim2.fromOffset(460, 110),
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
		newLabel(statePanel, "Text", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 58), 18, FONT)

	-- The level-up choice: the world dims and three cards stand in the middle.
	-- The run is paused while it is up.
	local offerLayer =
		newFrame(root, "Offer", UDim2.fromScale(1, 1), UDim2.new(), BLACK, 1 - OFFER_DIM_ALPHA)
	offerLayer.Visible = false
	local offerTitle = newLabel(
		offerLayer,
		"Title",
		UDim2.fromOffset(600, 40),
		UDim2.new(0.5, -300, 0.5, -190),
		28,
		FONT_BOLD
	)
	offerTitle.Text = Strings.cards.title
	offerTitle.TextColor3 = LEVEL_COLOR
	local cardRow = newFrame(
		offerLayer,
		"Cards",
		UDim2.fromOffset(720, 250),
		UDim2.new(0.5, -360, 0.5, -135),
		WHITE,
		1
	)
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Horizontal
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Padding = UDim.new(0, 16)
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Parent = cardRow
	local shownOffer = ""

	-- The pick screen: the title and one card per class.
	local pickLayer = newFrame(root, "Pick", UDim2.fromScale(1, 1), UDim2.new(), PANEL_COLOR, 0.15)
	local pickTitle = newLabel(
		pickLayer,
		"Title",
		UDim2.fromOffset(600, 50),
		UDim2.new(0.5, -300, 0.5, -230),
		36,
		FONT_BOLD
	)
	pickTitle.Text = Strings.pick.title
	local pickRow = newFrame(
		pickLayer,
		"Classes",
		UDim2.fromOffset(780, 280),
		UDim2.new(0.5, -390, 0.5, -160),
		WHITE,
		1
	)
	local pickLayout = Instance.new("UIListLayout")
	pickLayout.FillDirection = Enum.FillDirection.Horizontal
	pickLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pickLayout.Padding = UDim.new(0, 20)
	pickLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickLayout.Parent = pickRow
	local pickNote = newLabel(
		pickLayer,
		"Waiting",
		UDim2.fromOffset(600, 30),
		UDim2.new(0.5, -300, 0.5, 140),
		20,
		FONT_BOLD
	)
	pickNote.Text = Strings.pick.waiting
	pickNote.TextColor3 = EXTRACT_COLOR
	pickNote.Visible = false
	-- os.clock() of the last pick still waiting for the run to start.
	local pickedAt: number? = nil

	for order, class in sortedClasses() do
		local colour = hexColor(class.colour)
		local button = newButton(pickRow, class.id, UDim2.fromOffset(240, 270), PANEL_COLOR)
		button.LayoutOrder = order
		round(button, 10)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = colour
		stroke.Thickness = 3
		stroke.Parent = button
		local name =
			newLabel(button, "Name", UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 18), 30, FONT_BOLD)
		name.Text = class.name
		name.TextColor3 = colour
		local start = Config.skills[class.startSkill]
		local lines =
			newLabel(button, "Lines", UDim2.new(1, -24, 0, 180), UDim2.fromOffset(12, 74), 17, FONT)
		lines.TextWrapped = true
		lines.TextYAlignment = Enum.TextYAlignment.Top
		local synergies = class.synergies
		lines.Text = table.concat({
			string.format(Strings.pick.startSkill, if start then start.name else class.startSkill),
			string.format(Strings.pick.stats, class.maxHealth, class.walkSpeed),
			string.format(
				Strings.pick.synergies,
				if synergies[1] then synergies[1].name else "",
				if synergies[2] then synergies[2].name else ""
			),
		}, "\n\n")
		local classId = class.id
		button.Activated:Connect(function()
			pickedAt = os.clock()
			Net.pickClass(classId)
		end)
	end

	-- End-of-run summary.
	local summary = newFrame(
		root,
		"Summary",
		UDim2.fromOffset(400, 290),
		UDim2.new(0.5, -200, 0.5, -145),
		PANEL_COLOR,
		0.1
	)
	round(summary, 12)
	local summaryTitle =
		newLabel(summary, "Title", UDim2.new(1, 0, 0, 56), UDim2.fromOffset(0, 12), 34, FONT_BOLD)
	local summaryLines =
		newLabel(summary, "Lines", UDim2.new(1, 0, 0, 150), UDim2.fromOffset(0, 74), 21, FONT)
	local summaryNext =
		newLabel(summary, "Next", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 240), 17, FONT)
	summary.Visible = false

	-- What the HUD remembers between frames.
	local phaseAt = os.clock()
	local bannerUntil = 0
	local hurtAt = -math.huge
	-- The hurt flash's opacity when it popped.
	local hurtStrength = 0
	-- How far into the low-health state the HUD is, 0 to 1, and the pulse's phase in turns.
	local lowLevel = 0
	local pulsePhase = 0
	local levelUpAt = -math.huge
	local notices: { Notice } = {}
	-- The local player's state on screen and when it began, for the fade-in.
	local shownState: Types.PlayerState = "alive"
	local stateAt = -math.huge

	local function showBanner(text: string)
		bannerLabel.Text = text
		bannerLabel.Visible = true
		bannerUntil = os.clock() + BANNER_SECONDS
	end

	local function resetRun()
		bannerLabel.Visible = false
		bannerUntil = 0
		hurtAt = -math.huge
		hurtStrength = 0
		lowLevel = 0
		levelUpAt = -math.huge
		shownState = "alive"
		table.clear(notices)
	end

	-- Adds a notice line, dropping the oldest beyond MAX_NOTICES; the same line
	-- again only refreshes the newest.
	local function pushNotice(text: string)
		local now = os.clock()
		local newest = notices[#notices]
		if newest and newest.text == text then
			newest.at = now
			return
		end
		table.insert(notices, { text = text, at = now })
		while #notices > MAX_NOTICES do
			table.remove(notices, 1)
		end
	end

	local function hurtAlpha(now: number): number
		local t = (now - hurtAt) / HURT_FLASH_SECONDS
		return if t < 1 then hurtStrength * (1 - t) else 0
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

	-- A boss's name, from the latest snapshot's enemy with that id.
	local function bossName(enemyId: number): string
		local latest = Net.latest
		if latest then
			for _, enemy in latest.enemies do
				if enemy.id == enemyId then
					local kind = Config.enemies[enemy.kind]
					if kind then
						return kind.name
					end
				end
			end
		end
		return Strings.banners.someBoss
	end

	Net.onPhase(function(phase)
		phaseAt = os.clock()
		pickedAt = nil
		if phase == "run" then
			resetRun()
		end
	end)

	Net.onEvents(function(events: { Types.Event })
		for _, event in events do
			if event.kind == "bossSpawned" then
				local kind = Config.enemies[event.enemyKind]
				local name = if kind then kind.name else Strings.banners.someBoss
				showBanner(
					string.format(
						if event.final
							then Strings.banners.finalBossAwakens
							else Strings.banners.bossApproaches,
						name
					)
				)
			elseif event.kind == "closingRing" then
				showBanner(Strings.banners.closingRing)
			elseif event.kind == "bossPhase" then
				showBanner(string.format(Strings.banners.bossEnraged, bossName(event.enemyId)))
			elseif event.kind == "finalBossTimer" then
				showBanner(string.format(Strings.banners.finalBossTimer, math.ceil(event.seconds)))
			elseif event.kind == "compass" then
				showBanner(Strings.banners.compass)
			elseif event.kind == "chestOpened" and event.player == userId then
				showBanner(Strings.banners.chestOpened)
			elseif event.kind == "portalOpened" then
				showBanner(Strings.banners.portalOpened)
			elseif event.kind == "castInterrupted" and event.player == userId then
				pushNotice(Strings.notices.interrupted)
			elseif event.kind == "levelUp" and event.player == userId then
				levelUpAt = os.clock()
				levelPopup.Text = string.format(Strings.levelUp, event.level)
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
			end
		end
	end)

	-- Rebuilds the card buttons when the offer changes.
	local function showOffer(offer: { Types.Card }?, heroStats: Types.HeroStats?)
		local key = offerKey(offer)
		offerLayer.Visible = offer ~= nil
		if key == shownOffer then
			return
		end
		shownOffer = key
		for _, child in cardRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		if offer == nil or heroStats == nil then
			return
		end
		for index, card in offer do
			local title, subtitle, description = describeCard(card, heroStats)
			local colour = rarity(card)
			local button =
				newButton(cardRow, "Card" .. index, UDim2.fromOffset(220, 250), PANEL_COLOR)
			button.LayoutOrder = index
			button.BackgroundTransparency = 0.05
			round(button, 10)
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = colour
			stroke.Thickness = 3
			stroke.Parent = button
			if not touch then
				local hint = newLabel(
					button,
					"Key",
					UDim2.fromOffset(24, 24),
					UDim2.fromOffset(8, 6),
					16,
					FONT_BOLD
				)
				hint.Text = Strings.keys.utilities[index] or ""
				hint.TextColor3 = colour
			end
			local titleLabel = newLabel(
				button,
				"Title",
				UDim2.new(1, -20, 0, 50),
				UDim2.fromOffset(10, 26),
				20,
				FONT_BOLD
			)
			titleLabel.TextWrapped = true
			titleLabel.Text = title
			local subtitleLabel = newLabel(
				button,
				"Subtitle",
				UDim2.new(1, -20, 0, 20),
				UDim2.fromOffset(10, 78),
				15,
				FONT_BOLD
			)
			subtitleLabel.Text = subtitle
			subtitleLabel.TextColor3 = colour
			local descriptionLabel = newLabel(
				button,
				"Description",
				UDim2.new(1, -20, 0, 140),
				UDim2.fromOffset(10, 104),
				14,
				FONT
			)
			descriptionLabel.TextWrapped = true
			descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
			descriptionLabel.Text = description
			button.Activated:Connect(function()
				Net.chooseCard(index)
			end)
		end
	end

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

	-- Seconds of a cooldown left now: the event batch's count, run down since
	-- it came, except while the run stands still.
	local function cooldownLeft(readyIn: number, elapsed: number): number
		return math.max(0, readyIn - elapsed)
	end

	local function updateSkillBar(selfView: Protocol.SelfView?, elapsed: number)
		local owned = if selfView then selfView.skills else {}
		for index, tile in skillTiles do
			local skillView = owned[index]
			tile.root.Visible = skillView ~= nil
			if skillView then
				local skill = Config.skills[skillView.id]
				tile.root.BackgroundColor3 = skillColor(skill)
				tile.text.Text = initials(if skill then skill.name else skillView.id)
				local left = cooldownLeft(skillView.readyIn, elapsed)
				local fraction = if skillView.cooldown > 0
					then math.clamp(left / skillView.cooldown, 0, 1)
					else 0
				tile.sweep.Size = UDim2.fromScale(1, fraction)
				for rank, pip in tile.pips do
					pip.BackgroundColor3 = if rank <= skillView.rank then WHITE else PIP_EMPTY_COLOR
				end
			end
		end
		local utilities = if selfView then selfView.utilities else {}
		for index, tile in utilityTiles do
			local utilityView = utilities[index]
			local left = if utilityView then cooldownLeft(utilityView.readyIn, elapsed) else 0
			local fraction = if utilityView and utilityView.cooldown > 0
				then math.clamp(left / utilityView.cooldown, 0, 1)
				else 0
			local cooling = left > 0
			tile.root.BackgroundColor3 = if cooling then COOLDOWN_COLOR else UTILITY_COLOR
			tile.sweep.Size = UDim2.fromScale(1, fraction)
			tile.time.Text = if cooling then string.format("%.1f", left) else ""
			local button = utilityButtons[index]
			if button then
				local utility = Config.utilities[index]
				button.BackgroundColor3 = if cooling then COOLDOWN_COLOR else UTILITY_COLOR
				button.Text = if cooling
					then string.format("%.1f", left)
					else (if utility then utility.name else "")
			end
		end
	end

	-- The passives taken, one per line, sorted by name; the text is set only on a change.
	local function updatePassives(selfView: Protocol.SelfView?)
		local entries: { string } = {}
		if selfView then
			for id, rank in selfView.passives do
				local passive = Config.passives[id]
				table.insert(
					entries,
					string.format(
						Strings.passiveLine,
						if passive then passive.name else id,
						rank,
						if passive then passive.maxRank else rank
					)
				)
			end
			table.sort(entries)
		end
		local text = table.concat(entries, "\n")
		if text ~= shownPassives then
			shownPassives = text
			passiveList.Text = text
		end
	end

	-- Points the arrow from the screen's centre toward the chest, near the
	-- screen's edge, hidden while the chest itself is well on screen.
	local function updateCompass(chest: Protocol.ChestView?, here: Vector3?)
		local camera = workspace.CurrentCamera
		if chest == nil or here == nil or camera == nil then
			compassArrow.Visible = false
			return
		end
		local scale = uiScale.Scale
		local viewport = camera.ViewportSize
		local point, onScreen =
			camera:WorldToViewportPoint(Vector3.new(chest.x, Net.groundY(), chest.z))
		local margin = COMPASS_MARGIN * scale
		if
			onScreen
			and point.X > margin
			and point.X < viewport.X - margin
			and point.Y > margin
			and point.Y < viewport.Y - margin
		then
			compassArrow.Visible = false
			return
		end
		local dx, dz = chest.x - here.X, chest.z - here.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance <= 0 then
			compassArrow.Visible = false
			return
		end
		-- World +x is screen right and +z screen down, as the camera looks.
		local ux, uy = dx / distance, dz / distance
		local halfX = viewport.X / scale / 2 - COMPASS_MARGIN
		local halfY = viewport.Y / scale / 2 - COMPASS_MARGIN
		local reach = math.min(
			if math.abs(ux) > 1e-6 then halfX / math.abs(ux) else math.huge,
			if math.abs(uy) > 1e-6 then halfY / math.abs(uy) else math.huge
		)
		compassArrow.Visible = true
		compassArrow.Position = UDim2.fromOffset(ux * reach, uy * reach)
		-- The arrow points up at 0.
		arrowLabel.Rotation = math.deg(math.atan2(dx, -dz))
		distanceLabel.Text = string.format(Strings.compassDistance, math.floor(distance + 0.5))
	end

	local function renderPick(now: number)
		local waiting = pickedAt
		pickNote.Visible = waiting ~= nil and now - waiting >= PICK_WAIT_SECONDS
	end

	local function renderSummary(now: number)
		local result = Net.summary
		if result == nil then
			summaryTitle.Text = ""
			summaryLines.Text = ""
			summaryNext.Text = ""
			return
		end
		summaryTitle.Text = OUTCOME_TEXT[result.reason] or ""
		summaryTitle.TextColor3 = if result.extracted or result.reason == "finalBossKilled"
			then GOOD_COLOR
			else HEALTH_COLOR
		local class = Config.classes[result.class]
		summaryLines.Text = table.concat({
			string.format(Strings.summary.class, if class then class.name else result.class),
			string.format(Strings.summary.time, formatTime(result.time)),
			string.format(Strings.summary.level, result.level),
			string.format(Strings.summary.kills, result.kills),
			string.format(Strings.summary.damage, math.round(result.damageDone)),
		}, "\n")
		summaryNext.Text = string.format(
			Strings.summary.nextIn,
			math.max(0, math.ceil(result.nextIn - (now - phaseAt)))
		)
	end

	local function renderRun(now: number, deltaTime: number)
		local snapshot = Net.latest
		local selfView = Net.self
		local view = localView(snapshot)
		local world = if snapshot then snapshot.world else nil
		-- Seconds since the snapshot, which the clock and timers run on; none
		-- while the run stands still or has ended.
		local sinceSnapshot = if snapshot
				and world
				and not world.paused
				and not world.ended
			then now - snapshot.receivedAt
			else 0
		local sinceSelf = if world and (world.paused or world.ended) then 0 else now - Net.selfAt

		-- Health with the barrier, experience, kills.
		if view then
			local maxHealth = math.max(view.maxHealth, 1)
			local healthShare = math.clamp(view.health / maxHealth, 0, 1)
			local barrierShare = math.clamp(view.barrier / maxHealth, 0, 1)
			setBar(
				healthBar,
				healthShare,
				if view.barrier > 0
					then string.format(
						Strings.healthWithBarrier,
						math.ceil(math.max(0, view.health)),
						math.ceil(view.maxHealth),
						math.ceil(view.barrier)
					)
					else string.format(
						Strings.health,
						math.ceil(math.max(0, view.health)),
						math.ceil(view.maxHealth)
					)
			)
			barrierFill.Visible = barrierShare > 0
			barrierFill.Position = UDim2.fromScale(math.min(healthShare, 1 - barrierShare), 0)
			barrierFill.Size = UDim2.fromScale(barrierShare, 1)
		else
			setBar(healthBar, 0, "")
			barrierFill.Visible = false
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
					Strings.experience,
					selfView.level,
					math.floor(selfView.xp),
					math.floor(selfView.xpToNext)
				)
			)
			killsLabel.Text = string.format(Strings.kills, selfView.kills)
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

		updatePassives(selfView)
		updateSkillBar(selfView, sinceSelf)

		-- The run clock and the timers under it, run on between snapshots.
		clockLabel.Text = formatTime(if world then world.time + sinceSnapshot else 0)
		local bossLeft = if world then world.finalBossLeft else nil
		bossTimerLabel.Visible = bossLeft ~= nil
		if bossLeft then
			bossTimerLabel.Text =
				string.format(Strings.mapClosesIn, formatTime(bossLeft - sinceSnapshot))
		end
		local portal = if world then world.portal else nil
		portalTimerLabel.Visible = portal ~= nil
		if portal then
			portalTimerLabel.Text = string.format(
				Strings.portalClosesIn,
				math.max(0, math.ceil(portal.secondsLeft - sinceSnapshot))
			)
		end
		if bannerLabel.Visible and now >= bannerUntil then
			bannerLabel.Visible = false
		end

		-- Notices, fading out at the end of their time.
		for index = #notices, 1, -1 do
			if now - notices[index].at >= NOTICE_SECONDS then
				table.remove(notices, index)
			end
		end
		for index, label in noticeLabels do
			local notice = notices[index]
			label.Visible = notice ~= nil
			if notice then
				label.Text = notice.text
				local left = NOTICE_SECONDS - (now - notice.at)
				setTextAlpha(label, math.clamp(left / NOTICE_FADE_SECONDS, 0, 1))
			end
		end

		-- The prompt, the action bar and the compass, from where the local
		-- character stands. The portal wins over the chest, the chest over the spell.
		local character = player.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local here: Vector3? = if ownRoot and ownRoot:IsA("BasePart")
			then ownRoot.Position
			elseif view then Vector3.new(view.x, Net.groundY(), view.z)
			else nil
		local extraction = Config.extraction
		local promptText: string? = nil
		local barShown = false
		if alive and world and view and here then
			local function near(x: number, z: number, radius: number): boolean
				local dx, dz = x - here.X, z - here.Z
				return dx * dx + dz * dz <= radius * radius
			end
			local chest = world.chest
			if portal and near(portal.x, portal.z, extraction.portalRadius) then
				promptText = string.format(Strings.prompts.portal, interactName)
			elseif not chest.opened and near(chest.x, chest.z, extraction.openRadius) then
				promptText = string.format(Strings.prompts.open, interactName)
			elseif selfView and selfView.hasSpell and portal == nil and view.castingLeft <= 0 then
				promptText = string.format(Strings.prompts.cast, castName)
			end
			if view.castingLeft > 0 then
				barShown = true
				local left = math.max(0, view.castingLeft - sinceSnapshot)
				actionBar.fill.BackgroundColor3 = PORTAL_COLOR
				setBar(actionBar, 1 - left / extraction.castSeconds, Strings.bars.casting)
			elseif view.openProgress > 0 and not chest.opened then
				barShown = true
				actionBar.fill.BackgroundColor3 = EXTRACT_COLOR
				setBar(actionBar, view.openProgress / extraction.openSeconds, Strings.bars.opening)
			end
		end
		prompt.Visible = promptText ~= nil
		prompt.Text = promptText or ""
		actionBar.root.Visible = barShown
		local compassChest = if alive
				and world
				and world.compassOn
				and not world.chest.opened
			then world.chest
			else nil
		updateCompass(compassChest, here)

		-- The level-up choice, while the local player is alive with an offer waiting.
		local offer = if alive and selfView then selfView.offer else nil
		showOffer(offer, if selfView then selfView.stats else nil)

		-- Dead, extracted: the tint and the panel fade in when the state begins.
		local state: Types.PlayerState = if view then view.state else "alive"
		if state ~= shownState then
			shownState = state
			stateAt = now
		end
		local fadeIn = easeOut(math.clamp((now - stateAt) / STATE_FADE_SECONDS, 0, 1))
		stateTint.Visible = state ~= "alive"
		statePanel.BackgroundTransparency = 1 - (1 - STATE_PANEL_TRANSPARENCY) * fadeIn
		setTextAlpha(stateTitle, fadeIn)
		setTextAlpha(stateText, fadeIn)
		if state == "dead" then
			stateTint.BackgroundTransparency = 1 - DEAD_TINT_ALPHA * fadeIn
			stateTitle.Text = Strings.state.deadTitle
			stateText.Text = Strings.state.deadText
		elseif state == "extracted" then
			stateTint.BackgroundTransparency = 1
			stateTitle.Text = Strings.state.extractedTitle
			stateText.Text = Strings.state.extractedText
		end
	end

	local function render(deltaTime: number)
		local now = os.clock()
		local phase = Net.phase
		pickLayer.Visible = phase == "pick"
		runLayer.Visible = phase == "run"
		summary.Visible = phase == "summary"
		if phase == "run" then
			renderRun(now, deltaTime)
		else
			setVignette(lowHealthRim, 0)
			setVignette(hurtRim, 0)
			showOffer(nil, nil)
			if phase == "pick" then
				renderPick(now)
			else
				renderSummary(now)
			end
		end
	end

	RunService.RenderStepped:Connect(render)
end

return Hud
