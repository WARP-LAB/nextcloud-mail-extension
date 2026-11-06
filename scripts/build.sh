#!/usr/bin/env bash
# Builds the host app with the extension inside it, into build/<configuration>/NextcloudAppleMail.app.
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
fi

xcodebuild -project NextcloudAppleMail.xcodeproj -target NextcloudAppleMail -configuration "${configuration}" \
    SYMROOT="${PWD}/build" -allowProvisioningUpdates build -quiet

echo "Built build/${configuration}/NextcloudAppleMail.app"
