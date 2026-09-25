#!/usr/bin/env bash
# Type-checks all Luau source against the Roblox API with luau-lsp.
# src/server and src/client are strict (see their .luaurc); src/shared is nonstrict and is
# exercised behaviourally by the Lune test suite.
set -euo pipefail

LUAU_LSP_VERSION="1.70.0"
DEFINITIONS_DIR=".luau-lsp"
DEFINITIONS="${DEFINITIONS_DIR}/globalTypes-${LUAU_LSP_VERSION}.d.luau"

cd "$(dirname "$0")/.."

if [ ! -f "${DEFINITIONS}" ]; then
    mkdir -p "${DEFINITIONS_DIR}"
    # Download to a temporary file so a failed download never leaves a partial cache.
    partial="$(mktemp "${DEFINITIONS_DIR}/download.XXXXXX")"
    trap 'rm -f "${partial}"' EXIT
    curl --fail --silent --show-error --location \
        "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.d.luau" \
        --output "${partial}"
    mv "${partial}" "${DEFINITIONS}"
fi

rojo sourcemap default.project.json --output sourcemap.json
luau-lsp analyze \
    --platform=roblox \
    --definitions=@roblox="${DEFINITIONS}" \
    --sourcemap=sourcemap.json \
    src
