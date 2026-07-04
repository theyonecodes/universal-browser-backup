# Troubleshooting Guide

## Common Issues and Solutions

### Issue: "No browsers detected"

**Symptom:** The tool shows "No supported browsers found"

**Causes:**
- Browsers not installed
- Browser profile folder doesn't exist
- Insufficient permissions

**Solutions:**

1. **Verify browser is installed:**
   - Chrome: `%LOCALAPPDATA%\Google\Chrome\User Data`
   - Edge: `%LOCALAPPDATA%\Microsoft\Edge\User Data`
   - Firefox: `%APPDATA%\Mozilla\Firefox\Profiles`
   - Brave: `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data`
   - Opera: `%APPDATA%\Opera Software\Opera Stable`
   - Vivaldi: `%LOCALAPPDATA%\Vivaldi\User Data`
   - Thorium: `%LOCALAPPDATA%\Thorium\User Data`

2. **Run browser at least once:**
   - Launch the browser normally
   - It will create the profile folder on first run

3. **Check permissions:**
   - Ensure you have read access to browser folders
   - Run as Administrator if needed

---

### Issue: "Browser is currently running"

**Symptom:** Tool blocks and shows browser running error

**Solution:**
1. Close all windows of the browser
2. Check system tray (bottom-right) for hidden browser icons
3. If browser is stuck, open Task Manager (Ctrl+Shift+Esc)
4. End the browser process
5. Click OK in the tool prompt

---

### Issue: "Invalid backup folder"

**Symptom:** Restore fails with manifest.json not found error

**Solutions:**
1. Select the correct backup folder (the root folder, not a subfolder)
2. Ensure `manifest.json` exists in the selected folder
3. Don't select individual profile folders inside the backup

**Correct folder structure:**
```
Chrome_Backup_20260319_143000/    ← SELECT THIS
├── manifest.json
├── Default/
│   └── ...
└── Profile 1/
    └── ...
```

---

### Issue: "Access Denied" during backup/restore

**Symptom:** Tool shows access denied error

**Solutions:**

1. **Run as Administrator:**
   - Right-click `UniversalBrowserBackup.bat`
   - Select "Run as Administrator"

2. **Close browser completely:**
   - Some browsers lock files while running

3. **Check folder permissions:**
   - Ensure you can write to destination folder
   - Try Desktop or Documents as destination

---

### Issue: Backup is taking too long

**Symptom:** Backup operation seems stuck

**Solutions:**
1. Large profiles take time (500MB+ can take several minutes)
2. Check Task Manager for disk activity
3. Backups cannot be cancelled once started
4. For faster backups, consider:
   - Excluding cache folders manually
   - Using SSD as destination

---

### Issue: Profile size shows 0 MB

**Symptom:** Profile size shows as 0 MB in dropdown

**Explanation:**
- Size calculation may be slow for large profiles
- Size is calculated at profile detection time
- Actual backup size will be correct

**Solution:**
- Proceed with backup - actual size will be accurate

---

### Issue: Restore didn't restore all data

**Symptom:** After restore, some data is missing

**Solutions:**
1. **Check backup integrity:**
   - Verify manifest.json exists
   - Check robocopy logs in backup folder

2. **Check old profile backup:**
   - Old profiles renamed to `.backup_TIMESTAMP`
   - Check if data is in old profile folder

3. **Browser-specific data:**
   - Some browser data (e.g., extension settings) may not restore
   - Passwords stored in OS keychain may need re-entry

---

### Issue: Tool won't start

**Symptom:** Nothing happens when double-clicking bat file

**Solutions:**

1. **Check PowerShell is available:**
   ```powershell
   powershell -version
   ```

2. **Try running PowerShell directly:**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\UniversalBrowserBackup.ps1"
   ```

3. **Check for errors:**
   - Right-click bat file → Edit
   - Run the powershell command manually
   - Note any error messages

---

### Issue: Browser won't launch after restore

**Symptom:** Restore completes but browser doesn't start

**Solutions:**
1. Check "Launch browser after restore" option
2. Manually launch browser from Start Menu
3. Verify browser executable exists at expected path
4. Some browsers may require restart

---

### Issue: PowerShell execution policy error

**Symptom:** "Cannot be loaded because running scripts is disabled"

**Solution:**

Option 1 - Run as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Option 2 - Use bypass flag (tool already does this):
```powershell
powershell -ExecutionPolicy Bypass -File ".\UniversalBrowserBackup.ps1"
```

---

## Performance Tips

| Tip | Impact |
|-----|--------|
| Use SSD for backup destination | 2-3x faster |
| Close unnecessary programs | More RAM for operation |
| Exclude cache from manual backup | Smaller backup size |
| Backup regularly | Smaller incremental changes |

---

## Getting Help

If you've tried these solutions and still have issues:

1. Check existing [GitHub Issues](https://github.com/theyonecodes/universal-browser-backup-tool/issues)
2. Create a new issue with:
   - Windows version
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Browser(s) and versions
   - Error messages
   - Steps to reproduce

---

## Known Limitations

| Limitation | Description |
|------------|-------------|
| Browser must be closed | Cannot backup/restore while browser is running |
| Large profiles | May take several minutes for profiles > 1GB |
| Extension data | Some extension settings may not restore |
| Browser sync | External sync (Chrome, Edge) not affected |
| OS keychain | Saved passwords may need re-entry |

---

*Last updated: 2026-03-19*
