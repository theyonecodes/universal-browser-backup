# Cookbook — `Universal Browser Backup v2.1.1`

Concrete recipes for common jobs. Pick the one that matches your situation.

---

## 0. Detection — "what's installed?"

### PowerShell
```powershell
.\UniversalBrowserBackup.ps1 -List
```

### Python
```bash
python main.py --list
```

Sample output:

```
Installed Browsers:
------------------------------------------------------------
  Chrome (Chromium) v149.0.7827.201
    Type:           Chromium
    Profile folder: C:\Users\me\AppData\Local\Google\Chrome\User Data
      - Default [1595.57 MB] (default)
      - Profile 1 [1281.43 MB]
      ...

  Edge (Chromium) v149.0.7827.201 [RUNNING]
    Type:           Chromium
    Profile folder: C:\Users\me\AppData\Local\Microsoft\Edge\User Data
      - Default [577.28 MB] (default)
```

`[RUNNING]` means the corresponding `.exe` was found in `tasklist`. The GUI uses the same probe, refreshed on each click of **Refresh**.

---

## 1. One-shot backup of the default Chrome profile

### PowerShell
```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "D:\Backups"
```

### Python
```bash
python main.py --backup --browser Chrome --destination "D:\Backups"
```

Result: a folder `D:\Backups\Chrome_Default_YYYYMMDD_HHMMSS\` containing the profile + `manifest.json`.

---

## 2. Backup every profile of every detected browser

### GUI
1. Open `Backup` tab.
2. **Do not** pick a single browser — do nothing in the browser list (the script targets *all* selected).
3. Set destination.
4. **Start Backup**.
5. Wait — progress updates per profile.

### Python (scheduled)
Use the **Schedule** tab, set interval = `60`, destination = your folder, **Apply Schedule**.

---

## 3. Restore onto a fresh Windows machine

### PowerShell
```powershell
.\UniversalBrowserBackup.ps1 -Restore -Browser "Chrome" `
    -Source "\\nas01\backups\me\Chrome_Default_20260702_141522" `
    -Force
```

### Python
```bash
python main.py --restore --browser Chrome --source "\\nas01\backups\me\Chrome_Default_20260702_141522" --force
```

The tool will automatically backup the *current* (empty) profile to `rollback_<ts>` before copying the source. If anything fails part-way through, the rollback restores transparently.

---

## 4. Verify a backup's integrity

### GUI
**Verify** tab → double-click a backup → click **Verify Selected**.
Outcome: `[OK] Verified N critical files successfully.` or a list of mismatches.

### Python
```bash
python main.py --verify --source "D:\Backups\Chrome_Default_20260702_141522"
```

---

## 5. Compare two backups (what changed?)

### GUI
**Backups** tab → click one backup in the *left* list, one in the *right* list → **Compare Two**.

The result panel will tell you:

```
BACKUP COMPARISON
==============================================================
  OLD:  D:\Backups\Chrome_Default_20260701
  NEW:  D:\Backups\Chrome_Default_20260702
  Files in OLD only:    4
  Files in NEW only:    12
  Files modified:       1
  Files identical:      384
==============================================================
[REMOVED FILES (in OLD not in NEW)]
  - Extension Rules/1.0.0_0.crx
  ...
[NEW FILES (in NEW not in OLD)]
  + IndexedDB/...
  ...
[MODIFIED FILES]
  * Login Data
```

### Python
```python
from core.backup import BackupEngine
report = BackupEngine.compare_backups(old_path, new_path)
```

---

## 6. Export a profile as a `.zip` (portable)

### GUI
**Export / Import** tab → pick browser → pick profile → choose output `.zip` → **Export Now**.

### Python
```python
from core.detection import BrowserDetection
from core.backup import BackupEngine

browsers = BrowserDetection.get_installed_browsers()
chrome = next(b for b in browsers if "Chrome" in b["name"])
profiles = BrowserDetection.get_browser_profiles(chrome)
profile = profiles[0]

ok, msg = BackupEngine.export_profile_zip(
    chrome, profile, r"D:\my_chrome_profile.zip"
)
print(ok, msg)
```

The `.zip` excludes `Cache/`, `Code Cache/`, `GPUCache/` so it stays small.

---

## 7. Import a `.zip` profile

### GUI
**Export / Import** tab → "Archive" line → file-picker → **Import Now**.
Destination: `%LOCALAPPDATA%\Imported_Browser_Backups\<browser>_<profile>_<ts>\`

### Python
```python
from core.backup import BackupEngine
result = BackupEngine.import_profile_zip(r"D:\my_chrome_profile.zip")
print(result["browser_name"], "->", result["dest_path"])
```

---

## 8. Schedule hourly backups behind a terminal window

Long-running schedule in Python:

```bash
pythonw.exe main.py   # GUI starts → Schedule tab → Apply
```

To run headless from Task Scheduler instead:

```powershell
# Create a once-per-hour task
$Action = New-ScheduledTaskAction `
    -Execute "python.exe" `
    -Argument "main.py --no-gui --backup --all-profiles --destination D:\Hourly --exclude-cache" `
    -WorkingDirectory "C:\path\to\UniversalBrowserBackup"
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 60)
Register-ScheduledTask -TaskName "Hourly Browser Backup" `
    -Action $Action -Trigger $Trigger
```

---

## 9. Dry-run ("what would happen?")

### PowerShell
```powershell
.\UniversalBrowserBackup.ps1 -Backup -Browser "Chrome" -Destination "X:\test" -WhatIf
```
All logging runs, no files written.

### Python
Wrap the call in a temporary `destination` and inspect the manifest afterwards — Python doesn't have a native `-WhatIf`, but the engines are pure functions, so you can also call `BackupEngine.create_manifest()` on a synthetic empty dir to validate the format.

---

## 10. Recovering from a corrupted backup

1. **Verify** the backup (see recipe #4). If verification fails, **do not** restore.
2. List alternatives with `Backups → Backups` tab.
3. Compare each candidate against the broken one (`Compare Two`) to see which one is closest.
4. Restore the closest candidate with **Force** so the browser relaunches with the recovered profile.

---

## 11. Custom browser config

If you had to install an exotic browser that the auto-detect misses:

1. Open `Config\browsers.json`.
2. Add an entry under `chromiumPaths.local` (e.g. `"MyCorp\\MyBrowser"`).
3. Optionally add a `processNames` entry so `-Force` can kill it.
4. Save. Re-run `-List` to confirm.

Example:

```json
{
  "chromiumPaths": {
    "local": [
      "Google\\Chrome",
      "MyCorp\\MyBrowser"
    ]
  },
  "processNames": {
    "MyBrowser": "mybrowser"
  }
}
```

---

## 12. Logs and where they live

- GUI: **Logs** tab → click **Open Folder**.
- CLI: `python main.py --logs` prints the path.
- Directly: `%APPDATA%\UniversalBrowserBackup\logs\backup_YYYYMMDD_HHMMSS.log`

Default retention: 30 files. Set `maxLogFiles` in `Config\browsers.json` to change.

---

## 13. CI / scripted automation

Both runtimes return Windows-style **exit codes**:

| Exit | Meaning |
|------|---------|
| 0 | Success |
| 1 | Module load failed |
| 3 | Browser or path not found |
| 4 | No profiles found |
| 5 | Operation failed (one or more items) |

So you can do:

```bash
python main.py --backup --browser Chrome --destination "D:\Backups" || (
    echo "Backup failed with %ERRORLEVEL%, trying again tomorrow." | Out-File daily.log -Append
)
```

---

## 14. Want to extend?

* Adding a new browser → edit `Config\browsers.json`.
* Adding a new tab to the Python GUI → extend `MainWindow` in `main.py`.
* Adding a new module to PowerShell → drop a `.psm1` into `Modules\` and add an `Import-Module` line in `UniversalBrowserBackup.ps1`.
* Adding tests → see [Testing in the README](README.md#testing).

---

Happy backing up. 🛡️