[CmdletBinding(DefaultParameterSetName = 'GUI')]
param(
    [Parameter(ParameterSetName = 'Backup')] [switch]$Backup,
    [Parameter(ParameterSetName = 'Restore')] [switch]$Restore,
    [Parameter(ParameterSetName = 'List')] [switch]$List,
    [Parameter(ParameterSetName = 'Backup',  Mandatory)] [Parameter(ParameterSetName = 'Restore', Mandatory)] [string]$Browser,
    [Parameter(ParameterSetName = 'Backup')]                        [Parameter(ParameterSetName = 'Restore')]         [string]$Profile = 'Default',
    [Parameter(ParameterSetName = 'Backup', Mandatory)] [string]$Destination,
    [Parameter(ParameterSetName = 'Restore', Mandatory)] [string]$Source,
    [Parameter(ParameterSetName = 'Backup')]  [switch]$AllProfiles,
    [Parameter(ParameterSetName = 'Backup')]  [switch]$ExcludeCache,
    [Parameter(ParameterSetName = 'Restore')] [switch]$LaunchAfter,
    [Parameter()] [switch]$Force,
    [Parameter()] [switch]$WhatIf,
    [Parameter()] [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Enable -WhatIf to flow into CmdletBinding-aware functions inside the modules.
$PSDefaultParameterValues['*:WhatIf'] = $WhatIf.IsPresent

try {
    Import-Module (Join-Path $scriptRoot 'Modules\Config.psm1')          -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot 'Modules\Logging.psm1')          -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot 'Modules\BackupEngine.psm1')     -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot 'Modules\RestoreEngine.psm1')    -Force -DisableNameChecking
}
catch {
    Write-Host "Failed to load modules: $_" -ForegroundColor Red
    exit 2
}

$config  = Get-BrowserConfig -ConfigPath $ConfigPath
$logFile = Initialize-Log

switch ($PSCmdlet.ParameterSetName) {
    'GUI' {
        if (Test-Path -LiteralPath (Join-Path $scriptRoot 'GUI\App.ps1') -PathType Leaf) {
            & (Join-Path $scriptRoot 'GUI\App.ps1') -Config $config -LogFile $logFile
        } else {
            Write-Host 'GUI not found. Falling back to CLI usage hint.' -ForegroundColor Yellow
            Write-Host "Usage: .\UniversalBrowserBackup.ps1 -Backup -Browser 'Chrome' -Destination 'D:\Backups'" -ForegroundColor Cyan
            exit 0
        }
    }

    'List' {
        Write-Log -Message "Scanning for installed browsers..." -Level 'INFO' -LogFile $logFile
        $browsers = @(Get-InstalledBrowsers -Config $config)
        if ($browsers.Count -eq 0) {
            Write-Host "`nNo browsers found." -ForegroundColor Yellow
            exit 0
        }
        Write-Host "`nInstalled Browsers:" -ForegroundColor Green
        Write-Host ("-" * 60) -ForegroundColor DarkGray
        foreach ($b in $browsers) {
            $running = if (Test-BrowserRunning -Browser $b) { ' [RUNNING]' } else { '' }
            Write-Host "  $($b.Name) v$($b.Version)$running" -ForegroundColor Cyan
            Write-Host "    Type:           $($b.Type)" -ForegroundColor Gray
            Write-Host "    Profile folder: $($b.ProfilePath)" -ForegroundColor Gray
            if ($b.ExePath) { Write-Host "    Executable:     $($b.ExePath)" -ForegroundColor Gray }

            $profiles = @(Get-BrowserProfiles -Browser $b)
            foreach ($p in $profiles) {
                $default = if ($p.IsDefault) { ' (default)' } else { '' }
                Write-Host ("      - {0} [{1} MB]{2}" -f $p.Name, $p.SizeMB, $default) -ForegroundColor DarkCyan
            }
            Write-Host ''
        }
        exit 0
    }

    'Backup' {
        Write-Log -Message "Starting backup operation" -Level 'INFO' -LogFile $logFile
        $browsers = @(Get-InstalledBrowsers -Config $config)
        $target = $browsers | Where-Object { $_.Name -like "*$Browser*" -or $_.RawName -like "*$Browser*" } | Select-Object -First 1
        if (-not $target) {
            Write-Host ("Browser '{0}' not found. Use -List to see available browsers." -f $Browser) -ForegroundColor Red
            exit 3
        }

        $dest = Get-BackupDestination -CustomDestination $Destination -Config $config
        if ([string]::IsNullOrWhiteSpace($dest)) {
            Write-Host 'Backup destination is empty.' -ForegroundColor Red
            exit 3
        }
        if (-not (Test-Path -LiteralPath $dest)) {
            try { New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null }
            catch {
                Write-Host ("Cannot create destination '{0}': {1}" -f $dest, $_) -ForegroundColor Red
                exit 3
            }
        }

        $excludes = if ($ExcludeCache) { @(Get-ExcludedDirectories -Config $config) } else { @() }

        if ($AllProfiles) {
            $profiles = @(Get-BrowserProfiles -Browser $target)
            if ($profiles.Count -eq 0) {
                Write-Host "No profiles found for $($target.Name)." -ForegroundColor Red
                exit 4
            }
            $successCount = 0
            foreach ($p in $profiles) {
                Write-Log -Message "Backing up profile: $($p.Name)" -Level 'INFO' -LogFile $logFile
                $result = New-BrowserBackup -Browser $target -ProfileName $p.Name `
                    -Destination $dest `
                    -ExcludeDirs $excludes `
                    -LogFile $logFile `
                    -Force:$Force `
                    -RobocopyRetries $config.defaults.robocopyRetries `
                    -RobocopyWait $config.defaults.robocopyWait `
                    -CriticalFiles $config.defaults.checksumCriticalFiles

                if ($result.Success) {
                    Write-Host ("Backup completed: {0} ({1} MB)" -f $result.Path, $result.SizeMB) -ForegroundColor Green
                    $successCount++
                }
                else {
                    Write-Host ("Backup failed: {0}" -f $result.Message) -ForegroundColor Red
                }
            }
            if ($successCount -eq $profiles.Count) { exit 0 } else { exit 5 }
        }
        else {
            $result = New-BrowserBackup -Browser $target -ProfileName $Profile `
                -Destination $dest `
                -ExcludeDirs $excludes `
                -LogFile $logFile `
                -Force:$Force `
                -RobocopyRetries $config.defaults.robocopyRetries `
                -RobocopyWait $config.defaults.robocopyWait `
                -CriticalFiles $config.defaults.checksumCriticalFiles

            if ($result.Success) {
                Write-Host ("Backup completed: {0} ({1} MB)" -f $result.Path, $result.SizeMB) -ForegroundColor Green
                exit 0
            }
            Write-Host ("Backup failed: {0}" -f $result.Message) -ForegroundColor Red
            exit 5
        }
    }

    'Restore' {
        Write-Log -Message "Starting restore operation" -Level 'INFO' -LogFile $logFile
        $browsers = @(Get-InstalledBrowsers -Config $config)
        $target = $browsers | Where-Object { $_.Name -like "*$Browser*" -or $_.RawName -like "*$Browser*" } | Select-Object -First 1
        if (-not $target) {
            Write-Host ("Browser '{0}' not found. Use -List to see available browsers." -f $Browser) -ForegroundColor Red
            exit 3
        }

        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            Write-Host ("Backup path not found: {0}" -f $Source) -ForegroundColor Red
            exit 3
        }

        $result = Restore-BrowserProfile -Browser $target -BackupPath $Source `
            -ProfileName $Profile `
            -LaunchAfter:$LaunchAfter `
            -Force:$Force `
            -LogFile $logFile `
            -RobocopyRetries $config.defaults.robocopyRetries `
            -RobocopyWait $config.defaults.robocopyWait

        if ($result.Success) {
            Write-Host 'Restore completed successfully.' -ForegroundColor Green
            if ($result.Rollback) { Write-Host ("Rollback point: {0}" -f $result.Rollback) -ForegroundColor DarkGray }
            exit 0
        }
        Write-Host ("Restore failed: {0}" -f $result.Message) -ForegroundColor Red
        exit 5
    }
}
