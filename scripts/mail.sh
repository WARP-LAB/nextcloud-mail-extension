#!/usr/bin/env bash
# Drives Apple Mail with AppleScript for the Mail checks, between the two accounts in .env (docs/TESTING.md,
# "Driving Mail from the command line"). Their addresses stay in .env.
# Usage:
#   scripts/mail.sh send <A|B> <A|B> <subject> <body> <signature|none> [file ...]
#   scripts/mail.sh fetch <inbox|sent> <subject> <output file> [seconds to wait, default 240]
#   scripts/mail.sh respond <reply|forward> <subject> <forward to: A|B> [file ...]   for a message in the inboxes
#   scripts/mail.sh app <option> [argument]   the installed Debug build's options, such as --settings or --debug-dumps
# macOS only. The terminal's app needs the permissions listed in docs/TESTING.md.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="${HOME}/Applications/NextcloudAppleMail.app/Contents/MacOS/NextcloudAppleMail"

usage() {
    sed -n '4,8p' "$0" | sed 's/^# //' >&2
    exit 2
}

if [[ ! -f "${root}/.env" ]]; then
    echo "error: no .env. Copy .env.example to .env and fill it in." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. "${root}/.env"
set +a

address() {
    case "$1" in
        A) printf '%s' "${NCAM_MAIL_A_ADDRESS:?NCAM_MAIL_A_ADDRESS is not set in .env}" ;;
        B) printf '%s' "${NCAM_MAIL_B_ADDRESS:?NCAM_MAIL_B_ADDRESS is not set in .env}" ;;
        *) usage ;;
    esac
}

command="${1:-}"
[[ $# -gt 0 ]] && shift
case "${command}" in
    send)
        [[ $# -ge 5 ]] || usage
        from="$(address "$1")"
        to="$(address "$2")"
        shift 2
        osascript "${root}/scripts/mail/send.applescript" "${from}" "${to}" "$@" > /dev/null
        ;;
    fetch)
        [[ $# -ge 3 ]] || usage
        wait="${4:-240}"
        start="$(date +%s)"
        while true; do
            source="$(osascript "${root}/scripts/mail/fetch.applescript" "$1" "$2")"
            if [[ -n "${source}" ]]; then
                printf '%s' "${source}" > "$3"
                exit 0
            fi
            if (($(date +%s) - start >= wait)); then
                echo "error: no message with the subject \"$2\" in $1 after ${wait} seconds" >&2
                exit 1
            fi
            sleep 5
        done
        ;;
    respond)
        [[ $# -ge 3 ]] || usage
        action="$1"
        subject="$2"
        to="$(address "$3")"
        shift 3
        osascript "${root}/scripts/mail/respond.applescript" "${action}" "${subject}" "${to}" "$@" > /dev/null
        ;;
    app)
        exec "${app}" "$@"
        ;;
    *)
        usage
        ;;
esac
