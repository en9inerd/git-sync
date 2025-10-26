#!/bin/bash
# Convert mirrored Git repositories into regular bare repos (disable mirror)
set -euo pipefail

BASE_DIR="/home/git/repos"

cd "$BASE_DIR" || { echo "Base dir $BASE_DIR does not exist"; exit 1; }

# Iterate over all .git directories (mirrored repos)
for repo in *.git; do
    [ -d "$repo" ] || continue
    echo "[INFO] Processing $repo ..."

    cd "$BASE_DIR/$repo" || continue

    # Remove mirror setting if it exists
    if git config --get remote.origin.mirror >/dev/null; then
        git config --unset remote.origin.mirror
        echo "  - Removed mirror setting"
    fi

    # Optional: fetch latest changes if mirror previously disabled fetching
    git fetch --prune origin
    echo "  - Fetched latest from origin"

    cd "$BASE_DIR" || continue
done

echo "[DONE] All mirrored repos are now converted to normal bare repos."

