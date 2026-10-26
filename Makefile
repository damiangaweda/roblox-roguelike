# Run from the repository root. `make ci` is the gate before a merge; there is
# no hosted CI.

.PHONY: ci commits hooks

## Every check a pull request needs before a merge. Add the project's own
## checks (lint, tests, build) as targets here and list them after `commits`.
ci: commits

## Commit subjects on this branch since it left origin/main.
commits:
	scripts/check-commit-msg.sh --range "$$(git merge-base origin/main HEAD)" HEAD

## Enable the repository's Git hooks in this clone.
hooks:
	git config core.hooksPath .githooks
