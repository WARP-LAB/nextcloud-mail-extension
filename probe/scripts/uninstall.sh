#!/usr/bin/env bash
# Removes MailProbe from macOS, including its logs and message dumps.
set -euo pipefail

APP="$HOME/Applications/MailProbe.app"

if [ -d "$APP" ]; then
    pluginkit -r "$APP/Contents/PlugIns/MailProbeExtension.appex" || true
    rm -rf "$APP"
fi
rm -rf "$HOME/Library/Containers/lv.warp.mailprobe.extension" "$HOME/Library/Containers/lv.warp.mailprobe"

echo "MailProbe removed. Restart Mail if it is running."
