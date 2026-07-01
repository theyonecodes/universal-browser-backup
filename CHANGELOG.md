# Changelog

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
