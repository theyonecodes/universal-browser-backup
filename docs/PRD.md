# Universal Browser Backup Tool - PRD

## 1. Product Overview

**Product Name:** Universal Browser Backup Tool  
**Product Type:** Desktop Utility Application  
**Version:** 1.0.0  
**Author:** theyonecodes

### Product Vision
A simple, visual, one-click backup and restore utility for browser profiles that works for any user regardless of technical expertise. Users should be able to protect their browser data (bookmarks, history, passwords, extensions, settings) in under 2 minutes without any configuration.

### Product Positioning
Positioned as the "Time Machine for Browsers" - providing the same simplicity Apple users expect from Time Machine, but for browser data on Windows. Unlike complex migration tools or manual folder copying, this tool provides instant visual feedback and safety checks.

---

## 2. Feature Specifications

### F1: Browser Auto-Detection
**Priority:** P0 (Critical)

**Description:** Automatically detect installed browsers on the system and display them in a visual list.

**Requirements:**
- Detect browsers by checking known registry keys and folder paths
- Only show browsers actually installed on the system
- Display browser name and icon
- Show profile count for each browser
- Handle cases where browser is partially installed

**Browsers to Detect (v1.0):**
- Thorium
- Google Chrome
- Microsoft Edge
- Brave
- Mozilla Firefox
- Opera
- Vivaldi

**Edge Cases:**
- Browser installed but profile folder missing → Show "No profiles found"
- Browser partially installed → Show warning icon
- All browsers missing → Show error message with installation suggestions

---

### F2: Visual Browser Selector
**Priority:** P0 (Critical)

**Description:** Display browsers as clickable cards/tiles with icons for easy selection.

**Requirements:**
- Each browser displayed as a card with:
  - Browser icon (32x32 or 48x48 pixels)
  - Browser name
  - Profile count badge
- Selected browser highlighted with border/glow
- Smooth hover animations
- Keyboard navigation support (arrow keys + Enter)

**Visual Specifications:**
- Card size: 150x100 pixels
- Icon size: 48x48 pixels centered
- Grid layout: 3-4 cards per row depending on window size
- Selected state: Blue border (#0078D4) + subtle shadow
- Hover state: Slight scale up (1.05x) + lighter background

---

### F3: Profile Selection
**Priority:** P0 (Critical)

**Description:** Allow users to select which profile(s) to backup or restore.

**Requirements:**
- Dropdown or list showing all detected profiles
- Special option "All Profiles" for complete backup
- Show profile name and approximate size
- Remember last selected profile (optional)

**Profile Sources:**
- Default profile
- Profile 1, Profile 2, etc.
- Additional profiles created by user

---

### F4: Backup Operation
**Priority:** P0 (Critical)

**Description:** Create a backup of selected profile(s) to user-specified location.

**Requirements:**
- Create timestamped backup folder: `BrowserName_Backup_YYYYMMDD_HHMMSS`
- Copy all profile data using Robocopy (mirror mode)
- Preserve file timestamps and permissions
- Create manifest.json with backup metadata
- Show progress (optional for v1.0)
- Display success message with backup location

**Manifest Schema:**
```json
{
  "version": "1.0.0",
  "browser": "Chrome",
  "browserVersion": "120.0.6099.130",
  "profile": "Default",
  "backupTime": "2026-03-19T12:00:00Z",
  "fileCount": 1500,
  "totalSizeBytes": 524288000,
  "checksum": "sha256:abc123..."
}
```

---

### F5: Restore Operation
**Priority:** P0 (Critical)

**Requirements:**
- Validate backup folder contains manifest.json
- Parse manifest to verify backup integrity
- Check if browser is closed (safety check)
- Rename existing profile to `ProfileName.bak_TIMESTAMP` (safety)
- Copy backup data to profile location
- Optionally launch browser after restore
- Display success message

**Safety Features:**
- Never delete existing profile without backup
- Validate manifest before any restore
- Require explicit folder selection (not automatic)

---

### F6: Safety & Validation
**Priority:** P0 (Critical)

**Requirements:**
- Check browser is not running before backup/restore
- Validate backup folder structure
- Check available disk space before backup
- Provide clear error messages for all failure cases
- Log all operations to session log file

**Error Messages:**
- "Browser is running. Please close [Browser Name] before continuing."
- "Not enough disk space. Need X MB, only Y MB available."
- "Invalid backup folder. Please select a valid backup."
- "Backup failed. Check log file for details."

---

### F7: Folder Selection
**Priority:** P1 (High)

**Requirements:**
- Use native Windows folder browser dialog
- Remember last used folder (optional)
- Default to user's Documents folder
- Show folder path in text field for confirmation

---

### F8: Logging
**Priority:** P1 (High)

**Requirements:**
- Create log file in same directory as batch file
- Log filename: `BrowserBackupRestore_YYYYMMDD_HHMMSS.log`
- Log内容包括:
  - Operation start/end times
  - Selected browser and profile
  - Source and destination paths
  - File count and total size
  - Any warnings or errors
  - Operation result (success/failure)

---

### F9: Auto-Launch After Restore
**Priority:** P2 (Medium)

**Requirements:**
- Checkbox option "Launch browser after restore"
- Only visible/enabled in Restore mode
- Launch browser executable after successful restore
- Launch with normal user profile

---

### F10: Multi-Language Support
**Priority:** P3 (Future)

**Requirements:**
- English (default)
- Language selection in settings (future)
- Externalized strings for easy translation

---

## 3. UI/UX Specifications

### Window Properties
- **Size:** 600x500 pixels (resizable, minimum 500x400)
- **Title:** "Universal Browser Backup Tool"
- **Start Position:** Center screen
- **Style:** Modern Windows 11 aesthetic
- **Theme:** Light theme (dark theme future)

### Layout Structure
```
┌─────────────────────────────────────────────────────┐
│  [Icon] Universal Browser Backup Tool      [─][□][×] │
├─────────────────────────────────────────────────────┤
│                                                     │
│   ┌─────────────────────────────────────────────┐   │
│   │          SELECT BROWSER                     │   │
│   │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐          │   │
│   │  │Chrome│ │Edge │ │Firefox│ │Brave│          │   │
│   │  └─────┘ └─────┘ └─────┘ └─────┘          │   │
│   │  ┌─────┐ ┌─────┐ ┌─────┐                   │   │
│   │  │Opera│ │Vivaldi│ │Thorium│                │   │
│   │  └─────┘ └─────┘ └─────┘                   │   │
│   └─────────────────────────────────────────────┘   │
│                                                     │
│   ┌─────────────────────────────────────────────┐   │
│   │  Operation: (•) Backup  ( ) Restore         │   │
│   │  Profile:   [Default ▼]                    │   │
│   │  Location:  [________________...] [Browse]   │   │
│   │  ☐ Launch browser after restore             │   │
│   └─────────────────────────────────────────────┘   │
│                                                     │
│              [    Start Operation    ]              │
│                                                     │
│   Status: Ready                                      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Color Palette
| Element | Color | Hex |
|---------|-------|-----|
| Primary | Blue | #0078D4 |
| Primary Hover | Dark Blue | #106EBE |
| Background | White | #FFFFFF |
| Card Background | Light Gray | #F3F3F3 |
| Card Hover | Lighter Gray | #E5E5E5 |
| Selected Border | Blue | #0078D4 |
| Text Primary | Dark Gray | #1A1A1A |
| Text Secondary | Medium Gray | #666666 |
| Success | Green | #107C10 |
| Error | Red | #D13438 |
| Warning | Orange | #FF8C00 |

### Typography
| Element | Font | Size | Weight |
|---------|------|------|--------|
| Window Title | Segoe UI | 14px | Semibold |
| Section Headers | Segoe UI | 12px | Semibold |
| Body Text | Segoe UI | 11px | Regular |
| Button Text | Segoe UI | 11px | Semibold |
| Status Text | Segoe UI | 10px | Regular |

### Spacing
- Window padding: 16px
- Section spacing: 16px
- Card gap: 12px
- Button padding: 12px horizontal, 8px vertical
- Card padding: 12px

---

## 4. Functional Specifications

### 4.1 Application Flow

#### Backup Flow
```
Start
  │
  ▼
Detect Browsers ──► No Browsers Found ──► Show Error ──► End
  │
  │ Found
  ▼
Display Browser Grid
  │
  ▼
User Selects Browser ──► Load Profiles
  │
  ▼
Select "Backup" Mode
  │
  ▼
Select Profile (or All)
  │
  ▼
Browse for Destination Folder
  │
  ▼
Click "Start"
  │
  ▼
Check Browser Closed? ──► No ──► Show Error ──► End
  │
  │ Yes
  ▼
Check Disk Space
  │
  │ Insufficient
  ▼
Show Error ──► End
  │
  │ Sufficient
  ▼
Create Backup Folder
  │
  ▼
Robocopy Profile(s)
  │
  ▼
Create Manifest
  │
  ▼
Show Success ──► End
```

#### Restore Flow
```
Start
  │
  ▼
Browse for Backup Folder
  │
  ▼
Validate Manifest
  │
  │ Invalid
  ▼
Show Error ──► End
  │
  │ Valid
  ▼
Display Backup Info (Browser, Profile, Date)
  │
  ▼
Select Profile to Restore
  │
  ▼
Click "Start"
  │
  ▼
Check Browser Closed? ──► No ──► Show Error ──► End
  │
  │ Yes
  ▼
Rename Existing Profile (.bak)
  │
  ▼
Robocopy Backup to Profile
  │
  ▼
Show Success (+ Launch Option)
  │
  ▼
End
```

### 4.2 Data Flow

#### Browser Detection Module
```
Input: None
Process:
  1. Check registry for installed browsers
  2. Check common installation paths
  3. Verify profile folder exists
  4. Count profiles in User Data folder
Output: List<Browser> { Name, IconPath, ProfileCount, ProfilePath }
```

#### Backup Module
```
Input: Browser, Profile, DestinationPath
Process:
  1. Verify browser not running
  2. Create timestamped folder
  3. Robocopy profile data
  4. Create manifest.json
  5. Log operation
Output: BackupResult { Success, BackupPath, FileCount, Size }
```

#### Restore Module
```
Input: BackupPath, Profile
Process:
  1. Validate manifest.json
  2. Verify browser not running
  3. Backup existing profile (.bak)
  4. Robocopy backup to profile location
  5. Log operation
Output: RestoreResult { Success, RestoredPath }
```

---

## 5. Acceptance Criteria

### AC-01: Browser Detection
- [ ] All 7 supported browsers detected when installed
- [ ] Only installed browsers shown in grid
- [ ] Browser icons displayed correctly
- [ ] Profile count shown accurately
- [ ] Graceful handling when no browsers found

### AC-02: Backup Operation
- [ ] Single profile backup completes successfully
- [ ] All profiles backup includes all profiles
- [ ] Manifest.json created with correct metadata
- [ ] File timestamps preserved
- [ ] Robocopy logs generated
- [ ] Success message displayed

### AC-03: Restore Operation
- [ ] Manifest validated before restore
- [ ] Existing profile renamed (.bak) before restore
- [ ] Backup data copied to correct location
- [ ] Auto-launch works if checkbox selected
- [ ] Can restore from any valid backup folder

### AC-04: Safety Checks
- [ ] Blocked if browser is running
- [ ] Blocked if disk space insufficient
- [ ] Blocked if backup folder invalid
- [ ] Clear error messages for all failures
- [ ] Operations logged to file

### AC-05: User Interface
- [ ] Window opens centered on screen
- [ ] Browser cards display correctly
- [ ] Selection highlighting works
- [ ] All buttons respond to clicks
- [ ] Folder browser dialog works
- [ ] Status messages update correctly

### AC-06: Non-Functional
- [ ] Backup completes within 5 minutes (500MB profile)
- [ ] Application starts within 3 seconds
- [ ] No crashes during normal operation
- [ ] Memory usage under 100MB
- [ ] CPU usage minimal during backup

---

## 6. Test Cases

### TC-01: Full Backup and Restore Cycle
1. Launch application
2. Select Chrome browser
3. Select "All Profiles"
4. Browse to destination folder
5. Click "Start"
6. Verify backup folder created
7. Close application
8. Launch application
9. Select "Restore"
10. Select backup folder
11. Verify manifest displayed
12. Click "Start"
13. Verify profile restored
14. Launch Chrome
15. Verify data intact

### TC-02: Safety Check - Browser Running
1. Launch Chrome
2. Open backup tool
3. Select Chrome
4. Select profile
5. Click "Start"
6. Verify error message displayed
7. Close Chrome
8. Click "Start" again
9. Verify backup proceeds

### TC-03: Invalid Backup Restore
1. Select "Restore" mode
2. Select folder without manifest.json
3. Click "Start"
4. Verify error message displayed

---

## 7. Technical Constraints

### PowerShell Version
- Minimum: PowerShell 5.1 (Windows 10/11 built-in)
- Recommended: PowerShell 7+ (for cross-platform future)

### Windows Components
- Robocopy (built-in since Vista)
- .NET Framework 4.5+ (for WinForms)
- Windows Forms (System.Windows.Forms)

### Browser Executables
- Application must locate browser executables for version detection
- Profile paths must match Windows conventions

---

## 8. Future Enhancements (Post-v1.0)

### v1.1.0
- Profile preview (show size, last modified)
- Incremental backup (only changed files)
- Backup compression (ZIP)

### v1.2.0
- Scheduled backups
- Backup rotation (keep last N)
- Cloud upload (Google Drive, OneDrive)

### v2.0.0
- macOS support
- Linux support
- Unified cross-platform GUI

---

*Document Version: 1.0.0*  
*Last Updated: 2026-03-19*  
*Author: theyonecodes*
