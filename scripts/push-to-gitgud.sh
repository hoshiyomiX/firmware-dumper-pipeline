#!/usr/bin/env bash
# =============================================================================
# push-to-gitgud.sh
# Creates a repo on gitgud.io (Gitea), initializes Git + LFS, and pushes
# all extracted firmware files.
#
# Usage: push-to-gitgud.sh <output_dir> <repo_name> <device_name> <firmware_version>
# Traceability: T-09, T-10, T-11, T-12
# Environment: GITGUD_TOKEN, GITGUD_GROUP, GITGUD_SSH_KEY
# =============================================================================

set -euo pipefail

OUTPUT_DIR="${1:?Usage: push-to-gitgud.sh <output_dir> <repo_name> <device> <version>}"
REPO_NAME="${2:?}"
DEVICE_NAME="${3:?}"
FIRMWARE_VERSION="${4:?}"
GITGUD_API="https://gitgud.io/api/v1"

# Validate required environment variables
if [[ -z "${GITGUD_TOKEN:-}" ]]; then
    echo "::error::GITGUD_TOKEN secret is not set. Add it in GitHub Secrets."
    exit 1
fi

# =========================================================================
# T-09: Create gitgud.io repo via Gitea API (reuse if exists)
# =========================================================================
create_repo() {
    local repo_slug="$1"
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
# T-10: Initialize Git + Git LFS in output directory
# =========================================================================
init_git() {
    local repo_url="$1"

    cd "$OUTPUT_DIR"

    # Initialize git repo
    git init -b main
    git config user.name "Firmware Dumper Bot"
    git config user.email "firmware-bot@users.noreply.gitgud.io"
    git config http.sslVerify true

    # Setup SSH if key is provided, otherwise use HTTPS+token
    if [[ -n "${GITGUD_SSH_KEY:-}" ]]; then
        echo "[INFO] Setting up SSH key..."
        mkdir -p ~/.ssh
        echo "${GITGUD_SSH_KEY}" > ~/.ssh/id_ed25519
        chmod 600 ~/.ssh/id_ed25519
        ssh-keyscan -H gitgud.io >> ~/.ssh/known_hosts 2>/dev/null
        # Convert HTTPS URL to SSH
        REPO_SSH_URL="git@gitgud.io:${GITGUD_GROUP:-$(curl -sSL -H "Authorization: token ${GITGUD_TOKEN}" "${GITGUD_API}/user" | jq -r '.login')}/${REPO_NAME}.git"
        git remote add origin "$REPO_SSH_URL"
    else
        # Use HTTPS with token embedded in URL
        local owner="${GITGUD_GROUP:-$(curl -sSL -H "Authorization: token ${GITGUD_TOKEN}" "${GITGUD_API}/user" | jq -r '.login')}"
        local token_url="https://${GITGUD_TOKEN}@gitgud.io/${owner}/${REPO_NAME}.git"
        git remote add origin "$token_url"
    fi

    # Install and initialize Git LFS
    echo "[INFO] Installing Git LFS..."
    git lfs install
}

# =========================================================================
# T-11: Configure .gitattributes for LFS tracking
# Files > 100MB MUST use LFS on gitgud.io
# =========================================================================
configure_lfs() {
    cd "$OUTPUT_DIR"

    echo "[INFO] Configuring Git LFS tracking rules..."

    # Track all .img files (partition images are typically large)
    git lfs track "*.img"

    # Track other potentially large binary files
    git lfs track "*.bin"
    git lfs track "*.dat"
    git lfs track "*.br"
    git lfs track "*.ext4"

    # Track files larger than 100MB specifically
    find . -maxdepth 2 -type f -size +100M | while IFS= read -r file; do
        local ext="${file##*.}"
        local fname
        fname=$(basename "$file")
        # Track by specific pattern if not already covered
        if ! git lfs track | grep -q "\.${ext}"; then
            git lfs track "*.${ext}"
        fi
    done

    # Ensure .gitattributes is committed
    echo "[INFO] LFS tracking patterns:"
    git lfs track | head -20

    # Add .gitattributes to repo
    git add .gitattributes
}

# =========================================================================
# T-12: Git commit all extracted files + push to gitgud.io
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

    # Sanitize repo name (Gitea requirements)
    REPO_NAME=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')
    echo "[INFO] Sanitized repo name: ${REPO_NAME}"

    # T-09: Create repo
    create_repo "$REPO_NAME"

    # T-10: Initialize git
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
