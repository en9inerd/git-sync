#!/bin/bash
# Migrate all GitHub repositories (personal + orgs) to Codeberg
# Uses Codeberg's Gitea migration API for full migration:
#   code, issues, PRs, labels, milestones, releases, wiki
# Re-runnable: skips repos that already exist on Codeberg
set -euo pipefail

# --- Configuration ---
# Tokens can be set via environment variables or a config file.
# Config file is sourced as bash KEY=VALUE pairs.
# Environment variables take precedence over the config file.
CONFIG_FILE="${CODEBERG_MIGRATE_CONFIG:-$HOME/.config/codeberg-migrate.conf}"

_env_codeberg="${CODEBERG_TOKEN:-}"
_env_github="${GITHUB_TOKEN:-}"

if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

CODEBERG_TOKEN="${_env_codeberg:-${CODEBERG_TOKEN:-}}"
GITHUB_TOKEN="${_env_github:-${GITHUB_TOKEN:-}}"
unset _env_codeberg _env_github
CODEBERG_API="https://codeberg.org/api/v1"
GITHUB_API="https://api.github.com"

log() {
    local level="$1"; shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

github_api() {
    curl -s -H "Authorization: token $GITHUB_TOKEN" "$@"
}

codeberg_api() {
    curl -s -H "Authorization: token $CODEBERG_TOKEN" "$@"
}

# --- Validate tokens ---
if [ -z "$CODEBERG_TOKEN" ]; then
    log ERROR "CODEBERG_TOKEN is not set."
    log ERROR "Set it via environment variable or in $CONFIG_FILE"
    log ERROR "Generate one at: https://codeberg.org/user/settings/applications"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    log ERROR "GITHUB_TOKEN is not set."
    log ERROR "Set it via environment variable or in $CONFIG_FILE"
    log ERROR "Generate one at: https://github.com/settings/tokens"
    exit 1
fi

# --- Verify API access ---
GITHUB_USER=$(github_api "$GITHUB_API/user" | jq -r '.login')
if [ -z "$GITHUB_USER" ] || [ "$GITHUB_USER" = "null" ]; then
    log ERROR "Failed to authenticate with GitHub. Check your GITHUB_TOKEN."
    exit 1
fi
log INFO "GitHub user: $GITHUB_USER"

CODEBERG_USER=$(codeberg_api "$CODEBERG_API/user" | jq -r '.login')
if [ -z "$CODEBERG_USER" ] || [ "$CODEBERG_USER" = "null" ]; then
    log ERROR "Failed to authenticate with Codeberg. Check your CODEBERG_TOKEN."
    exit 1
fi
log INFO "Codeberg user: $CODEBERG_USER"

# --- Fetch GitHub repositories ---
TMP_LIST=$(mktemp /tmp/codeberg-migrate.XXXXXX)
trap 'rm -f "$TMP_LIST"' EXIT

fetch_github_repos() {
    local url=$1
    local mode=${2:-user}
    local page=1

    while true; do
        response=$(github_api "${url}?per_page=100&page=${page}")

        if ! echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1 || [ -z "$response" ]; then
            break
        fi

        count=$(echo "$response" | jq 'length')
        [ "$count" -eq 0 ] && break

        # Output: full_name \t clone_url \t private(bool)
        if [ "$mode" = "user" ]; then
            echo "$response" | jq -r \
                ".[] | select(.owner.login==\"$GITHUB_USER\") | [.full_name, .clone_url, (.private | tostring)] | @tsv"
        else
            echo "$response" | jq -r \
                '.[] | [.full_name, .clone_url, (.private | tostring)] | @tsv'
        fi

        page=$((page + 1))
    done
}

SKIP_ORGS="${SKIP_ORGS:-false}"

log INFO "Fetching personal GitHub repositories..."
fetch_github_repos "$GITHUB_API/user/repos" user >> "$TMP_LIST"

if [ "$SKIP_ORGS" = "true" ]; then
    log INFO "Skipping organization repositories (SKIP_ORGS=true)."
else
    log INFO "Fetching GitHub organizations..."
    ORGS=$(github_api "$GITHUB_API/user/orgs?per_page=100" | jq -r '.[].login // empty')

    for org in $ORGS; do
        log INFO "Fetching repos for org: $org"
        fetch_github_repos "$GITHUB_API/orgs/$org/repos" org >> "$TMP_LIST"
    done
fi

sort -u "$TMP_LIST" -o "$TMP_LIST"

TOTAL=$(grep -c . "$TMP_LIST" || true)
if [ "$TOTAL" -eq 0 ]; then
    log INFO "No repositories found on GitHub."
    exit 0
fi
log INFO "Found $TOTAL repositories to process."

# --- Migrate repositories ---
migrated=0
skipped=0
failed=0
current=0

while IFS=$'\t' read -r full_name clone_url is_private; do
    [ -z "$full_name" ] && continue

    current=$((current + 1))
    owner="${full_name%%/*}"
    name="${full_name#*/}"

    # Map GitHub owner to Codeberg owner
    if [ "$owner" = "$GITHUB_USER" ]; then
        codeberg_owner="$CODEBERG_USER"
    else
        codeberg_owner="$owner"
    fi

    # Check if repo already exists on Codeberg
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $CODEBERG_TOKEN" \
        "$CODEBERG_API/repos/$codeberg_owner/$name")

    if [ "$http_code" = "200" ]; then
        log SKIP "[$current/$TOTAL] $codeberg_owner/$name (already exists)"
        skipped=$((skipped + 1))
        continue
    fi

    log MIGRATE "[$current/$TOTAL] $full_name -> $codeberg_owner/$name"

    # Call Codeberg migration API
    # Try full migration first, then fall back to code-only on 500
    migrate_success=false
    for mode in full code_only; do
        payload=$(jq -n \
            --arg clone_addr "$clone_url" \
            --arg auth_token "$GITHUB_TOKEN" \
            --arg repo_name "$name" \
            --arg repo_owner "$codeberg_owner" \
            --argjson private "$is_private" \
            --argjson full "$([ "$mode" = "full" ] && echo true || echo false)" \
            '{
                clone_addr: $clone_addr,
                auth_token: $auth_token,
                repo_name: $repo_name,
                repo_owner: $repo_owner,
                service: "github",
                mirror: false,
                private: $private,
                issues: $full,
                labels: $full,
                milestones: $full,
                pull_requests: $full,
                releases: $full,
                wiki: $full
            }')

        tmp_body=$(mktemp)
        http_code=$(curl -s -o "$tmp_body" -w "%{http_code}" \
            -H "Authorization: token $CODEBERG_TOKEN" \
            -H "Content-Type: application/json" \
            -X POST "$CODEBERG_API/repos/migrate" \
            -d "$payload") || true

        if [ "$http_code" = "201" ]; then
            if [ "$mode" = "full" ]; then
                log OK "$codeberg_owner/$name migrated successfully"
            else
                log OK "$codeberg_owner/$name migrated (code only — issues/PRs/wiki skipped)"
            fi
            migrated=$((migrated + 1))
            migrate_success=true
            rm -f "$tmp_body"
            break
        fi

        error_msg=$(jq -r '.message // "unknown error"' < "$tmp_body" 2>/dev/null || echo "unknown error")
        rm -f "$tmp_body"

        if [ "$mode" = "full" ] && [ "$http_code" = "500" ]; then
            log WARN "$codeberg_owner/$name full migration failed (HTTP 500), retrying code-only..."
            curl -s -X DELETE \
                -H "Authorization: token $CODEBERG_TOKEN" \
                "$CODEBERG_API/repos/$codeberg_owner/$name" >/dev/null 2>&1 || true
            sleep 3
        fi
    done

    if [ "$migrate_success" = false ]; then
        log ERROR "$codeberg_owner/$name failed: $error_msg (HTTP $http_code)"
        failed=$((failed + 1))
    fi
done < "$TMP_LIST"

log DONE "Migration complete: $migrated migrated, $skipped skipped, $failed failed (out of $TOTAL)."
