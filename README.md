# Android ROM Firmware Dumper Pipeline

Automated GitHub Actions CI that downloads an Android ROM from Pixeldrain, extracts all firmware partitions using [DumprX](https://github.com/DumprX/DumprX), and pushes the dumped files to [gitgud.io](https://gitgud.io).

## Pipeline Overview

```
Pixeldrain Download → DumprX Extract → Git LFS Push to gitgud.io
```

### What It Does

1. **Downloads** an Android ROM `.zip` from a Pixeldrain share URL using the official Pixeldrain API
2. **Verifies** the download integrity via SHA256 checksum
3. **Extracts** firmware partitions using [DumprX](https://github.com/DumprX/DumprX) — a comprehensive toolkit that supports 20+ firmware formats including:
   - Standard archives (`.zip`, `.rar`, `.7z`, `.tar`)
   - OEM-specific formats (`.ozip`, `.ofp`, `.ops`, `.kdz`, `payload.bin`, `UPDATE.APP`)
   - Raw images (`system.img`, `super.img`, `*.sparsechunk`)
   - OTA formats (`.dat`, `.dat.br`, `.dat.xz`, `payload.bin`)
4. **Pushes** only the extracted firmware files to a gitgud.io repository using Git LFS for large files (>100MB)
5. **Generates** a job summary with a full file manifest

> The original ROM `.zip` is **not** uploaded — only the dumped/extracted partition images and metadata files.

## Supported Firmware Formats

DumprX supports a wide range of Android firmware formats. The most common ones include:

- **Qualcomm**: `payload.bin`, `system.new.dat`, `super.img`, `*.sparsechunk`
- **MediaTek**: `*.scatter*.txt`, `system.img`, `*.ext4`
- **Samsung**: `AP_*.tar.md5`, `*.lz4`
- **Oppo/Realme/OnePlus**: `.ozip`, `.ofp`, `.ops`
- **LG**: `.kdz`
- **Xiaomi**: `.tgz`, `.tar.gz`
- **HTC**: `ruu_*.exe`
- **Huawei**: `UPDATE.APP`
- **Sony**: `*.sin`
- **Spreadtrum**: `*.pac`
- **Nokia**: `*.nb0`

## Prerequisites

### 1. GitHub Repository

Fork or create a repository containing these workflow files.

### 2. gitgud.io Account

- Create a free account at [gitgud.io](https://gitgud.io)
- Create a **personal access token** with `repo` and `write` scopes
- (Optional) Create a **group/organization** to organize firmware dumps

### 3. Configure GitHub Secrets

Go to your repository **Settings → Secrets and variables → Actions** and add:

| Secret | Required | Description |
|--------|----------|-------------|
| `GITGUD_TOKEN` | Yes | gitgud.io personal access token |
| `GITGUD_GROUP` | Yes | gitgud.io group/organization name (e.g. `my-dumps`) |
| `GITGUD_SSH_KEY` | No | Private SSH key for gitgud.io (uses HTTPS+token if not set) |

### 4. Pixeldrain API Key (Optional)

If you expect the file to be rate-limited (many downloads), get a free API key from your Pixeldrain account settings page. This avoids captcha blocks during download.

## Usage

1. Go to **Actions → "Dump Android ROM Firmware"** in your GitHub repository
2. Click **"Run workflow"**
3. Fill in the inputs:

| Input | Required | Example |
|-------|----------|---------|
| **Pixeldrain URL** | Yes | `https://pixeldrain.com/u/PxG66dBX` |
| **Device Name** | Yes | `pixel8a` or `redmi13c` |
| **Firmware Version** | Yes | `15.0.0` or `AP3A.240919.001` |
| **Pixeldrain API Key** | No | Your API key to bypass rate-limits |

4. Wait for the workflow to complete (typically 10–30 minutes)

### Repository Naming

The created gitgud.io repository will be named:

```
firmware-{device_name}-{firmware_version}
```

Examples:
- `firmware-pixel8a-15.0.0`
- `firmware-redmi13c-v14.0.8.0.tnoinxm`
- `firmware-samsung-a55-a556xxu4axk1`

## Project Structure

```
.github/
└── workflows/
    └── dump-rom.yml          # Main CI workflow orchestrator
scripts/
├── download-pixeldrain.sh    # Pixeldrain API download + SHA256 verify
├── setup-dumprx.sh           # DumprX installation + dependency setup
├── dump-firmware.sh          # DumprX execution wrapper
├── push-to-gitgud.sh         # Gitgud.io repo creation + Git LFS push
└── notify-summary.sh         # Job summary generation
```

## Limitations

- **Timeout**: The workflow has a 120-minute timeout. Extremely large firmware packages (>4GB) or complex super images may approach this limit.
- **Disk space**: GitHub Actions runners have ~14GB free. Very large firmware packages may require cleanup steps between stages.
- **Git LFS**: Files larger than 100MB are tracked via Git LFS. Ensure your gitgud.io account has sufficient storage.
- **Format support**: If DumprX doesn't support a particular firmware format, the extraction will fail. Check the [DumprX README](https://github.com/DumprX/DumprX) for the full list.
- **Split super images in OTA**: Split super images as part of OTA/payload extraction may not work in all cases.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Failed to parse file ID" | Ensure the URL is in format `https://pixeldrain.com/u/<ID>` |
| "SHA256 checksum mismatch" | The download was corrupted — re-run the workflow |
| "Rate limit / captcha" | Provide a Pixeldrain API key in the workflow input |
| "DumprX output directory is empty" | The firmware format may not be supported — check the logs |
| "Push failed" | Verify your `GITGUD_TOKEN` is valid and has sufficient permissions |
| "LFS upload failed" | Check gitgud.io LFS storage limits |
