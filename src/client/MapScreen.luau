--!strict
-- The map screen (stage 2d): the run's layout of points and paths, the local
-- character, the open zones, the flood's safe square, what is known of each
-- leader's area, chests, the clues found and a pulse where each announcement
-- with a place happened.
-- Opened with M or the HUD's Map button (Hud.toggleMap). It draws only what
-- every player of the run may know: never an enemy or another player.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Net)

local MapScreen = {}

-- Presentation constants; nothing here is a gameplay number.
-- The panel's side, as a share of the shorter side of the screen.
local PANEL_SHARE = 0.8
-- The world on the panel is redrawn from the latest snapshot at most this often.
local REDRAW_SECONDS = 0.1
-- Smallest sizes in pixels, so every marker reads on a phone.
local MIN_POINT_PIXELS = 10
local MIN_ZONE_PIXELS = 16
local MIN_AREA_PIXELS = 18
local PATH_PIXELS = 3
local ENTRY_RING_PIXELS = 2
local LEADER_POINT_PIXELS = 14
local CHEST_PIXELS = 11
local CLUE_PIXELS = 8
local PLAYER_PIXELS = 14
local PLAYER_STROKE_PIXELS = 2
-- The facing tick: a bar this long and wide from the marker's centre.
local TICK_LENGTH = 13
local TICK_WIDTH = 3
-- An open zone's pulse: a ring growing to this many times the zone over each period.
local ZONE_PULSE_SECONDS = 1.2
local ZONE_PULSE_GROWTH = 1.2
-- An announcement's marker: a dot and a ring that grows from `FROM` to `TO`
-- pixels each period, for `SECONDS`; the oldest is reused past the cap.
local ANNOUNCE_SECONDS = 3
local ANNOUNCE_PERIOD = 1
local ANNOUNCE_FROM = 10
local ANNOUNCE_TO = 60
local ANNOUNCE_DOT_PIXELS = 10
local ANNOUNCE_STROKE_PIXELS = 3
local MAX_ANNOUNCEMENTS = 6
-- Transparencies: the panel, the screen behind it, the flood, a leader's area.
local PANEL_TRANSPARENCY = 0.12
local BACKDROP_TRANSPARENCY = 0.6
local FLOOD_TRANSPARENCY = 0.3
local AREA_FILL_TRANSPARENCY = 0.78
local AREA_STROKE_TRANSPARENCY = 0.25
local AREA_STROKE_PIXELS = 2
local ZONE_PULSE_PIXELS = 2
local FLOOD_EDGE_PIXELS = 2
local BORDER_PIXELS = 2
-- Above the HUD.
local DISPLAY_ORDER = 5
local TITLE_SIZE = 18
local LEGEND_SIZE = 13
local CLOSE_PIXELS = 36

local WHITE = Color3.new(1, 1, 1)
local BACKDROP_COLOR = Color3.fromRGB(0, 0, 0)
local PANEL_COLOR = Color3.fromRGB(26, 31, 27)
local BORDER_COLOR = Color3.fromRGB(90, 96, 90)
local PATH_COLOR = Color3.fromRGB(150, 138, 108)
local POINT_COLOR = Color3.fromRGB(104, 112, 102)
local ENTRY_COLOR = Color3.fromRGB(128, 136, 150)
local ENTRY_RING_COLOR = Color3.fromRGB(235, 238, 245)
-- The same green as the zone in the world (Effects).
local ZONE_COLOR = Color3.fromRGB(80, 255, 140)
local FLOOD_COLOR = Color3.fromRGB(10, 8, 22)
local FLOOD_EDGE_COLOR = Color3.fromRGB(130, 105, 190)
local AREA_COLOR = Color3.fromRGB(230, 45, 45)
local CHEST_COLOR = Color3.fromRGB(240, 196, 70)
local OPENED_COLOR = Color3.fromRGB(92, 92, 98)
local CLUE_COLOR = Color3.fromRGB(90, 170, 255)
local READ_COLOR = Color3.fromRGB(125, 125, 135)
local PLAYER_COLOR = Color3.fromRGB(255, 255, 255)
local PLAYER_STROKE_COLOR = Color3.fromRGB(20, 20, 24)
local TICK_COLOR = Color3.fromRGB(255, 230, 120)
-- An announcement's marker, by what was announced; an incursion wave and the
-- flood's start carry no place, so they have none.
local ANNOUNCE_COLORS: { [string]: Color3 } = {
	zoneOpened = ZONE_COLOR,
	zoneClosed = Color3.fromRGB(150, 150, 160),
	chestDrop = CHEST_COLOR,
	wanderingBoss = Color3.fromRGB(255, 60, 60),
}
local FONT_BOLD = Enum.Font.GothamBold
local FONT = Enum.Font.GothamMedium

-- A pool of markers of one kind, reused across redraws: `used` are shown, the
-- rest are hidden.
type Pool<T> = {
	items: { T },
	used: number,
	build: () -> T,
	root: (T) -> GuiObject,
}

type ZoneMarker = { root: Frame, ring: Frame, ringScale: UIScale, ringStroke: UIStroke }

type Announcement = { root: Frame, ring: Frame, stroke: UIStroke, at: number }

local gui: ScreenGui
local panel: Frame
-- Layers inside the panel, bottom to top.
local staticLayer: Frame
local floodLayer: Frame
local areaLayer: Frame
local zoneLayer: Frame
local itemLayer: Frame
local pulseLayer: Frame
local playerLayer: Frame
-- The flood: four dark frames round the safe square, and its edge.
local floodSides: { Frame } = {}
local floodEdge: Frame
local playerMarker: Frame
local open = false
local lastRedraw = -math.huge
local shownZones: { ZoneMarker } = {}
local announcements: { Announcement } = {}
local announceCursor = 0
local started = false

local function newFrame(parent: Instance, name: string, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- A transparent frame filling its parent.
local function newLayer(name: string, zIndex: number): Frame
	local layer = newFrame(panel, name, WHITE, 1)
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = zIndex
	return layer
end

local function round(frame: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
end

local function stroke(
	frame: GuiObject,
	color: Color3,
	pixels: number,
	transparency: number
): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = pixels
	line.Transparency = transparency
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = frame
	return line
end

local function minimum(frame: GuiObject, pixels: number)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(pixels, pixels)
	constraint.Parent = frame
end

-- A marker centred on its position.
local function newMarker(parent: Instance, name: string, color: Color3, transparency: number): Frame
	local frame = newFrame(parent, name, color, transparency)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	return frame
end

local function newPool<T>(build: () -> T, root: (T) -> GuiObject): Pool<T>
	return { items = {}, used = 0, build = build, root = root }
end

local function take<T>(pool: Pool<T>): T
	pool.used += 1
	local item = pool.items[pool.used]
	if item == nil then
		item = pool.build()
		pool.items[pool.used] = item
	end
	pool.root(item).Visible = true
	return item
end

-- Hides the markers not taken since the last call and starts over.
local function finish<T>(pool: Pool<T>)
	for index = pool.used + 1, #pool.items do
		pool.root(pool.items[index]).Visible = false
	end
	pool.used = 0
end

local function frameOf(frame: Frame): GuiObject
	return frame
end

-- Where (x, z) is on the panel: world +x is right and +z down, as the camera sees it.
local function place(x: number, z: number, half: number): UDim2
	return UDim2.fromScale((x + half) / (2 * half), (z + half) / (2 * half))
end

-- A world length as a share of the panel.
local function span(studs: number, half: number): UDim2
	return UDim2.fromScale(studs / (2 * half), studs / (2 * half))
end

local areaPool = newPool(function(): Frame
	local frame = newMarker(areaLayer, "LeaderArea", AREA_COLOR, AREA_FILL_TRANSPARENCY)
	round(frame)
	stroke(frame, AREA_COLOR, AREA_STROKE_PIXELS, AREA_STROKE_TRANSPARENCY)
	minimum(frame, MIN_AREA_PIXELS)
	return frame
end, frameOf)

-- A leader's point once its last clue marked it: a small red diamond.
local leaderPointPool = newPool(function(): Frame
	local frame = newMarker(areaLayer, "LeaderPoint", AREA_COLOR, 0)
	frame.Size = UDim2.fromOffset(LEADER_POINT_PIXELS, LEADER_POINT_PIXELS)
	frame.Rotation = 45
	stroke(frame, WHITE, 1, 0.3)
	return frame
end, frameOf)

local zonePool = newPool(function(): ZoneMarker
	local frame = newMarker(zoneLayer, "Zone", ZONE_COLOR, 0.15)
	round(frame)
	minimum(frame, MIN_ZONE_PIXELS)
	local ring = newMarker(frame, "Pulse", ZONE_COLOR, 1)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	round(ring)
	local ringStroke = stroke(ring, ZONE_COLOR, ZONE_PULSE_PIXELS, 0)
	local ringScale = Instance.new("UIScale")
	ringScale.Parent = ring
	return { root = frame, ring = ring, ringScale = ringScale, ringStroke = ringStroke }
end, function(marker: ZoneMarker): GuiObject
	return marker.root
end)

local chestPool = newPool(function(): Frame
	local frame = newMarker(itemLayer, "Chest", CHEST_COLOR, 0)
	frame.Size = UDim2.fromOffset(CHEST_PIXELS, CHEST_PIXELS)
	stroke(frame, PLAYER_STROKE_COLOR, 1, 0.2)
	return frame
end, frameOf)

local cluePool = newPool(function(): Frame
	local frame = newMarker(itemLayer, "Clue", CLUE_COLOR, 0)
	frame.Size = UDim2.fromOffset(CLUE_PIXELS, CLUE_PIXELS)
	round(frame)
	stroke(frame, PLAYER_STROKE_COLOR, 1, 0.3)
	return frame
end, frameOf)

-- The points and paths: drawn once per map.
local function drawLayout()
	for _, child in staticLayer:GetChildren() do
		child:Destroy()
	end
	local map = Net.map
	if map == nil then
		return
	end
	local half = map.half
	local byId = {}
	for _, point in map.points do
		byId[point.id] = point
	end
	for _, path in map.paths do
		local a, b = byId[path.a], byId[path.b]
		if a and b then
			local dx, dz = b.x - a.x, b.z - a.z
			local line = newMarker(staticLayer, "Path", PATH_COLOR, 0)
			line.Position = place((a.x + b.x) / 2, (a.z + b.z) / 2, half)
			-- The panel is square, so a share of its width is the same stud length on screen.
			line.Size = UDim2.new(math.sqrt(dx * dx + dz * dz) / (2 * half), 0, 0, PATH_PIXELS)
			line.Rotation = math.deg(math.atan2(dz, dx))
			line.ZIndex = 1
		end
	end
	for _, point in map.points do
		local disc = newMarker(
			staticLayer,
			if point.isEntry then "Entry" else "Point",
			if point.isEntry then ENTRY_COLOR else POINT_COLOR,
			0
		)
		disc.Position = place(point.x, point.z, half)
		disc.Size = span(point.radius * 2, half)
		disc.ZIndex = 2
		round(disc)
		minimum(disc, MIN_POINT_PIXELS)
		if point.isEntry then
			stroke(disc, ENTRY_RING_COLOR, ENTRY_RING_PIXELS, 0)
		end
	end
end

local function setFlood(safe: number)
	local share = math.clamp(safe, 0, 1)
	local flooding = share < 1
	local rim = (1 - share) / 2
	floodEdge.Visible = flooding
	for _, side in floodSides do
		side.Visible = flooding
	end
	if not flooding then
		return
	end
	-- Top, bottom, left, right of the safe square.
	floodSides[1].Position = UDim2.new()
	floodSides[1].Size = UDim2.fromScale(1, rim)
	floodSides[2].Position = UDim2.fromScale(0, rim + share)
	floodSides[2].Size = UDim2.fromScale(1, rim)
	floodSides[3].Position = UDim2.fromScale(0, rim)
	floodSides[3].Size = UDim2.fromScale(rim, share)
	floodSides[4].Position = UDim2.fromScale(rim + share, rim)
	floodSides[4].Size = UDim2.fromScale(rim, share)
	floodEdge.Position = UDim2.fromScale(rim, rim)
	floodEdge.Size = UDim2.fromScale(share, share)
end

-- Everything the snapshots change: the flood, leader areas, zones, chests and clues.
local function drawWorld()
	local map = Net.map
	local snapshot = Net.latest
	if map == nil or snapshot == nil then
		setFlood(1)
		finish(areaPool)
		finish(leaderPointPool)
		finish(zonePool)
		finish(chestPool)
		finish(cluePool)
		table.clear(shownZones)
		return
	end
	local world = snapshot.world
	local half = map.half
	setFlood(world.floodHalf / half)

	for _, area in world.leaderAreas do
		if area.radius > 0 then
			local frame = take(areaPool)
			frame.Position = place(area.x, area.z, half)
			frame.Size = span(area.radius * 2, half)
		else
			take(leaderPointPool).Position = place(area.x, area.z, half)
		end
	end
	finish(areaPool)
	finish(leaderPointPool)

	table.clear(shownZones)
	for _, zone in world.zones do
		if zone.open then
			local marker = take(zonePool)
			marker.root.Position = place(zone.x, zone.z, half)
			marker.root.Size = span(zone.radius * 2, half)
			table.insert(shownZones, marker)
		end
	end
	finish(zonePool)

	for _, chest in world.chests do
		local frame = take(chestPool)
		frame.Position = place(chest.x, chest.z, half)
		frame.BackgroundColor3 = if chest.opened then OPENED_COLOR else CHEST_COLOR
	end
	finish(chestPool)

	-- The world view carries only the clues someone has found.
	for _, clue in world.clues do
		local frame = take(cluePool)
		frame.Position = place(clue.x, clue.z, half)
		frame.BackgroundColor3 = if clue.read then READ_COLOR else CLUE_COLOR
	end
	finish(cluePool)
end

-- The local character and the pulses, every frame while open.
local function animate(now: number)
	local map = Net.map
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if map and root and root:IsA("BasePart") then
		local position = root.Position
		local look = root.CFrame.LookVector
		playerMarker.Visible = true
		playerMarker.Position = place(position.X, position.Z, map.half)
		-- The tick points up at 0; world +x is right and +z down.
		playerMarker.Rotation = math.deg(math.atan2(look.X, -look.Z))
	else
		playerMarker.Visible = false
	end

	local phase = (now / ZONE_PULSE_SECONDS) % 1
	for _, marker in shownZones do
		marker.ringScale.Scale = 1 + ZONE_PULSE_GROWTH * phase
		marker.ringStroke.Transparency = phase
	end

	for _, announcement in announcements do
		local age = now - announcement.at
		local live = age < ANNOUNCE_SECONDS
		announcement.root.Visible = live
		if live then
			local wave = (age / ANNOUNCE_PERIOD) % 1
			local pixels = ANNOUNCE_FROM + (ANNOUNCE_TO - ANNOUNCE_FROM) * wave
			announcement.ring.Size = UDim2.fromOffset(pixels, pixels)
			announcement.stroke.Transparency = wave
		end
	end
end

local function render()
	if not open then
		return
	end
	local now = os.clock()
	if now - lastRedraw >= REDRAW_SECONDS then
		lastRedraw = now
		drawWorld()
	end
	animate(now)
end

-- Marks (x, z) on the map with a pulse for a few seconds, in the colour of `what`.
local function announce(what: string, x: number, z: number)
	local map = Net.map
	if map == nil then
		return
	end
	announceCursor = announceCursor % MAX_ANNOUNCEMENTS + 1
	local announcement = announcements[announceCursor]
	if announcement == nil then
		local dot = newMarker(pulseLayer, "Announcement", WHITE, 0)
		dot.Size = UDim2.fromOffset(ANNOUNCE_DOT_PIXELS, ANNOUNCE_DOT_PIXELS)
		round(dot)
		local ring = newMarker(dot, "Ring", WHITE, 1)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		round(ring)
		local line = stroke(ring, WHITE, ANNOUNCE_STROKE_PIXELS, 0)
		announcement = { root = dot, ring = ring, stroke = line, at = 0 }
		announcements[announceCursor] = announcement
	end
	local color = ANNOUNCE_COLORS[what] or WHITE
	announcement.root.BackgroundColor3 = color
	announcement.stroke.Color = color
	announcement.root.Position = place(x, z, map.half)
	announcement.at = os.clock()
	announcement.root.Visible = true
end

function MapScreen.isOpen(): boolean
	return open
end

function MapScreen.setOpen(value: boolean)
	if not started then
		return
	end
	open = value
	gui.Enabled = value
	if value then
		lastRedraw = os.clock()
		drawWorld()
		animate(lastRedraw)
	end
end

function MapScreen.toggle()
	MapScreen.setOpen(not open)
end

function MapScreen.start()
	if started then
		return
	end
	started = true
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	gui = Instance.new("ScreenGui")
	gui.Name = "MapScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false

	-- A dim over the game; it takes no input, so the character still moves and fires.
	local backdrop = newFrame(gui, "Backdrop", BACKDROP_COLOR, BACKDROP_TRANSPARENCY)
	backdrop.Size = UDim2.fromScale(1, 1)

	-- A centred square, its side PANEL_SHARE of the shorter side of the screen.
	panel = newFrame(gui, "Panel", PANEL_COLOR, PANEL_TRANSPARENCY)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(PANEL_SHARE, PANEL_SHARE)
	panel.ClipsDescendants = true
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = panel
	stroke(panel, BORDER_COLOR, BORDER_PIXELS, 0)

	staticLayer = newLayer("Layout", 1)
	floodLayer = newLayer("Flood", 2)
	areaLayer = newLayer("LeaderAreas", 3)
	zoneLayer = newLayer("Zones", 4)
	itemLayer = newLayer("Items", 5)
	pulseLayer = newLayer("Announcements", 6)
	playerLayer = newLayer("Player", 7)

	for index, name in { "Top", "Bottom", "Left", "Right" } do
		local side = newFrame(floodLayer, name, FLOOD_COLOR, FLOOD_TRANSPARENCY)
		side.Visible = false
		floodSides[index] = side
	end
	floodEdge = newFrame(floodLayer, "Edge", WHITE, 1)
	floodEdge.Visible = false
	stroke(floodEdge, FLOOD_EDGE_COLOR, FLOOD_EDGE_PIXELS, 0)

	-- The local character: a bright disc and a tick toward its facing; the
	-- holder turns, so the tick sits at its top.
	playerMarker = newMarker(playerLayer, "You", WHITE, 1)
	playerMarker.Size =
		UDim2.fromOffset(TICK_LENGTH * 2 + PLAYER_PIXELS, TICK_LENGTH * 2 + PLAYER_PIXELS)
	playerMarker.Visible = false
	local tick = newMarker(playerMarker, "Facing", TICK_COLOR, 0)
	tick.AnchorPoint = Vector2.new(0.5, 1)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Size = UDim2.fromOffset(TICK_WIDTH, TICK_LENGTH + PLAYER_PIXELS / 2)
	stroke(tick, PLAYER_STROKE_COLOR, 1, 0.3)
	local dot = newMarker(playerMarker, "Dot", PLAYER_COLOR, 0)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(PLAYER_PIXELS, PLAYER_PIXELS)
	-- Over the tick's foot.
	dot.ZIndex = 2
	round(dot)
	stroke(dot, PLAYER_STROKE_COLOR, PLAYER_STROKE_PIXELS, 0)

	-- Title, close button and legend, above every layer.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20 - CLOSE_PIXELS, 0, TITLE_SIZE + 6)
	title.Font = FONT_BOLD
	title.TextSize = TITLE_SIZE
	title.TextColor3 = WHITE
	title.TextStrokeTransparency = 0.5
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = if touch then "Map" else "Map (M)"
	title.ZIndex = 8
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.fromOffset(CLOSE_PIXELS, CLOSE_PIXELS)
	close.BackgroundColor3 = BORDER_COLOR
	close.BackgroundTransparency = 0.3
	close.BorderSizePixel = 0
	close.Font = FONT_BOLD
	close.TextSize = 18
	close.TextColor3 = WHITE
	close.Text = "X"
	close.ZIndex = 8
	close.Parent = panel
	round(close)
	close.Activated:Connect(function()
		MapScreen.setOpen(false)
	end)

	local legend = Instance.new("TextLabel")
	legend.Name = "Legend"
	legend.BackgroundTransparency = 1
	legend.AnchorPoint = Vector2.new(0, 1)
	legend.Position = UDim2.new(0, 10, 1, -4)
	legend.Size = UDim2.new(1, -20, 0, LEGEND_SIZE + 6)
	legend.Font = FONT
	legend.TextSize = LEGEND_SIZE
	legend.TextColor3 = WHITE
	legend.TextStrokeTransparency = 0.4
	legend.TextXAlignment = Enum.TextXAlignment.Left
	legend.TextScaled = false
	legend.RichText = true
	legend.Text = string.format(
		'<font color="#%s">●</font> Zone   <font color="#%s">■</font> Chest   '
			.. '<font color="#%s">●</font> Clue   <font color="#%s">◆</font> Leader   '
			.. '<font color="#%s">■</font> Flood',
		ZONE_COLOR:ToHex(),
		CHEST_COLOR:ToHex(),
		CLUE_COLOR:ToHex(),
		AREA_COLOR:ToHex(),
		FLOOD_EDGE_COLOR:ToHex()
	)
	legend.ZIndex = 8
	legend.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	drawLayout()
	Net.onMap(function()
		drawLayout()
		if open then
			drawWorld()
		end
	end)
	Net.onEvents(function(events)
		for _, event in events do
			if event.kind == "announcement" then
				-- Only an announcement with a place gets a marker: an incursion
				-- wave and the flood's start carry none, so for them the HUD's
				-- notice is all (the plan's "with a marker" is for events with a place).
				local x, z = event.x, event.z
				if x and z then
					announce(event.what, x, z)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return MapScreen
