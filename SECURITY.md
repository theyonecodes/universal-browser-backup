# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.0   | ✅ Currently Supported |

## Reporting a Vulnerability

If you discover a security vulnerability within this tool, please follow these steps:

### For Security Researchers

1. **Do Not** create a public GitHub issue for security vulnerabilities
2. Send a detailed description to the maintainer via GitHub
3. Include the following information:
   - Type of vulnerability
   - Full paths of source file(s) related to the vulnerability
   - Location of the affected source code
   - Step-by-step instructions to reproduce the issue
   - Proof-of-concept or exploit code (if possible)
   - Impact of the issue

### What to Expect

- **Response Time:** We aim to respond within 48 hours
- **Status Updates:** We will provide updates on the vulnerability status
- **Credit:** Security researchers who report valid issues will be credited (if desired)

## Security Best Practices

### When Using This Tool

1. **Backup Location**
   - Store backups in secure locations
   - Avoid public or shared folders for sensitive data
   - Consider encrypting backup folders

2. **Browser Closure**
   - Always close browsers before backup/restore
   - The tool will warn you if a browser is running

3. **Manifest Verification**
   - Always verify manifest.json before restoring
   - Check the backup metadata matches your expectations

4. **Existing Profile Backup**
   - The tool automatically backs up existing profiles before restore
   - Old profiles are renamed with `.backup_TIMESTAMP` suffix

### Known Considerations

| Concern | Mitigation |
|---------|------------|
| Browser running during backup | Tool detects and warns user |
| Corrupted backup | Manifest validation prevents restore |
| Data loss during restore | Automatic backup of existing profiles |
| Unauthorized access to backups | User's file system permissions apply |

## Data Privacy

### What This Tool Accesses

- Browser profile folders in `%LOCALAPPDATA%` and `%APPDATA%`
- Registry keys for browser detection (read-only)
- File system for backup/restore operations

### What This Tool Does NOT Do

- ❌ Transmit data over the network
- ❌ Access browser passwords (though stored files may contain encrypted data)
- ❌ Collect telemetry or analytics
- ❌ Modify system files
- ❌ Install additional software

## Version Security Updates

Security updates will be released as patch versions (e.g., 1.0.1) and announced through:
- GitHub Releases
- Project README

## Security-Related Contributions

When contributing to this project:
- Do not introduce new dependencies
- Do not add network communication
- Do not add telemetry or tracking
- Follow secure coding practices

---

*Thank you for helping keep this project secure!*
