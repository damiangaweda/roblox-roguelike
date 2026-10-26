# roblox-roguelike – agent instructions

`CLAUDE.md` imports this file, so Claude Code and Codex read the same instructions; edit this file only.

## What this project is
A multiplayer action roguelite for Roblox: a world generated for each run, aimed combat, builds from perks, alliances and betrayal, extraction with gear at risk. `docs/plan.md` describes the game and its stages; a stage without acceptance criteria is grilled before anything is implemented.

## Language
- Talk to the user in Polish.
- The repository is in English: code, comments, identifiers, commits and documentation. In-game localization is the only place for Polish text.

## The contract
The **contract** is what the user has agreed to, and the only authority on scope:

- `docs/plan.md` – stages with acceptance criteria, open questions, the simplification register (the only place a shortcut is allowed), parking.
- `docs/adr/` – decisions, one file each, cited as `ADR-NNNN`.
- `GLOSSARY.md` – vocabulary, created with the first resolved term.

Agents read it, cite it and propose amendments; only the user changes it. A stage is **done** when its acceptance criteria are met, `make ci` passes, its status in the plan is updated and its PR is merged.

## Read before editing
| When | Read |
|---|---|
| Every repository change | [Workflow](docs/agent/workflow.md): branches, commits, hooks, the gate, PRs, Q&A |
| A task with more than one independent part, or concurrent tasks | [Delegation](docs/agent/delegation.md): the lead, `implementer`, `reviewer`, `investigator` |
| Stage work | The stage in `docs/plan.md`, the ADRs it cites, `GLOSSARY.md` |
| This file, `docs/agent/`, `.claude/agents/`, `.codex/agents/`, `.claude/skills/` | The `writing-for-agents` skill |

## Skills
**Grilling** is how design happens here: rounds of numbered questions, each with a recommended answer, until nothing is left silently assumed. The skills in `.claude/skills/` run it:

- `/grill-me-with-docs` (user-invoked): an idea into a plan stage, ADRs and glossary terms. Propose it whenever a task arrives without a settled stage.
- `grilling`: one open decision stress-tested, docs untouched. Also the format for every question to the user.
- `domain-modeling`: a term coined, challenged or contradicted by code; a decision that meets the skill's three ADR criteria.
- `writing-for-agents`: any document an agent consumes.

## Non-negotiable rules
1. The server is authoritative: damage, loot, currency and progression are decided on the server, which validates every remote; the client asks and renders.
2. Every persisted format (saves, run state) carries a version from day one and changes through numbered migrations.
3. Spawn rates, timers, drop tables and limits are configuration, read from one place.
4. Secrets live outside the repository and outside logs.
5. A recorded decision changes through a new ADR that supersedes it, proposed to the user.

## Stack and layout
Toolchain, gate and Studio use: `ADR-0001`; the rules core: `ADR-0002`. `default.project.json` maps the folders into the place:

- `src/shared/Core/`: the pure rules core. No Roblox API, time or randomness of its own (`make purity`); the adapter passes them in.
- `src/shared/Config.luau`: every gameplay number (rule 3). `src/shared/Protocol.luau`: the wire format; every remote is parsed there.
- `src/server/`, `src/client/`: the engine adapter, verified in Studio through the Studio MCP. Code changes only in files; Rojo syncs them into Studio.
- `tests/`: Lune specs of the core and protocol.

## Commands
`make ci` is the **gate** before a merge; there is no hosted CI. The targets are documented in the `Makefile`; `make setup` and `make hooks` once per clone.

## Conventions
- Conventional Commits 1.0.0-beta.2 subjects (`feat(combat): add dash cooldown`), branches `<type>/<short-kebab-case-description>`, every change on its own branch ending in a PR: [workflow](docs/agent/workflow.md).
- Code and docs use the glossary's terms; a new term goes through `domain-modeling` first.
- A dependency is checked for current version, maintenance and known issues before it is added.

## How we work
- One session = one stage, or a narrower task the user names; a task authorizes only itself.
- The lead (Opus) grills, decides, integrates and reviews; `implementer` (Sonnet) implements bounded units; `reviewer` and `investigator` (Opus) give independent opinions; `make` and hooks check. [Delegation](docs/agent/delegation.md).
- Merging, publishing the game and messaging others need the user's explicit go-ahead, each time.
- A question goes to the user when the contract is silent and the answer changes scope, player-visible behavior, fairness, cost or a hard-to-reverse choice. Minor choices are made and described in the commit body. Ideas outside the task go to the plan's "Parking".
