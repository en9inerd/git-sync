# GitHub Backup & Self-Hosted Git Server Scripts

This repository contains two Bash scripts to back up GitHub repositories and host them on your own self-hosted Git server.

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

## Notes

- **Execution order:** Always run `github-sync.sh` first to populate the mirrored repos, then run `convert-to-bare.sh` to make them independent.
- **Repository structure:** Mirrored repos are stored as `.git` directories under `/home/git/repos/`.
- **Cloning:** After conversion, you can clone repositories from your server:
    ```bash
    git clone git@your-server:repo-name
    ```
- **Dependencies:** Both scripts require `jq` and `curl` to fetch repository lists from GitHub.

---

## License

MIT License
