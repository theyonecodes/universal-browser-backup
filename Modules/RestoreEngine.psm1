# RestoreEngine.psm1 — backup validation, rollback creation, restore execution.

Set-StrictMode -Version Latest

function Test-RestorePrerequisites {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$BackupPath,
        [Parameter(Mandatory)] [PSCustomObject]$Browser
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $manifest = $null

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        [void]$issues.Add("Backup path not found: $BackupPath")
        return @{ Valid = $false; Issues = $issues.ToArray(); Manifest = $null }
    }

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        [void]$issues.Add("No manifest.json found in backup")
        return @{ Valid = $false; Issues = $issues.ToArray(); Manifest = $null }
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        [void]$issues.Add("Cannot parse manifest.json: $_")
        return @{ Valid = $false; Issues = $issues.ToArray(); Manifest = $null }
    }

    $integrity = Test-BackupIntegrity -BackupPath $BackupPath
    if (-not $integrity.Valid) {
        [void]$issues.Add("Backup integrity check failed: $($integrity.Message)")
        return @{ Valid = $false; Issues = $issues.ToArray(); Manifest = $manifest }
    }

    if ($manifest.browser -and $manifest.browser.type) {
        if ([string]$manifest.browser.type -ne [string]$Browser.Type) {
            [void]$issues.Add("Backup browser type mismatch: expected '$($Browser.Type)', found '$($manifest.browser.type)'")
        }

        $targetBase    = ([string]$Browser.Name).Split([char]' ')[0]
        $backupBase    = ([string]$manifest.browser.name).Split([char]' ')[0]
        if ($targetBase -and $backupBase -and
            ($Browser.Name     -notlike "*$backupBase*") -and
            ($manifest.browser.name -notlike "*$targetBase*")) {
            [void]$issues.Add("Browser name mismatch: backup='$($manifest.browser.name)', target='$($Browser.Name)'")
        }
    }

    $profiles = @(Get-BrowserProfiles -Browser $Browser)
    if ($profiles.Count -eq 0) {
        [void]$issues.Add("No profiles found for $($Browser.Name)")
    }

    if (Test-BrowserRunning -Browser $Browser) {
        [void]$issues.Add("$($Browser.Name) is running. Close it before restoring.")
    }

    return @{
        Valid    = ($issues.Count -eq 0)
        Issues   = $issues.ToArray()
        Manifest = $manifest
    }
}

function Invoke-Rollback {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$ProfilePath,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$RollbackPath,
        [string]$LogFile
    )

    if (-not (Test-Path -LiteralPath $RollbackPath -PathType Container)) {
        Write-Log -Message "No rollback point found at $RollbackPath" -Level "WARN" -LogFile $LogFile
        return $false
    }

    try {
        Write-Log -Message "Rolling back from $RollbackPath" -Level "INFO" -LogFile $LogFile
        if (Test-Path -LiteralPath $ProfilePath) {
            Remove-Item -LiteralPath $ProfilePath -Recurse -Force -ErrorAction Stop
        }
        $leaf = Split-Path -Path $ProfilePath -Leaf
        Rename-Item -LiteralPath $RollbackPath -NewName $leaf -Force -ErrorAction Stop
        Write-Log -Message "Rollback successful" -Level "INFO" -LogFile $LogFile
        return $true
    } catch {
        Write-Log -Message "Rollback failed: $_" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

function Restore-BrowserProfile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Browser,
        [Parameter(Mandatory)] [string]$BackupPath,
        [string]$ProfileName = "Default",
        [switch]$LaunchAfter,
        [switch]$Force,
        [string]$LogFile,
        [int]$RobocopyRetries = 3,
        [int]$RobocopyWait = 2
    )

    $prereq = Test-RestorePrerequisites -BackupPath $BackupPath -Browser $Browser
    if (-not $prereq.Valid) {
        foreach ($i in $prereq.Issues) {
            Write-Log -Message $i -Level "ERROR" -LogFile $LogFile
        }
        return @{ Success = $false; Message = "Prerequisites failed: $([string]::Join('; ', $prereq.Issues))"; Issues = $prereq.Issues }
    }

    if ([string]::IsNullOrWhiteSpace($ProfileName)) { $ProfileName = "Default" }
    $profiles = @(Get-BrowserProfiles -Browser $Browser)
    $profile = $profiles | Where-Object { $_.Name -eq $ProfileName } | Select-Object -First 1
    if (-not $profile) {
        Write-Log -Message "Profile '$ProfileName' not found" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Profile not found" }
    }

    if (-not $Force) {
        $confirmMsg = "Restore '$($Browser.Name)' - $ProfileName from '$BackupPath'? A rollback of the existing profile will be created."
        $shouldContinue = $true
        $promptTitle = "Restore $($Browser.Name) - $ProfileName"
        if ($PSCmdlet.ShouldContinue($confirmMsg, $promptTitle) -eq $false) {
            $shouldContinue = $false
        }
        if (-not $shouldContinue) {
            Write-Log -Message "Restore cancelled by user" -Level "WARN" -LogFile $LogFile
            return @{ Success = $false; Message = "Cancelled by user" }
        }
    }

    $profileParent = Split-Path -Parent $profile.FullName
    $profileLeaf = Split-Path -Leaf $profile.FullName
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $rollbackPath = Join-Path $profileParent "${profileLeaf}.backup_${timestamp}"

    if (Test-Path -LiteralPath $profile.FullName) {
        if ($PSCmdlet.ShouldProcess($profile.FullName, "Create rollback point")) {
            Write-Log -Message "Creating rollback point: $rollbackPath" -Level "INFO" -LogFile $LogFile
            try {
                New-Item -ItemType Directory -Path $rollbackPath -Force -ErrorAction Stop | Out-Null
                $rbCode = Invoke-RobocopyMirror `
                    -Source $profile.FullName `
                    -Destination $rollbackPath `
                    -Retries $RobocopyRetries `
                    -Wait $RobocopyWait `
                    -LogFile $LogFile `
                    -RedirectOutput (Join-Path $rollbackPath "rollback_robocopy.txt")
                if ($rbCode -ge 8) {
                    Write-Log -Message "Rollback copy had errors (exit code $rbCode) but continuing." -Level "WARN" -LogFile $LogFile
                }
            } catch {
                Write-Log -Message "Failed to create rollback point: $_" -Level "ERROR" -LogFile $LogFile
                return @{ Success = $false; Message = "Rollback creation failed: $_" }
            }
        }
    }

    Write-Log -Message "Restoring $($Browser.Name) - $ProfileName from $BackupPath" -Level "INFO" -LogFile $LogFile

    $exitCode = 0
    $redirectFile = Join-Path $BackupPath "robocopy_restore_output.txt"
    try {
        $exitCode = Invoke-RobocopyMirror `
            -Source $BackupPath `
            -Destination $profile.FullName `
            -Retries $RobocopyRetries `
            -Wait $RobocopyWait `
            -LogFile $LogFile `
            -RedirectOutput $redirectFile
    } catch {
        Write-Log -Message "Robocopy restore failed: $_" -Level "ERROR" -LogFile $LogFile
        Write-Log -Message "Rolling back..." -Level "INFO" -LogFile $LogFile
        [void](Invoke-Rollback -ProfilePath $profile.FullName -RollbackPath $rollbackPath -LogFile $LogFile)
        return @{ Success = $false; Message = "Restore failed: $_" }
    }

    if ($exitCode -ge 8) {
        Write-Log -Message "Restore failed with exit code $exitCode" -Level "ERROR" -LogFile $LogFile
        Write-Log -Message "Rolling back..." -Level "INFO" -LogFile $LogFile
        [void](Invoke-Rollback -ProfilePath $profile.FullName -RollbackPath $rollbackPath -LogFile $LogFile)
        return @{ Success = $false; Message = "Restore failed with exit code $exitCode"; ExitCode = $exitCode }
    }

    try {
        $postFiles = @(Get-ChildItem -LiteralPath $profile.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $preFiles = if ($prereq.Manifest -and $prereq.Manifest.stats -and $prereq.Manifest.stats.fileCount) {
            [int]$prereq.Manifest.stats.fileCount
        } else { 0 }
        Write-Log -Message "Restore complete: $postFiles files (expected $preFiles)" -Level "INFO" -LogFile $LogFile
    } catch { }

    if ($LaunchAfter -and $Browser.ExePath -and (Test-Path -LiteralPath $Browser.ExePath -PathType Leaf)) {
        try {
            Write-Log -Message "Launching $($Browser.Name)..." -Level "INFO" -LogFile $LogFile
            Start-Process -FilePath $Browser.ExePath -ErrorAction Stop
        } catch {
            Write-Log -Message "Could not launch browser: $_" -Level "WARN" -LogFile $LogFile
        }
    }

    return @{
        Success  = $true
        Profile  = $profile.FullName
        Rollback = $rollbackPath
        ExitCode = $exitCode
    }
}

function Get-BackupInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$BackupPath
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) { return $null }

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log -Message "Cannot read manifest: $_" -Level "WARN" -LogFile
        return $null
    }

    $integrity = Test-BackupIntegrity -BackupPath $BackupPath
    return @{
        Manifest  = $manifest
        Integrity = $integrity
        Path      = $BackupPath
    }
}

Export-ModuleMember -Function Test-RestorePrerequisites, Restore-BrowserProfile, Invoke-Rollback, Get-BackupInfo
