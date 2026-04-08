#!/usr/bin/env bash
# =============================================================================
# download-pixeldrain.sh
# Downloads an Android ROM from Pixeldrain via API, verifies SHA256 checksum.
#
# Usage: download-pixeldrain.sh <pixeldrain_url> <output_dir>
# Traceability: T-02, T-03, T-04, T-05
# =============================================================================

set -euo pipefail

PIXELDRAIN_URL="${1:?Usage: download-pixeldrain.sh <pixeldrain_url> <output_dir>}"
OUTPUT_DIR="${2:?Usage: download-pixeldrain.sh <pixeldrain_url> <output_dir>}"
API_BASE="https://pixeldrain.com/api"

# ---------------------------------------------------------------------------
# T-02: Parse the Pixeldrain URL to extract the file ID
# Handles: trailing slashes, query params, bare domain, whitespace
# ---------------------------------------------------------------------------
parse_url() {
    local url="$1"
    url=$(echo "$url" | xargs)          # Trim whitespace
    url="${url%/}"                       # Remove trailing slash
    url="${url%%\?*}"                    # Remove query parameters

    # Extract file ID: everything after the last '/u/'
    local file_id
    file_id=$(echo "$url" | sed -n 's|.*/u/\([^/]*\)$|\1|p')

    if [[ -z "$file_id" ]]; then
        echo "::error::Failed to parse file ID from URL: $PIXELDRAIN_URL"
        echo "Expected format: https://pixeldrain.com/u/<FILE_ID>"
        exit 1
    fi

    echo "$file_id"
}

# ---------------------------------------------------------------------------
# T-03: Fetch file metadata via Pixeldrain API
# Returns: file name, size, SHA256, MIME type
# ---------------------------------------------------------------------------
fetch_metadata() {
    local file_id="$1"
    local info_url="${API_BASE}/file/${file_id}/info"
    local auth_header=""

    # Build auth header if API key is provided (bypasses rate-limit)
    if [[ -n "${PIXELDRAIN_API_KEY:-}" ]]; then
        auth_header="Authorization: Basic $(echo -n ":${PIXELDRAIN_API_KEY}" | base64)"
        echo "[INFO] Using API key for authentication"
    fi

    echo "[INFO] Fetching metadata from: $info_url"

    local response
    if [[ -n "$auth_header" ]]; then
        response=$(curl -fsSL -H "$auth_header" "$info_url")
    else
        response=$(curl -fsSL "$info_url")
    fi

    # Check for API errors
    local success
    success=$(echo "$response" | jq -r '.success // "true"')
    if [[ "$success" == "false" ]]; then
        local msg
        msg=$(echo "$response" | jq -r '.message // "Unknown error"')
        echo "::error::API returned error: $msg"
        exit 1
    fi

    FILE_NAME=$(echo "$response" | jq -r '.name')
    FILE_SIZE=$(echo "$response" | jq -r '.size')
    SHA256_EXPECTED=$(echo "$response" | jq -r '.hash_sha256')
    MIME_TYPE=$(echo "$response" | jq -r '.mime_type')

    # Validate
    if [[ -z "$FILE_NAME" || "$FILE_NAME" == "null" ]]; then
        echo "::error::Could not retrieve file name from API"
        exit 1
    fi

    echo "[INFO] File name   : $FILE_NAME"
    echo "[INFO] File size   : $FILE_SIZE bytes ($(( FILE_SIZE / 1048576 )) MB)"
    echo "[INFO] SHA256      : $SHA256_EXPECTED"
    echo "[INFO] MIME type   : $MIME_TYPE"

    # Export for use by caller
    export FILE_NAME FILE_SIZE SHA256_EXPECTED MIME_TYPE
}

# ---------------------------------------------------------------------------
# T-04: Download the file binary with retry and resume support
# ---------------------------------------------------------------------------
download_file() {
    local file_id="$1"
    local output_path="$2"
    local download_url="${API_BASE}/file/${file_id}?download"
    local auth_args=()

    # Build auth args if API key is provided
    if [[ -n "${PIXELDRAIN_API_KEY:-}" ]]; then
        auth_args=(-H "Authorization: Basic $(echo -n ":${PIXELDRAIN_API_KEY}" | base64)")
    fi

    echo "[INFO] Downloading from: $download_url"

    # curl options:
    #   -L  : follow redirects
    #   -f  : fail on server errors (4xx/5xx)
    #   -C - : resume partial download
    #   --retry 5 --retry-delay 15 : retry up to 5 times with 15s delay
    #   --connect-timeout 30 : 30s connection timeout
    #   --max-time 5400 : max 90 minutes for the download itself
    curl -L -f -C - \
        --retry 5 \
        --retry-delay 15 \
        --retry-all-errors \
        --connect-timeout 30 \
        --max-time 5400 \
        "${auth_args[@]}" \
        -o "$output_path" \
        "$download_url"

    local downloaded_size
    downloaded_size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
    echo "[INFO] Downloaded size: $downloaded_size bytes ($(( downloaded_size / 1048576 )) MB)"
}

# ---------------------------------------------------------------------------
# T-05: Verify SHA256 checksum
# ---------------------------------------------------------------------------
verify_checksum() {
    local file_path="$1"
    local expected="$2"

    if [[ -z "$expected" || "$expected" == "null" ]]; then
        echo "[WARN] No SHA256 checksum available from API — skipping verification"
        return 0
    fi

    echo "[INFO] Computing SHA256 of downloaded file..."
    local actual
    actual=$(sha256sum "$file_path" | awk '{print $1}')
    echo "[INFO] Expected : $expected"
    echo "[INFO] Actual   : $actual"

    if [[ "$actual" != "$expected" ]]; then
        echo "::error::SHA256 checksum mismatch! File may be corrupted."
        exit 1
    fi

    echo "[INFO] Checksum verified successfully"
}

# ===========================================================================
# Main
# ===========================================================================
main() {
    echo "=== Pixeldrain Downloader ==="

    mkdir -p "$OUTPUT_DIR"

    # T-02: Parse URL
    FILE_ID=$(parse_url "$PIXELDRAIN_URL")
    echo "[INFO] Parsed file ID: $FILE_ID"

    # T-03: Fetch metadata
    fetch_metadata "$FILE_ID"

    local rom_path="${OUTPUT_DIR}/${FILE_NAME}"

    # T-04: Download file
    download_file "$FILE_ID" "$rom_path"

    # T-05: Verify checksum
    verify_checksum "$rom_path" "$SHA256_EXPECTED"

    # Output the ROM file path for the next step
    echo "rom_file=${rom_path}" >> "$GITHUB_OUTPUT"
    echo "[INFO] ROM saved to: $rom_path"
}

main
