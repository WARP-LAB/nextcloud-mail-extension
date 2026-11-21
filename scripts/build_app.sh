#!/usr/bin/env bash
# Builds the host app with the extension inside it, into build/<configuration>/NextcloudMailExtension.app.zip, and
# optionally installs it to ~/Applications and registers its Mail extension with macOS (D32).
# Usage: scripts/build_app.sh [--configuration debug|release] [--zip yes|no] [--install yes|no] [extra xcodebuild
# arguments]. Agents must ask the user before installing (AGENTS.md).
# Signing comes from Config/Signing.xcconfig and the git-ignored Config/Local.xcconfig. Runs on macOS only, because
# it needs Xcode. -allowProvisioningUpdates lets Xcode create the provisioning profiles the App Group needs. It
# installs outside the repository because ~/Downloads, where it may live, is a privacy-protected folder.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat << EOF
Usage: scripts/build_app.sh [options] [extra xcodebuild arguments]

Options:
  -c, --configuration <debug|release>  Build configuration (default: release)
  -z, --zip <yes|no>                   Zip the .app bundle after building
                                       and remove the bare bundle (default: yes)
  -i, --install <yes|no>               Install the built app into
                                       ~/Applications (default: no).
                                       Implies zip: the app is installed
                                       from the zip, whatever the zip setting
  -h, --help                           Show this help and exit

Any other arguments are passed through to xcodebuild, for example
CURRENT_PROJECT_VERSION=42. Use -- to pass ones that look like the options above.
EOF
}

# Exits with an error if an option has no value after it.
needs_value() {
    if [[ $2 -lt 2 ]]; then
        echo "error: $1 needs a value ($3)" >&2
        exit 2
    fi
}

configuration=release
zip=yes
install=no
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c | --configuration)
            needs_value "$1" $# "debug or release"
            configuration="$2"
            shift 2
            ;;
        --configuration=?*)
            configuration="${1#*=}"
            shift
            ;;
        -z | --zip)
            needs_value "$1" $# "yes or no"
            zip="$2"
            shift 2
            ;;
        --zip=?*)
            zip="${1#*=}"
            shift
            ;;
        -i | --install)
            needs_value "$1" $# "yes or no"
            install="$2"
            shift 2
            ;;
        --install=?*)
            install="${1#*=}"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done

case "${configuration}" in
    debug | Debug) configuration=Debug ;;
    release | Release) configuration=Release ;;
    *)
        echo "error: unknown configuration '${configuration}' (expected debug or release)" >&2
        exit 2
        ;;
esac
case "${zip}" in
    yes | y | true) zip=yes ;;
    no | n | false) zip=no ;;
    *)
        echo "error: unknown zip value '${zip}' (expected yes or no)" >&2
        exit 2
        ;;
esac
case "${install}" in
    yes | y | true) install=yes ;;
    no | n | false) install=no ;;
    *)
        echo "error: unknown install value '${install}' (expected yes or no)" >&2
        exit 2
        ;;
esac
if [[ "${install}" == yes && "${zip}" == no ]]; then
    echo "note: installing needs the zip, so the build is zipped anyway"
    zip=yes
fi

if ! command -v xcodebuild > /dev/null 2>&1; then
    echo "error: xcodebuild not found. This script needs Xcode, on macOS." >&2
    exit 1
fi
if [[ ! -f Config/Local.xcconfig ]]; then
    echo "warning: no Config/Local.xcconfig, so the build is ad-hoc signed and the App Group won't work" >&2
    echo "         Copy Config/Local.example.xcconfig to Config/Local.xcconfig and fill in DEVELOPMENT_TEAM" >&2
fi

products="build/${configuration}"
zip_file="${products}/NextcloudMailExtension.app.zip"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# A zip from an earlier build would no longer match the build, whether or not this one is zipped.
rm -f "${zip_file}"
xcodebuild -project NextcloudMailExtension.xcodeproj -target NextcloudMailExtension -configuration "${configuration}" \
    SYMROOT="${PWD}/build" -allowProvisioningUpdates "$@" build -quiet

# macOS registers every bare bundle it finds, and an old one with the same bundle ID can stand in for the installed
# app: for its icon, its extension, or its Local Network rule (docs/MAIL.md). So only the installed copy stays a
# bundle. The build is kept as a zip, which ditto makes with the signatures intact, and the bare bundles go.
if [[ "${zip}" == yes ]]; then
    ditto -c -k --keepParent "${products}/NextcloudMailExtension.app" "${zip_file}"
    for bundle in "${products}/NextcloudMailExtension.app" "${products}/NextcloudMailExtensionPlugIn.appex"; do
        pluginkit -r "${PWD}/${bundle}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex" 2> /dev/null || true
        pluginkit -r "${PWD}/${bundle}" 2> /dev/null || true
        "${lsregister}" -u "${PWD}/${bundle}" 2> /dev/null || true
        rm -rf "${bundle}"
    done
    echo "Built ${zip_file}"
else
    echo "Built ${products}/NextcloudMailExtension.app"
    echo "warning: macOS can take this bare bundle for the installed app. Delete it when you're done with it." >&2
fi

if [[ "${install}" == no ]]; then
    exit 0
fi

app="${HOME}/Applications/NextcloudMailExtension.app"
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
ditto -x -k "${zip_file}" "${HOME}/Applications"
# ditto keeps the build's dates, and Xcode doesn't change the bundle's own, while macOS's icon cache takes an app with
# the same date as unchanged. Dating the bundle now makes the Dock and Cmd-Tab show a changed icon.
touch "${app}"

"${lsregister}" -f "${app}"
pluginkit -a "${app}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex"

echo "Installed ${app}"
echo "In Mail: Settings > Extensions, enable NextcloudMailExtension, and choose it in the"
echo "\"Message security extension\" popup if the tab shows one, then restart Mail."
pluginkit -m -p com.apple.email.extension
