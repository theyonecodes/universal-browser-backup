# Agent Instructions - universal-browser-backup

## Repository Overview

**Name**: universal-browser-backup
**Type**: PowerShell + Python v2.2.0 tool for browser profile backup/restore
**Primary Language**: PowerShell (core), Python 3.11+ (GUI/encryption)
**Package Manager**: pip, PowerShell modules

## Architecture Overview

```
universal-browser-backup/
├── core/
│   ├── backup.py              # BackupEngine (Python) - AES-256-GCM encryption
│   ├── restore.py             # RestoreEngine
│   ├── detection.py           # BrowserDetection (Chromium/Gecko)
│   ├── config_manager.py      # Config management
│   └── logger.py              # Logging
├── Modules/                   # PowerShell modules (legacy, being consolidated)
├── main.py                    # PySide6 GUI entry point (v2.2.0)
├── SECURITY.md                # Security policy
├── LICENSE                    # MIT License
├── pyproject.toml             # Python config
└── README.md
```

## Key Components

| Component | Path | Description |
|-----------|------|-------------|
| BackupEngine | core/backup.py | Python core with AES-256-GCM encryption |
| RestoreEngine | core/restore.py | Restore with rollback capability |
| BrowserDetection | core/detection.py | Detects Chromium/Gecko browsers & profiles |
| GUI | main.py | PySide6 DarkTheme (v2.2.0) |
| PowerShell Modules | Modules/ | Legacy PS scripts (being consolidated) |

## Development Commands

```bash
# Install Python dependencies
pip install -e ".[dev]"

# Run tests
pytest --cov=core --cov-report=term-missing -q

# Run linting
ruff check .
ruff format --check .

# Run security scan
bandit -r core/ -f json -o bandit-results.json

# Build executable
pyinstaller universal-browser-backup.spec

# Run GUI
python main.py

# Run PowerShell tests
Invoke-Pester Tests/
```

## Code Style & Conventions

- **Python**: ruff for lint/formatting, pytest for tests
- **PowerShell**: PSScriptAnalyzer, strict mode
- **Encryption**: AES-256-GCM via `cryptography` library
- **Commit Messages**: Conventional Commits

## Encryption Implementation (Critical)

```python
# core/encryption.py - AES-256-GCM
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

def derive_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=100_000)
    return kdf.derive(password.encode('utf-8'))

def encrypt_file(input_path: str, output_path: str, password: str) -> dict:
    salt = os.urandom(16)
    key = derive_key(password, salt)
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)
    with open(input_path, 'rb') as f:
        plaintext = f.read()
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    with open(output_path, 'wb') as f:
        f.write(salt + nonce + ciphertext)
    return {"encrypted": True, "algorithm": "AES-256-GCM", "salt": b64encode(salt).decode(), "nonce": b64encode(nonce).decode()}
```

## CI/CD Pipeline

- **Provider**: GitHub Actions (`.github/workflows/ci.yml`)
- **Jobs**: lint (ruff), test (pytest), security (bandit), build (PyInstaller)
- **Artifacts**: Build outputs, coverage reports, security scan results

## Security Considerations

- **Encryption**: AES-256-GCM mandatory for all backups containing credentials
- **Secrets**: Managed via GitHub Secrets, never in code
- **Dependencies**: Scanned via `pip-audit`, `bandit` in CI
- **Supply Chain**: Dependencies pinned in pyproject.toml, signed releases
- **DPAPI**: Windows Credential Manager integration for key storage

## Architecture Invariants (Non-Negotiable)

1. **AES-256-GCM Encryption**: ALL backups containing Login Data/Cookies MUST be encrypted
2. **Rollback Capability**: Every restore MUST create pre-restore snapshot
3. **Browser Lock Detection**: MUST detect running browsers before backup (VSS or graceful close)
4. **DPAPI Migration**: Cross-machine restore MUST handle DPAPI re-encryption
5. **Consolidation**: PowerShell logic MUST be migrated to Python core

## Common Tasks

### Running GUI
```bash
python main.py
```

### Running Tests
```bash
pytest --cov=core --cov-report=term-missing -q
```

### Building Executable
```bash
pyinstaller universal-browser-backup.spec --clean --noconfirm
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Browser locked during backup | Use VSS or close browser gracefully |
| DPAPI decryption fails on new machine | Use cross-machine DPAPI migration wizard |
| Encryption fails | Ensure `cryptography` library installed |

## Useful Links

- **Repo**: `https://github.com/theyonecodes/universal-browser-backup`
- **Issues**: `https://github.com/theyonecodes/universal-browser-backup/issues`
- **CI**: `https://github.com/theyonecodes/universal-browser-backup/actions`
- **Security**: `https://github.com/theyonecodes/universal-browser-backup/security/advisories`