#!/usr/bin/env bash
# Builds MailProbe, installs it to ~/Applications and registers the extension with macOS.
# It installs outside the project because ~/Downloads is a privacy-protected folder.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/MailProbe.app"

xcodebuild -project MailProbe.xcodeproj -target MailProbe -configuration Debug SYMROOT="$PWD/build" build -quiet

mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto build/Debug/MailProbe.app "$APP"
pluginkit -a "$APP/Contents/PlugIns/MailProbeExtension.appex"

echo "Installed $APP"
pluginkit -m -p com.apple.email.extension
