#!/usr/bin/env bash
# Runs the Nextcloud server tests, tests/NextcloudServerTests, against the test server in .env (D14).
# Usage: scripts/test-nextcloud.sh [more swift test options]
# Each test uploads into its own folder inside NCAM_TEST_DIRECTORY and deletes it. Needs Swift, so macOS with Xcode.
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

exec swift test --package-path "${root}" --filter NextcloudServerTests "$@"
