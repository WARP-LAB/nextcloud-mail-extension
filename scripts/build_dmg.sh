#!/usr/bin/env bash
# Builds the Release app with scripts/build_app.sh and packs it into dmg/NextcloudMailExtension.dmg, whose volume is
# named "Nextcloud Mail Extension <version>", optionally signed and notarized for distribution (D33).
# Usage: scripts/build_dmg.sh [--sign yes|no] [--notarize yes|no] [extra xcodebuild arguments]
# Signing comes from the Release settings in Config/Local.xcconfig, and the DMG is signed with the identity that
# signed the app. Notarizing uploads the app and the DMG to Apple. No bare app bundle is left behind. macOS only.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    cat << EOF
Usage: scripts/build_dmg.sh [options] [extra xcodebuild arguments]

Builds dmg/NextcloudMailExtension.dmg from a Release build.

Options:
  -s, --sign <yes|no>       Check that the app is signed for distribution,
                            and sign the DMG (default: no). Needs the Release
                            signing in Config/Local.xcconfig
  -n, --notarize <yes|no>   Notarize and staple the app and the DMG
                            (default: no). Implies sign. Needs NOTARY_PROFILE
  -h, --help                Show this help and exit

Any other arguments are passed through to xcodebuild. Use -- to pass ones
that look like the options above.
EOF
}

# Exits with an error if an option has no value after it.
needs_value() {
    if [[ $2 -lt 2 ]]; then
        echo "error: $1 needs a value (yes or no)" >&2
        exit 2
    fi
}

sign=no
notarize=no
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s | --sign)
            needs_value "$1" $#
            sign="$2"
            shift 2
            ;;
        --sign=?*)
            sign="${1#*=}"
            shift
            ;;
        -n | --notarize)
            needs_value "$1" $#
            notarize="$2"
            shift 2
            ;;
        --notarize=?*)
            notarize="${1#*=}"
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

case "${sign}" in
    yes | y | true) sign=yes ;;
    no | n | false) sign=no ;;
    *)
        echo "error: unknown sign value '${sign}' (expected yes or no)" >&2
        exit 2
        ;;
esac
case "${notarize}" in
    yes | y | true) notarize=yes ;;
    no | n | false) notarize=no ;;
    *)
        echo "error: unknown notarize value '${notarize}' (expected yes or no)" >&2
        exit 2
        ;;
esac
if [[ "${notarize}" == yes && "${sign}" == no ]]; then
    echo "note: notarizing needs signing, so the DMG is signed anyway"
    sign=yes
fi

# Settings Xcode ignores, such as NOTARY_PROFILE, are read the way Xcode reads Config/Local.xcconfig. The
# environment overrides them.
notary_profile="${NOTARY_PROFILE:-}"
if [[ "${notarize}" == yes && -z "${notary_profile}" ]]; then
    notary_profile="$(xcodebuild -project NextcloudMailExtension.xcodeproj -target NextcloudMailExtension \
        -configuration Release -showBuildSettings 2> /dev/null | sed -n 's/^ *NOTARY_PROFILE = //p')"
    if [[ -z "${notary_profile}" ]]; then
        echo "error: no NOTARY_PROFILE in Config/Local.xcconfig or the environment (Config/Local.example.xcconfig)" >&2
        exit 1
    fi
fi

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
zip_file="build/Release/NextcloudMailExtension.app.zip"
dmg_file="dmg/NextcloudMailExtension.dmg"
mkdir -p build
staging="$(mktemp -d "${PWD}/build/dmg.XXXXXX")"
app="${staging}/root/NextcloudMailExtension.app"

# The app is a bare bundle only inside the staging folder, and only while the DMG is made. Unregistering it first
# keeps macOS from taking it for the installed app afterwards (AGENTS.md).
cleanup() {
    if [[ -d "${app}" ]]; then
        pluginkit -r "${app}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex" 2> /dev/null || true
        pluginkit -r "${app}" 2> /dev/null || true
        "${lsregister}" -u "${app}" 2> /dev/null || true
    fi
    rm -rf "${staging}"
}
trap cleanup EXIT

# Exits with an error unless a bundle is signed for distribution outside the App Store: Developer ID, hardened
# runtime, a secure timestamp, no debugging entitlement, and a Developer ID profile where an entitlement needs one.
check_signature() {
    local bundle="$1" details entitlements profile
    details="$(codesign -d --verbose=2 "${bundle}" 2>&1)" || {
        echo "error: ${bundle##*/} isn't signed" >&2
        exit 1
    }
    if ! grep -q '^Authority=Developer ID Application:' <<< "${details}"; then
        echo "error: ${bundle##*/} isn't signed with a Developer ID Application identity. Set the Release signing" >&2
        echo "       in Config/Local.xcconfig (Config/Local.example.xcconfig)." >&2
        exit 1
    fi
    if ! grep -q '^CodeDirectory .*flags=.*runtime' <<< "${details}"; then
        echo "error: ${bundle##*/} doesn't have the hardened runtime (ENABLE_HARDENED_RUNTIME)" >&2
        exit 1
    fi
    if ! grep -q '^Timestamp=' <<< "${details}"; then
        echo "error: ${bundle##*/} has no secure timestamp (OTHER_CODE_SIGN_FLAGS = --timestamp)" >&2
        exit 1
    fi
    entitlements="$(codesign -d --entitlements - --xml "${bundle}" 2> /dev/null || true)"
    if grep -q 'com.apple.security.get-task-allow' <<< "${entitlements}"; then
        echo "error: ${bundle##*/} has the debugging entitlement get-task-allow" >&2
        exit 1
    fi
    if grep -q 'keychain-access-groups' <<< "${entitlements}"; then
        profile="${bundle}/Contents/embedded.provisionprofile"
        if [[ ! -f "${profile}" ]] ||
            [[ "$(security cms -D -i "${profile}" 2> /dev/null |
                plutil -extract ProvisionsAllDevices raw -o - - 2> /dev/null)" != true ]]; then
            echo "error: ${bundle##*/} needs a Developer ID provisioning profile for keychain-access-groups" >&2
            exit 1
        fi
    fi
}

# Uploads a file to Apple's notary service, waits for the result, and exits with Apple's log unless it's accepted.
notarize_file() {
    local file="$1" result id status
    echo "Notarizing ${file##*/}, which takes a few minutes"
    result="$(xcrun notarytool submit "${file}" --keychain-profile "${notary_profile}" --wait \
        --output-format json)" || true
    id="$(plutil -extract id raw -o - - <<< "${result}" 2> /dev/null || true)"
    status="$(plutil -extract status raw -o - - <<< "${result}" 2> /dev/null || true)"
    if [[ "${status}" != Accepted ]]; then
        echo "error: notarization of ${file##*/} ended with '${status:-no result}'" >&2
        if [[ -n "${id}" ]]; then
            xcrun notarytool log "${id}" --keychain-profile "${notary_profile}" >&2 || true
        fi
        exit 1
    fi
}

# Passes the extra arguments after --, so that build_app.sh hands all of them to xcodebuild.
scripts/build_app.sh --configuration release --zip yes --install no -- "$@"

mkdir -p "${staging}/root"
ditto -x -k "${zip_file}" "${staging}/root"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app}/Contents/Info.plist")"
volume="Nextcloud Mail Extension ${version}"

identity=""
if [[ "${sign}" == yes ]]; then
    check_signature "${app}"
    check_signature "${app}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex"
    codesign --verify --deep --strict "${app}"
    identity="$(codesign -d --verbose=2 "${app}" 2>&1 | sed -n 's/^Authority=//p' | sed -n 1p)"
fi

# The app's own ticket lets it open without a network check after it's copied out of the DMG.
if [[ "${notarize}" == yes ]]; then
    ditto -c -k --keepParent "${app}" "${staging}/NextcloudMailExtension.app.zip"
    notarize_file "${staging}/NextcloudMailExtension.app.zip"
    xcrun stapler staple -q "${app}"
    spctl --assess --type execute "${app}"
fi

ln -s /Applications "${staging}/root/Applications"
mkdir -p dmg
rm -f "${dmg_file}"
hdiutil create -volname "${volume}" -srcfolder "${staging}/root" -format UDZO -quiet "${dmg_file}"

if [[ "${sign}" == yes ]]; then
    codesign --sign "${identity}" --timestamp "${dmg_file}"
    codesign --verify --strict "${dmg_file}"
fi
if [[ "${notarize}" == yes ]]; then
    notarize_file "${dmg_file}"
    xcrun stapler staple -q "${dmg_file}"
    spctl --assess --type open --context context:primary-signature "${dmg_file}"
fi

state="not signed"
if [[ "${notarize}" == yes ]]; then
    state="signed and notarized"
elif [[ "${sign}" == yes ]]; then
    state="signed, not notarized"
fi
echo "Built ${dmg_file}, volume \"${volume}\", ${state}"
