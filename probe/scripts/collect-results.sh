#!/usr/bin/env bash
# Copies the extension's events and message dumps, plus recent system log lines, into test-results/.
# Usage: collect-results.sh [--clear] [log window, default 3h]
#   --clear  empties the extension's data folder after copying, ready for the next round
set -euo pipefail
cd "$(dirname "$0")/.."

CLEAR=0
if [ "${1:-}" = "--clear" ]; then
    CLEAR=1
    shift
fi
WINDOW="${1:-3h}"

SOURCE="$HOME/Library/Containers/lv.warp.mailprobe.extension/Data/Library/Application Support/MailProbe"
OUTPUT="test-results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT"

if [ -d "$SOURCE" ]; then
    cp -R "$SOURCE/." "$OUTPUT/"
else
    echo "No extension data yet at: $SOURCE"
fi

log show --last "$WINDOW" --info --style compact --predicate \
    'subsystem == "lv.warp.mailprobe" OR (process == "Mail" AND (composedMessage CONTAINS "Encoding message" OR composedMessage CONTAINS[c] "mailprobe"))' \
    > "$OUTPUT/system.log" || echo "Could not read the system log"
pluginkit -m -p com.apple.email.extension > "$OUTPUT/pluginkit.txt" || true

if [ "$CLEAR" = 1 ] && [ -d "$SOURCE" ]; then
    find "$SOURCE" -mindepth 1 -delete
fi

echo "Collected into $OUTPUT"
ls -la "$OUTPUT"
