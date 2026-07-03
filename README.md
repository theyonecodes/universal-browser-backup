# Universal Browser Backup v2.1.1

A PowerShell + Python tool to back up, restore, verify, compare, schedule, and export browser profiles across Chromium and Gecko browsers on Windows 10/11.

```
   _   _                   ____                            _
  | | | | ___  _ __   ___ | __ )  __ _ _ __ __ _ _ __ ___ (_)_ __
  | | | |/ _ \| '_ \ / _ \|  _ \ / _` | '__/ _` | '_ ` _ \| | '_ \
  | |_| | (_) | | | | (_) | |_) | (_| | | | (_| | | | | | | | | | |
   \___/ \___/|_| |_|\___/|____/ \__,_|_|  \__,_|_| |_| |_|_|_| |_|
              Browser backup · restore · verify · schedule
```

---

## Features

- **Auto-detection** of every Chromium and Gecko browser installed locally — Chrome, Edge, Firefox, Brave, Vivaldi, Opera, Arc, Floorp, Zen, Thorium, Ladybird and 20 + more
- **Multi-profile** — back up individual profiles or every profile at once
- **Multi-browser select** — tick several browsers in the GUI and back them all up in one click
- **Two GUI front-ends** — native WPF dark-theme (PowerShell) and PySide6 (Python); both produce identical backups
- **Full PowerShell + Python CLI** — same flags on both runtimes: `--list`, `--backup`, `--restore`, `--verify`, `--all-profiles`, `--exclude-cache`, etc.
- **Integrity verification** — SHA-256 checksums of every critical file stored in `manifest.json`
- **Backup comparison** — diff two backups; see exactly which files were added, removed or modified
- **Profile export / import** — zip an entire profile for transport, restore the zip on another machine
- **Scheduled backups** — interval-based automatic backups driven by QTimer (Python GUI)
- **Rollback protection** — automatic snap-shot before restore; one-click rollback on failure
- **Smart exclusions** — skips cache, thumbnails, service workers, shader caches, local storage, IndexedDB by default
- **Structured logging** with rotation (default 30 files)
- **Cancelable** — long-running operations can be cancelled from the GUI
- **Cross-runtime** — Windows PowerShell 5.1, PowerShell 7+ (`pwsh`), Python 3.11+

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Detailed Usage](#detailed-usage)
   - [Option A — PowerShell GUI](#option-a--powershell-gui)
   - [Option B — Python GUI (recommended for advanced features)](#option-b--python-gui-recommended-for-advanced-features)
   - [Option C — CLI mode (PowerShell)](#option-c--cli-mode-powershell)
   - [Option D — CLI mode (Python)](#option-d--cli-mode-python)
3. [How Backups Work](#how-backups-work)
4. [How Restore Works](#how-restore-works)
5. [How Verification Works](#how-verification-works)
6. [How Comparison Works](#how-comparison-works)
7. [How Schedule Works](#how-schedule-works)
8. [How Export / Import Works](#how-export--import-works)
9. [Project Structure](#project-structure)
10. [Configuration](#configuration)
11. [CLI Reference](#cli-reference)
12. [Testing](#testing)
13. [Troubleshooting](#troubleshooting)
14. [Requirements](#requirements)
15. [License](#license)

---

## Quick Start

### Windows users — one command

```cmd
:: 1. Install Python deps (only needed for the Python GUI / CLI)
setup.bat

:: 2a. Launch the WPF GUI (no Python needed)
UniversalBrowserBackup.bat

:: 2b. Or launch the Python GUI (richer features)
python main.py

:: 2c. Or use the CLI directly
python main.py --list
```

That's it — no installer, no admin rights, no service registration.

---

## Detailed Usage

### Option A — PowerShell GUI

Double-click `UniversalBrowserBackup.bat`, *or* from PowerShell:

```powershell
.\UniversalBrowserBackup.ps1
```

The WPF window appears:

| Region | Purpose |
|--------|---------|
| **Left panel** | Detected browsers with profile count + size. Select one or more. |
| **Right panel** | Activity log + destination folder picker + Start/Cancel button. |
| **Top radio** | Switch between **Backup** and **Restore** modes. |

When you click **Start Backup** the long-running copy is dispatched to a separate runspace so the UI never freezes; click **Cancel** to abort.

### Option B — Python GUI (recommended for advanced features)

```bash
python main.py
```

The Python GUI has **seven tabs**:

| # | Tab | What it does |
|---|-----|--------------|
| 1 | **Backup** | Pick 1+ browsers → pick profiles → choose destination → start. Shows progress bar and live status. |
| 2 | **Restore** | Pick the target browser + profile → pick a backup folder → start. Rolls back automatically on failure. |
| 3 | **Verify** | Pick any backup folder → SHA-256 re-hash is run and the result is printed in the log. |
| 4 | **Backups** | List every backup produced. **Compare Two** opens a file-level added/removed/modified diff between any two folders. |
| 5 | **Schedule** | Set an interval (in minutes) and a destination; backups of **every** detected browser run on schedule. |
| 6 | **Export / Import** | Zip a profile and save anywhere; paste a `.zip` later to re-hydrate it under `%LOCALAPPDATA%\Imported_Browser_Backups`. |
| 7 | **Logs** | Live tail of `backup_YYYYMMDD_HHMMSS.log` with a button to open the log folder. |

`Refresh` is right next to the browser list — click it whenever you install or remove a browser.

### Option C — CLI mode (PowerShell)

List everything that's detected:

```powershell
.\UniversalBrowserBackup.ps1 -List
```

Back up one profile:

```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups"
```

Back up **every** profile of a browser:

```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -AllProfiles -ExcludeCache
```

Restore:

```powershell
.\UniversalBrowserBackup.ps1 -Restore -Browser "Chrome" -Source "D:\Backups\Chrome_Default_20260702_141522"
```

Preview without changes (PowerShell `-WhatIf` propagates to the modules):

```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -WhatIf
```

Force-snap the browser if it's running:

```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -Force
```

The CLI uses sensible exit codes (0 = success, 3 = not found, 5 = operation failed, etc.) so you can chain it in scripts or scheduled tasks.

### Option D — CLI mode (Python)

```bash
python main.py --version
python main.py --logs
python main.py --list

python main.py --backup --browser Chrome --destination "D:\Backups" --all-profiles --exclude-cache
python main.py --restore --browser Chrome --source "D:\Backups\Chrome_Default_20260702_141522"
python main.py --verify --source "D:\Backups\Chrome_Default_20260702_141522"

python main.py --no-gui --backup --browser Edge --destination "D:\Backups" --force
```

Run `python main.py --help` for the full flag list.

---

## How Backups Work

1. The tool scans your browser fingerprints from `Config\browsers.json` and the `processNames` map.
2. For each selected (browser, profile):
   * If the browser process is running and you didn't pass `-Force` the backup is **refused** (can't robocopy a moving target).
   * If `-Force` is on, the process is killed via `taskkill /F /IM <exe>`.
   * A timestamped folder `<Browser>_<Profile>_<YYYYMMDD_HHMMSS>` is created in the destination.
   * `robocopy /MIR /NP /BYTES /NDL /NFL /NC /NS /MT:4` mirrors the profile into that folder.
   * Anything in `excludeFromBackup` (cache, thumbnails, etc.) is skipped via `/XD`.
   * `manifest.json` is written with stats, browser info, robocopy exit code and SHA-256 checksums of the critical files (Bookmarks, History, Login Data, Cookies, …).
3. Success and a one-line summary are returned (or printed).

A backup is therefore **three things**:

```
<destination>/
└── Chrome_Default_20260702_141522/
    ├── Bookmarks
    ├── Bookmarks.bak
    ├── History
    ...
    └── manifest.json      <- integrity evidence
```

---

## How Restore Works

1. You point the tool at a backup folder.
2. The tool **validates** `manifest.json` is present.
3. A `rollback_<timestamp>` snapshot of the current profile is created next to it (using robocopy with retries).
4. The contents of the backup folder are copied over the live profile.
5. If anything fails, the snapshot is restored; otherwise the snapshot is deleted.

The `-LaunchAfter` flag (PowerShell) relaunches the browser once the restore is complete.

---

## How Verification Works

`BackupEngine.verify_backup(path)` (Python) / `Test-BackupIntegrity` (PowerShell):

1. Reads `manifest.json`.
2. Recomputes SHA-256 on every critical file listed in `checksums`.
3. Compares the recomputed hashes to the stored ones.
4. Returns `success=True` only when **every** hash matches.

A verification failure tells you the backup has been tampered with or corrupted at the block level.

---

## How Comparison Works

`BackupEngine.compare_backups(old, new)` walks both folders and:

| Bucket | Meaning |
|--------|---------|
| `files_only_in_old` | Removed since the old backup |
| `files_only_in_new` | Added since the old backup |
| `files_modified` | Same relative path, different size or different SHA-256 |
| `files_identical` | Same size + same SHA-256 |

This is useful for:
- Spotting telemetry that has changed between snapshots.
- Verifying that a given restore didn't quietly fall back to a different version.
- Triaging "the bookmark toolbar isn't showing my imported bookmarks" type issues.

The GUI's **Backups → Compare Two** tab wraps this in a pretty side-by-side display.

---

## How Schedule Works

The Python GUI exposes a `Schedule` tab:

1. Set the destination folder.
2. Set the interval in minutes (1 – 1440).
3. Click **Apply Schedule**.

Behind the scenes a `QTimer` fires once per interval and runs `BackupEngine.run_backup` on **every** detected browser + profile, using your existing `Config\` defaults. Status is shown in the status bar; logs go to the same `Logs` tab.

Click **Stop Schedule** to disarm it. The schedule is in-process only (closing the GUI stops it).

---

## How Export / Import Works

**Export** zips the entire profile (minus cache folders) into a single `.zip` for transport:

```python
BackupEngine.export_profile_zip(browser, profile, "C:\\my_backup.zip")
```

**Import** extracts a previously exported `.zip` into a managed folder under `%LOCALAPPDATA%\Imported_Browser_Backups\`:

```python
BackupEngine.import_profile_zip("C:\\my_backup.zip")
```

The GUI's **Export / Import** tab wires both of these to file-pickers and shows the destination on success.

---

## Project Structure

```
UniversalBrowserBackup/
├── UniversalBrowserBackup.ps1    # PowerShell CLI entry point
├── UniversalBrowserBackup.bat    # Windows launcher for the WPF GUI
├── main.py                       # Python GUI + CLI entry point
├── requirements.txt              # PySide6, pywin32
├── setup.bat                     # Windows Python install helper
├── setup.sh                      # POSIX Python install helper
│
├── Config/
│   └── browsers.json             # Browser paths, excludes, critical files, process names
│
├── Modules/                      # PowerShell modules (.psm1)
│   ├── Config.psm1               # Config loader (AppData + script-dir fallback)
│   ├── BrowserDetection.psm1     # Chromium + Gecko detection w/ dedup
│   ├── Logging.psm1              # Rotating timestamped logger
│   ├── BackupEngine.psm1         # Robocopy + manifest + SHA256
│   └── RestoreEngine.psm1        # Validate + rollback + restore
│
├── GUI/                          # PowerShell WPF GUI
│   ├── MainWindow.xaml           # XAML dark-theme layout
│   └── App.ps1                   # Runspace-based controller
│
├── core/                         # Python implementation (parity with Modules/)
│   ├── config_manager.py
│   ├── detection.py
│   ├── backup.py                 # + verify / compare / zip export+import
│   ├── restore.py
│   └── logger.py
│
├── Tests/
│   └── BackupEngine.Tests.ps1    # Pester — 18 tests
│
├── py_tests/
│   └── test_core.py              # pytest — 12 tests
│
├── CHANGELOG.md
├── LICENSE
└── README.md                     # ← this file
```

---

## Configuration

Config is loaded in order:

1. `%APPDATA%\UniversalBrowserBackup\browsers.json` (per-user override)
2. `<script>\Config\browsers.json` (shipped defaults)
3. Built-in fallback constants

Override any field by copying `Config\browsers.json` to `%APPDATA%\UniversalBrowserBackup\` and editing the copy. Useful keys:

| Key | Purpose |
|-----|---------|
| `defaults.backupDestination` | Where backups go by default. Supports `%USERPROFILE%`, `%LOCALAPPDATA%`. |
| `defaults.excludeFromBackup` | Sub-folders that `robocopy /XD` will skip. |
| `defaults.robocopyRetries` | Number of retries for locked files. |
| `defaults.robocopyWait` | Seconds between retries. |
| `defaults.maxLogFiles` | How many log files to retain. |
| `defaults.checksumCriticalFiles` | Files rehashed for verification. |
| `chromiumPaths.local` | Local-AppData folders to scan (legacy format). |
| `chromiumPaths.programFiles` | Program-Files folders used to find executables (legacy format). |
| `geckoPaths.appData` | Firefox AppData root (legacy format). |
| `processNames` | `DisplayName → process.exe` mapping for robust browser detection. |
| `browsers[]` | **New format** — 46 browser definitions with `detectStrategy`, `profilePath`, `exePath`, `engineFamily`. |

### Manifest v2.1.1

Every backup creates `manifest.json` with:

```json
{
  "version": "2.1.1",
  "created": "2026-07-03T12:00:00Z",
  "browser": "Chrome",
  "profile": "Default",
  "vTag": "Chrome-Default",
  "selectionHash": "a1b2c3d4e5f6g7h8",
  "preflight": {
    "browserRunning": false,
    "diskFreeGB": 45.2,
    "processName": "chrome.exe"
  },
  "checksums": { ... }
}
```

- **vTag** — short human-readable identifier (`browser-profile`)
- **selectionHash** — SHA-256 truncated to 16 chars; changes if browser/profile/destination selection changes
- **preflight** — snapshot of pre-backup conditions for diagnostics

---

## CLI Reference

### PowerShell (`UniversalBrowserBackup.ps1`)

```
-List                        List detected browsers and profiles, then exit.
-Backup                      Switch to backup mode (must provide Destination).
-Restore                     Switch to restore mode (must provide Source).
-Browser "<name>"            Browser name (substring matches — "Chrome" matches "Google Chrome (Chromium)").
-Profile "<name>"            Profile name (default "Default"). Ignored when -AllProfiles is set.
-AllProfiles                 Back up / restore every profile the browser exposes.
-Destination "<path>"        Required for -Backup. Folder will be created if missing.
-Source "<path>"             Required for -Restore. Must contain manifest.json.
-ExcludeCache                Adds the configured exclude list to the robocopy call.
-Force                       Kills the browser process before touching the profile.
-LaunchAfter                 (Restore only) Opens the browser after restore.
-WhatIf                      PowerShell preview mode — no writes.
-ConfigPath "<path>"         Use an explicit config file instead of the default discovery.
```

### Python (`main.py`)

```
--version                    Print version and exit.
--logs                       Print log file path and exit.
--list                       List detected browsers and exit.
--backup                     Run a backup from CLI.
--restore                    Run a restore from CLI.
--verify                     Verify a backup folder from CLI.
--browser "<name>"           Filter for the browser you want.
--profile "<name>"           Profile name (default "Default").
--destination "<path>"       Required with --backup.
--source "<path>"            Required with --restore / --verify.
--all-profiles               Backup every profile.
--exclude-cache              Skip cache, thumbnails, etc.
--force                      Kill the browser process first.
--no-gui                     (Implicit whenever --list / --backup / --restore / --verify is used.)
```

Run any tool with `--help` for the live description.

---

## Testing

```powershell
# Pester (PowerShell)
Invoke-Pester Tests\BackupEngine.Tests.ps1
```

```bash
# pytest (Python)
python -m pytest py_tests/ -v
```

Current counts: **18 + 12 = 30 tests, all passing.**

Tests cover: config loading, browser detection, profile discovery, dedup, process-name mapping, rotated logging, manifest integrity, and every Python backup-tool variant (verify / compare / zip / list).

---

## Troubleshooting

### "Character '0' was unexpected in string '0'" on GUI launch

You're on Windows PowerShell 5.1 and the XAML has been modified to contain non-ASCII characters. The shipped `MainWindow.xaml` uses full ARGB hex colors (`#FF1E1E2E` etc.) and no emoji — if you've edited it, only use ASCII glyphs.

### `UniversalBrowserBackup.bat` opens and closes immediately

Make sure your editor saved the file with Windows line endings (`CRLF`). Run `.\UniversalBrowserBackup.bat` from a regular `cmd.exe`, **not** from PowerShell with strict-mode `Set-StrictMode -Version Latest`, because the bat relies on `!errorlevel!` delayed expansion.

### "Browser is running" but you've already closed it

Open `Task Manager → Details`, sort by *Image name*, look for `chrome.exe` / `msedge.exe` / `brave.exe` etc., and end any zombie processes. The `--force` flag automates this.

### "Cannot create destination" / "Access denied"

The destination must be writable for the current user. On managed Windows machines `C:\Program Files\…` is often blocked; choose `D:\Backups` or `\\nas01\backups\me` instead.

### Backup is much smaller than the profile

This is **expected** when `ExcludeCache` is used. The default exclude list drops ~30 % of a typical profile's volume (cache, thumbnails, IndexedDB, etc.). Toggle the option off if you want a literal mirror.

### Logs are huge / filling the disk

`maxLogFiles` defaults to 30 in `Config\browsers.json`. Bump it down, or clear `%APPDATA%\UniversalBrowserBackup\logs\` manually.

---

## Requirements

| | |
|---|---|
| **OS** | Windows 10 / 11 |
| **PowerShell** | Windows PowerShell 5.1 *or* PowerShell 7+ (`pwsh`) |
| **Python** | 3.11+ (only for the Python GUI / CLI) |
| **Python deps** | `PySide6`, `pywin32` (installed by `setup.bat`) |
| **Privileges** | Standard user; no admin required |
| **Internet** | Not required. Tool talks to no remote endpoint. |

---

## License

MIT — see [LICENSE](LICENSE).