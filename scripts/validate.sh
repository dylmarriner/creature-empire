#!/usr/bin/env bash
# Runs every CI check locally: formatting, lint, type-check, tests and the Rojo build.
# Needs the Rokit-pinned tools on PATH (`rokit install`). Costs nothing to run.
set -euo pipefail

cd "$(dirname "$0")/.."

step() {
    printf '\n==> %s\n' "$1"
}

step "Formatting (stylua)"
stylua --check src tests scripts

step "Lint (selene)"
selene src tests scripts

step "Type-check against the Roblox API (luau-lsp)"
./scripts/typecheck.sh

step "Tests (lune)"
lune run tests/run

step "Place build (rojo)"
build_output="$(mktemp -d)/CreatureEmpire.rbxlx"
rojo build default.project.json --output "${build_output}"

printf '\nAll checks passed.\n'
