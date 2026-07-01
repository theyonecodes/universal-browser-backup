[CmdletBinding(DefaultParameterSetName = 'GUI')]
param(
    [Parameter(ParameterSetName = 'Backup')]
    [switch]$Backup,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Backup', Mandatory)]
    [Parameter(ParameterSetName = 'Restore', Mandatory)]
    [string]$Browser,

    [Parameter(ParameterSetName = 'Backup')]
    [Parameter(ParameterSetName = 'Restore')]
    [string]$Profile = 'Default',

    [Parameter(ParameterSetName = 'Backup', Mandatory)]
    [string]$Destination,

    [Parameter(ParameterSetName = 'Restore', Mandatory)]
    [string]$Source,

    [Parameter(ParameterSetName = 'Backup')]
    [switch]$AllProfiles,

    [Parameter(ParameterSetName = 'Backup')]
    [switch]$ExcludeCache,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$LaunchAfter,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$WhatIf,

    [Parameter()]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

Import-Module "$scriptRoot\Modules\Config.psm1" -Force
Import-Module "$scriptRoot\Modules\BrowserDetection.psm1" -Force
Import-Module "$scriptRoot\Modules\Logging.psm1" -Force
Import-Module "$scriptRoot\Modules\BackupEngine.psm1" -Force
Import-Module "$scriptRoot\Modules\RestoreEngine.psm1" -Force

$config = Get-BrowserConfig -ConfigPath $ConfigPath
$logFile = Initialize-Log

switch ($PSCmdlet.ParameterSetName) {
    'GUI' {
        Write-Verbose "Launching GUI..."
        if (Test-Path "$scriptRoot\GUI\App.ps1") {
            & "$scriptRoot\GUI\App.ps1"
        } else {
            Write-Host "GUI not found. Falling back to CLI mode." -ForegroundColor Yellow
            Write-Host "Usage: .\UniversalBrowserBackup.ps1 -Backup -Browser 'Chrome' -Destination 'D:\Backups'" -ForegroundColor Cyan
        }
    }

    'List' {
        Write-Log -Message "Scanning for installed browsers..." -Level "INFO" -LogFile $logFile
        $browsers = Get-InstalledBrowsers -Config $config

        if ($browsers.Count -eq 0) {
            Write-Host "`nNo browsers found." -ForegroundColor Yellow
        } else {
            Write-Host "`nInstalled Browsers:" -ForegroundColor Green
            Write-Host ("-" * 60) -ForegroundColor DarkGray
            foreach ($b in $browsers) {
                $running = if (Test-BrowserRunning -Browser $b) { " [RUNNING]" } else { "" }
                Write-Host "  $($b.Name) v$($b.Version)$running" -ForegroundColor Cyan
                Write-Host "    Type: $($b.Type)" -ForegroundColor Gray
                Write-Host "    Profiles: $($b.ProfilePath)" -ForegroundColor Gray

                $profiles = Get-BrowserProfiles -Browser $b
                foreach ($p in $profiles) {
                    $default = if ($p.IsDefault) { " (default)" } else { "" }
                    Write-Host "      - $($p.Name) [$($p.SizeMB) MB]$default" -ForegroundColor DarkCyan
                }
                Write-Host ""
            }
        }
    }

    'Backup' {
        Write-Log -Message "Starting backup operation" -Level "INFO" -LogFile $logFile
        $browsers = Get-InstalledBrowsers -Config $config
        $target = $browsers | Where-Object { $_.Name -like "*$Browser*" } | Select-Object -First 1

        if (-not $target) {
            Write-Log -Message "Browser '$Browser' not found" -Level "ERROR" -LogFile $logFile
            Write-Host "Browser '$Browser' not found. Use -List to see available browsers." -ForegroundColor Red
            exit 1
        }

        $dest = Get-BackupDestination -CustomDestination $Destination -Config $config
        $excludes = if ($ExcludeCache) { Get-ExcludedDirectories -Config $config } else { @() }

        if ($AllProfiles) {
            $profiles = Get-BrowserProfiles -Browser $target
            foreach ($p in $profiles) {
                Write-Log -Message "Backing up profile: $($p.Name)" -Level "INFO" -LogFile $logFile
                $result = New-BrowserBackup -Browser $target -ProfileName $p.Name `
                    -Destination $dest -ExcludeDirs $excludes -LogFile $logFile -Force:$Force -WhatIf:$WhatIf

                if ($result.Success) {
                    Write-Host "Backup completed: $($result.Path) ($($result.SizeMB) MB)" -ForegroundColor Green
                } else {
                    Write-Host "Backup failed: $($result.Message)" -ForegroundColor Red
                }
            }
        } else {
            $result = New-BrowserBackup -Browser $target -ProfileName $Profile `
                -Destination $dest -ExcludeDirs $excludes -LogFile $logFile -Force:$Force -WhatIf:$WhatIf

            if ($result.Success) {
                Write-Host "Backup completed: $($result.Path) ($($result.SizeMB) MB)" -ForegroundColor Green
            } else {
                Write-Host "Backup failed: $($result.Message)" -ForegroundColor Red
            }
        }
    }

    'Restore' {
        Write-Log -Message "Starting restore operation" -Level "INFO" -LogFile $logFile
        $browsers = Get-InstalledBrowsers -Config $config
        $target = $browsers | Where-Object { $_.Name -like "*$Browser*" } | Select-Object -First 1

        if (-not $target) {
            Write-Log -Message "Browser '$Browser' not found" -Level "ERROR" -LogFile $logFile
            Write-Host "Browser '$Browser' not found. Use -List to see available browsers." -ForegroundColor Red
            exit 1
        }

        if (-not (Test-Path $Source)) {
            Write-Log -Message "Backup path not found: $Source" -Level "ERROR" -LogFile $logFile
            Write-Host "Backup path not found: $Source" -ForegroundColor Red
            exit 1
        }

        $result = Restore-BrowserProfile -Browser $target -BackupPath $Source `
            -ProfileName $Profile -LaunchAfter:$LaunchAfter -Force:$Force `
            -LogFile $logFile -WhatIf:$WhatIf

        if ($result.Success) {
            Write-Host "Restore completed successfully." -ForegroundColor Green
            if ($result.Rollback) {
                Write-Host "Rollback point: $($result.Rollback)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "Restore failed: $($result.Message)" -ForegroundColor Red
        }
    }
}
