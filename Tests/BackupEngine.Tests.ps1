# Tests/BackupEngine.Tests.ps1
$script:ModuleRoot = Split-Path -Parent $PSScriptRoot

Describe "Config Module" {
    Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force -DisableNameChecking

    Context "Get-BrowserConfig" {
        It "Returns a config object with required keys" {
            $config = Get-BrowserConfig
            $config | Should Not BeNullOrEmpty
            $config.defaults | Should Not BeNullOrEmpty
            $config.chromiumPaths | Should Not BeNullOrEmpty
            $config.geckoPaths | Should Not BeNullOrEmpty
            $config.processNames | Should Not BeNullOrEmpty
        }

        It "Has defaults with excludeFromBackup array" {
            $config = Get-BrowserConfig
            $config.defaults.excludeFromBackup | Should Not BeNullOrEmpty
        }

        It "Has checksumCriticalFiles" {
            $config = Get-BrowserConfig
            $config.defaults.checksumCriticalFiles | Should Not BeNullOrEmpty
        }
    }

    Context "Get-BackupDestination" {
        It "Returns custom destination when provided" {
            $config = Get-BrowserConfig
            $result = Get-BackupDestination -CustomDestination "D:\TestBackups" -Config $config
            $result | Should Be "D:\TestBackups"
        }
    }

    Context "Get-ExcludedDirectories" {
        It "Returns defaults when no additional excludes" {
            $config = Get-BrowserConfig
            $result = Get-ExcludedDirectories -Config $config
            $result | Should Not BeNullOrEmpty
        }
        It "Merges additional excludes" {
            $config = Get-BrowserConfig
            $result = Get-ExcludedDirectories -Config $config -AdditionalExcludes @("TestDir")
            $result -contains "TestDir" | Should Be $true
        }
        It "Deduplicates entries" {
            $config = Get-BrowserConfig
            $result = Get-ExcludedDirectories -Config $config -AdditionalExcludes @("Cache", "Cache")
            ($result | Where-Object { $_ -eq "Cache" }).Count | Should Be 1
        }
    }

    Context "Get-ProcessNameForBrowser" {
        It "Returns mapped process name" {
            $config = Get-BrowserConfig
            $result = Get-ProcessNameForBrowser -BrowserRawName "Chrome" -Config $config
            $result | Should Be "chrome"
        }
        It "Falls back to sanitized lowercase" {
            $config = Get-BrowserConfig
            $result = Get-ProcessNameForBrowser -BrowserRawName "Unknown Browser" -Config $config
            $result | Should Be "unknownbrowser"
        }
    }
}

Describe "BrowserDetection Module" {
    Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force -DisableNameChecking
    Import-Module "$script:ModuleRoot\Modules\BrowserDetection.psm1" -Force -DisableNameChecking

    Context "Get-InstalledBrowsers" {
        It "Returns an array of browser objects" {
            $config = Get-BrowserConfig
            $browsers = Get-InstalledBrowsers -Config $config
            $browsers | Should Not BeNullOrEmpty
        }

        It "Each browser has required properties" {
            $config = Get-BrowserConfig
            $browsers = Get-InstalledBrowsers -Config $config
            foreach ($b in $browsers) {
                $b.Name | Should Not BeNullOrEmpty
                $b.Type | Should Not BeNullOrEmpty
                $b.ProfilePath | Should Not BeNullOrEmpty
                $b.ProcessName | Should Not BeNullOrEmpty
            }
        }

        It "No duplicate ProfilePath per Type" {
            $config = Get-BrowserConfig
            $browsers = Get-InstalledBrowsers -Config $config
            $seen = @{}
            foreach ($b in $browsers) {
                $key = "$($b.Type)|$($b.ProfilePath.ToString().ToLowerInvariant())"
                $seen[$key] = $true
            }
            $seen.Count | Should Be $browsers.Count
        }
    }

    Context "Get-BrowserProfiles" {
        It "Returns profiles for a browser" {
            $config = Get-BrowserConfig
            $browsers = Get-InstalledBrowsers -Config $config
            if ($browsers.Count -gt 0) {
                $profiles = Get-BrowserProfiles -Browser $browsers[0]
                $profiles | Should Not BeNullOrEmpty
            }
        }
    }

    Context "Test-BrowserRunning" {
        It "Returns a boolean" {
            $config = Get-BrowserConfig
            $browsers = Get-InstalledBrowsers -Config $config
            if ($browsers.Count -gt 0) {
                $result = Test-BrowserRunning -Browser $browsers[0]
                $result | Should BeOfType System.Boolean
            }
        }
    }
}

Describe "Logging Module" {
    Import-Module "$script:ModuleRoot\Modules\Logging.psm1" -Force -DisableNameChecking

    Context "Initialize-Log" {
        It "Creates a log file" {
            $logFile = Initialize-Log
            $logFile | Should Not BeNullOrEmpty
            Test-Path -LiteralPath $logFile | Should Be $true
        }
    }

    Context "Write-Log" {
        It "Writes to log file" {
            $logFile = Initialize-Log
            Write-Log -Message "Test log entry" -Level "INFO" -LogFile $logFile
            $content = Get-Content -LiteralPath $logFile -Raw
            $content | Should Match "Test log entry"
            $content | Should Match "\[INFO\]"
        }
    }
}

Describe "BackupEngine Module" {
    Import-Module "$script:ModuleRoot\Modules\BackupEngine.psm1" -Force -DisableNameChecking

    Context "Test-BackupIntegrity" {
        It "Returns invalid for nonexistent backup" {
            $result = Test-BackupIntegrity -BackupPath "C:\NonExistentPath"
            $result.Valid | Should Be $false
        }
    }
}

Describe "RestoreEngine Module" {
    Import-Module "$script:ModuleRoot\Modules\RestoreEngine.psm1" -Force -DisableNameChecking
    Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force -DisableNameChecking
    Import-Module "$script:ModuleRoot\Modules\BrowserDetection.psm1" -Force -DisableNameChecking

    Context "Get-BackupInfo" {
        It "Returns null for nonexistent backup" {
            $result = Get-BackupInfo -BackupPath "C:\NonExistentPath"
            $result | Should BeNullOrEmpty
        }
    }

    Context "Test-RestorePrerequisites (legacy fallback)" {
        It "Accepts legacy backup without manifest.json when ≥3 critical files exist" {
            $tmpRoot = Join-Path $env:TEMP "ubb_pester_legacy_$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
            try {
                $profileDir = Join-Path $tmpRoot "Default"
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                "x" | Set-Content -LiteralPath (Join-Path $profileDir "Bookmarks")
                "x" | Set-Content -LiteralPath (Join-Path $profileDir "Login Data")
                "x" | Set-Content -LiteralPath (Join-Path $profileDir "Cookies")
                "x" | Set-Content -LiteralPath (Join-Path $profileDir "Preferences")
                "x" | Set-Content -LiteralPath (Join-Path $tmpRoot "Local State")

                $cfg = Get-BrowserConfig -ConfigPath $null
                $browsers = @(Get-InstalledBrowsers -Config $cfg)
                $chrome = $browsers | Where-Object { $_.Name -like 'Chrome*' } | Select-Object -First 1
                if (-not $chrome) {
                    $chrome = [PSCustomObject]@{ Name = 'Chrome'; Type = 'Chromium' }
                }

                $result = Test-RestorePrerequisites -BackupPath $tmpRoot -Browser $chrome
                $result.Valid | Should Be $true
                $result.LegacyDetected | Should Be $true
                $result.DetectedCriticalFiles.Count | Should BeGreaterThan 2
            } finally {
                Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Rejects legacy backup without manifest.json and <3 critical files" {
            $tmpRoot = Join-Path $env:TEMP "ubb_pester_legacy_empty_$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
            try {
                "x" | Set-Content -LiteralPath (Join-Path $tmpRoot "Bookmarks")
                $cfg = Get-BrowserConfig -ConfigPath $null
                $chrome = [PSCustomObject]@{ Name = 'Chrome'; Type = 'Chromium' }
                $result = Test-RestorePrerequisites -BackupPath $tmpRoot -Browser $chrome
                $result.Valid | Should Be $false
            } finally {
                Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}