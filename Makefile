# Run from the repository root. `make ci` is the gate before a merge; there is
# no hosted CI. `make setup` needs the network once per clone; `make ci` does
# not (ADR-0001).

# Rokit's shims run the versions pinned in rokit.toml. Called by path, since a
# shell may not have them on PATH yet and macOS make ignores an exported PATH.
TOOLS := $(HOME)/.rokit/bin

LUAU_LSP_VERSION := 1.70.1
DEFINITIONS := .cache/globalTypes-$(LUAU_LSP_VERSION).d.luau

.PHONY: ci commits setup hooks fmt fmt-check lint types purity compile test build serve

## Every check a pull request needs before a merge.
ci: commits fmt-check lint types purity compile test build

## Commit subjects on this branch since it left origin/main.
commits:
	scripts/check-commit-msg.sh --range "$$(git merge-base origin/main HEAD)" HEAD

## Install the pinned tools and fetch what the offline checks read.
setup:
	$(TOOLS)/rokit install --no-trust-check
	mkdir -p .cache
	curl -fsSL -o $(DEFINITIONS) \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$(LUAU_LSP_VERSION)/scripts/globalTypes.d.luau
	$(TOOLS)/selene generate-roblox-std

## Enable the repository's Git hooks in this clone.
hooks:
	git config core.hooksPath .githooks

## Format the sources in place.
fmt:
	$(TOOLS)/stylua src tests scripts

fmt-check:
	$(TOOLS)/stylua --check src tests scripts

lint:
	$(TOOLS)/selene src tests scripts

## Strict type check of the game's sources against the Roblox API.
types:
	$(TOOLS)/rojo sourcemap default.project.json --output sourcemap.json
	$(TOOLS)/luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
		--definitions=@roblox=$(DEFINITIONS) src

## The rules core must not touch the Roblox API (ADR-0002).
purity:
	scripts/check-core-purity.sh $(TOOLS)/luau-lsp

## Every source compiles under Luau's compiler (Studio's limits, e.g. 200 locals).
compile:
	$(TOOLS)/lune run scripts/check-compile src tests

## Core tests under Lune; `make test FILTER=perk` runs the matching ones.
test:
	$(TOOLS)/lune run tests/runner $(FILTER)

## Build the place file from the sources.
build:
	mkdir -p build
	$(TOOLS)/rojo build default.project.json --output build/roguelike.rbxl

## Serve the sources to Studio's Rojo plugin while developing.
serve:
	$(TOOLS)/rojo serve default.project.json
