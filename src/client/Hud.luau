--!strict
-- The HUD of the solo run, built in code (stage 3b's layout): the class pick
-- screen; in the run the experience bar across the top with the level and
-- kills, the run clock and its timers, banners and notices under it, health
-- with the barrier and the dash charges at the bottom centre above the skill
-- bar with ranks and cooldowns and the three utility skills, the passives,
-- boons and pacts on the right, the three-card level-up choice and the great
-- offer, the chest compass, the chest, shrine, spell and portal prompts with
-- their bars, the touch buttons and the death and extraction overlay; then the
-- summary. The top-left corner stays clear for the chat. Skills, passives and
-- utilities show their icon from Config.icons, or their initials without one.
-- It only shows state and sends intents through Net or Input (AGENTS.md rule
-- 1); every string it shows comes from Strings or Config.

local GuiService = game:GetService("GuiService")
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
-- Under the experience bar: the clock, the timer lines under it, the first
-- notice line under them, and the step between lines.
local CLOCK_TOP = 2
local TIMER_TOP = 38
local NOTICE_TOP = 82
local NOTICE_STEP = 20
-- The experience bar: its height and the margin it keeps from the screen's
-- edges (or the topbar's buttons) and the narrowest it gets.
local XP_HEIGHT = 20
local TOP_MARGIN = 12
local MIN_XP_WIDTH = 160
-- Health above the skill bar: its height and the gap to the tiles; the dash
-- charges beside it: each pip's width and the gap between them.
local HEALTH_HEIGHT = 24
local VITALS_GAP = 6
local DASH_PIP_WIDTH = 10
local DASH_PIP_GAP = 4
-- Cards and class cards: the icon's side and the card's size.
local CARD_ICON = 96
local CARD_WIDTH = 220
local CARD_HEIGHT = 300
local CLASS_ICON = 64
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
-- An icon's inset on a tile.
local ICON_INSET = 4
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
-- A great offer's title and frame.
local GREAT_COLOR = Color3.fromRGB(255, 176, 30)
local DASH_COLOR = Color3.fromRGB(120, 220, 255)
-- A shrine's colour, by kind: its prompt's name and its hold bar.
local SHRINE_COLORS: { [string]: Color3 } = {
	boon = Color3.fromRGB(255, 200, 60),
	pact = Color3.fromRGB(200, 30, 50),
	trial = Color3.fromRGB(150, 80, 240),
	spring = Color3.fromRGB(70, 220, 240),
}
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
local SHRINE_TEXT = Strings.shrines :: { [string]: string }

type Bar = {
	root: Frame,
	fill: Frame,
	label: TextLabel,
}

-- A tile of the skill bar: a skill with its rank pips, or a utility skill.
-- `icon` shows the skill's icon when it has one, `text` its initials otherwise.
type Tile = {
	root: Frame,
	icon: ImageLabel,
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

-- The icon of a skill, passive, utility or class by id, or nil without one.
local function iconOf(id: string?): string?
	local icons = (Config :: any).icons
	if id == nil or type(icons) ~= "table" then
		return nil
	end
	local image = icons[id]
	return if type(image) == "string" and image ~= "" then image else nil
end

-- "+15% damage", "-3 armour": a shrine's change to `stat` by `amount`, a
-- share or, for FLAT_STATS, a flat number.
local function statChange(stat: string, amount: number, up: boolean): string
	local name = STAT_TEXT[stat] or stat
	local details = Strings.shrineDetails
	if FLAT_STATS[stat] then
		return string.format(
			if up then details.flatUp else details.flatDown,
			trimNumber(amount),
			name
		)
	end
	return string.format(
		if up then details.percentUp else details.percentDown,
		trimNumber(amount * 100),
		name
	)
end

-- A boon's or pact's name by id, from Config.shrines, and what it gives:
-- a boon's gain, a pact's gain and cost.
local function boonOrPactName(id: string): (string, string)
	for _, boon in Config.shrines.boons do
		if boon.id == id then
			return boon.name, statChange(boon.stat, boon.amount, true)
		end
	end
	for _, pact in Config.shrines.pacts do
		if pact.id == id then
			return pact.name,
				string.format(
					Strings.shrineDetails.pact,
					statChange(pact.up, pact.upAmount, true),
					statChange(pact.down, pact.downAmount, false)
				)
		end
	end
	return id, ""
end

-- A square face `side` wide: the icon of `id` when it has one, else the
-- initials of `name` on a tile of `color`.
local function newFace(
	parent: Instance,
	side: number,
	position: UDim2,
	id: string?,
	name: string,
	color: Color3
): GuiObject
	local image = iconOf(id)
	if image then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.fromOffset(side, side)
		icon.Position = position
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = parent
		return icon
	end
	local tile = newFrame(parent, "Icon", UDim2.fromOffset(side, side), position, color, 0.1)
	round(tile, math.floor(side / 6))
	local letters = newLabel(
		tile,
		"Initials",
		UDim2.fromScale(1, 1),
		UDim2.new(),
		math.floor(side * 0.4),
		FONT_BOLD
	)
	letters.Text = initials(name)
	return tile
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

-- How many ranks a card adds to what the player holds: one at a level-up,
-- more in a great offer; none for the heal.
local function ranksGained(card: Types.Card, selfView: Protocol.SelfView): number
	if card.kind == "skillRank" then
		for _, owned in selfView.skills do
			if owned.id == card.skill then
				return card.rank - owned.rank
			end
		end
		return 1
	elseif card.kind == "newSkill" or card.kind == "newPassive" then
		return card.rank or 1
	elseif card.kind == "passiveRank" then
		return card.rank - (selfView.passives[card.passive] or 0)
	end
	return 0
end

-- A card's title, subtitle and description; `gained` is ranksGained's.
local function describeCard(
	card: Types.Card,
	stats: Types.HeroStats,
	gained: number
): (string, string, string)
	if card.kind == "skillRank" then
		local skill = Config.skills[card.skill]
		return if skill then skill.name else card.skill,
			if gained > 1
				then string.format(Strings.cards.skillRanks, card.rank, gained)
				else string.format(Strings.cards.skillRank, card.rank),
			describeSkill(card.skill, card.rank, stats)
	elseif card.kind == "newSkill" then
		local skill = Config.skills[card.skill]
		local rank = card.rank or 1
		return if skill then skill.name else card.skill,
			if rank > 1
				then string.format(Strings.cards.newSkillRank, rank)
				else Strings.cards.newSkill,
			describeSkill(card.skill, rank, stats)
	elseif card.kind == "passiveRank" then
		local passive = Config.passives[card.passive]
		return if passive then passive.name else card.passive,
			if gained > 1
				then string.format(Strings.cards.passiveRanks, card.rank, gained)
				else string.format(Strings.cards.passiveRank, card.rank),
			describePassive(card.passive)
	elseif card.kind == "newPassive" then
		local passive = Config.passives[card.passive]
		local rank = card.rank or 1
		return if passive then passive.name else card.passive,
			if rank > 1
				then string.format(Strings.cards.newPassiveRank, rank)
				else Strings.cards.newPassive,
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

	-- Top: the experience bar across the screen, in the topbar's free row when
	-- there is one, with the level at its left, the experience in the middle
	-- and the kills at its right; everything else at the top hangs under it.
	local xpBar = newBar(
		runLayer,
		"Experience",
		UDim2.fromOffset(MIN_XP_WIDTH, XP_HEIGHT),
		UDim2.fromOffset(TOP_MARGIN, TOP_MARGIN),
		XP_COLOR,
		15
	)
	xpBar.label.TextXAlignment = Enum.TextXAlignment.Left
	xpBar.label.Size = UDim2.new(1, -16, 1, 0)
	xpBar.label.Position = UDim2.fromOffset(8, 0)
	local xpAmount =
		newLabel(xpBar.root, "Amount", UDim2.fromScale(1, 1), UDim2.new(), 14, FONT_BOLD)
	xpAmount.ZIndex = 2
	local killsLabel = newLabel(
		xpBar.root,
		"Kills",
		UDim2.new(1, -16, 1, 0),
		UDim2.fromOffset(8, 0),
		15,
		FONT_BOLD
	)
	killsLabel.ZIndex = 2
	killsLabel.TextXAlignment = Enum.TextXAlignment.Right
	local topLayer = newFrame(runLayer, "Top", UDim2.fromScale(1, 1), UDim2.new(), WHITE, 1)

	-- Bottom centre: health with the barrier as wide as the skill bar, right
	-- above it, and the dash charges beside it.
	local utilityCount = #Config.utilities
	local skillsWidth = MAX_SKILLS * TILE_STEP - (TILE_STEP - TILE_SIZE)
	local barWidth = skillsWidth + UTILITY_GAP + utilityCount * TILE_STEP - (TILE_STEP - TILE_SIZE)
	local vitalsTop = -TILE_SIZE - 16 - VITALS_GAP - HEALTH_HEIGHT
	local healthBar = newBar(
		runLayer,
		"Health",
		UDim2.fromOffset(barWidth, HEALTH_HEIGHT),
		UDim2.new(0.5, -barWidth / 2, 1, vitalsTop),
		HEALTH_COLOR,
		17
	)
	local dashCount = math.max(0, Config.player.dashCharges)
	local dashPips: { Bar } = {}
	for index = 1, dashCount do
		local pip = newBar(
			runLayer,
			"Dash" .. index,
			UDim2.fromOffset(DASH_PIP_WIDTH, HEALTH_HEIGHT),
			UDim2.new(
				0.5,
				barWidth / 2 + DASH_PIP_GAP + (index - 1) * (DASH_PIP_WIDTH + DASH_PIP_GAP),
				1,
				vitalsTop
			),
			DASH_COLOR,
			1
		)
		-- Fills from the bottom up as the charge comes back.
		pip.fill.AnchorPoint = Vector2.new(0, 1)
		pip.fill.Position = UDim2.fromScale(0, 1)
		dashPips[index] = pip
	end
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

	-- Right edge: the passives taken, with their ranks, then the boons and pacts.
	local passiveList =
		newLabel(topLayer, "Passives", UDim2.fromOffset(200, 0), UDim2.new(1, -16, 0, 8), 16, FONT)
	passiveList.AnchorPoint = Vector2.new(1, 0)
	passiveList.AutomaticSize = Enum.AutomaticSize.Y
	passiveList.TextXAlignment = Enum.TextXAlignment.Right
	passiveList.TextYAlignment = Enum.TextYAlignment.Top
	local shownPassives = ""

	-- Top centre: the run clock, the final boss's and the portal's timers, the
	-- notices and the banner.
	local clockLabel = newLabel(
		topLayer,
		"Clock",
		UDim2.fromOffset(220, 36),
		UDim2.new(0.5, -110, 0, CLOCK_TOP),
		30,
		FONT_BOLD
	)
	local bossTimerLabel = newLabel(
		topLayer,
		"FinalBossTimer",
		UDim2.fromOffset(460, 20),
		UDim2.new(0.5, -230, 0, TIMER_TOP),
		17,
		FONT_BOLD
	)
	bossTimerLabel.TextColor3 = HURT_COLOR
	local portalTimerLabel = newLabel(
		topLayer,
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
			topLayer,
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
		topLayer,
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
		newLabel(topLayer, "LevelUp", UDim2.fromOffset(320, 56), levelPopupPosition, 40, FONT_BOLD)
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
		-- The icon, above the rank pips; hidden while the skill has none.
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size =
			UDim2.new(1, -2 * ICON_INSET, 1, -2 * ICON_INSET - (if pipCount > 0 then 8 else 0))
		icon.Position = UDim2.fromOffset(ICON_INSET, ICON_INSET)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Visible = false
		icon.Parent = tile
		-- Covers the tile from the bottom up while the cooldown runs, draining away.
		local sweep = newFrame(tile, "Cooldown", UDim2.new(), UDim2.fromScale(0, 1), BLACK, 0.45)
		sweep.AnchorPoint = Vector2.new(0, 1)
		sweep.ZIndex = 2
		round(sweep, 8)
		local text = newLabel(
			tile,
			"Text",
			UDim2.new(1, 0, 1, if pipCount > 0 then -10 else 0),
			UDim2.new(),
			18,
			FONT_BOLD
		)
		text.ZIndex = 3
		local time =
			newLabel(tile, "Time", UDim2.new(1, -4, 0, 16), UDim2.new(0, 2, 1, -18), 14, FONT_BOLD)
		time.ZIndex = 3
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
				pip.ZIndex = 3
				pips[index] = pip
			end
		end
		return { root = tile, icon = icon, sweep = sweep, text = text, time = time, pips = pips }
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
		-- With an icon the name gives way to it.
		local image = iconOf(utility.id)
		if image then
			tile.icon.Image = image
			tile.icon.Visible = true
			tile.text.Visible = false
		end
		local key = newLabel(
			tile.root,
			"Key",
			UDim2.fromOffset(16, 16),
			UDim2.fromOffset(4, 2),
			13,
			FONT_BOLD
		)
		key.ZIndex = 3
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Text = if touch then "" else (Strings.keys.utilities[index] or "")
		utilityTiles[index] = tile
	end

	-- What the interact key would do here, if anything, above the health bar;
	-- a shrine in reach is named above it, over a line of what it does.
	local prompt = newLabel(
		runLayer,
		"Prompt",
		UDim2.fromOffset(520, 26),
		UDim2.new(0.5, -260, 1, vitalsTop - 8 - 26),
		20,
		FONT_BOLD
	)
	prompt.TextColor3 = EXTRACT_COLOR
	prompt.Visible = false
	local shrineLabel = newLabel(
		runLayer,
		"Shrine",
		UDim2.fromOffset(520, 28),
		UDim2.new(0.5, -260, 1, vitalsTop - 8 - 26 - 22 - 28),
		22,
		FONT_BOLD
	)
	shrineLabel.Visible = false
	local shrineDetail = newLabel(
		runLayer,
		"ShrineDetail",
		UDim2.fromOffset(640, 22),
		UDim2.new(0.5, -320, 1, vitalsTop - 8 - 26 - 22),
		16,
		FONT
	)
	shrineDetail.Visible = false
	local interactName = if touch then Strings.buttons.interact else Strings.keys.interact

	-- Touch: large round buttons in the bottom-right corner: the utility skills
	-- in the bottom row, interact and dash above. Interact is held: opening the
	-- chest or activating a shrine takes a moment; elsewhere it casts the spell.
	local utilityButtons: { TextButton } = {}
	local dashButton: TextButton? = nil
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
			cornerButton("InteractButton", Strings.buttons.interact, EXTRACT_COLOR, 0, 1)
		interact.MouseButton1Down:Connect(function()
			Input.interact(true)
		end)
		interact.MouseButton1Up:Connect(function()
			Input.interact(false)
		end)
		interact.MouseLeave:Connect(function()
			Input.interact(false)
		end)

		local dash = cornerButton("DashButton", Strings.buttons.dash, DASH_COLOR, 1, 1)
		dash.Activated:Connect(function()
			Input.dash()
		end)
		dashButton = dash
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
		UDim2.new(0.5, -300, 0.5, -CARD_HEIGHT / 2 - 56),
		28,
		FONT_BOLD
	)
	offerTitle.Text = Strings.cards.title
	offerTitle.TextColor3 = LEVEL_COLOR
	-- A great offer stands in a gold frame.
	local greatFrame = newFrame(
		offerLayer,
		"GreatFrame",
		UDim2.fromOffset(720 + 24, CARD_HEIGHT + 24),
		UDim2.new(0.5, -372, 0.5, -CARD_HEIGHT / 2 - 12),
		GREAT_COLOR,
		0.85
	)
	round(greatFrame, 14)
	local greatStroke = Instance.new("UIStroke")
	greatStroke.Color = GREAT_COLOR
	greatStroke.Thickness = 3
	greatStroke.Parent = greatFrame
	greatFrame.Visible = false
	local cardRow = newFrame(
		offerLayer,
		"Cards",
		UDim2.fromOffset(720, CARD_HEIGHT),
		UDim2.new(0.5, -360, 0.5, -CARD_HEIGHT / 2),
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
	-- A trial was won by the local player: the next offer to show is its great offer.
	local greatPending = false

	-- The pick screen: the title and one card per class.
	local pickLayer = newFrame(root, "Pick", UDim2.fromScale(1, 1), UDim2.new(), PANEL_COLOR, 0.15)
	local pickTitle = newLabel(
		pickLayer,
		"Title",
		UDim2.fromOffset(600, 50),
		UDim2.new(0.5, -300, 0.5, -240),
		36,
		FONT_BOLD
	)
	pickTitle.Text = Strings.pick.title
	local pickRow = newFrame(
		pickLayer,
		"Classes",
		UDim2.fromOffset(780, 310),
		UDim2.new(0.5, -390, 0.5, -175),
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
		UDim2.new(0.5, -300, 0.5, 150),
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
		local button = newButton(pickRow, class.id, UDim2.fromOffset(240, 300), PANEL_COLOR)
		button.LayoutOrder = order
		round(button, 10)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = colour
		stroke.Thickness = 3
		stroke.Parent = button
		newFace(
			button,
			CLASS_ICON,
			UDim2.new(0.5, -CLASS_ICON / 2, 0, 14),
			if iconOf(class.id) then class.id else class.startSkill,
			class.name,
			colour
		)
		local name =
			newLabel(button, "Name", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 82), 30, FONT_BOLD)
		name.Text = class.name
		name.TextColor3 = colour
		local start = Config.skills[class.startSkill]
		local lines = newLabel(
			button,
			"Lines",
			UDim2.new(1, -24, 0, 168),
			UDim2.fromOffset(12, 126),
			17,
			FONT
		)
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
		greatPending = false
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
			elseif event.kind == "shrineActivated" and event.player == userId then
				local given = event.given
				if type(given) == "string" then
					local name, gain = boonOrPactName(given)
					pushNotice(string.format(Strings.notices.given, name, gain))
				elseif event.shrineKind == "spring" then
					pushNotice(Strings.notices.springUsed)
				end
			elseif event.kind == "trialStarted" then
				pushNotice(Strings.notices.trialStarted)
			elseif event.kind == "trialCompleted" then
				pushNotice(Strings.notices.trialCompleted)
				if event.player == userId then
					greatPending = true
				end
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

	-- Rebuilds the card buttons when the offer changes. A great offer (the
	-- one after a trial the local player won, or any card worth more than one
	-- rank) gets its own title and a gold frame.
	local function showOffer(offer: { Types.Card }?, selfView: Protocol.SelfView?)
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
		if offer == nil or selfView == nil then
			return
		end
		local heroStats = selfView.stats
		local gains: { number } = {}
		local great = greatPending
		greatPending = false
		for index, card in offer do
			gains[index] = ranksGained(card, selfView)
			if gains[index] > 1 then
				great = true
			end
		end
		offerTitle.Text = if great then Strings.cards.greatTitle else Strings.cards.title
		offerTitle.TextColor3 = if great then GREAT_COLOR else LEVEL_COLOR
		offerTitle.TextSize = if great then 34 else 28
		greatFrame.Visible = great
		for index, card in offer do
			local title, subtitle, description = describeCard(card, heroStats, gains[index])
			local colour = rarity(card)
			local button = newButton(
				cardRow,
				"Card" .. index,
				UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
				PANEL_COLOR
			)
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
				hint.Text = Strings.keys.cards[index] or ""
				hint.TextColor3 = colour
			end
			-- The icon large, the name under it, then the rank and the description.
			local id: string? = (card :: any).skill or (card :: any).passive
			local faceColor = if (card :: any).skill
				then skillColor(Config.skills[(card :: any).skill])
				elseif (card :: any).passive then UTILITY_COLOR
				else HEALTH_COLOR
			newFace(
				button,
				CARD_ICON,
				UDim2.new(0.5, -CARD_ICON / 2, 0, 12),
				id or "heal",
				title,
				faceColor
			)
			local titleLabel = newLabel(
				button,
				"Title",
				UDim2.new(1, -20, 0, 44),
				UDim2.fromOffset(10, CARD_ICON + 16),
				19,
				FONT_BOLD
			)
			titleLabel.TextWrapped = true
			titleLabel.Text = title
			local subtitleLabel = newLabel(
				button,
				"Subtitle",
				UDim2.new(1, -20, 0, 20),
				UDim2.fromOffset(10, CARD_ICON + 60),
				15,
				FONT_BOLD
			)
			subtitleLabel.Text = subtitle
			subtitleLabel.TextColor3 = if gains[index] > 1 then GREAT_COLOR else colour
			local descriptionLabel = newLabel(
				button,
				"Description",
				UDim2.new(1, -20, 0, CARD_HEIGHT - CARD_ICON - 90),
				UDim2.fromOffset(10, CARD_ICON + 84),
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

	-- Lays the experience bar along the topbar's free row (between Roblox's
	-- own buttons), or along the screen's top without one, and hangs the rest
	-- of the top under it. Offsets are in the scaled root's units.
	local function layoutTop()
		local camera = workspace.CurrentCamera
		local scale = math.max(uiScale.Scale, 1e-3)
		local screenWidth = (if camera then camera.ViewportSize.X else 1280) / scale
		local inset = GuiService.TopbarInset
		local left, width, top, below
		if inset.Width > 0 and inset.Height > 0 then
			local rowTop = inset.Min.Y / scale
			local rowHeight = inset.Height / scale
			left = inset.Min.X / scale + TOP_MARGIN
			width = inset.Width / scale - 2 * TOP_MARGIN
			top = rowTop + math.max(0, (rowHeight - XP_HEIGHT) / 2)
			below = rowTop + rowHeight
		else
			left = TOP_MARGIN
			width = screenWidth - 2 * TOP_MARGIN
			top = TOP_MARGIN
			below = TOP_MARGIN + XP_HEIGHT
		end
		width = math.max(width, MIN_XP_WIDTH)
		xpBar.root.Position = UDim2.fromOffset(left, top)
		xpBar.root.Size = UDim2.fromOffset(width, XP_HEIGHT)
		topLayer.Position = UDim2.fromOffset(0, below + 4)
	end

	local function updateScale()
		local camera = workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else DESIGN_HEIGHT
		local scale = math.clamp(height / DESIGN_HEIGHT, MIN_SCALE, MAX_SCALE)
		uiScale.Scale = scale
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
		layoutTop()
	end
	updateScale()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layoutTop)
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
				local image = iconOf(skillView.id)
				tile.icon.Visible = image ~= nil
				tile.icon.Image = image or ""
				tile.text.Visible = image == nil
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

	-- The dash charges: a full pip per charge held, the next one filling as its
	-- cooldown runs, the rest empty; the touch button greys with none held.
	local function updateDash(selfView: Protocol.SelfView?, elapsed: number)
		local charges = if selfView and type(selfView.dashCharges) == "number"
			then selfView.dashCharges
			else 0
		local readyIn = if selfView and type(selfView.dashReadyIn) == "number"
			then cooldownLeft(selfView.dashReadyIn, elapsed)
			else 0
		local cooldown = Config.player.dashCooldownSeconds
		for index, pip in dashPips do
			local fraction = if index <= charges
				then 1
				elseif index == charges + 1 and cooldown > 0 then math.clamp(
					1 - readyIn / cooldown,
					0,
					1
				)
				else 0
			pip.fill.Size = UDim2.fromScale(1, fraction)
			pip.fill.BackgroundColor3 = if index <= charges then DASH_COLOR else COOLDOWN_COLOR
		end
		local button = dashButton
		if button then
			button.BackgroundColor3 = if charges > 0 then DASH_COLOR else COOLDOWN_COLOR
		end
	end

	-- The passives taken, one per line, sorted by name, then the boons and
	-- pacts in the order taken; the text is set only on a change.
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
			local shrinesTaken = selfView.shrinesTaken
			if type(shrinesTaken) == "table" and #shrinesTaken > 0 then
				if #entries > 0 then
					table.insert(entries, "")
				end
				for _, id in shrinesTaken do
					table.insert(entries, (boonOrPactName(id)))
				end
			end
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
				string.format(Strings.level, selfView.level)
			)
			xpAmount.Text = string.format(
				Strings.experienceShort,
				math.floor(selfView.xp),
				math.floor(selfView.xpToNext)
			)
			killsLabel.Text = string.format(Strings.kills, selfView.kills)
		else
			setBar(xpBar, 0, "")
			xpAmount.Text = ""
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
		updateDash(selfView, sinceSelf)

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
		-- character stands. The portal wins over the chest, the chest over a
		-- shrine, a shrine over the spell, as Input decides what F does.
		local character = player.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local here: Vector3? = if ownRoot and ownRoot:IsA("BasePart")
			then ownRoot.Position
			elseif view then Vector3.new(view.x, Net.groundY(), view.z)
			else nil
		local extraction = Config.extraction
		local promptText: string? = nil
		local shrineText: string? = nil
		local detailText: string? = nil
		local shrineColor = EXTRACT_COLOR
		local barShown = false
		if alive and world and view and here then
			local chest = world.chest
			local target, shrine = Input.target(here)
			-- A spring still recharging is named, and F casts beside it.
			local named = shrine or (if target == nil then Input.shrineNear(here) else nil)
			if named then
				shrineColor = SHRINE_COLORS[named.kind] or EXTRACT_COLOR
				local given = named.given
				local details = Strings.shrineDetails
				if type(given) == "string" then
					local gain
					shrineText, gain = boonOrPactName(given)
					detailText = if named.kind == "boon"
						then string.format(details.boon, gain)
						else gain
				else
					shrineText = SHRINE_TEXT[named.kind] or named.kind
				end
				if named.kind == "spring" and named.readyIn > 0 then
					detailText = string.format(
						details.springBack,
						formatTime(math.max(1, math.ceil(named.readyIn - sinceSnapshot)))
					)
				elseif named.kind == "spring" then
					detailText = string.format(
						details.spring,
						formatTime(Config.shrines.springRechargeSeconds)
					)
				elseif named.kind == "trial" then
					detailText = string.format(
						details.trial,
						Config.shrines.trialRingCount,
						Config.shrines.greatOfferRanks
					)
				end
			end
			if target == "portal" then
				promptText = string.format(Strings.prompts.portal, interactName)
			elseif target == "chest" then
				promptText = string.format(Strings.prompts.open, interactName)
			elseif target == "shrine" then
				promptText = string.format(Strings.prompts.hold, interactName)
			elseif selfView and selfView.hasSpell and portal == nil and view.castingLeft <= 0 then
				promptText = string.format(Strings.prompts.cast, interactName)
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
			elseif (view.shrineProgress or 0) > 0 then
				barShown = true
				actionBar.fill.BackgroundColor3 = shrineColor
				setBar(
					actionBar,
					view.shrineProgress / math.max(Config.shrines.holdSeconds, 1e-3),
					Strings.bars.activating
				)
			end
		end
		prompt.Visible = promptText ~= nil
		prompt.Text = promptText or ""
		shrineLabel.Visible = shrineText ~= nil
		shrineLabel.Text = shrineText or ""
		shrineLabel.TextColor3 = shrineColor
		shrineDetail.Visible = detailText ~= nil
		shrineDetail.Text = detailText or ""
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
		showOffer(offer, selfView)

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
