#!/usr/bin/env bash
# =============================================================================
# push-to-gitgud.sh
# Creates a repo on gitgud.io (Gitea), initializes Git + LFS, and pushes
# all extracted firmware files.
#
# Auth modes (determined by available secrets):
#   SSH (primary):  GITGUD_SSH_KEY set → push via git@gitgud.io
#                   GITGUD_TOKEN optional → used for API repo creation if set
#   HTTPS (fallback): GITGUD_TOKEN set → push via HTTPS + .netrc
#
# Usage: push-to-gitgud.sh <output_dir> <repo_name> <device_name> <firmware_version>
# Traceability: T-09, T-10, T-11, T-12, T-R3, T-R4, T-R5, T-R6
# Environment: GITGUD_TOKEN (optional), GITGUD_GROUP (required), GITGUD_SSH_KEY (optional)
# =============================================================================

set -euo pipefail

# T-10b: Prevent Git from prompting for credentials in headless CI
export GIT_TERMINAL_PROMPT=0

OUTPUT_DIR="${1:?Usage: push-to-gitgud.sh <output_dir> <repo_name> <device> <version>}"
REPO_NAME="${2:?}"
DEVICE_NAME="${3:?}"
FIRMWARE_VERSION="${4:?}"
GITGUD_API="https://gitgud.io/api/v1"

# T-R3: Determine auth mode — at least one method must be available
if [[ -n "${GITGUD_SSH_KEY:-}" ]]; then
    AUTH_MODE="ssh"
    echo "[INFO] Auth mode: SSH key (primary)"
elif [[ -n "${GITGUD_TOKEN:-}" ]]; then
    AUTH_MODE="token"
    echo "[INFO] Auth mode: HTTPS token (fallback)"
else
    echo "::error::No authentication configured. Set GITGUD_SSH_KEY or GITGUD_TOKEN."
    exit 1
fi

# Track whether .netrc was created (for cleanup)
NETRC_CREATED=false

# =========================================================================
# T-R4: Create gitgud.io repo via Gitea API (only if token is available)
#   Without a token, the repo must pre-exist on gitgud.io.
#   With SSH-only mode, the push itself will fail if the repo is missing.
# =========================================================================
create_repo() {
    local repo_slug="$1"

    # Skip API repo creation if no token is available (SSH-only mode)
    if [[ -z "${GITGUD_TOKEN:-}" ]]; then
        local group="${GITGUD_GROUP:?GITGUD_GROUP is required for SSH-only mode}"
        echo "[INFO] No GITGUD_TOKEN set — skipping API repo creation"
        echo "[INFO] Target owner: ${group}"
        echo "[INFO] Repo name: ${repo_slug}"
        echo "[WARN] Repository must already exist on gitgud.io or push will fail"
        REPO_URL="https://gitgud.io/${group}/${repo_slug}.git"
        return 0
    fi

    local group="${GITGUD_GROUP:-}"
    local owner="${group:-$(curl -sSL -H "Authorization: token ${GITGUD_TOKEN}" "${GITGUD_API}/user" | jq -r '.login')}"

    echo "[INFO] Target owner: ${owner}"
    echo "[INFO] Repo name: ${repo_slug}"

    # Check if repo already exists
    local http_code
    http_code=$(curl -sSL -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${GITGUD_TOKEN}" \
        "${GITGUD_API}/repos/${owner}/${repo_slug}")

    if [[ "$http_code" == "200" ]]; then
        echo "[INFO] Repository already exists: ${owner}/${repo_slug}"
        REPO_URL="https://gitgud.io/${owner}/${repo_slug}.git"
        return 0
    fi

    echo "[INFO] Creating repository: ${owner}/${repo_slug}..."

    # Create repo via API
    local create_payload
    create_payload=$(jq -n \
        --arg name "$repo_slug" \
        --arg desc "Firmware dump for ${DEVICE_NAME} - ${FIRMWARE_VERSION}" \
        --argjson private false \
        --argjson auto_init false \
        '{
            name: $name,
            description: $desc,
            private: $private,
            auto_init: $auto_init
        }')

    local response
    response=$(curl -sSL \
        -X POST \
        -H "Authorization: token ${GITGUD_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$create_payload" \
        "${GITGUD_API}/orgs/${owner}/repos" 2>/dev/null || \
    curl -sSL \
        -X POST \
        -H "Authorization: token ${GITGUD_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$create_payload" \
        "${GITGUD_API}/user/repos")

    local clone_url
    clone_url=$(echo "$response" | jq -r '.clone_url // .html_url')

    if [[ -z "$clone_url" || "$clone_url" == "null" ]]; then
        echo "::error::Failed to create repository. API response:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        exit 1
    fi

    echo "[INFO] Repository created: $clone_url"

    # If group is set, the URL format differs
    REPO_URL="https://gitgud.io/${owner}/${repo_slug}.git"
}

# =========================================================================
# T-10 / T-R5: Initialize Git + Git LFS in output directory
#   SSH key takes priority; falls back to HTTPS + .netrc
# =========================================================================
init_git() {
    local repo_url="$1"

    cd "$OUTPUT_DIR"

    # Initialize git repo
    git init -b main
    git config user.name "Firmware Dumper Bot"
    git config user.email "firmware-bot@users.noreply.gitgud.io"
    git config http.sslVerify true

    # Determine owner
    local owner
    if [[ -n "${GITGUD_GROUP:-}" ]]; then
        owner="${GITGUD_GROUP}"
    elif [[ -n "${GITGUD_TOKEN:-}" ]]; then
        owner=$(curl -sSL -H "Authorization: token ${GITGUD_TOKEN}" "${GITGUD_API}/user" | jq -r '.login')
    else
        echo "::error::Cannot determine repo owner — GITGUD_GROUP or GITGUD_TOKEN is required"
        exit 1
    fi

    # T-R5: SSH key takes priority over HTTPS
    if [[ -n "${GITGUD_SSH_KEY:-}" ]]; then
        echo "[INFO] Setting up SSH key..."
        mkdir -p ~/.ssh
        echo "${GITGUD_SSH_KEY}" > ~/.ssh/id_ed25519
        chmod 600 ~/.ssh/id_ed25519

        # Convert PKCS#8 format to OpenSSH native format if needed
        # GitHub Secrets may store keys as -----BEGIN PRIVATE KEY----- (PKCS#8)
        # but OpenSSH requires -----BEGIN OPENSSH PRIVATE KEY-----
        if head -1 ~/.ssh/id_ed25519 | grep -q "BEGIN PRIVATE KEY$"; then
            echo "[INFO] Converting PKCS#8 key to OpenSSH native format..."
            # Rewrite the key in OpenSSH format (default on ubuntu-latest)
            # -P "" = current passphrase is empty, -N "" = new passphrase is empty
            ssh-keygen -p -f ~/.ssh/id_ed25519 -P "" -N "" 2>/dev/null || true
            # Verify conversion succeeded
            if ! head -1 ~/.ssh/id_ed25519 | grep -q "OPENSSH"; then
                echo "::error::Failed to convert SSH key to OpenSSH format"
                exit 1
            fi
        fi

        ssh-keyscan -H gitgud.io >> ~/.ssh/known_hosts 2>/dev/null
        git remote add origin "git@gitgud.io:${owner}/${REPO_NAME}.git"
    elif [[ -n "${GITGUD_TOKEN:-}" ]]; then
        # T-10a: Use .netrc for credential storage (works for git + git-lfs)
        # Gitea accepts token as password with any username
        echo "[INFO] Configuring .netrc for gitgud.io authentication..."
        cat > ~/.netrc << NETRC_EOF
machine gitgud.io
login token
password ${GITGUD_TOKEN}
NETRC_EOF
        chmod 600 ~/.netrc

        # Tell git to use .netrc for credentials
        git config --global credential.helper "netrc --file ${HOME}/.netrc"
        NETRC_CREATED=true

        # Use clean URL — no token embedded (prevents leaks in logs/processes)
        git remote add origin "https://gitgud.io/${owner}/${REPO_NAME}.git"
    else
        echo "::error::No authentication available for git push"
        exit 1
    fi

    # Install and initialize Git LFS
    echo "[INFO] Installing Git LFS..."
    git lfs install

    # T-11c: Tune LFS for faster uploads
    git config lfs.concurrenttransfers 8
    git config lfs.https://gitgud.io.locksverify true
}

# =========================================================================
# T-11: Configure .gitattributes for LFS tracking
# Files > 100MB MUST use LFS on gitgud.io
# =========================================================================
configure_lfs() {
    cd "$OUTPUT_DIR"

    echo "[INFO] Configuring Git LFS tracking rules..."

    # T-11a: Only track .img files by extension (these are the large partition images)
    # Small .bin/.dat/.so files are committed as normal git objects — much faster
    git lfs track "*.img"

    # T-11b: Track any individual file >100MB regardless of extension
    # This catches outliers without needlessly LFS-tracking small files
    local lfs_count=0
    find . -type f -size +100M | while IFS= read -r file; do
        local ext="${file##*.}"
        # Only add extension-level rule if not already tracked
        if ! git lfs track | grep -q "\.${ext} filter=lfs"; then
            git lfs track "*.${ext}"
            lfs_count=$((lfs_count + 1))
            echo "  [LFS] Added *.${ext} (>100MB file found: ${file})"
        fi
    done

    echo "[INFO] LFS tracking patterns:"
    git lfs track

    # Add .gitattributes to repo
    git add .gitattributes
}

# =========================================================================
# T-12 / T-R6: Git commit all extracted files + push to gitgud.io
# Cleanup: only remove .netrc when it was actually created
# =========================================================================
commit_and_push() {
    cd "$OUTPUT_DIR"

    echo "[INFO] Staging all extracted files..."

    # Stage everything
    git add -A

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo "[INFO] No changes to commit (repo may already be up to date)"
        return 0
    fi

    # Create commit
    local commit_msg="Dump firmware for ${DEVICE_NAME} ${FIRMWARE_VERSION}

Extracted from Pixeldrain on $(date -u '+%Y-%m-%d')

Device: ${DEVICE_NAME}
Firmware: ${FIRMWARE_VERSION}
Files: $(find . -type f | wc -l)"

    git commit -m "$commit_msg"

    # Push to remote
    echo "[INFO] Pushing to gitgud.io..."
    git push -u origin main --force 2>&1 || {
        echo "[WARN] Push failed, attempting with pull --rebase first..."
        git pull origin main --rebase --allow-unrelated-histories 2>/dev/null || true
        git push -u origin main --force 2>&1
    }

    # T-R6: Cleanup .netrc only if it was created in this session
    if [[ "$NETRC_CREATED" == "true" ]]; then
        rm -f ~/.netrc
        git config --global --unset credential.helper 2>/dev/null || true
    fi

    echo "[INFO] Push complete!"
}

# ===========================================================================
# Main
# ===========================================================================
main() {
    echo "=== Push to gitgud.io ==="

    # Validate output directory
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        echo "::error::Output directory not found: $OUTPUT_DIR"
        exit 1
    fi

    # Sanitize repo name (Gitea requirements):
    #   - lowercase only
    #   - replace invalid chars with '-'
    #   - trim whitespace first
    #   - strip leading/trailing '.' '_' '-' (Gitea rejects these)
    REPO_NAME=$(echo "$REPO_NAME" | xargs | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g' | sed 's/^[._-]*//' | sed 's/[._-]*$//')
    echo "[INFO] Sanitized repo name: ${REPO_NAME}"

    # T-R4: Create repo (skipped in SSH-only mode if no token)
    create_repo "$REPO_NAME"

    # T-R5: Initialize git
    init_git "$REPO_URL"

    # T-11: Configure LFS
    configure_lfs

    # T-12: Commit and push
    commit_and_push

    # Determine display URL (without token)
    local owner="${GITGUD_GROUP:-}"
    local display_url="https://gitgud.io/${owner:+${owner}/}${REPO_NAME}"
    echo "repo_url=${display_url}" >> "$GITHUB_OUTPUT"
    echo "[INFO] Repository URL: ${display_url}"
}

main
