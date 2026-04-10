#!/usr/bin/env bash
# =============================================================================
# dump-firmware.sh
# Wraps DumprX dumper.sh to extract firmware partitions from a ROM file.
# Parses the output directory and reports extracted files.
#
# Usage: dump-firmware.sh <dumprx_dir> <rom_file> <output_dir>
# Traceability: T-07, T-08, T-15
# =============================================================================

set -euo pipefail

DUMPRX_DIR="${1:?Usage: dump-firmware.sh <dumprx_dir> <rom_file> <output_dir>}"
ROM_FILE="${2:?}"
OUTPUT_DIR="${3:?}"

main() {
    echo "=== DumprX Firmware Dumper ==="

    # Validate inputs
    if [[ ! -d "$DUMPRX_DIR" ]]; then
        echo "::error::DumprX directory not found: $DUMPRX_DIR"
        exit 1
    fi
    if [[ ! -f "$ROM_FILE" ]]; then
        echo "::error::ROM file not found: $ROM_FILE"
        exit 1
    fi

    echo "[INFO] ROM file    : $ROM_FILE ($(du -h "$ROM_FILE" | cut -f1))"
    echo "[INFO] DumprX dir  : $DUMPRX_DIR"
    echo "[INFO] Output dir  : $OUTPUT_DIR"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # =========================================================================
    # T-07: Execute DumprX
    # DumprX's dumper.sh uses hardcoded relative paths (input/, out/, utils/)
    # so we need to work within its directory structure.
    # =========================================================================
    echo "[INFO] Starting DumprX extraction (this may take 10-30 minutes)..."

    # Copy ROM into DumprX's input directory
    mkdir -p "${DUMPRX_DIR}/input"
    cp -a "$ROM_FILE" "${DUMPRX_DIR}/input/"

    # Run DumprX
    cd "$DUMPRX_DIR"
    if bash dumper.sh "${DUMPRX_DIR}/input/$(basename "$ROM_FILE")"; then
        echo "[INFO] DumprX extraction completed"
    else
        # DumprX may exit non-zero for some formats but still produce output
        echo "[WARN] DumprX exited with non-zero status, checking output..."
    fi

    # =========================================================================
    # T-08: Parse DumprX output directory
    # DumprX puts extracted files in ${DUMPRX_DIR}/out/
    # =========================================================================
    DUMPRX_OUT="${DUMPRX_DIR}/out"

    if [[ ! -d "$DUMPRX_OUT" || -z "$(ls -A "$DUMPRX_OUT" 2>/dev/null)" ]]; then
        echo "::error::DumprX output directory is empty. Extraction may have failed."
        echo "Check DumprX logs above for errors."
        exit 1
    fi

    # Copy extracted files to our output directory
    echo "[INFO] Copying extracted files to ${OUTPUT_DIR}..."
    cp -a "${DUMPRX_OUT}"/* "$OUTPUT_DIR/"

    # Count and list extracted files
    local file_count=0
    local total_size=0
    local partition_list=""

    # Collect partition images
    while IFS= read -r -d '' file; do
        file_count=$((file_count + 1))
        local fsize
        fsize=$(stat -c%s "$file")
        total_size=$((total_size + fsize))
        local fname
        fname=$(basename "$file")
        partition_list="${partition_list}  - ${fname} ($(numfmt --to=iec $fsize))\n"
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name "*.img" -o -name "*.dat" -o -name "*.bin" -o -name "*.prop" -o -name "*.txt" -o -name "*.xml" -o -name "*.cfg" \) -print0 2>/dev/null)

    # Count all files including subdirectories
    local all_files
    all_files=$(find "$OUTPUT_DIR" -type f | wc -l)

    echo "[INFO] Found ${all_files} total files (${file_count} partition images)"

    # =========================================================================
    # T-15: Cleanup ROM zip (not uploaded to gitgud.io)
    # =========================================================================
    echo "[INFO] Cleaning up original ROM file (not needed for upload)..."
    rm -f "$ROM_FILE"
    rm -rf "${DUMPRX_DIR}/input/"*

    # Output for GitHub Actions
    echo "dumped_files=${all_files}" >> "$GITHUB_OUTPUT"
    echo "partition_images=${file_count}" >> "$GITHUB_OUTPUT"

    # Write manifest file for summary
    cat > "${OUTPUT_DIR}/DUMP_MANIFEST.txt" << EOF
=== Firmware Dump Manifest ===
Source: $(basename "$ROM_FILE")
Extracted at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Total files: ${all_files}
Partition images: ${file_count}
Total size: $(numfmt --to=iec $total_size)

Extracted partitions:
$(echo -e "$partition_list")
EOF

    echo "[INFO] Dump complete. Manifest saved to ${OUTPUT_DIR}/DUMP_MANIFEST.txt"
}

main
