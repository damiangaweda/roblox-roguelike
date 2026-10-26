#!/bin/sh
# Fails when the pure rules core (src/shared/Core) touches the Roblox API or
# reads time or randomness itself (ADR-0002).
#   check-core-purity.sh [luau-lsp]
set -eu

core=src/shared/Core
luau_lsp="${1:-luau-lsp}"

# Type-checked without the Roblox definitions, any Roblox global is unknown.
"$luau_lsp" analyze --platform=standard "$core"

# Standard Luau still has its own clock and random numbers.
if grep -nE '(^|[^A-Za-z0-9_])(math\.random|os\.)' "$core"/*.luau | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--'; then
  echo "the core must not read time or randomness itself; the adapter passes them in (ADR-0002)" >&2
  exit 1
fi
