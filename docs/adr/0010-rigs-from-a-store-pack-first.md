# Rigged models from a store pack first, generated creatures later

**Status:** superseded by [ADR-0024](0024-enemies-are-rigged-meshy-models-with-clips.md) on 2026-10-28: Meshy now rigs and animates every enemy kind, so the store pack was never republished.

Stage 2a draws enemies from one Creator Store pack of rigged, animated low-poly monsters (Lukami's "Studded Rigged Monster Pack", twenty monsters with idle, walk, run, attack, hit and die), republished under the game owner's account, and draws players from Avatar Auto Setup R15 rigs with catalogue and Mixamo animations. Generated creatures (Meshy or Tripo on a commercial plan, with attack and death clips authored in Studio) come in the art stage, once combat is proven. We chose this because no AI tool rigs or animates a non-humanoid monster today: Roblox's generator yields unrigged meshes, Auto Setup takes humanoids only, and Meshy and Tripo rig creatures but animate only their walk.

## Considered options

- **Generated creatures from day one**: a month of animating seven archetypes before anyone knows whether the combat is fun, and a subscription.
- **Rig Builder blocks**: free and immediate, with no variety and nothing that reads as a monster.
- **Commissioned art**: the best consistency, at a cost and a wait that precede the proof.

## Consequences

Enemies stay server data drawn by client clones ([ADR-0004](0004-lightweight-enemies.md)): each clone carries an AnimationController and Animator, and the server sends an animation state, never a clip. Animation assets must belong to the experience owner, so every pack clip is republished once and the ids live in configuration. Every pack is reviewed for scripts before it enters the repository, and checked in as a file.
