# Contributing to Universal Browser Backup Tool

Thank you for your interest in contributing to the Universal Browser Backup Tool!

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## How Can I Contribute?

### Reporting Bugs

Before submitting a bug report:
1. Check the [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
2. Search existing issues
3. Verify the bug is reproducible

When submitting a bug report:
- Use a clear and descriptive title
- Describe the exact steps to reproduce the bug
- Include your Windows version and PowerShell version
- Attach any relevant log files

### Suggesting Features

We welcome feature suggestions! Please:
- Search existing suggestions first
- Provide a clear use case
- Explain the expected behavior
- Consider backward compatibility

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development Setup

### Prerequisites
- Windows 10/11
- PowerShell 5.1+
- Git

### Local Development

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/universal-browser-backup-tool.git

# Navigate to project
cd universal-browser-backup-tool

# Create a feature branch
git checkout -b feature/your-feature-name

# Test locally
.\UniversalBrowserBackup.bat
```

### Testing

Before submitting:
1. Test backup with each supported browser
2. Test restore functionality
3. Verify manifest.json is created correctly
4. Check error handling for edge cases

## Style Guidelines

### PowerShell Style
- Use descriptive variable names
- Add comments for complex logic
- Follow [PowerShell best practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/best-practices/)
- Maximum line length: 120 characters

### Naming Conventions
| Type | Convention | Example |
|------|------------|---------|
| Variables | $script:VerbNoun | `$script:selectedBrowser` |
| Functions | Verb-Noun | `Get-BrowserProfiles` |
| Constants | $script:ALL_CAPS | `$script:Browsers` |

## Commit Messages

Use clear, descriptive commit messages:
- Use present tense ("Add feature" not "Added feature")
- Start with capital letter
- Keep first line under 50 characters
- Add detailed description if needed

## License

By submitting a contribution, you agree that your contributions will be licensed under the MIT License.

---

## Questions?

Feel free to:
- Open an issue for questions
- Contact the maintainer via GitHub

Thank you for contributing! 🚀
