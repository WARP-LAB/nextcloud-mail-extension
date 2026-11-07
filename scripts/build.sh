#!/usr/bin/env bash
# Builds the host app with the extension inside it, into build/<configuration>/NextcloudMailExtension.app.zip.
# Usage: scripts/build.sh [Debug|Release]
# Signing comes from Config/Signing.xcconfig and the git-ignored Config/Local.xcconfig. Runs on macOS only, because
# it needs Xcode. -allowProvisioningUpdates lets Xcode create the provisioning profiles the App Group needs.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-Debug}"
case "${configuration}" in
    Debug | Release) ;;
    *)
        echo "usage: scripts/build.sh [Debug|Release]" >&2
        exit 2
        ;;
esac

if ! command -v xcodebuild > /dev/null 2>&1; then
    echo "error: xcodebuild not found. This script needs Xcode, on macOS." >&2
    exit 1
fi
if [[ ! -f Config/Local.xcconfig ]]; then
    echo "warning: no Config/Local.xcconfig, so the build is ad-hoc signed and the App Group won't work" >&2
    echo "         Copy Config/Local.example.xcconfig to Config/Local.xcconfig and fill in DEVELOPMENT_TEAM" >&2
fi

xcodebuild -project NextcloudMailExtension.xcodeproj -target NextcloudMailExtension -configuration "${configuration}" \
    SYMROOT="${PWD}/build" -allowProvisioningUpdates build -quiet

# macOS registers every bare bundle it finds, and an old one with the same bundle ID can stand in for the installed
# app: for its icon, its extension, or its Local Network rule (docs/MAIL.md). So only the installed copy stays a
# bundle. The build is kept as a zip, which ditto makes with the signatures intact, and the bare bundles go.
products="build/${configuration}"
zip="${products}/NextcloudMailExtension.app.zip"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
rm -f "${zip}"
ditto -c -k --keepParent "${products}/NextcloudMailExtension.app" "${zip}"
for bundle in "${products}/NextcloudMailExtension.app" "${products}/NextcloudMailExtensionPlugIn.appex"; do
    pluginkit -r "${PWD}/${bundle}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex" 2> /dev/null || true
    pluginkit -r "${PWD}/${bundle}" 2> /dev/null || true
    "${lsregister}" -u "${PWD}/${bundle}" 2> /dev/null || true
    rm -rf "${bundle}"
done

echo "Built ${zip}"
