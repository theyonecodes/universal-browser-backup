function New-Manifest {
    [CmdletBinding()]
    param(
        [string]$BackupPath,
        [PSCustomObject]$Browser,
        [string]$ProfileName,
        [int]$RobocopyExitCode,
        [string]$LogFile
    )

    $manifestPath = Join-Path $BackupPath "manifest.json"

    $criticalFiles = @(
        "Bookmarks", "Bookmarks.bak", "History", "Login Data",
        "Preferences", "Secure Preferences", "Cookies", "Web Data"
    )

    $checksums = @{}
    foreach ($file in $criticalFiles) {
        $filePath = Join-Path $BackupPath $file
        if (Test-Path $filePath) {
            try {
                $hash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
                $checksums[$file] = $hash
            } catch {
                $checksums[$file] = "ERROR: $_"
            }
        }
    }

    $files = Get-ChildItem -Path $BackupPath -Recurse -File -ErrorAction SilentlyContinue
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    $fileCount = ($files | Measure-Object).Count

    $manifest = @{
        version     = "2.0.0"
        timestamp   = (Get-Date).ToString("o")
        browser     = @{
            name    = $Browser.Name
            type    = $Browser.Type
            version = $Browser.Version
        }
        profile     = $ProfileName
        source      = $Browser.ProfilePath
        destination = $BackupPath
        stats       = @{
            fileCount = $fileCount
            totalSize = $totalSize
            totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        }
        robocopy    = @{
            exitCode = $RobocopyExitCode
            logFile  = $LogFile
        }
        checksums   = $checksums
        machine     = @{
            name     = $env:COMPUTERNAME
            user     = $env:USERNAME
            os       = [System.Environment]::OSVersion.VersionString
        }
    }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8
    return $manifestPath
}

function Test-BackupIntegrity {
    [CmdletBinding()]
    param(
        [string]$BackupPath
    )

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        return @{
            Valid   = $false
            Message = "No manifest.json found"
        }
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $issues = @()

    foreach ($file in $manifest.checksums.PSObject.Properties) {
        $filePath = Join-Path $BackupPath $file.Name
        if (-not (Test-Path $filePath)) {
            $issues += "Missing file: $($file.Name)"
            continue
        }
        if ($file.Value -ne "ERROR") {
            $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
            if ($actualHash -ne $file.Value) {
                $issues += "Checksum mismatch: $($file.Name)"
            }
        }
    }

    $actualCount = (Get-ChildItem -Path $BackupPath -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object).Count
    if ($actualCount -ne $manifest.stats.fileCount) {
        $issues += "File count mismatch: expected $($manifest.stats.fileCount), got $actualCount"
    }

    return @{
        Valid   = $issues.Count -eq 0
        Message = if ($issues.Count -eq 0) { "Backup is valid" } else { $issues -join "; " }
        Manifest = $manifest
    }
}

function New-BrowserBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser,
        [string]$ProfileName = "Default",
        [Parameter(Mandatory)]
        [string]$Destination,
        [string[]]$ExcludeDirs,
        [string]$LogFile,
        [switch]$Force
    )

    $profiles = Get-BrowserProfiles -Browser $Browser
    $profile = $profiles | Where-Object { $_.Name -eq $ProfileName }
    if (-not $profile) {
        Write-Log -Message "Profile '$ProfileName' not found for $($Browser.Name)" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Profile not found" }
    }

    $isRunning = Test-BrowserRunning -Browser $Browser
    if ($isRunning -and -not $Force) {
        Write-Log -Message "$($Browser.Name) is running. Close it or use -Force." -Level "WARN" -LogFile $LogFile
        return @{ Success = $false; Message = "Browser is running" }
    }

    if ($isRunning -and $Force) {
        Write-Log -Message "Stopping $($Browser.Name)..." -Level "INFO" -LogFile $LogFile
        Stop-BrowserGracefully -Browser $Browser -Force
    }

    $safeBrowserName = ($Browser.Name -replace '[^a-zA-Z0-9]', '_')
    $backupFolder = Join-Path $Destination "${safeBrowserName}_${ProfileName}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if ($PSCmdlet.ShouldProcess($backupFolder, "Create backup directory")) {
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    }

    $robocopyArgs = @(
        $profile.FullName,
        $backupFolder,
        "/MIR", "/NP", "/R:3", "/W:2",
        "/LOG:$LogFile"
    )

    if ($ExcludeDirs) {
        foreach ($dir in $ExcludeDirs) {
            $robocopyArgs += "/XD"
            $robocopyArgs += (Join-Path $profile.FullName $dir)
        }
    }

    Write-Log -Message "Starting backup of $($Browser.Name) - $ProfileName" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Source: $($profile.FullName)" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Destination: $backupFolder" -Level "INFO" -LogFile $LogFile

    if ($PSCmdlet.ShouldProcess($backupFolder, "Run robocopy")) {
        $exitCode = 0
        try {
            $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs `
                -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$backupFolder\robocopy_output.txt"
            $exitCode = $process.ExitCode
        } catch {
            Write-Log -Message "Robocopy failed: $_" -Level "ERROR" -LogFile $LogFile
            return @{ Success = $false; Message = "Robocopy failed: $_" }
        }

        switch ($exitCode) {
            { $_ -le 3 } {
                Write-Log -Message "Backup completed (exit code: $exitCode)" -Level "INFO" -LogFile $LogFile
            }
            { $_ -ge 8 } {
                Write-Log -Message "Backup failed (exit code: $exitCode)" -Level "ERROR" -LogFile $LogFile
                return @{ Success = $false; Message = "Backup failed with exit code $exitCode" }
            }
            default {
                Write-Log -Message "Backup completed with warnings (exit code: $exitCode)" -Level "WARN" -LogFile $LogFile
            }
        }

        $manifestPath = New-Manifest -BackupPath $backupFolder -Browser $Browser `
            -ProfileName $ProfileName -RobocopyExitCode $exitCode -LogFile $LogFile

        $result = Get-Item $backupFolder
        $totalSize = (Get-ChildItem -Path $backupFolder -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

        Write-Log -Message "Backup complete: $($result.FullName) ($([math]::Round($totalSize / 1MB, 2)) MB)" -Level "INFO" -LogFile $LogFile

        return @{
            Success    = $true
            Path       = $backupFolder
            SizeMB     = [math]::Round($totalSize / 1MB, 2)
            Manifest   = $manifestPath
            ExitCode   = $exitCode
        }
    }

    return @{ Success = $true; Message = "WhatIf mode - no changes made" }
}

Export-ModuleMember -Function New-Manifest, Test-BackupIntegrity, New-BrowserBackup
