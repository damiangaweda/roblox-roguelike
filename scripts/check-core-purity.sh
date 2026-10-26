#!/bin/sh
# Fails when the pure rules core (src/shared/Core) touches the Roblox API
# (ADR-0002). Matches globals and services, not words inside comments.
set -eu

core=src/shared/Core
globals='game|workspace|script|Instance|Vector3|Vector2|CFrame|Enum|task|tick|time|wait|delay|spawn|Random|Color3|UDim2|TweenInfo|RaycastParams|DateTime|os'
pattern="(^|[^A-Za-z0-9_.\"])($globals)([.(]|:[A-Za-z])"

if grep -nE "$pattern" "$core"/*.luau | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--'; then
  echo "the core must not use the Roblox API or read time or randomness itself (ADR-0002)" >&2
  exit 1
fi
