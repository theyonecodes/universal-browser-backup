# Universal Browser Backup v2.0

A PowerShell tool for backing up and restoring browser profiles across Chromium and Gecko browsers.

## Features

- **Auto-detection** of all installed Chromium and Gecko browsers
- **Multi-profile** support — backup individual profiles or all at once
- **CLI + GUI** — command-line automation or visual interface
- **Integrity verification** — SHA256 checksums of critical files
- **Rollback protection** — automatic backup before restore
- **Smart exclusions** — skips cache, thumbnails, service workers by default
- **Structured logging** — timestamped logs with rotation

## Supported Browsers

### Chromium (auto-detected)
Google Chrome, Microsoft Edge, Brave, Vivaldi, Opera, Opera GX, Arc, Floorp, Zen Browser, Yandex, UC Browser, Avast, AVG, CCleaner Browser, Epic Privacy, Comodo Dragon, SRWare Iron

### Gecko (auto-detected)
Mozilla Firefox, Floorp, Waterfox

## Quick Start

### GUI Mode (default)
```powershell
.\UniversalBrowserBackup.ps1
```
Or double-click `UniversalBrowserBackup.bat`

### CLI Mode
```powershell
# List all detected browsers and profiles
.\UniversalBrowserBackup.ps1 -List

# Backup Chrome Default profile
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups"

# Backup all Chrome profiles
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -AllProfiles -ExcludeCache

# Backup with force (stops browser if running)
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -AllProfiles -Force

# Restore from backup
.\UniversalBrowserBackup.ps1 -Restore -Browser "Chrome" -Source "D:\Backups\Chrome_Default_20260702"

# Preview without changes
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups" -WhatIf
```

## Project Structure

```
UniversalBrowserBackup/
├── UniversalBrowserBackup.ps1    # CLI entry point
├── UniversalBrowserBackup.bat    # Batch launcher
├── Config/
│   └── browsers.json             # Browser paths and defaults
├── Modules/
│   ├── Config.psm1               # Config loading (AppData + script fallback)
│   ├── BrowserDetection.psm1     # Auto-detect Chromium/Gecko browsers
│   ├── Logging.psm1              # Timestamped structured logging
│   ├── BackupEngine.psm1         # Robocopy backup + manifest + SHA256
│   └── RestoreEngine.psm1        # Validate + rollback + restore
├── GUI/
│   ├── MainWindow.xaml           # WPF dark theme layout
│   └── App.ps1                   # GUI controller with async execution
└── Tests/
    └── BackupEngine.Tests.ps1    # Pester test suite
```

## Configuration

Config is loaded from (in priority order):
1. `%APPDATA%\UniversalBrowserBackup\browsers.json`
2. `<script>\Config\browsers.json` (fallback)

### Default Excluded Directories
Cache, Code Cache, Service Worker, cache2, startupCache, GPUCache, Thumbnails, blob_storage, Network, Session Storage

## CLI Parameters

| Parameter | Description |
|-----------|-------------|
| `-List` | Show all detected browsers and profiles |
| `-Backup` | Start a backup operation |
| `-Restore` | Start a restore operation |
| `-Browser <name>` | Browser name (partial match supported) |
| `-Profile <name>` | Profile to backup/restore (default: "Default") |
| `-AllProfiles` | Backup/restore all profiles |
| `-Destination <path>` | Backup destination folder |
| `-Source <path>` | Backup source folder (for restore) |
| `-ExcludeCache` | Skip cache directories |
| `-Force` | Stop browser if running |
| `-WhatIf` | Preview without changes |

## Requirements

- PowerShell 5.1+ (Windows PowerShell)
- Windows 10/11
- No external dependencies

## License

MIT
