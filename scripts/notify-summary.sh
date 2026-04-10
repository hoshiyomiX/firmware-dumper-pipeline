#!/usr/bin/env bash
# =============================================================================
# notify-summary.sh
# Generates a GitHub Actions job summary with the dump results.
#
# Usage: notify-summary.sh <repo_name> <dumped_files> <repo_url>
# Traceability: T-13
# =============================================================================

set -euo pipefail

REPO_NAME="${1:-unknown}"
DUMPED_FILES="${2:-0}"
REPO_URL="${3:-}"

main() {
    # Write GitHub Actions job summary
    cat >> "$GITHUB_STEP_SUMMARY" << EOF
## Dump Summary

| Field | Value |
|-------|-------|
| **Repository** | \`${REPO_NAME}\` |
| **Files Dumped** | ${DUMPED_FILES} |
${REPO_URL:+| **gitgud.io URL** | [${REPO_URL}](${REPO_URL}) |}
| **Completed At** | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |

### Extracted Firmware Partitions

EOF

    # Append manifest if it exists
    if [[ -f "/tmp/rom-workspace/out/DUMP_MANIFEST.txt" ]]; then
        echo '```' >> "$GITHUB_STEP_SUMMARY"
        cat /tmp/rom-workspace/out/DUMP_MANIFEST.txt >> "$GITHUB_STEP_SUMMARY"
        echo '```' >> "$GITHUB_STEP_SUMMARY"
    else
        echo "_No manifest found._" >> "$GITHUB_STEP_SUMMARY"
    fi

    echo "[INFO] Job summary written."
}

main
