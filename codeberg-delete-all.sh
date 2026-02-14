#!/bin/bash
# Delete ALL repositories owned by the authenticated Codeberg user
# WARNING: This is destructive and irreversible!
# Requires interactive confirmation before proceeding.
set -euo pipefail

# --- Configuration ---
CONFIG_FILE="${CODEBERG_MIGRATE_CONFIG:-$HOME/.config/codeberg-migrate.conf}"

_env_codeberg="${CODEBERG_TOKEN:-}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

CODEBERG_TOKEN="${_env_codeberg:-${CODEBERG_TOKEN:-}}"
unset _env_codeberg
CODEBERG_API="https://codeberg.org/api/v1"

log() {
    local level="$1"; shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

codeberg_api() {
    curl -s -H "Authorization: token $CODEBERG_TOKEN" "$@"
}

# --- Validate token ---
if [ -z "$CODEBERG_TOKEN" ]; then
    log ERROR "CODEBERG_TOKEN is not set."
    log ERROR "Set it via environment variable or in $CONFIG_FILE"
    exit 1
fi

# --- Verify API access ---
CODEBERG_USER=$(codeberg_api "$CODEBERG_API/user" | jq -r '.login')
if [ -z "$CODEBERG_USER" ] || [ "$CODEBERG_USER" = "null" ]; then
    log ERROR "Failed to authenticate with Codeberg. Check your CODEBERG_TOKEN."
    exit 1
fi
log INFO "Codeberg user: $CODEBERG_USER"

# --- Fetch all repos ---
repos=()
page=1

while true; do
    response=$(codeberg_api "$CODEBERG_API/user/repos?page=${page}&limit=50")

    if ! echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1 || [ -z "$response" ]; then
        break
    fi

    count=$(echo "$response" | jq 'length')
    [ "$count" -eq 0 ] && break

    while IFS= read -r name; do
        repos+=("$name")
    done < <(echo "$response" | jq -r '.[].full_name')

    page=$((page + 1))
done

TOTAL=${#repos[@]}

if [ "$TOTAL" -eq 0 ]; then
    log INFO "No repositories found on Codeberg."
    exit 0
fi

# --- List repos and confirm ---
log WARN "The following $TOTAL repositories will be PERMANENTLY DELETED:"
echo ""
for repo in "${repos[@]}"; do
    echo "  - $repo"
done
echo ""

FORCE="${FORCE:-false}"

if [ "$FORCE" != "true" ]; then
    printf '%s [%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "CONFIRM" \
        "Type 'delete all' to confirm: "
    read -r confirmation

    if [ "$confirmation" != "delete all" ]; then
        log INFO "Aborted."
        exit 0
    fi
fi

# --- Delete repos ---
deleted=0
failed=0

for repo in "${repos[@]}"; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $CODEBERG_TOKEN" \
        -X DELETE "$CODEBERG_API/repos/$repo")

    if [ "$http_code" = "204" ]; then
        log DELETE "$repo"
        deleted=$((deleted + 1))
    else
        log ERROR "$repo failed (HTTP $http_code)"
        failed=$((failed + 1))
    fi
done

log DONE "Deletion complete: $deleted deleted, $failed failed (out of $TOTAL)."
