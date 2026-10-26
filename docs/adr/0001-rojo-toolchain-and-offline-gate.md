# Rojo toolchain and an offline gate

The place is built from files in Git with Rojo 7.7, with every tool pinned per repository by Rokit, packages from Wally, StyLua for formatting, Selene for linting and `luau-lsp analyze` for strict types. `make ci` runs offline: it needs neither Roblox Studio nor network access, because macOS has no headless Studio and engine tests in the cloud need a secret, a test place and rate limits.

## Considered options

- **Aftman** instead of Rokit: archived. **Foreman**: maintained, but Rojo's own docs point to Rokit.
- **pesde** instead of Wally: very active but still before 1.0; revisit after 1.0.
- **Studio Script Sync** instead of Rojo: syncs scripts only, not the whole place.
- **Engine tests through Open Cloud Luau Execution** in the gate from the start: deferred until the engine adapter grows (remotes, DataStores), then added as a separate `make test-cloud`.

## Studio MCP verifies, files stay the source

Roblox Studio's built-in MCP server lets an agent start and stop playtests, run Luau on the server or client, read the output log, capture the screen and simulate input. Agents use it to check the engine adapter against a stage's acceptance criteria, not to change the place: code changes only in files, which Rojo syncs into Studio, and the MCP's script editing and asset insertion are not used. It needs an open Studio, so it stays outside `make ci`.

## Consequences

Game rules must be testable without the engine, which is why they live in a pure core ([ADR-0002](0002-pure-rules-core.md)). The engine adapter is checked in Studio, by an agent through the Studio MCP or by hand, against the stage's acceptance criteria until `make test-cloud` exists.
