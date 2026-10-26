--!strict
-- The stage 1 HUD, built in code: health, level and experience, the skill
-- cooldown (with a button on touch), the run clock, banners, the perk choice,
-- the downed, extraction and end-of-run panels. It only shows state and sends
-- intents through Net (AGENTS.md rule 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Types = require(ReplicatedStorage.Shared.Core.Types)
local Net = require(script.Parent.Net)

local Hud = {}

-- Presentation constants; gameplay numbers come from Config.
local DESIGN_HEIGHT = 720
local MIN_SCALE = 0.55
local MAX_SCALE = 1.25
local BANNER_SECONDS = 4

local WHITE = Color3.new(1, 1, 1)
local PANEL_COLOR = Color3.fromRGB(20, 22, 28)
local TRACK_COLOR = Color3.fromRGB(45, 48, 58)
local HEALTH_COLOR = Color3.fromRGB(214, 69, 65)
local XP_COLOR = Color3.fromRGB(86, 156, 236)
local SKILL_COLOR = Color3.fromRGB(120, 200, 120)
local SKILL_COOLDOWN_COLOR = Color3.fromRGB(110, 114, 126)
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

	-- Top left: health, experience, kills.
	local stats = newFrame(
		root,
		"Stats",
		UDim2.fromOffset(280, 100),
		UDim2.fromOffset(16, 16),
		PANEL_COLOR,
		1
	)
	local healthBar =
		newBar(stats, "Health", UDim2.fromOffset(280, 28), UDim2.new(), HEALTH_COLOR, 18)
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

	-- Top centre: run clock, zone note, banner.
	local clockLabel = newLabel(
		root,
		"Clock",
		UDim2.fromOffset(220, 36),
		UDim2.new(0.5, -110, 0, 12),
		30,
		FONT_BOLD
	)
	local zoneLabel =
		newLabel(root, "ZoneNote", UDim2.fromOffset(460, 22), UDim2.new(0.5, -230, 0, 48), 16, FONT)
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

	-- Skill cooldown, bottom centre; touch adds a large button.
	local skillBar = newBar(
		root,
		"Skill",
		UDim2.fromOffset(260, 24),
		UDim2.new(0.5, -130, 1, -44),
		SKILL_COLOR,
		15
	)
	local skillButton: TextButton? = nil
	if touch then
		local button = Instance.new("TextButton")
		button.Name = "SkillButton"
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -36, 1, -36)
		button.Size = UDim2.fromOffset(130, 130)
		button.BackgroundColor3 = SKILL_COLOR
		button.BackgroundTransparency = 0.15
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Font = FONT_BOLD
		button.TextSize = 26
		button.TextColor3 = WHITE
		button.TextStrokeTransparency = 0.6
		button.Text = "SKILL"
		button.Parent = root
		round(button, 65)
		button.Activated:Connect(function()
			Net.useActiveSkill(nil)
		end)
		skillButton = button

		-- Held, not tapped: revive and extraction take seconds.
		local interact = Instance.new("TextButton")
		interact.Name = "InteractButton"
		interact.AnchorPoint = Vector2.new(1, 1)
		interact.Position = UDim2.new(1, -186, 1, -36)
		interact.Size = UDim2.fromOffset(100, 100)
		interact.BackgroundColor3 = EXTRACT_COLOR
		interact.BackgroundTransparency = 0.15
		interact.BorderSizePixel = 0
		interact.Font = FONT_BOLD
		interact.TextSize = 18
		interact.TextColor3 = WHITE
		interact.TextStrokeTransparency = 0.6
		interact.Text = "HOLD"
		interact.Parent = root
		round(interact, 50)
		interact.MouseButton1Down:Connect(function()
			Net.interact(true)
		end)
		interact.MouseButton1Up:Connect(function()
			Net.interact(false)
		end)
		interact.MouseLeave:Connect(function()
			Net.interact(false)
		end)
	end

	-- What holding interact would do here, if anything.
	local interactPrompt = newLabel(
		root,
		"InteractPrompt",
		UDim2.fromOffset(420, 26),
		UDim2.new(0.5, -210, 1, -110),
		20,
		FONT_BOLD
	)
	interactPrompt.Visible = false
	local holdWord = if touch then "Hold HOLD" else "Hold E"

	-- Perk choice: a row of buttons that leaves the middle and the corners free
	-- for movement.
	local perkPanel = newFrame(
		root,
		"Perks",
		UDim2.fromOffset(640, 150),
		UDim2.new(0.5, -320, 0.62, 0),
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
	local selfAt = os.clock()
	local lastWorldTime = -1
	local bannerUntil = 0
	local ended = false
	-- The run time when the local player extracted or died, and which.
	local finishedAt: number? = nil
	local outcome: "Extracted" | "Died" | nil = nil

	local function worldTime(): number
		local snapshot = Net.latest
		return if snapshot then snapshot.world.time else 0
	end

	local function showBanner(text: string)
		bannerLabel.Text = text
		bannerLabel.Visible = true
		bannerUntil = os.clock() + BANNER_SECONDS
	end

	local function resetRun()
		ended = false
		finishedAt = nil
		outcome = nil
		summary.Visible = false
		bannerLabel.Visible = false
		bannerUntil = 0
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
		selfAt = os.clock()
		for _, event in events do
			if event.kind == "zonesOpened" then
				showBanner("Extraction zones are open")
			elseif event.kind == "flood" then
				showBanner("The horde floods the map")
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
		for index, id in offer do
			local perk = Config.perks.pool[id]
			local button = Instance.new("TextButton")
			button.Name = "Perk" .. index
			button.LayoutOrder = index
			button.Size = UDim2.fromOffset(200, 104)
			button.BackgroundColor3 = PANEL_COLOR
			button.BackgroundTransparency = 0.1
			button.BorderSizePixel = 0
			button.AutoButtonColor = true
			button.Font = FONT_BOLD
			button.TextSize = 20
			button.TextColor3 = WHITE
			button.TextWrapped = true
			local name = if perk then perk.name else id
			local tags = if perk and #perk.tags > 0 then table.concat(perk.tags, ", ") else "no tag"
			local prefix = if touch then "" else index .. ". "
			button.Text = prefix .. name .. "\n[" .. tags .. "]"
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

		-- Run clock and zone note; the clock runs on between snapshots and
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
		if runTime < Config.run.zonesOpenAtSeconds then
			zoneLabel.Text = "Extraction zones open in "
				.. formatTime(Config.run.zonesOpenAtSeconds - runTime)
		elseif runTime < duration then
			zoneLabel.Text = "Zones are open - the horde floods in "
				.. formatTime(duration - runTime)
		else
			zoneLabel.Text = ""
		end
		if bannerLabel.Visible and now >= bannerUntil then
			bannerLabel.Visible = false
		end

		-- Skill cooldown, counted down locally between event batches.
		local ready = true
		local skillText = "Skill ready"
		local skillFraction = 1
		local remaining = 0
		if selfView then
			remaining = selfView.activeSkillReadyIn - (now - selfAt)
			if remaining > 0 then
				ready = false
				skillText = string.format("Skill %.1f s", remaining)
				skillFraction = if selfView.activeSkillCooldown > 0
					then 1 - remaining / selfView.activeSkillCooldown
					else 0
			end
		end
		skillBar.fill.BackgroundColor3 = if ready then SKILL_COLOR else SKILL_COOLDOWN_COLOR
		setBar(skillBar, skillFraction, skillText)
		if skillButton then
			skillButton.BackgroundColor3 = if ready then SKILL_COLOR else SKILL_COOLDOWN_COLOR
			skillButton.Text = if ready then "SKILL" else string.format("%.1f", remaining)
		end

		-- Perk choice.
		showOffer(if selfView then selfView.offer else nil)

		-- The interact prompt, from where the local character stands.
		local prompt: string? = nil
		local character = Players.LocalPlayer.Character
		local ownRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if view and view.state == "alive" and snapshot and ownRoot and ownRoot:IsA("BasePart") then
			local here = ownRoot.Position
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
