--!strict
-- The HUD, built in code: health, potions, level and experience, the three
-- active skills and the dash, the run clock, the zone compass, banners, the perk
-- choice and list, the downed, extraction and end-of-run panels, and the touch
-- buttons. It only shows state and sends intents through Net or Input
-- (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Input = require(script.Parent.Input)
local Net = require(script.Parent.Net)

local Hud = {}

-- Presentation constants; gameplay numbers come from Config.
local DESIGN_HEIGHT = 720
local MIN_SCALE = 0.55
local MAX_SCALE = 1.25
local BANNER_SECONDS = 4
local CAMP_BANNER_SECONDS = 2
local HURT_FLASH_SECONDS = 0.25
local HURT_FLASH_TRANSPARENCY = 0.7
local COMPASS_RADIUS = 110
-- A zone this close (edge to character) is on screen; its arrow is hidden.
local COMPASS_HIDE_STUDS = 25
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
	label.TextStrokeTransparency = 0.6
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
	local root = newFrame(parent, name, size, position, TRACK_COLOR, 0.15)
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

function Hud.start()
	if started then
		return
	end
	started = true

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

	-- Hurt flash: a red wash that fades out; behind every panel.
	local hurtFlash =
		newFrame(root, "HurtFlash", UDim2.fromScale(1, 1), UDim2.new(), BLEED_COLOR, 1)

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
	local drinkBar = newBar(
		potionRow,
		"Drinking",
		UDim2.fromOffset(120, POTION_SLOT_SIZE),
		UDim2.fromOffset(160, 0),
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
	local bannerLabel = newLabel(
		root,
		"Banner",
		UDim2.fromOffset(560, 48),
		UDim2.new(0.5, -280, 0, 84),
		28,
		FONT_BOLD
	)
	bannerLabel.TextColor3 = EXTRACT_COLOR
	bannerLabel.Visible = false

	-- The zone compass: one arrow per extraction zone on a ring around the screen centre.
	local compass =
		newFrame(root, "Compass", UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.5), PANEL_COLOR, 1)
	local arrows: { Arrow } = {}
	local function newArrow(index: number): Arrow
		local frame = newFrame(
			compass,
			"Zone" .. index,
			UDim2.fromOffset(56, 48),
			UDim2.new(),
			PANEL_COLOR,
			1
		)
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

	-- Extraction progress, above the middle of the screen.
	local extractBar = newBar(
		root,
		"Extraction",
		UDim2.fromOffset(320, 28),
		UDim2.new(0.5, -160, 0.28, 0),
		EXTRACT_COLOR,
		16
	)
	extractBar.root.Visible = false

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
		0.3
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
				showBanner("A camp notices you", CAMP_BANNER_SECONDS)
			elseif event.kind == "levelUp" and event.player == userId then
				showBanner("Level " .. event.level, BANNER_SECONDS)
			elseif event.kind == "playerHurt" and event.player == userId then
				hurtAt = os.clock()
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
		local snapshot = Net.latest
		local drinking = 0
		if view and snapshot and view.drinkingFor > 0 then
			drinking = math.max(0, view.drinkingFor - (now - snapshot.receivedAt))
		end
		drinkBar.root.Visible = drinking > 0
		if drinking > 0 then
			setBar(drinkBar, 1 - drinking / Config.player.drinkSeconds, "Drinking…")
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

	-- Points one arrow per zone from the character toward it; none for a zone already on screen.
	local function updateCompass(
		snapshot: Net.Snapshot?,
		view: Protocol.PlayerView?,
		ownRoot: BasePart?
	)
		local zones = if snapshot
				and view
				and view.state == "alive"
				and ownRoot
			then snapshot.world.zones
			else {}
		for index = #arrows + 1, #zones do
			arrows[index] = newArrow(index)
		end
		for index, arrow in arrows do
			local zone = zones[index]
			local visible = false
			if zone and ownRoot then
				local dx = zone.x - ownRoot.Position.X
				local dz = zone.z - ownRoot.Position.Z
				local distance = math.sqrt(dx * dx + dz * dz)
				if distance - zone.radius > COMPASS_HIDE_STUDS and distance > 0 then
					visible = true
					arrow.root.Position = UDim2.fromOffset(
						dx / distance * COMPASS_RADIUS,
						dz / distance * COMPASS_RADIUS
					)
					-- World +x is screen right and +z screen down; the arrow points up at 0.
					arrow.arrow.Rotation = math.deg(math.atan2(dx, -dz))
					arrow.distance.Text = tostring(math.floor(distance + 0.5))
				end
			end
			arrow.root.Visible = visible
		end
	end

	local function render()
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
		updatePotions(selfView, view, now)
		updatePerkList(selfView)

		-- Hurt flash.
		local sinceHurt = now - hurtAt
		hurtFlash.BackgroundTransparency = if sinceHurt < HURT_FLASH_SECONDS
			then HURT_FLASH_TRANSPARENCY + (1 - HURT_FLASH_TRANSPARENCY) * sinceHurt / HURT_FLASH_SECONDS
			else 1

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
		floodLabel.Text = if runTime < duration
			then "flood in " .. formatTime(duration - runTime)
			else ""
		if bannerLabel.Visible and now >= bannerUntil then
			bannerLabel.Visible = false
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

		-- The interact prompt and the zone compass, from where the local character stands.
		local prompt: string? = nil
		local character = Players.LocalPlayer.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local ownPart = if ownRoot and ownRoot:IsA("BasePart") then ownRoot else nil
		if view and view.state == "alive" and snapshot and ownPart then
			local here = ownPart.Position
			for _, zone in snapshot.world.zones do
				if (Vector3.new(zone.x, here.Y, zone.z) - here).Magnitude <= zone.radius then
					prompt = holdWord .. " to extract"
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
					and (otherRoot.Position - here).Magnitude <= Config.player.reviveRadius
				then
					prompt = holdWord .. " to revive"
				end
			end
		end
		interactPrompt.Visible = prompt ~= nil
		interactPrompt.Text = prompt or ""
		updateCompass(if summary.Visible then nil else snapshot, view, ownPart)

		-- Extraction progress.
		local extracting = view ~= nil and view.state == "alive" and view.extractProgress > 0
		extractBar.root.Visible = extracting
		if view and extracting then
			setBar(extractBar, view.extractProgress / Config.run.extractSeconds, "Extracting...")
		end

		-- Downed, dead, extracted.
		local state = if view then view.state else "alive"
		stateTint.Visible = state ~= "alive" and not summary.Visible
		bleedBar.root.Visible = false
		reviveBar.root.Visible = false
		if state == "downed" and view then
			stateTint.BackgroundTransparency = 0.85
			stateTitle.Text = "Downed"
			stateText.Text = "Another player can revive you"
			bleedBar.root.Visible = true
			reviveBar.root.Visible = true
			setBar(bleedBar, 1 - view.downedFor / Config.player.downedSeconds, "Bleeding out")
			setBar(reviveBar, view.reviveProgress / Config.player.reviveSeconds, "Being revived")
		elseif state == "dead" then
			stateTint.BackgroundTransparency = 0.9
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
