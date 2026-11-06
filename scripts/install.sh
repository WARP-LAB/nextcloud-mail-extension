#!/usr/bin/env bash
# Installs the built app to ~/Applications and registers its Mail extension with macOS.
# Usage: scripts/install.sh [Debug|Release]
# Run scripts/build.sh first. Agents must ask the user before running this (AGENTS.md). Runs on macOS only.
# It installs outside the repository because ~/Downloads, where it may live, is a privacy-protected folder.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"
built="build/${configuration}/NextcloudMailExtension.app"
app="${HOME}/Applications/NextcloudMailExtension.app"

if [[ ! -d "${built}" ]]; then
    echo "error: ${built} doesn't exist. Run scripts/build.sh ${configuration} first." >&2
    exit 1
fi

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

mkdir -p "${HOME}/Applications"
rm -rf "${app}"
ditto "${built}" "${app}"
# ditto keeps the build's dates, and Xcode doesn't change the bundle's own, while macOS's icon cache takes an app with
# the same date as unchanged. Dating the bundle now makes the Dock and Cmd-Tab show a changed icon.
touch "${app}"

# macOS registers the copy Xcode builds, and won't list a second copy with the same bundle ID. Unregister the
# build's copy, so that only the installed one is used.
pluginkit -r "${PWD}/${built}/Contents/PlugIns/NextcloudMailExtensionAppex.appex" 2> /dev/null || true
"${lsregister}" -u "${PWD}/${built}" 2> /dev/null || true
"${lsregister}" -f "${app}"
pluginkit -a "${app}/Contents/PlugIns/NextcloudMailExtensionAppex.appex"

echo "Installed ${app}"
echo "In Mail: Settings > Extensions, enable NextcloudMailExtension, choose it for message security, then restart Mail."
pluginkit -m -p com.apple.email.extension
