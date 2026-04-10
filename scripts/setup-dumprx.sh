#!/usr/bin/env bash
# =============================================================================
# setup-dumprx.sh
# Clones DumprX, installs system dependencies, runs its setup.sh
#
# Usage: setup-dumprx.sh <install_dir>
# Traceability: T-06
# =============================================================================

set -euo pipefail

INSTALL_DIR="${1:?Usage: setup-dumprx.sh <install_dir>}"
DUMPRX_REPO="https://github.com/DumprX/DumprX.git"

main() {
    echo "=== DumprX Setup ==="

    # Install system-level dependencies required by DumprX
    echo "[INFO] Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends \
        aria2 \
        binwalk \
        brotli \
        curl \
        detox \
        file \
        gawk \
        git \
        jq \
        liblz4-tool \
        lz4 \
        p7zip-full \
        python3 \
        python3-pip \
        python3-venv \
        rename \
        tar \
        unzip \
        wget \
        xz-utils \
        zlib1g-dev \
        > /dev/null 2>&1

    # Install uv (Python package manager used by DumprX)
    echo "[INFO] Installing uv (Python package manager)..."
    if ! command -v uv &>/dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
    echo "[INFO] uv version: $(uv --version)"

    # Clone DumprX (shallow clone for speed)
    echo "[INFO] Cloning DumprX to ${INSTALL_DIR}..."
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "[INFO] DumprX directory exists, updating..."
        git -C "$INSTALL_DIR" pull --ff-only || true
    else
        git clone --depth=1 --single-branch "$DUMPRX_REPO" "$INSTALL_DIR"
    fi

    # Run DumprX's own setup.sh
    echo "[INFO] Running DumprX setup.sh..."
    cd "$INSTALL_DIR"
    bash setup.sh

    echo "[INFO] DumprX setup complete"
    echo "[INFO] DumprX ready at: ${INSTALL_DIR}"
}

main
