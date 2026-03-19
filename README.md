# Universal Browser Backup Tool

![Banner](docs/images/banner.png)

**A simple, one-click utility to back up and restore browser profiles on Windows.**

Supports Chrome, Edge, Firefox, Brave, Opera, Vivaldi, and Thorium with automatic browser detection, visual icons, and a friendly GUI. No installation required - just download and run.

---

## Features

| Feature | Description |
|---------|-------------|
| **Multi-Browser Support** | Supports 7 popular browsers automatically detected |
| **Visual Interface** | Color-coded browser icons for easy identification |
| **Profile Preview** | Shows profile size before backup |
| **Safety First** | Validates backups, auto-closes browsers, creates backups of existing profiles |
| **Manifest System** | Every backup includes metadata for verification |
| **No Installation** | Pure PowerShell - no dependencies needed |
| **Cross-Version** | Works on Windows 10 and Windows 11 |

---

## Supported Browsers

| Browser | Auto-Detected | Profile Support |
|---------|----------------|-----------------|
| Google Chrome | ✅ | Multiple profiles |
| Microsoft Edge | ✅ | Multiple profiles |
| Mozilla Firefox | ✅ | Multiple profiles |
| Brave | ✅ | Multiple profiles |
| Opera | ✅ | Single profile |
| Vivaldi | ✅ | Multiple profiles |
| Thorium | ✅ | Multiple profiles |

---

## Quick Start

### 1. Download
Download the latest release from the [Releases](https://github.com/theyonecodes/universal-browser-backup-tool/releases) page.

### 2. Run
Double-click `UniversalBrowserBackup.bat`

### 3. Backup
- Select your browser from the visual grid
- Choose "Backup" mode
- Select profile (or "All Profiles")
- Pick a save location
- Click "START BACKUP"

### 4. Restore
- Select your browser
- Choose "Restore" mode
- Select your backup folder
- Choose profile to restore
- Click "START RESTORE"

---

## Screenshots

### Main Interface
![Main Interface](docs/images/main-interface.png)

### Browser Selection
![Browser Selection](docs/images/browser-selection.png)

### Backup Complete
![Backup Complete](docs/images/backup-complete.png)

---

## Requirements

- **Operating System:** Windows 10 or Windows 11
- **PowerShell:** Version 5.1 or later (pre-installed on Windows 10/11)
- **Disk Space:** Depends on profile size (typically 100MB - 2GB)

No additional software required.

---

## Backup Structure

When you create a backup, the following structure is created:

```
Chrome_Backup_20260319_143000/
├── manifest.json          # Backup metadata
├── Default/               # Profile folder
│   ├── Bookmarks
│   ├── History
│   ├── Login Data
│   └── ...
├── Profile 1/
│   └── ...
└── robocopy_Default.log  # Copy logs
```

### Manifest Contents
```json
{
  "version": "1.0.0",
  "tool": "Universal Browser Backup Tool",
  "browser": "Google Chrome",
  "browserVersion": "120.0.6099.130",
  "profile": "All",
  "profiles": ["Default", "Profile 1"],
  "backupTime": "2026-03-19T14:30:00.000Z",
  "totalFiles": 1500,
  "machineName": "DESKTOP-PC",
  "userName": "Username"
}
```

---

## Safety Features

| Feature | Description |
|---------|-------------|
| **Browser Check** | Prompts to close browser if running |
| **Profile Backup** | Renames existing profiles to `.backup_TIMESTAMP` before restore |
| **Manifest Validation** | Verifies backup integrity before restore |
| **Error Handling** | Clear error messages with recovery suggestions |
| **Logging** | All operations logged for troubleshooting |

---

## Roadmap

| Version | Feature |
|---------|---------|
| v1.1.0 | Profile compression (ZIP) |
| v1.1.0 | Scheduled automatic backups |
| v1.2.0 | Cloud storage integration (Google Drive, OneDrive) |
| v2.0.0 | Cross-platform support (macOS, Linux) |

---

## Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Business Requirements](docs/BRD.md)
- [Product Requirements](docs/PRD.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Contributing

Contributions are welcome! Please read the [Contributing Guide](CONTRIBUTING.md) before submitting pull requests.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=theyonecodes/universal-browser-backup-tool&type=Date)](https://star-history.com/#theyonecodes/universal-browser-backup-tool&Date)

---

<p align="center">
  <strong>Made with ❤️ by <a href="https://github.com/theyonecodes">theyonecodes</a></strong>
  <br>
  <sub>Universal Browser Backup Tool v1.0.0</sub>
</p>
