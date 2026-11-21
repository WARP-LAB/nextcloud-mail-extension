#!/usr/bin/env bash
# Checks that the release DMG is ready to distribute: that on any Mac, once downloaded, macOS lets the app and its
# Mail extension run, and they can reach their App Group and Keychain item (D33). Prints a PASS or FAIL line for each
# check, and exits non-zero if any fails.
# Usage: scripts/build_validate.sh [path/to/NextcloudMailExtension.dmg], by default dmg/NextcloudMailExtension.dmg.
# Everything is checked from the DMG itself, mounted read-only and hidden, so a DMG downloaded from a GitHub release
# is checked the same way as a fresh build. Gatekeeper may ask Apple's servers about anything without a stapled
# ticket, so run it online. macOS only.
set -euo pipefail

usage() {
    cat << EOF
Usage: scripts/build_validate.sh [path/to/NextcloudMailExtension.dmg]

Checks a DMG made by scripts/build_dmg.sh --notarize yes, by default
dmg/NextcloudMailExtension.dmg, and prints a PASS or FAIL line for each check.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi
# A path given relative to where the script was run from.
dmg="${1:-}"
if [[ -n "${dmg}" && "${dmg}" != /* ]]; then
    dmg="${PWD}/${dmg}"
fi
cd "$(dirname "$0")/.."
dmg="${dmg:-${PWD}/dmg/NextcloudMailExtension.dmg}"
if [[ ! -f "${dmg}" ]]; then
    echo "error: no DMG at ${dmg}. Run scripts/build_dmg.sh --notarize yes first." >&2
    exit 1
fi

app_id=lv.warp.nextcloudmailextension
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The physical path (/private/var/...), as the mount table lists it.
work="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ncme-validate.XXXXXX")" && pwd -P)"
mount_dir="${work}/mnt"
app="${mount_dir}/NextcloudMailExtension.app"
appex="${app}/Contents/PlugIns/NextcloudMailExtensionPlugIn.appex"
mounted=no

# Gatekeeper's checks can register the mounted app, which would then stand in for the installed one (AGENTS.md), so
# it's unregistered before the DMG is detached.
cleanup() {
    if [[ "${mounted}" == yes ]]; then
        pluginkit -r "${appex}" 2> /dev/null || true
        "${lsregister}" -u "${app}" 2> /dev/null || true
        hdiutil detach -quiet "${mount_dir}" || hdiutil detach -quiet -force "${mount_dir}" || true
    fi
    # Never deletes into a volume that's still mounted.
    if ! grep -qF " on ${mount_dir} " <<< "$(mount)"; then
        rm -rf "${work}"
    fi
}
trap cleanup EXIT

passed=0
failed=0
# One signing team per line, which must all be the same.
teams=""

pass() {
    echo "  [PASS] $1"
    passed=$((passed + 1))
}

# fail "label" ["output to show"]
fail() {
    echo "  [FAIL] $1"
    failed=$((failed + 1))
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2" | sed 's/^/         | /'
    fi
}

# check "label" command...: passes when the command exits with 0.
check() {
    local label="$1" out
    shift
    if out="$("$@" 2>&1)"; then
        pass "${label}"
    else
        fail "${label}" "${out}"
    fi
}

# expect "label" "output" "extended regex": passes when the output matches.
expect() {
    if grep -qE "$3" <<< "$2"; then
        pass "$1"
    else
        fail "$1" "$2"
    fi
}

# same "label" "actual" "expected": passes when the two are equal.
same() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1" "expected '$3', found '$2'"
    fi
}

# value "plist text" "key path": one value of a property list, or nothing. Dots inside keys are escaped as \.
value() {
    plutil -extract "$2" raw -o - - <<< "$1" 2> /dev/null || true
}

# code_signature "label" path runtime(yes|no): a valid signature by Developer ID Application with a secure timestamp,
# and the hardened runtime if asked. Records the team.
code_signature() {
    local label="$1" path="$2" runtime="$3" info
    check "${label}: signature valid (strict)" codesign --verify --deep --strict --verbose=2 "${path}"
    info="$(codesign -dvv "${path}" 2>&1 || true)"
    expect "${label}: signed by Developer ID Application" "${info}" '^Authority=Developer ID Application: '
    expect "${label}: secure timestamp" "${info}" '^Timestamp='
    if [[ "${runtime}" == yes ]]; then
        expect "${label}: hardened runtime" "${info}" '^CodeDirectory .*flags=0x[0-9a-f]*\(.*runtime.*\)'
    fi
    teams="${teams}$(sed -n 's/^TeamIdentifier=//p' <<< "${info}")"$'\n'
}

# gatekeeper "label" path spctl-arguments...: Gatekeeper accepts it as notarized Developer ID.
gatekeeper() {
    local label="$1" path="$2" out
    shift 2
    if out="$(spctl --assess "$@" -vv "${path}" 2>&1)" && grep -q '^source=Notarized Developer ID' <<< "${out}"; then
        pass "${label}"
    else
        fail "${label}" "${out}"
    fi
}

# bundle "label" path bundle-id: what macOS checks before it lets a sandboxed bundle with an App Group and a Keychain
# access group run: its entitlements, and a Developer ID profile that allows them and its signing certificate.
bundle() {
    local label="$1" path="$2" bundle_id="$3" info team entitlements group keychain profile profile_keychain
    local leaf certificate index found now
    info="$(codesign -dvv "${path}" 2>&1 || true)"
    team="$(sed -n 's/^TeamIdentifier=//p' <<< "${info}")"
    entitlements="$(codesign -d --entitlements - --xml "${path}" 2> /dev/null || true)"
    same "${label}: bundle ID" "$(value "$(plutil -convert xml1 -o - "${path}/Contents/Info.plist")" \
        CFBundleIdentifier)" "${bundle_id}"
    same "${label}: App Sandbox" "$(value "${entitlements}" 'com\.apple\.security\.app-sandbox')" true
    if [[ "$(value "${entitlements}" 'com\.apple\.security\.get-task-allow')" == true ]]; then
        fail "${label}: no debugging entitlement (get-task-allow)"
    else
        pass "${label}: no debugging entitlement (get-task-allow)"
    fi
    same "${label}: application identifier" "$(value "${entitlements}" 'com\.apple\.application-identifier')" \
        "${team}.${bundle_id}"
    group="$(value "${entitlements}" 'com\.apple\.security\.application-groups.0')"
    same "${label}: App Group named with the signing team" "${group}" "${team}.${app_id}"
    same "${label}: App Group in Info.plist matches the entitlement" \
        "$(/usr/libexec/PlistBuddy -c "Print :NCMEAppGroupIdentifier" "${path}/Contents/Info.plist" 2> /dev/null)" \
        "${group}"
    keychain="$(value "${entitlements}" 'keychain-access-groups.0')"
    same "${label}: Keychain access group" "${keychain}" "${team}.${app_id}"
    if /usr/libexec/PlistBuddy -c "Print :NSLocalNetworkUsageDescription" "${path}/Contents/Info.plist" \
        > /dev/null 2>&1; then
        fail "${label}: no NSLocalNetworkUsageDescription, which makes macOS refuse local servers (D27)"
    else
        pass "${label}: no NSLocalNetworkUsageDescription (D27)"
    fi

    if [[ ! -f "${path}/Contents/embedded.provisionprofile" ]]; then
        fail "${label}: has a provisioning profile, which keychain-access-groups needs"
        return
    fi
    pass "${label}: has a provisioning profile, which keychain-access-groups needs"
    profile="$(security cms -D -i "${path}/Contents/embedded.provisionprofile" 2> /dev/null || true)"
    same "${label}: profile is Developer ID, for every Mac" "$(value "${profile}" ProvisionsAllDevices)" true
    same "${label}: profile's team" "$(value "${profile}" TeamIdentifier.0)" "${team}"
    same "${label}: profile's application identifier" \
        "$(value "${profile}" 'Entitlements.com\.apple\.application-identifier')" "${team}.${bundle_id}"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [[ "$(value "${profile}" ExpirationDate)" > "${now}" ]]; then
        pass "${label}: profile not expired ($(value "${profile}" ExpirationDate))"
    else
        fail "${label}: profile not expired ($(value "${profile}" ExpirationDate))"
    fi
    # The profile allows the team's groups as "<team>.*".
    profile_keychain="$(value "${profile}" 'Entitlements.keychain-access-groups.0')"
    if [[ -n "${keychain}" && ("${profile_keychain}" == "${keychain}" ||
        ("${profile_keychain}" == *'.*' && "${keychain}" == "${profile_keychain%\*}"*)) ]]; then
        pass "${label}: profile allows the Keychain access group"
    else
        fail "${label}: profile allows the Keychain access group" "profile: '${profile_keychain}'"
    fi
    # The certificate that signed the bundle has to be one of the profile's.
    leaf="${work}/${label}-certificate-"
    codesign -d --extract-certificates="${leaf}" "${path}" > /dev/null 2>&1 || true
    found=no
    index=0
    while certificate="$(value "${profile}" "DeveloperCertificates.${index}")" && [[ -n "${certificate}" ]]; do
        if [[ -f "${leaf}0" && "$(base64 -d <<< "${certificate}" | shasum | cut -d ' ' -f 1)" == \
            "$(shasum < "${leaf}0" | cut -d ' ' -f 1)" ]]; then
            found=yes
        fi
        index=$((index + 1))
    done
    same "${label}: profile includes the signing certificate" "${found}" yes
}

echo "Validating ${dmg}"

echo "==> DMG"
check "dmg: checksum intact" hdiutil verify -quiet "${dmg}"
code_signature "dmg" "${dmg}" no
check "dmg: notarization ticket stapled" xcrun stapler validate "${dmg}"
gatekeeper "dmg: Gatekeeper accepts (notarized)" "${dmg}" --type open --context context:primary-signature

if hdiutil attach -nobrowse -noautoopen -readonly -mountpoint "${mount_dir}" "${dmg}" > /dev/null 2>&1; then
    mounted=yes
    pass "dmg: mounts"
else
    fail "dmg: mounts"
fi
if [[ "${mounted}" == yes ]]; then
    if [[ -L "${mount_dir}/Applications" && "$(readlink "${mount_dir}/Applications")" == /Applications ]]; then
        pass "dmg: Applications links to /Applications"
    else
        fail "dmg: Applications links to /Applications"
    fi
fi

if [[ "${mounted}" == yes && -d "${app}" ]]; then
    pass "dmg: contains NextcloudMailExtension.app"
    version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${app}/Contents/Info.plist" \
        2> /dev/null || true)"
    build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${app}/Contents/Info.plist" 2> /dev/null || true)"
    same "dmg: volume named for the version" \
        "$(value "$(diskutil info -plist "${mount_dir}" 2> /dev/null || true)" VolumeName)" \
        "Nextcloud Mail Extension ${version}"

    echo "==> NextcloudMailExtension.app (from the DMG)"
    expect "app: version is MAJOR.MINOR.PATCH (${version})" "${version}" '^[0-9]+\.[0-9]+\.[0-9]+$'
    expect "app: build number is a number (${build})" "${build}" '^[0-9]+$'
    executable="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${app}/Contents/Info.plist" \
        2> /dev/null || true)"
    expect "app: built for Apple silicon" "$(lipo -archs "${app}/Contents/MacOS/${executable}" 2>&1 || true)" \
        '(^| )arm64( |$)'
    code_signature "app" "${app}" yes
    bundle "app" "${app}" "${app_id}"
    check "app: notarization ticket stapled" xcrun stapler validate "${app}"
    gatekeeper "app: Gatekeeper accepts (notarized)" "${app}" --type execute
    if command -v syspolicy_check > /dev/null 2>&1; then
        check "app: Apple's distribution checks (syspolicy_check)" syspolicy_check distribution "${app}"
    fi

    echo "==> NextcloudMailExtensionPlugIn.appex (from the app)"
    if [[ -d "${appex}" ]]; then
        pass "extension: present in the app"
        extension_info="$(plutil -convert xml1 -o - "${appex}/Contents/Info.plist")"
        same "extension: a Mail extension" "$(value "${extension_info}" NSExtension.NSExtensionPointIdentifier)" \
            com.apple.email.extension
        same "extension: same version as the app" "$(value "${extension_info}" CFBundleShortVersionString)" \
            "${version}"
        same "extension: same build number as the app" "$(value "${extension_info}" CFBundleVersion)" "${build}"
        code_signature "extension" "${appex}" yes
        bundle "extension" "${appex}" "${app_id}.extension"
    else
        fail "extension: present in the app"
    fi
else
    fail "dmg: contains NextcloudMailExtension.app"
fi

echo "==> Consistency"
# An unreadable team is an empty line, which fails this too.
unique_teams="$(printf '%s' "${teams}" | sort -u)"
if [[ -n "${unique_teams}" && "$(grep -c '' <<< "${unique_teams}")" -eq 1 ]]; then
    pass "same team everywhere (${unique_teams})"
else
    fail "same team everywhere (found: $(paste -sd ',' - <<< "${unique_teams}"))"
fi

echo
echo "${passed} passed, ${failed} failed"
[[ "${failed}" -eq 0 ]]
