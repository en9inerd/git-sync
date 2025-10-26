#!/bin/bash
# Sync all GitHub repositories (personal + orgs) to self-hosted Git server
# Uses ~/.netrc for authentication (no tokens in URLs)
set -euo pipefail

BASE_DIR="/home/git/repos"
NETRC_FILE="/home/git/.netrc"
TMP_LIST="/tmp/github-repos.txt"

# Ensure ~/.netrc exists
if [ ! -f "$NETRC_FILE" ]; then
    echo "~/.netrc not found! Create it with your GitHub token:"
    echo "machine github.com login YOUR_GITHUB_USERNAME password YOUR_GITHUB_TOKEN"
    echo "machine api.github.com login YOUR_GITHUB_USERNAME password YOUR_GITHUB_TOKEN"
    exit 1
fi

chmod 600 "$NETRC_FILE"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit 1

# Clear temporary repo list
> "$TMP_LIST"

# Get GitHub username automatically from API
GITHUB_USER=$(curl -s --netrc-file "$NETRC_FILE" https://api.github.com/user | jq -r '.login')
if [ -z "$GITHUB_USER" ]; then
    echo "Failed to get GitHub username from API"
    exit 1
fi
echo "[INFO] Detected GitHub username: $GITHUB_USER"

# Fetch personal repositories (skip forks from others)
fetch_repos() {
    local url=$1
    local mode=${2:-user}
    local page=1

    while true; do
        response=$(curl -s --netrc-file "$NETRC_FILE" "${url}?per_page=100&page=${page}")

        # stop if not valid JSON or empty
        if ! echo "$response" | jq empty >/dev/null 2>&1 || [ -z "$response" ]; then
            break
        fi

        count=$(echo "$response" | jq 'length')
        [ "$count" -eq 0 ] && break

        if [ "$mode" = "user" ]; then
            echo "$response" | jq -r ".[] | select(.owner.login==\"$GITHUB_USER\") | .clone_url"
        else
            echo "$response" | jq -r '.[] | .clone_url'
        fi

        ((page++))
    done
}

echo "[INFO] Fetching personal repositories..."
fetch_repos "https://api.github.com/user/repos" >> "$TMP_LIST"

# Fetch organizations
echo "[INFO] Fetching organizations..."
ORGS=$(curl -s --netrc-file "$NETRC_FILE" "https://api.github.com/user/orgs?per_page=100" \
| jq -r '.[].login')

for org in $ORGS; do
    echo "[INFO] Fetching repos for org: $org"
    fetch_repos "https://api.github.com/orgs/$org/repos" org >> "$TMP_LIST"
done

# Remove duplicates and empty lines
sort -u "$TMP_LIST" -o "$TMP_LIST"
sed -i '/^$/d' "$TMP_LIST"

# Mirror repositories
echo "[INFO] Mirroring repositories..."
while read -r repo; do
    [ -z "$repo" ] && continue
    name=$(basename "$repo" .git)
    echo "[SYNC] $name"

    if [ -d "$BASE_DIR/$name.git" ]; then
        cd "$BASE_DIR/$name.git" || continue
        git remote set-url origin "$repo" >/dev/null 2>&1 || true
        git remote update --prune
    else
        git clone --mirror "$repo" "$BASE_DIR/$name.git"
    fi
done < "$TMP_LIST"

echo "[DONE] All repositories synced successfully."
