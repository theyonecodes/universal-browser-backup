$script:ModuleRoot = Split-Path -Parent $PSScriptRoot

Describe "Config Module" {
    Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force

    Context "Get-BrowserConfig" {
        It "Returns a config object with required keys" {
            $config = Get-BrowserConfig
            $config | Should Not BeNullOrEmpty
            $config.defaults | Should Not BeNullOrEmpty
            $config.chromiumPaths | Should Not BeNullOrEmpty
            $config.geckoPaths | Should Not BeNullOrEmpty
        }

        It "Has defaults with excludeFromBackup array" {
            $config = Get-BrowserConfig
            $config.defaults.excludeFromBackup | Should Not BeNullOrEmpty
        }
    }

    Context "Get-BackupDestination" {
        It "Returns custom destination when provided" {
            $config = Get-BrowserConfig
            $result = Get-BackupDestination -CustomDestination "D:\TestBackups" -Config $config
            $result | Should Be "D:\TestBackups"
        }
    }
}

Describe "BrowserDetection Module" {
    Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force
    Import-Module "$script:ModuleRoot\Modules\BrowserDetection.psm1" -Force

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
    Import-Module "$script:ModuleRoot\Modules\Logging.psm1" -Force

    Context "Initialize-Log" {
        It "Creates a log file" {
            $logFile = Initialize-Log
            $logFile | Should Not BeNullOrEmpty
            Test-Path $logFile | Should Be $true
        }
    }

    Context "Write-Log" {
        It "Writes to log file" {
            $logFile = Initialize-Log
            Write-Log -Message "Test log entry" -Level "INFO" -LogFile $logFile
            $content = Get-Content -Path $logFile -Raw
            $content | Should Match "Test log entry"
            $content | Should Match "\[INFO\]"
        }
    }
}

Describe "BackupEngine Module" {
    Import-Module "$script:ModuleRoot\Modules\BackupEngine.psm1" -Force

    Context "Test-BackupIntegrity" {
        It "Returns invalid for nonexistent backup" {
            $result = Test-BackupIntegrity -BackupPath "C:\NonExistentPath"
            $result.Valid | Should Be $false
        }
    }
}

Describe "RestoreEngine Module" {
    Import-Module "$script:ModuleRoot\Modules\RestoreEngine.psm1" -Force

    Context "Get-BackupInfo" {
        It "Returns null for nonexistent backup" {
            $result = Get-BackupInfo -BackupPath "C:\NonExistentPath"
            $result | Should BeNullOrEmpty
        }
    }
}
