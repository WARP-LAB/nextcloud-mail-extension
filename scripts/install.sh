#!/usr/bin/env bash
# Installs the built app to ~/Applications and registers its Mail extension with macOS.
# Usage: scripts/install.sh [Debug|Release]
# Run scripts/build.sh first. Agents must ask the user before running this (AGENTS.md). Runs on macOS only.
# It installs outside the repository because ~/Downloads, where it may live, is a privacy-protected folder.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"
zip="build/${configuration}/NextcloudMailExtension.app.zip"
app="${HOME}/Applications/NextcloudMailExtension.app"

if [[ ! -f "${zip}" ]]; then
    echo "error: ${zip} doesn't exist. Run scripts/build.sh ${configuration} first." >&2
    exit 1
fi

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# The build is a zip, so that this is the only bare copy of the app on disk (scripts/build.sh).
mkdir -p "${HOME}/Applications"
# Unregister the old copy's plug-ins before deleting it, so that macOS doesn't keep a registration whose files are
# gone, which it can confuse with the new copy (AGENTS.md).
for plugin in "${app}"/Contents/PlugIns/*.appex; do
    if [[ -d "${plugin}" ]]; then
        pluginkit -r "${plugin}" 2> /dev/null || true
        "${lsregister}" -u "${plugin}" 2> /dev/null || true
    fi
done
rm -rf "${app}"
ditto -x -k "${zip}" "${HOME}/Applications"
# ditto keeps the build's dates, and Xcode doesn't change the bundle's own, while macOS's icon cache takes an app with
# the same date as unchanged. Dating the bundle now makes the Dock and Cmd-Tab show a changed icon.
touch "${app}"

"${lsregister}" -f "${app}"
pluginkit -a "${app}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex"

echo "Installed ${app}"
echo "In Mail: Settings > Extensions, enable NextcloudMailExtension, choose it for message security, then restart Mail."
pluginkit -m -p com.apple.email.extension
