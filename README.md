# GitHub Backup & Migration Scripts

Scripts to back up GitHub repositories to a self-hosted Git server and migrate them to Codeberg.

## Scripts

### 1. `github-sync.sh`

**Purpose:**  
Fetch all repositories from GitHub (personal and organization repos) and mirror them on a self-hosted Git server.  

**Usage:**

1. Ensure you have a `.netrc` file with your GitHub credentials:
    ```
    machine github.com
    login YOUR_GITHUB_USERNAME
    password YOUR_GITHUB_TOKEN

    machine api.github.com
    login YOUR_GITHUB_USERNAME
    password YOUR_GITHUB_TOKEN
    ```
2. Place `github-sync.sh` on your Git server (e.g., `/home/git/`).
3. Make it executable:
    ```bash
    chmod +x github-sync.sh
    ```
4. Run the script:
    ```bash
    ./github-sync.sh
    ```
5. All repositories will be mirrored under `/home/git/repos/`.

---

### 2. `convert-to-bare.sh`

**Purpose:**  
Convert mirrored repositories created by `github-sync.sh` into independent bare repositories so they can be used independently from GitHub.

**Usage:**

1. Place `convert-to-bare.sh` on your Git server (same location as mirrored repos).
2. Make it executable:
    ```bash
    chmod +x convert-to-bare.sh
    ```
3. Run the script:
    ```bash
    ./convert-to-bare.sh
    ```
4. The script will:
    - Remove the `mirror` setting from each repo
    - Fetch the latest changes from origin
    - Leave you with standard bare repositories that can be pushed or cloned independently

---

### 3. `codeberg-migrate.sh`

**Purpose:**  
Migrate all GitHub repositories (personal and organization) to Codeberg using the Gitea migration API. Includes full migration of code, issues, pull requests, labels, milestones, releases, and wikis. Safe to re-run — repos that already exist on Codeberg are skipped.

**Setup:**

1. Create a GitHub token at https://github.com/settings/tokens (needs `repo` scope for private repos).
2. Create a Codeberg token at https://codeberg.org/user/settings/applications.
3. Provide tokens via **environment variables** or a **config file**:

    **Option A — Environment variables:**
    ```bash
    export GITHUB_TOKEN="your_github_token"
    export CODEBERG_TOKEN="your_codeberg_token"
    ```

    **Option B — Config file** (`~/.config/codeberg-migrate.conf`):
    ```bash
    GITHUB_TOKEN="your_github_token"
    CODEBERG_TOKEN="your_codeberg_token"
    ```

4. If migrating org repos, ensure the matching organizations already exist on Codeberg.

**Usage:**

```bash
chmod +x codeberg-migrate.sh
./codeberg-migrate.sh
```

The script will:
- Discover all your personal and organization repos on GitHub
- Skip any repos that already exist on Codeberg
- Migrate new repos with issues, PRs, labels, milestones, releases, and wikis
- Preserve repo visibility (public stays public, private stays private)
- Print a summary of migrated / skipped / failed repos

---

## Notes

- **Execution order:** Always run `github-sync.sh` first to populate the mirrored repos, then run `convert-to-bare.sh` to make them independent.
- **Repository structure:** Mirrored repos are stored as `.git` directories under `/home/git/repos/`.
- **Cloning:** After conversion, you can clone repositories from your server:
    ```bash
    git clone git@your-server:repo-name
    ```
- **Dependencies:** All scripts require `jq`, `curl`, and `git`.

---

## License

MIT License
