--!strict
-- Builds the rigged enemy models (ADR-0024) from the JSON dumps that Studio
-- posted after importing the Meshy FBX files: one .rbxm a kind under
-- src/shared/Assets/Enemies, holding the skinned MeshPart with its bones and a
-- Clips folder with the walking, running and attack KeyframeSequences.
--   lune run scripts/build-enemy-rigs build/meshy/_dump src/shared/Assets/Enemies

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local dumpDir = process.args[1]
local outDir = process.args[2]
assert(dumpDir and outDir, "usage: build-enemy-rigs <dumpDir> <outDir>")

type Dumped = {
	kind: string,
	meshId: string,
	textureId: string,
	size: { number },
	bones: { { name: string, parent: string, cf: { number } } },
	clips: {
		[string]: {
			name: string,
			loop: boolean,
			priority: string,
			frames: {
				{
					t: number,
					poses: {
						{
							name: string,
							parent: string,
							w: number,
							cf: { number },
							es: string,
							ed: string,
						}
					},
				}
			},
		},
	},
}

local function toCFrame(c: { number }): any
	return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
end

-- Attack plays once per attack event over the locomotion; walk and run loop.
local LOOPS: { [string]: boolean } = { walking = true, running = true, attack = false }
local PRIORITIES: { [string]: string } =
	{ walking = "Movement", running = "Movement", attack = "Action" }

local function buildClip(clipName: string, clip): any
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = clipName
	sequence.Loop = LOOPS[clipName] ~= false
	sequence.Priority = (Enum.AnimationPriority :: any)[PRIORITIES[clipName] or clip.priority]
	for _, frame in clip.frames do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = frame.t
		local byName: { [string]: any } = {}
		-- A parent always precedes its children in the dump (GetDescendants order).
		for _, p in frame.poses do
			local pose = Instance.new("Pose")
			-- The Animator matches the root pose to the root part by name: the
			-- dump's "Armature" root becomes the part's name, or nothing plays.
			pose.Name = if p.parent == "" then "Mesh" else p.name
			pose.Weight = p.w
			pose.CFrame = toCFrame(p.cf)
			pose.EasingStyle = (Enum.PoseEasingStyle :: any)[p.es]
			pose.EasingDirection = (Enum.PoseEasingDirection :: any)[p.ed]
			pose.Parent = if p.parent == ""
				then keyframe
				else assert(
					byName[p.parent],
					`{clipName}: pose {p.name} before its parent {p.parent}`
				)
			byName[p.name] = pose
		end
		keyframe.Parent = sequence
	end
	return sequence
end

local function buildRig(d: Dumped): any
	local model = Instance.new("Model")
	model.Name = d.kind
	local part = Instance.new("MeshPart")
	part.Name = "Mesh"
	part.MeshId = d.meshId
	part.TextureID = d.textureId
	part.Size = Vector3.new(d.size[1], d.size[2], d.size[3])
	-- The skin is deformed relative to the mesh's native size; without it a
	-- MeshPart built from a file renders the skin at the wrong scale.
	local untyped: any = part
	untyped.InitialSize = Vector3.new(d.size[1], d.size[2], d.size[3])
	-- Only the importer sets this; without it the mesh draws its bind pose and
	-- ignores the bones, so the clips play and nothing on screen moves.
	untyped.HasSkinnedMesh = true
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Parent = model
	local byName: { [string]: any } = {}
	for _, b in d.bones do
		local bone = Instance.new("Bone")
		bone.Name = b.name
		bone.CFrame = toCFrame(b.cf)
		bone.Parent = if b.parent == ""
			then part
			else assert(
				byName[b.parent],
				`{d.kind}: bone {b.name} before its parent {b.parent}`
			)
		byName[b.name] = bone
	end
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	local clips = Instance.new("Folder")
	clips.Name = "Clips"
	for clipName, clip in d.clips do
		buildClip(clipName, clip).Parent = clips
	end
	clips.Parent = model
	model.PrimaryPart = part
	return model
end

if not fs.isDir(outDir) then
	fs.writeDir(outDir)
end
local built = 0
for _, file in fs.readDir(dumpDir) do
	if string.sub(file, -5) ~= ".json" then
		continue
	end
	local d: Dumped = serde.decode("json", fs.readFile(dumpDir .. "/" .. file))
	if type(d) ~= "table" or type(d.kind) ~= "string" then
		continue
	end
	-- EnemyView plays all three; a rig missing one is not written.
	for clipName in LOOPS do
		assert(d.clips[clipName], `{d.kind}: no {clipName} clip`)
	end
	local model = buildRig(d)
	fs.writeFile(outDir .. "/" .. d.kind .. ".rbxm", roblox.serializeModel({ model }))
	built += 1
	print(("%s: %d bones, clips %s"):format(
		d.kind,
		#d.bones,
		table.concat(
			(function()
				local names = {}
				for n in d.clips do
					table.insert(names, n)
				end
				table.sort(names)
				return names
			end)(),
			","
		)
	))
end
print(("built %d rigs into %s"):format(built, outDir))
