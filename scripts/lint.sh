#!/usr/bin/env bash
# Runs the repository's linters on every file git tracks or would track, so anything .gitignore excludes is skipped.
# Usage: scripts/lint.sh [--fix]
#   --fix  apply the automatic fixes of swift-format, SwiftLint and markdownlint-cli2 first, then lint
# Exits non-zero if any linter reports a problem or is missing. See docs/TESTING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

fix=0
case "${1:-}" in
    --fix) fix=1 ;;
    "") ;;
    *)
        echo "usage: scripts/lint.sh [--fix]" >&2
        exit 2
        ;;
esac

failed=0
swift_specs="*.swift :!probe/"

# Prints the files matching the space-separated git pathspecs in $1, NUL-separated.
files() {
    local -a specs
    read -r -a specs <<< "$1"
    git ls-files -z --cached --others --exclude-standard -- "${specs[@]}"
}

# Prints how many files match the git pathspecs in $1.
count() {
    echo $(($(files "$1" | tr -cd '\0' | wc -c)))
}

# Runs a command, in batches, on the files matching the git pathspecs in $1.
on_files() {
    local pathspecs=$1
    shift
    files "${pathspecs}" | xargs -0 "$@"
}

# Runs markdownlint-cli2 on the Markdown files. The ":" prefix makes it read each path literally, not as a glob.
markdownlint_files() {
    files "*.md" | xargs -0 printf ':%s\0' | xargs -0 markdownlint-cli2 "$@"
}

# Succeeds if command $1 is available, and otherwise reports it as missing, with install hint $2.
need() {
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi
    echo "error: $1 is not installed. Install it with: $2" >&2
    failed=1
    return 1
}

# Runs a linter, and records a failure without stopping the other linters.
run() {
    if ! "$@"; then
        failed=1
    fi
}

swift_files=$(count "${swift_specs}")
if ((swift_files == 0)); then
    echo "== Swift: no files, skipped"
else
    if command -v xcrun > /dev/null 2>&1 && xcrun --find swift-format > /dev/null 2>&1; then
        echo "== Swift layout (swift-format): ${swift_files} files"
        if ((fix)); then
            run on_files "${swift_specs}" xcrun swift-format format --in-place
        fi
        run on_files "${swift_specs}" xcrun swift-format lint --strict
    elif need swift-format "Xcode on macOS, or the Swift toolchain on Linux"; then
        echo "== Swift layout (swift-format): ${swift_files} files"
        if ((fix)); then
            run on_files "${swift_specs}" swift-format format --in-place
        fi
        run on_files "${swift_specs}" swift-format lint --strict
    fi
    if need swiftlint "brew install swiftlint"; then
        echo "== Swift code quality (SwiftLint): ${swift_files} files"
        if ((fix)); then
            run on_files "${swift_specs}" swiftlint --fix --quiet
        fi
        run on_files "${swift_specs}" swiftlint lint --strict --quiet
    fi
fi

shell_files=$(count "*.sh")
if ((shell_files == 0)); then
    echo "== Bash: no files, skipped"
elif need shellcheck "brew install shellcheck"; then
    echo "== Bash (ShellCheck): ${shell_files} files"
    run on_files "*.sh" shellcheck
fi

markdown_files=$(count "*.md")
if ((markdown_files == 0)); then
    echo "== Markdown: no files, skipped"
elif need markdownlint-cli2 "brew install markdownlint-cli2"; then
    echo "== Markdown (markdownlint-cli2): ${markdown_files} files"
    if ((fix)); then
        run markdownlint_files --fix
    else
        run markdownlint_files
    fi
fi

if ((failed)); then
    echo "lint: problems found" >&2
    exit 1
fi
echo "lint: all clean"
