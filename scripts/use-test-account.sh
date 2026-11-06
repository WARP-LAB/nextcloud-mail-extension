#!/usr/bin/env bash
# Logs the installed app in to the test server in .env with a new app password, instead of the browser login, and
# sets the upload directory to NCAM_TEST_DIRECTORY, so that the extension in Mail uploads there (D14).
# Usage: scripts/use-test-account.sh [--log-out]. --log-out revokes the app password and deletes it again.
# Needs a Debug build installed by scripts/install.sh, since Release builds leave these options out. macOS only.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="${HOME}/Applications/NextcloudAppleMail.app/Contents/MacOS/NextcloudAppleMail"

case "${1:-}" in
    "") option=--use-test-account ;;
    --log-out) option=--log-out ;;
    *)
        echo "usage: scripts/use-test-account.sh [--log-out]" >&2
        exit 2
        ;;
esac
if [[ ! -x "${app}" ]]; then
    echo "error: ${app} isn't installed. Run scripts/build.sh and scripts/install.sh first." >&2
    exit 1
fi
if [[ ! -f "${root}/.env" ]]; then
    echo "error: no .env. Copy .env.example to .env and fill it in." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "${root}/.env"
set +a

exec "${app}" "${option}"
