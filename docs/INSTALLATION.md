# Installation Guide

## Quick Install (Recommended)

### Step 1: Download

Download the latest release from the [Releases](https://github.com/theyonecodes/universal-browser-backup-tool/releases) page.

You will receive a ZIP file containing:
```
UniversalBrowserBackup.bat
UniversalBrowserBackup.ps1
LICENSE
README.md
```

### Step 2: Extract

Extract the ZIP file to your desired location, for example:
- Desktop
- Documents
- USB Drive (for portable use)

### Step 3: Run

Double-click `UniversalBrowserBackup.bat`

That's it! No installation required.

---

## System Requirements

### Minimum Requirements
| Component | Requirement |
|-----------|-------------|
| OS | Windows 10 or Windows 11 |
| PowerShell | Version 5.1 or later |
| RAM | 4 GB |
| Disk Space | 100 MB (plus backup storage) |
| Display | 800x600 resolution |

### Recommended Requirements
| Component | Requirement |
|-----------|-------------|
| OS | Windows 11 (latest updates) |
| PowerShell | Version 7.0+ |
| RAM | 8 GB or more |
| Disk Space | 1 GB+ (for backups) |

---

## Verifying Installation

### Check PowerShell Version

Open PowerShell and run:
```powershell
$PSVersionTable.PSVersion
```

You should see version 5.1 or higher.

### Check GitHub Repository

Visit: https://github.com/theyonecodes/universal-browser-backup-tool

Verify you're using the latest version by checking the Releases page.

---

## Portable Installation (USB)

For portable use (e.g., IT technicians):

1. Create a folder on your USB drive (e.g., `BrowserBackupTool`)
2. Extract all files to that folder
3. Run `UniversalBrowserBackup.bat` from the USB

### Advantages
- ✅ No installation on host PC
- ✅ Works on any Windows 10/11 PC
- ✅ Portable across machines
- ✅ Leave no traces on host PC

### Limitations
- ⚠️ Backups stored locally on each PC
- ⚠️ Requires USB drive access

---

## System-Wide Installation

For IT administrators who want to deploy to multiple machines:

### Option 1: Batch File Distribution

1. Create a shared network folder
2. Place `UniversalBrowserBackup.bat` and `UniversalBrowserBackup.ps1` in the folder
3. Create a shortcut to `UniversalBrowserBackup.bat`
4. Distribute shortcut to users

### Option 2: Software Deployment

Use your preferred deployment tool (SCCM, Intune, PDQ Deploy, etc.) to:
1. Copy files to a local folder (e.g., `C:\Program Files\BrowserBackupTool`)
2. Create a Start Menu shortcut
3. Optionally create a Desktop shortcut

### Option 3: Portable Mode

Users can extract and run from any location they choose.

---

## Post-Installation

### First Run Checklist

1. ✅ Close all browsers
2. ✅ Double-click `UniversalBrowserBackup.bat`
3. ✅ Verify browser detection (should show installed browsers)
4. ✅ Test with a small backup to a test folder
5. ✅ Verify backup contains `manifest.json`

### Configuration (Optional)

The tool stores no persistent configuration. All settings are per-session.

For custom default backup location, you can:
1. Edit `UniversalBrowserBackup.ps1`
2. Find the line: `$script:txtFolder.Text = [Environment]::GetFolderPath("Desktop")`
3. Change to your preferred path

---

## Uninstallation

To remove the tool:

1. Delete the folder containing the tool files
2. Delete any backup folders you created
3. No registry changes or system files are modified

---

## Updating

To update to a new version:

1. Close the tool if running
2. Download the new release
3. Replace the old files with new files
4. Keep your backup folders (they are compatible)

---

## Troubleshooting Installation

### "Cannot run scripts" Error

If you see a PowerShell execution policy error:

1. Right-click `UniversalBrowserBackup.bat`
2. Select "Run as Administrator"
3. Or run PowerShell as Admin and execute:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### "Access Denied" Error

Ensure you have write permissions to the target folder.

### Browser Not Detected

- Ensure browser is installed
- Ensure browser has been run at least once to create profile
- Try running the browser normally first

---

## Next Steps

- Read the [README](README.md) for usage instructions
- See [Troubleshooting](docs/TROUBLESHOOTING.md) for common issues
- Review [Security Policy](SECURITY.md) for security information

---

*For additional help, please open an issue on GitHub.*
