#!/usr/bin/env bash
# Puts the Nextcloud test server into a failure state and back, over SSH, for testing what the app and the extension
# say when the server is unavailable (T21, docs/NEXTCLOUD.md).
#
# Usage:
#   scripts/server-state.sh status
#   scripts/server-state.sh maintenance on|off   Nextcloud's maintenance mode, with occ as the web app's user
#   scripts/server-state.sh php on|off           the site's PHP-FPM pool, so nginx answers 5xx
#   scripts/server-state.sh site on|off          the site in nginx, so the host isn't served
#   scripts/server-state.sh restore              PHP-FPM on, the site on, maintenance off, in that order
#   scripts/server-state.sh with maintenance|php|site -- <command> [argument ...]
#                                                sets the state, runs the command, and restores everything afterwards,
#                                                also when the command fails or is interrupted
#
# Reads NCSERVER_HOST, NCSERVER_PHP_VERSION, NCSERVER_WEBAPP_USER, NCSERVER_WEBAPP_DIR, NCSERVER_NGINX_USER,
# NCSERVER_NGINX_CONF, NCSERVER_PHPFPM_USER, NCSERVER_PHPFPM_POOL_AVAILABLE, NCSERVER_PHPFPM_POOL_ACTIVE and
# NCSERVER_PHPFPM_CONF from .env. Use it only with the test server (AGENTS.md). Restarting PHP-FPM restarts every pool
# of that PHP version on the server, and reloading nginx reloads every site.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
    echo "error: no .env. Copy .env.example to .env and fill it in." >&2
    exit 1
fi
set -a
# shellcheck source=/dev/null
. ./.env
set +a

for key in NCSERVER_HOST NCSERVER_PHP_VERSION NCSERVER_WEBAPP_USER NCSERVER_WEBAPP_DIR NCSERVER_NGINX_USER \
    NCSERVER_NGINX_CONF NCSERVER_PHPFPM_USER NCSERVER_PHPFPM_POOL_AVAILABLE NCSERVER_PHPFPM_POOL_ACTIVE \
    NCSERVER_PHPFPM_CONF; do
    if [[ -z "${!key:-}" ]]; then
        echo "error: ${key} isn't set in .env" >&2
        exit 1
    fi
done

php="php${NCSERVER_PHP_VERSION}"
occ="${php} ${NCSERVER_WEBAPP_DIR}/occ"
pool_active="${NCSERVER_PHPFPM_POOL_ACTIVE}/${NCSERVER_PHPFPM_CONF}"
pool_available="${NCSERVER_PHPFPM_POOL_AVAILABLE}/${NCSERVER_PHPFPM_CONF}"
restart_php="php-fpm${NCSERVER_PHP_VERSION} -t && systemctl restart php${NCSERVER_PHP_VERSION}-fpm"
reload_nginx="nginx -t && systemctl reload nginx"

# Runs a command on the server as the given user, and prints only its output: a login may print a welcome text
# first, so the output is taken from between two markers. Fails when the command does.
remote() {
    local user="$1" command="$2" output status
    output="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "${user}@${NCSERVER_HOST}" \
        "echo __NCME_BEGIN__; ( ${command} ) 2>&1; echo \"__NCME_END__ \$?\"")" || {
        echo "error: ssh to ${user}@ the test server failed" >&2
        return 1
    }
    status="$(printf '%s\n' "${output}" | sed -n 's/^__NCME_END__ \([0-9]*\)$/\1/p' | tail -n 1)"
    printf '%s\n' "${output}" | sed -n '/^__NCME_BEGIN__$/,/^__NCME_END__ /p' | sed '1d;$d'
    [[ "${status}" == "0" ]]
}

status() {
    remote "${NCSERVER_WEBAPP_USER}" "${occ} maintenance:mode" || echo "maintenance: unknown, occ failed"
    if remote "${NCSERVER_NGINX_USER}" "test -L /etc/nginx/sites-enabled/${NCSERVER_NGINX_CONF}"; then
        echo "nginx: the site is enabled"
    else
        echo "nginx: the site is disabled"
    fi
    if remote "${NCSERVER_PHPFPM_USER}" "test -f ${pool_active}"; then
        echo "PHP-FPM: the site's pool is active"
    else
        echo "PHP-FPM: the site's pool is inactive"
    fi
}

maintenance() {
    remote "${NCSERVER_WEBAPP_USER}" "${occ} maintenance:mode --$1"
}

php_pool() {
    case "$1" in
        on) remote "${NCSERVER_PHPFPM_USER}" "cp -f ${pool_available} ${NCSERVER_PHPFPM_POOL_ACTIVE}/ && ${restart_php}" ;;
        off) remote "${NCSERVER_PHPFPM_USER}" "rm -f ${pool_active} && ${restart_php}" ;;
    esac
}

site() {
    case "$1" in
        on) remote "${NCSERVER_NGINX_USER}" "nginx_ensite ${NCSERVER_NGINX_CONF}; ${reload_nginx}" ;;
        off) remote "${NCSERVER_NGINX_USER}" "nginx_dissite ${NCSERVER_NGINX_CONF}; ${reload_nginx}" ;;
    esac
}

# PHP-FPM first, which occ and a working site need, then the site, then maintenance mode.
restore() {
    local failed=0
    php_pool on > /dev/null || failed=1
    site on > /dev/null || failed=1
    maintenance off > /dev/null || failed=1
    if [[ "${failed}" == 1 ]]; then
        echo "error: the test server may not be fully restored. Check it with scripts/server-state.sh status." >&2
        return 1
    fi
    echo "restored"
}

set_state() {
    case "$1" in
        maintenance) maintenance on ;;
        php) php_pool off ;;
        site) site off ;;
        *)
            echo "error: unknown state $1. Use maintenance, php or site." >&2
            return 2
            ;;
    esac
}

on_off() {
    case "${1:-}" in
        on | off) ;;
        *)
            echo "usage: scripts/server-state.sh $2 on|off" >&2
            exit 2
            ;;
    esac
}

case "${1:-}" in
    status) status ;;
    maintenance)
        on_off "${2:-}" maintenance
        maintenance "$2"
        ;;
    php)
        on_off "${2:-}" php
        php_pool "$2"
        ;;
    site)
        on_off "${2:-}" site
        site "$2"
        ;;
    restore) restore ;;
    with)
        state="${2:-}"
        if [[ "${3:-}" != "--" || -z "${4:-}" ]]; then
            echo "usage: scripts/server-state.sh with maintenance|php|site -- <command> [argument ...]" >&2
            exit 2
        fi
        shift 3
        trap 'restore' EXIT
        trap 'exit 130' INT TERM
        set_state "${state}" > /dev/null
        echo "the test server is now in state: ${state}" >&2
        NCME_SERVER_STATE="${state}" "$@"
        ;;
    *)
        sed -n '5,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
