#!/usr/bin/env bash
# Publishes a release: commits everything as "v<version>", tags it with a signed tag, builds and notarizes the DMG
# from that tree, validates it, pushes main and the tag, and creates the GitHub release with the DMG and the
# CHANGELOG.md section as its notes (D33).
# Usage: scripts/build_publish.sh. The version is the app's, CFBundleShortVersionString, which Xcode takes from
# MARKETING_VERSION. It asks before it changes anything, and pushes only once the DMG passes scripts/build_validate.sh.
# Needs git with a GPG signing key, gh logged in, and the Release signing in Config/Local.xcconfig. macOS only.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    "") ;;
    -h | --help)
        sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "usage: scripts/build_publish.sh" >&2
        exit 2
        ;;
esac

for tool in git gh xcodebuild; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "error: ${tool} not found" >&2
        exit 1
    fi
done

# What Xcode writes into the app's Info.plist as CFBundleShortVersionString.
version="$(xcodebuild -project NextcloudMailExtension.xcodeproj -target NextcloudMailExtension -configuration Release \
    -showBuildSettings 2> /dev/null | sed -n 's/^ *MARKETING_VERSION = //p')"
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: the app's version is '${version}', expected MAJOR.MINOR.PATCH (MARKETING_VERSION)" >&2
    exit 1
fi
tag="v${version}"

# The section "## [<version>] - <date>" up to the next section or the links at the end. Blank lines are held back
# until more text follows, so none are left around the notes.
notes="$(awk -v heading="## [${version}]" '
    index($0, heading) == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]*\]: /) { exit }
    found && /^[[:space:]]*$/ { if (printed) blank++; next }
    found { while (blank > 0) { print ""; blank-- } print; printed = 1 }
' CHANGELOG.md)"
if [[ -z "${notes}" ]]; then
    echo "error: CHANGELOG.md has no \"## [${version}]\" section with notes. Move Unreleased's changes there first." >&2
    exit 1
fi

if [[ "$(git branch --show-current)" != main ]]; then
    echo "error: not on main" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/${tag}" > /dev/null; then
    echo "error: the tag ${tag} already exists here. Raise MARKETING_VERSION, or delete it: git tag -d ${tag}" >&2
    exit 1
fi
git fetch --quiet origin
if [[ -n "$(git ls-remote --tags origin "refs/tags/${tag}")" ]]; then
    echo "error: the tag ${tag} already exists on GitHub" >&2
    exit 1
fi
if [[ "$(git rev-list --count HEAD..origin/main)" -ne 0 ]]; then
    echo "error: main is behind origin/main. Pull first." >&2
    exit 1
fi
gh auth status > /dev/null

echo "Release ${tag}, with these notes:"
printf '%s\n' "${notes}" | sed 's/^/  | /'
echo
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Changes to commit as \"${tag}\":"
    git status --short
else
    echo "Nothing to commit: the tag goes on the last commit, $(git log -1 --format='%h %s')."
fi
echo "$(git rev-list --count origin/main..HEAD) commit(s) not yet on GitHub, plus any commit above."
echo
read -r -p "Commit, tag, build, notarize, push and publish ${tag}? [y/N] " answer < /dev/tty
if [[ "${answer}" != y && "${answer}" != Y ]]; then
    echo "Nothing changed."
    exit 1
fi

# Until the push, everything is local, and a failure says how to undo the tag.
tagged=no
pushed=no
on_exit() {
    local status=$?
    if [[ ${status} -ne 0 && "${tagged}" == yes && "${pushed}" == no ]]; then
        echo "error: stopped before pushing. The tag ${tag} is only local: git tag -d ${tag}" >&2
    fi
}
trap on_exit EXIT

if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -S -m "${tag}"
    git verify-commit HEAD
fi
git tag -s "${tag}" -m "NextcloudMailExtension ${version}"
tagged=yes
git tag -v "${tag}"

scripts/build_dmg.sh --notarize yes
built="$(unzip -p build/Release/NextcloudMailExtension.app.zip NextcloudMailExtension.app/Contents/Info.plist |
    plutil -extract CFBundleShortVersionString raw -o - -)"
if [[ "${built}" != "${version}" ]]; then
    echo "error: the built app's version is ${built}, not ${version}" >&2
    exit 1
fi
scripts/build_validate.sh

git push origin main
pushed=yes
git push origin "${tag}"
gh release create "${tag}" dmg/NextcloudMailExtension.dmg --verify-tag --title "${tag}" --notes "${notes}"
echo "Published ${tag}"
