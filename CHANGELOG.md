# Changelog

## [2.1.1] - 2026-07-02

### Added
- New `COOKBOOK.md` — 14 numbered, ready-to-paste recipes (CLI, GUI, scheduled-task examples, forensics recipes for damaged backups, custom-config walkthrough, exit codes).
- README rewritten with TOC, ASCII banner, full "How X Works" sections (backup / restore / verify / compare / schedule / export-import), troubleshooting matrix, exit-code table.

## [2.1.0] - 2026-07-02

### Added
- Python/PySide6 GUI (`main.py`) as alternative to WPF GUI
- `processNames` mapping in config for robust browser process detection
- `checksumCriticalFiles` config array for customizable integrity verification
- Expanded browser support: Thorium, Ladybird, Arc (User Data V2 path), Opera Stable, Chromium
- Additional default exclusions: File System, Storage, ShaderCache, GrShaderCache, GraphiteDawnCache, DawnWebGPUCache, Local Storage, IndexedDB, Visited Links
- Robust config path resolution with upward directory walk (max 5 levels)
- Deduplication in `Get-InstalledBrowsers` by (Type, ProfilePath) with preference for entries with ExePath
- Pester test coverage for Config, BrowserDetection, Logging, BackupEngine, RestoreEngine (18 tests)
- Python unit tests for config loading, browser detection, profile discovery (5 tests)
- Runspace-based async execution in WPF GUI with proper cleanup on window close
- Structured logging with `AppLogger` class, lazy initialization, no duplicate handlers
- Robocopy optimization flags: `/BYTES /NDL /NFL /NC /NS /MT:4` for faster, quieter operation

### Fixed
- Config JSON parsing: strict validation, UTF-8 encoding, fallback to built-in defaults
- Duplicate "Opera stable" key in processNames hashtable (PowerShell parser error)
- `foreach` variable scoping in BrowserDetection `Resolve-Executable`
- Win32API version parsing in Python: now constructs string from FileVersionMS/LS instead of returning dict
- Manifest file counting: only counts files, not directories
- Python logger: prevents duplicate handlers, uses `propagate=False`
- GUI event handler cleanup: removed duplicate `Request-Cancel` function in App.ps1
- XAML: removed code-behind `Click` attributes, all wiring done in PowerShell
- **XAML parse error** "Character '0' was unexpected in string '0'" — removed non-ASCII bullet chars (`•`) and switched to full ARGB hex colors (`#FF1E1E2E`) for Windows PowerShell 5.1 compatibility
- `UniversalBrowserBackup.bat` now uses `start ""` for GUI launch — opens in new window without closing the console
- `main.py` `setStyleSheet()` calls had unterminated string literals; added missing `+` concatenation
- GUI XAML no longer crashes on double-click
- PowerShell 5.1 compatibility: removed ternary operator (`? :`), replaced with explicit `if/else`
- Exit codes in CLI: 0=success, 1=module load fail, 2=general error, 3=not found, 4=no profiles, 5=operation failed
- Background job cleanup in CLI `-AllProfiles`: `Remove-Job` after `Receive-Job`
- Rollback creation in RestoreEngine: uses robocopy with retries instead of `Copy-Item`
- Fuzzy browser name matching: compares base names (first word) only

### Added (Python GUI v2.1 enhancements)
- **Multi-browser selection** tab — backup several browsers at once with checkboxes
- **Verify tab** — SHA-256 integrity check against manifest.json for any backup folder
- **Backups tab** — list, delete, **compare** two backups side-by-side (added/removed/modified/identical)
- **Schedule tab** — interval-based QTimer-driven automatic backups
- **Export/Import tab** — `.zip` archives for portable profiles (skips Cache folders on export)
- **CLI flags for Python** — `--list`, `--backup`, `--restore`, `--verify`, `--all-profiles`, `--exclude-cache`, `--force`, `--browser`, `--destination`, `--source`, `--profile`, `--logs`, `--version`, `--no-gui`
- **Cancel button** in the GUI for long-running operations (QThread.cancel-safe)
- **`test_browser_running` / `is_browser_running`** — check if a browser process is currently active
- **`BackupEngine.verify_backup()`** — recompute and compare checksums
- **`BackupEngine.compare_backups()`** — diff structure between two backups
- **`BackupEngine.export_profile_zip()`** — portable `.zip` of a profile
- **`BackupEngine.import_profile_zip()`** — restore from a `.zip` archive
- **`list_backups()`** helper — enumerate every backup under a destination, grouped by browser

### Changed
- Config version bumped to 2.1.0
- Complete rewrite of all 5 PowerShell modules with strict mode, proper typing, error handling
- Python core modules rewritten to match PowerShell functionality
- Test suite expanded from 10 to 18 Pester tests + 5 Python tests
- Documentation updated to reflect actual architecture

## [2.0.0] - 2026-07-02

### Added
- Auto-detection of all Chromium and Gecko browsers
- Multi-profile backup support
- WPF dark theme GUI with async job execution
- SHA256 manifest integrity verification
- Automatic rollback before restore
- Structured logging with rotation
- Smart cache exclusion defaults
- Pester test suite (10 tests)

### Fixed
- Type conversion issues between PSCustomObject and hashtable
- Pester v3 compatibility (BeforeAll placement, ContainsKey on PSCustomObject)
- Initialize-Log now creates the file on call

### Changed
- Complete rewrite from v1 (370-line monolith to modular architecture)
- Config loaded from both AppData and script directory

## [1.0.0] - 2026-07-01

### Added
- Initial release with basic backup/restore functionality
- Browser definition JSON files
- Simple CLI with batch launcher