# Enemies are rigged Meshy models with walk, run and attack clips

**Status:** proposed on 2026-10-28; once accepted it supersedes [ADR-0022](0022-enemies-are-generated-meshes.md).

ADR-0022 drew every enemy as an unrigged generated mesh with procedural motion because rigging twenty-five kinds looked like the art stage's work. The Meshy trial changed the arithmetic: a stylized prompt gives a model that matches the forest's props, its auto-rig takes any biped or quadruped for five credits with a walk and a run, and an attack preset costs three more, so the whole roster was rigged in an evening (three kinds redesigned into quadrupeds so the rig would take). Every enemy kind is now a skinned MeshPart with bones, imported into Studio from the FBX, and plays three clips: walk and run chosen by its speed, attack on the attack event; what has no clip (sleep, hit, telegraph, death, the wraith's drift) stays procedural as in ADR-0022. We chose this over keeping procedural motion because the user judges the game by its look and asked for animation on every kind, and over hand-made or store animations because Meshy's clips come with the rig and fit each body.

## Where the assets live

The Studio import publishes the mesh and its texture under the owner's account, so `Config.enemyMeshes` keeps their ids as before. The rig (the bones and their initial poses) and the clips (KeyframeSequences) have no asset id until published, so they are checked in as `src/shared/Assets/Enemies/<kind>.rbxm`, which Rojo syncs into the place; the client clones the rig and registers the clips with the KeyframeSequenceProvider at start. If registering a local clip turns out to work only in Studio, the clips are published as animation assets through the Animation Editor once, their ids go into `Config.enemyMeshes`, and the local files remain the source. The FBX files themselves stay outside the repository in `build/meshy/` with a ledger of Meshy task ids; they are imported by hand, all at once from one flat folder with File → Import 3D (neither the MCP nor a plugin can reach the import service in this Studio), and Studio posts each rig back as JSON for `scripts/build-enemy-rigs.luau` to rebuild the `.rbxm` files.

## Considered options

- **Procedural motion only** (ADR-0022): cheaper on the client, but the user asked for animation after seeing the clips.
- **Publish every clip as an animation asset first:** seventy-five manual publishes before anything moves; deferred until a published server proves it needs them.
- **Humanoid rigs:** the Meshy rig is a plain skeleton without a Humanoid, and an AnimationController is enough; a Humanoid would cost physics and state we do not use.

## Consequences

The client draws a Model per enemy instead of one MeshPart, and an Animator per enemy; the cap of ADR-0019 (220) must be measured again with rigs playing, and a kind can be sent back to parts by removing its config entry if the frame cannot afford it (the rigged mesh without its clips would stand in a T-pose, so there is no static fallback). Meshy models come in centimetres (a human is 180 units tall), so each kind's `scale` in Config does the fitting as before. Spiders stay out of the roster's shapes: Meshy rigs only bipeds and quadrupeds, so a kind that must rig is drawn as one.
