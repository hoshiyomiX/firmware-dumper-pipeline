# 📦 Firmware Dumper Pipeline

[![CI: Dump Android ROM Firmware](https://img.shields.io/github/actions/workflow/status/hoshiyomiX/firmware-dumper-pipeline/dump-rom.yml?branch=main&label=Dump%20ROM&logo=github&style=flat-square)](https://github.com/hoshiyomiX/firmware-dumper-pipeline/actions)
[![License: MIT](https://img.shields.io/github/license/hoshiyomiX/firmware-dumper-pipeline?style=flat-square)](LICENSE)

Automated GitHub Actions pipeline that downloads an Android ROM from [Pixeldrain](https://pixeldrain.com), extracts firmware partitions using [DumprX](https://github.com/DumprX/DumprX), and pushes the results to [gitgud.io](https://gitgud.io) via SSH + Git LFS.

## Overview

```
Download (Pixeldrain) → DumprX Extract → Git LFS Push to gitgud.io
```

| Step | What happens |
|------|-------------|
| **1. Download** | Fetches the ROM from Pixeldrain (SHA256 verified) via API |
| **2. Extract** | Runs DumprX to unpack firmware partitions (20+ formats: `payload.bin`, `.ozip`, `.ofp`, `UPDATE.APP`, etc.) |
| **3. Push** | Creates a repo on gitgud.io, commits extracted files with all-files-LFS, pushes via SSH |

> The original ROM archive is **not uploaded** — only the extracted partition images and metadata.

## Supported Formats

DumprX handles a wide range of Android firmware packaging formats. Common ones include:

| OEM | Formats |
|-----|---------|
| Qualcomm | `payload.bin`, `system.new.dat`, `super.img`, `*.sparsechunk` |
| MediaTek | `*.scatter*.txt`, `system.img`, `*.ext4` |
| Samsung | `AP_*.tar.md5`, `*.lz4` |
| Oppo / Realme / OnePlus | `.ozip`, `.ofp`, `.ops` |
| LG | `.kdz` |
| Xiaomi | `.tgz`, `.tar.gz` |
| Huawei | `UPDATE.APP` |
| Sony | `*.sin` |
| HTC | `ruu_*.exe` |
| Spreadtrum | `*.pac` |
| Nokia | `*.nb0` |

## Setup

### 1. Fork / Clone

```bash
git clone https://github.com/hoshiyomiX/firmware-dumper-pipeline.git
```

### 2. gitgud.io Account

- Sign up at [gitgud.io](https://gitgud.io)
- Create a **personal access token** with `repo` and `write` scopes
- Optionally create a group/organization to organize firmware dumps

### 3. GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and configure:

| Secret | Required | Description |
|--------|----------|-------------|
| `GITGUD_SSH_KEY` | No* | ED25519 private SSH key for gitgud.io (recommended, primary auth) |
| `GITGUD_TOKEN` | No* | gitgud.io personal access token (fallback auth; also used for API repo creation) |
| `GITGUD_GROUP` | Yes | gitgud.io group/organization name (e.g. `my-dumps`) |

> *At least one of `GITGUD_SSH_KEY` or `GITGUD_TOKEN` is required. When both are set, the SSH key handles git push and the token is used for API repo creation. SSH-only mode (no token) works for pushing, but the target repo must be created manually on gitgud.io beforehand.

### 4. Pixeldrain API Key (Optional)

Add a Pixeldrain API key in the workflow input to bypass rate-limits and captcha challenges. Get one free from your Pixeldrain account settings.

## Usage

1. Navigate to **Actions → "Dump Android ROM Firmware"**
2. Click **"Run workflow"**
3. Fill in the inputs:

| Input | Required | Example |
|-------|----------|---------|
| **Pixeldrain URL** | Yes | `https://pixeldrain.com/u/PxG66dBX` |
| **Device Name** | Yes | `pixel8a` or `redmi13c` |
| **Firmware Version** | Yes | `15.0.0` or `AP3A.240919.001` |
| **Pixeldrain API Key** | No | API key to bypass rate-limits |

4. Wait for the workflow to complete (typically 15–90 minutes depending on ROM size and LFS upload speed)

### Repository Naming

The created gitgud.io repository follows this format (uppercase):

```
FIRMWARE-{DEVICE_NAME}-{FIRMWARE_VERSION}
```

Examples:
- `FIRMWARE-PIXEL8A-15.0.0`
- `FIRMWARE-REDMI13C-V14.0.8.0.TNOINXM`
- `FIRMWARE-SAMSUNG-A55-A556XXU4AXK1`

## Project Structure

```
.github/
└── workflows/
    └── dump-rom.yml               # Full pipeline: download → extract → push
scripts/
├── download-pixeldrain.sh        # Pixeldrain API download + SHA256 verification
├── setup-dumprx.sh               # DumprX installation + dependency setup
├── dump-firmware.sh              # DumprX execution wrapper + manifest generation
├── push-to-gitgud.sh             # gitgud.io repo creation + Git LFS push
└── notify-summary.sh             # GitHub Actions job summary generation
```

## How It Works

### Authentication (SSH primary, token fallback)

The pipeline prefers SSH key authentication for git operations. When `GITGUD_SSH_KEY` is set, git push goes through `git@gitgud.io` over SSH. If only `GITGUD_TOKEN` is available, the pipeline falls back to HTTPS with `.netrc` credential storage. The token (when available) is always used for Gitea API calls (repo creation, existence checks).

### LFS Strategy

All files are tracked via Git LFS using a single `*` wildcard in `.gitattributes`. This means the git pack only contains ~130-byte pointer stubs per file plus `.gitattributes` itself — keeping the pack tiny regardless of total firmware size. LFS objects upload separately via the batch API and are not subject to gitgud.io's SSH push limit.

## Limitations

- **Timeout**: The workflow has a 360-minute timeout. Large firmware dumps with many LFS objects may take 60–90 minutes for the push step alone.
- **Push size limit**: gitgud.io enforces a **4.883 GiB** maximum git pack size. With the all-files-LFS strategy this is not a concern — only pointer stubs and `.gitattributes` enter the pack.
- **Disk space**: GitHub Actions runners have ~14 GB free. Very large firmware packages may require cleanup steps between stages.
- **Git LFS**: Ensure your gitgud.io account has sufficient LFS storage. All extracted files are tracked via LFS.
- **Format support**: If DumprX doesn't support a particular firmware format, extraction will fail. Check the [DumprX README](https://github.com/DumprX/DumprX) for the full list.
- **Split super images in OTA**: Split super images as part of OTA/payload extraction may not work in all cases.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Failed to parse file ID` | Ensure the URL is in format `https://pixeldrain.com/u/<ID>` |
| `SHA256 checksum mismatch` | The download was corrupted — re-run the workflow |
| `Rate limit / captcha` | Provide a Pixeldrain API key in the workflow input |
| `DumprX output directory is empty` | The firmware format may not be supported — check the logs |
| `Push failed` | Verify your `GITGUD_SSH_KEY` or `GITGUD_TOKEN` is valid |
| `No authentication configured` | Add at least one of `GITGUD_SSH_KEY` or `GITGUD_TOKEN` in GitHub Secrets |
| `Repository must already exist` | In SSH-only mode (no token), create the repo on gitgud.io manually first |
| `LFS upload failed` | Check gitgud.io LFS storage limits |

## License

MIT
