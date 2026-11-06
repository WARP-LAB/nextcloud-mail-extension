#!/usr/bin/env bash
# Runs the Nextcloud command-line tool, tools/ncam-nextcloud, against the test server in .env (D14).
# Usage: scripts/nextcloud.sh <command> [arguments], or with no command for the list.
# Needs Swift, so macOS with Xcode. Relative file arguments are relative to the current directory.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "${root}/.env" ]]; then
    echo "error: no .env. Copy .env.example to .env and fill it in." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "${root}/.env"
set +a

exec swift run --quiet --package-path "${root}" ncam-nextcloud "$@"
