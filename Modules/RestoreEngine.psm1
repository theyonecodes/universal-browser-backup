function Test-RestorePrerequisites {
    [CmdletBinding()]
    param(
        [string]$BackupPath,
        [PSCustomObject]$Browser
    )

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        return @{
            Valid  = $false
            Issues = @("No manifest.json found in backup")
        }
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $issues = @()

    $integrity = Test-BackupIntegrity -BackupPath $BackupPath
    if (-not $integrity.Valid) {
        $issues += "Backup integrity check failed: $($integrity.Message)"
    }

    $profiles = Get-BrowserProfiles -Browser $Browser
    if ($profiles.Count -eq 0) {
        $issues += "No profiles found for $($Browser.Name)"
    }

    $isRunning = Test-BrowserRunning -Browser $Browser
    if ($isRunning) {
        $issues += "$($Browser.Name) is running. Close it before restoring."
    }

    return @{
        Valid    = $issues.Count -eq 0
        Issues   = $issues
        Manifest = $manifest
    }
}

function Restore-BrowserProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser,
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [string]$ProfileName = "Default",
        [switch]$LaunchAfter,
        [switch]$Force,
        [string]$LogFile
    )

    $prereq = Test-RestorePrerequisites -BackupPath $BackupPath -Browser $Browser
    if (-not $prereq.Valid) {
        foreach ($issue in $prereq.Issues) {
            Write-Log -Message $issue -Level "ERROR" -LogFile $LogFile
        }
        return @{ Success = $false; Message = "Prerequisites failed: $($prereq.Issues -join '; ')" }
    }

    $profiles = Get-BrowserProfiles -Browser $Browser
    $profile = $profiles | Where-Object { $_.Name -eq $ProfileName }
    if (-not $profile) {
        Write-Log -Message "Profile '$ProfileName' not found" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Profile not found" }
    }

    if (-not $Force -and -not $PSCmdlet.ShouldContinue(
        "This will restore the backup to '$($profile.FullName)'. The existing profile will be backed up to a rollback point. Continue?",
        "Restore $($Browser.Name) - $ProfileName"
    )) {
        Write-Log -Message "Restore cancelled by user" -Level "WARN" -LogFile $LogFile
        return @{ Success = $false; Message = "Cancelled by user" }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $rollbackPath = "$($profile.FullName).backup_$timestamp"
    if ($PSCmdlet.ShouldProcess($profile.FullName, "Create rollback point")) {
        Write-Log -Message "Creating rollback point: $rollbackPath" -Level "INFO" -LogFile $LogFile
        try {
            Copy-Item -Path $profile.FullName -Destination $rollbackPath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log -Message "Failed to create rollback point: $_" -Level "ERROR" -LogFile $LogFile
            return @{ Success = $false; Message = "Rollback creation failed: $_" }
        }
    }

    $robocopyArgs = @(
        $BackupPath,
        $profile.FullName,
        "/MIR", "/NP", "/R:3", "/W:2",
        "/LOG:$LogFile"
    )

    Write-Log -Message "Restoring $($Browser.Name) - $ProfileName from $BackupPath" -Level "INFO" -LogFile $LogFile

    if ($PSCmdlet.ShouldProcess($profile.FullName, "Run robocopy restore")) {
        $exitCode = 0
        try {
            $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs `
                -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$BackupPath\robocopy_restore_output.txt"
            $exitCode = $process.ExitCode
        } catch {
            Write-Log -Message "Robocopy restore failed: $_" -Level "ERROR" -LogFile $LogFile
            Write-Log -Message "Rolling back..." -Level "INFO" -LogFile $LogFile
            Invoke-Rollback -ProfilePath $profile.FullName -RollbackPath $rollbackPath -LogFile $LogFile
            return @{ Success = $false; Message = "Restore failed: $_" }
        }

        if ($exitCode -ge 8) {
            Write-Log -Message "Restore failed with exit code $exitCode" -Level "ERROR" -LogFile $LogFile
            Write-Log -Message "Rolling back..." -Level "INFO" -LogFile $LogFile
            Invoke-Rollback -ProfilePath $profile.FullName -RollbackPath $rollbackPath -LogFile $LogFile
            return @{ Success = $false; Message = "Restore failed with exit code $exitCode" }
        }

        $postFiles = (Get-ChildItem -Path $profile.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object).Count
        $preFiles = $prereq.Manifest.stats.fileCount

        Write-Log -Message "Restore complete: $postFiles files (expected $preFiles)" -Level "INFO" -LogFile $LogFile

        if ($LaunchAfter -and $Browser.ExePath -and (Test-Path $Browser.ExePath)) {
            Write-Log -Message "Launching $($Browser.Name)..." -Level "INFO" -LogFile $LogFile
            Start-Process -FilePath $Browser.ExePath
        }

        return @{
            Success  = $true
            Profile  = $profile.FullName
            Rollback = $rollbackPath
            ExitCode = $exitCode
        }
    }

    return @{ Success = $true; Message = "WhatIf mode - no changes made" }
}

function Invoke-Rollback {
    [CmdletBinding()]
    param(
        [string]$ProfilePath,
        [string]$RollbackPath,
        [string]$LogFile
    )

    if (Test-Path $RollbackPath) {
        Write-Log -Message "Rolling back from $RollbackPath" -Level "INFO" -LogFile $LogFile
        try {
            Remove-Item -Path $ProfilePath -Recurse -Force -ErrorAction Stop
            Rename-Item -Path $RollbackPath -NewName (Split-Path $ProfilePath -Leaf) -Force -ErrorAction Stop
            Write-Log -Message "Rollback successful" -Level "INFO" -LogFile $LogFile
        } catch {
            Write-Log -Message "Rollback failed: $_" -Level "ERROR" -LogFile $LogFile
        }
    } else {
        Write-Log -Message "No rollback point found at $RollbackPath" -Level "WARN" -LogFile $LogFile
    }
}

function Get-BackupInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        return $null
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $integrity = Test-BackupIntegrity -BackupPath $BackupPath

    return @{
        Manifest  = $manifest
        Integrity = $integrity
        Path      = $BackupPath
    }
}

Export-ModuleMember -Function Test-RestorePrerequisites, Restore-BrowserProfile, Invoke-Rollback, Get-BackupInfo
