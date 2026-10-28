# Enemies are generated meshes without rigs

**Status:** proposed on 2026-10-28; once accepted it supersedes [ADR-0010](0010-rigs-from-a-store-pack-first.md).

ADR-0010 chose a store pack of rigged monsters first and generated creatures later, because nothing generated could be rigged or animated. Since then the map's props, the shrines and the chest became meshes generated with the Studio MCP and the user judged them the fastest way to a game that looks made, and asked for enemies the same way. Every enemy kind is now a generated, unrigged mesh drawn by the client at its scale; movement, attacks, telegraphs and deaths are shown by moving, tilting, scaling and fading the whole mesh and by the rings, lights and particles the effects already draw. We chose this over the store pack because the pack never got republished and its twenty monsters would not match the forest's own kinds, and over rigged generated creatures because rigging and animating twenty-five kinds is the art stage's work and the fight reads from silhouettes and telegraphs, not from limbs.

## Considered options

- **The store pack** (ADR-0010): twenty generic monsters, a republish that never happened.
- **Rigged, animated generated creatures (Meshy, Tripo):** a subscription and weeks of animation before the loop is settled.
- **Keeping the part silhouettes:** what the user called plasticine.

## Consequences

Enemy kinds become data with a mesh each; adding a kind means a prompt and a config line. Animation stays procedural (bob, lean, lunge, fall), which the client does for every enemy in one place. A later art stage may replace the meshes with rigged ones without touching the rules.
