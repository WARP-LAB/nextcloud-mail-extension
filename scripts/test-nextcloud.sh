#!/usr/bin/env bash
# Runs the Nextcloud server tests, tests/NextcloudServerTests, against the test server in .env (D14).
# Usage: scripts/test-nextcloud.sh [--server-settings] [more swift test options]
# Each test uploads into its own folder inside NCME_TEST_DIRECTORY and deletes it. With --server-settings, it runs
# only the tests that switch on an enforced expiry maximum and enforced passwords for the whole server, and switch
# them back off afterwards (D18). Needs Swift, so macOS with Xcode.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

filter=NextcloudServerTests
if [[ "${1:-}" == "--server-settings" ]]; then
    shift
    filter=ServerSettingsTests
    export NCME_TEST_CHANGE_SERVER_SETTINGS=1
fi
if [[ ! -f "${root}/.env" ]]; then
    echo "error: no .env. Copy .env.example to .env and fill it in." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "${root}/.env"
set +a

exec swift test --package-path "${root}" --filter "${filter}" "$@"
