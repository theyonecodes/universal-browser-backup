# BackupEngine.psm1 — robocopy backup + manifest + SHA256 verification.

Set-StrictMode -Version Latest

function New-Manifest {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$BackupPath,
        [Parameter(Mandatory)] $Browser,
        [Parameter(Mandatory)] [string]$ProfileName,
        [int]$RobocopyExitCode = 0,
        [string]$LogFile,
        [string[]]$CriticalFiles
    )

    if (-not $CriticalFiles) {
        $CriticalFiles = @(
            "Bookmarks", "Bookmarks.bak", "History", "Login Data",
            "Preferences", "Secure Preferences", "Cookies", "Web Data"
        )
    }

    $manifestPath = Join-Path $BackupPath "manifest.json"

    $checksums = [ordered]@{}
    foreach ($file in $CriticalFiles) {
        $filePath = Join-Path $BackupPath $file
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            try {
                $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction Stop).Hash
                $checksums[$file] = $hash
            } catch {
                $checksums[$file] = "ERROR: $($_.Exception.Message)"
            }
        }
    }

    $files = @(Get-ChildItem -LiteralPath $BackupPath -Recurse -File -Force -ErrorAction SilentlyContinue)
    $totalSize = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if ($null -eq $totalSize) { $totalSize = 0 }
    $fileCount = $files.Count

    $manifest = [ordered]@{
        version     = "2.1.0"
        timestamp   = (Get-Date).ToString("o")
        browser     = [ordered]@{
            name    = [string]$Browser.Name
            type    = [string]$Browser.Type
            version = [string]$Browser.Version
            rawName = [string]$Browser.RawName
        }
        profile     = $ProfileName
        source      = [string]$Browser.ProfilePath
        destination = $BackupPath
        stats       = [ordered]@{
            fileCount    = $fileCount
            totalSize    = $totalSize
            totalSizeMB  = [math]::Round($totalSize / 1MB, 2)
        }
        robocopy    = [ordered]@{
            exitCode = $RobocopyExitCode
            logFile  = $LogFile
        }
        checksums   = $checksums
        machine     = [ordered]@{
            name = [string]$env:COMPUTERNAME
            user = [string]$env:USERNAME
            os   = [System.Environment]::OSVersion.VersionString
        }
    }

    try {
        $json = $manifest | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $manifestPath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log -Message "Failed to write manifest: $_" -Level "ERROR" -LogFile $LogFile
        return $null
    }

    return $manifestPath
}

function Test-BackupIntegrity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$BackupPath
    )

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        return @{ Valid = $false; Message = "Backup path does not exist: $BackupPath"; Manifest = $null }
    }

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return @{ Valid = $false; Message = "No manifest.json found"; Manifest = $null }
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @{ Valid = $false; Message = "Cannot parse manifest.json: $_"; Manifest = $null }
    }

    $issues = [System.Collections.Generic.List[string]]::new()

    if ($manifest.checksums) {
        foreach ($file in $manifest.checksums.PSObject.Properties) {
            $filePath = Join-Path $BackupPath $file.Name
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                [void]$issues.Add("Missing file: $($file.Name)")
                continue
            }
            $expected = [string]$file.Value
            if ($expected.StartsWith("ERROR")) {
                [void]$issues.Add("Original checksum failure carried over: $($file.Name)")
                continue
            }
            try {
                $actual = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($actual -ne $expected) {
                    [void]$issues.Add("Checksum mismatch: $($file.Name)")
                }
            } catch {
                [void]$issues.Add("Cannot re-hash '$($file.Name)': $_")
            }
        }
    }

    try {
        $actualCount = @(Get-ChildItem -LiteralPath $BackupPath -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        if ($manifest.stats -and $manifest.stats.fileCount -and ($actualCount -ne [int]$manifest.stats.fileCount)) {
            [void]$issues.Add("File count mismatch: expected $($manifest.stats.fileCount), got $actualCount")
        }
    } catch { }

    return @{
        Valid    = ($issues.Count -eq 0)
        Message  = if ($issues.Count -eq 0) { "Backup is valid" } else { ($issues -join "; ") }
        Manifest = $manifest
        Issues   = $issues.ToArray()
    }
}

function Invoke-RobocopyMirror {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination,
        [string[]]$ExcludeDirs,
        [int]$Retries = 3,
        [int]$Wait = 2,
        [string]$LogFile,
        [string]$RedirectOutput
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source path not found: $Source"
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
    }

    $args = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/MIR", "/NP", "/BYTES", "/NDL", "/NFL", "/NC", "/NS",
        "/R:$Retries",
        "/W:$Wait",
        "/MT:4"
    )

    if ($ExcludeDirs) {
        foreach ($d in $ExcludeDirs) {
            if ([string]::IsNullOrWhiteSpace($d)) { continue }
            $args += "/XD"
            $args += "`"$((Join-Path $Source $d) -replace '/+$','')`""
        }
    }

    if ($LogFile) {
        $logDir = Split-Path -Parent $LogFile
        if (-not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $args += "/LOG+:`"$LogFile`""
    }

    if ($RedirectOutput) {
        $redirectDir = Split-Path -Parent $RedirectOutput
        if (-not (Test-Path -LiteralPath $redirectDir)) {
            New-Item -ItemType Directory -Path $redirectDir -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    $redirectPath = if ($RedirectOutput) { $RedirectOutput } else { [System.IO.Path]::GetTempFileName() }
    $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $args `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $redirectPath
    return [int]$process.ExitCode
}

function New-BrowserBackup {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Browser,
        [string]$ProfileName = "Default",
        [Parameter(Mandatory)] [string]$Destination,
        [string[]]$ExcludeDirs,
        [string]$LogFile,
        [switch]$Force,
        [int]$RobocopyRetries = 3,
        [int]$RobocopyWait = 2,
        [string[]]$CriticalFiles
    )

    if (-not $PSCmdlet.ShouldProcess("Backup of $($Browser.Name)")) {
        return @{ Success = $true; Message = "WhatIf mode - no changes made" }
    }

    if ([string]::IsNullOrWhiteSpace($ProfileName)) { $ProfileName = "Default" }

    $profiles = @(Get-BrowserProfiles -Browser $Browser)
    $profile = $profiles | Where-Object { $_.Name -eq $ProfileName } | Select-Object -First 1
    if (-not $profile) {
        Write-Log -Message "Profile '$ProfileName' not found for $($Browser.Name)" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Profile not found"; Profile = $ProfileName }
    }

    $isRunning = Test-BrowserRunning -Browser $Browser
    if ($isRunning -and -not $Force) {
        Write-Log -Message "$($Browser.Name) is running. Close it or use -Force." -Level "WARN" -LogFile $LogFile
        return @{ Success = $false; Message = "Browser is running"; Running = $true }
    }
    if ($isRunning -and $Force) {
        Write-Log -Message "Stopping $($Browser.Name)..." -Level "INFO" -LogFile $LogFile
        [void](Stop-BrowserGracefully -Browser $Browser -Force)
    }

    $safeName = ($Browser.Name -replace '[^a-zA-Z0-9]', '_').Trim('_')
    if (-not $safeName) { $safeName = "Browser" }
    $safeProfile = ($ProfileName -replace '[^a-zA-Z0-9._-]', '_').Trim('_')
    if (-not $safeProfile) { $safeProfile = "Profile" }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFolder = Join-Path $Destination "${safeName}_${safeProfile}_${timestamp}"

    try {
        New-Item -ItemType Directory -Path $backupFolder -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log -Message "Cannot create backup folder '$backupFolder': $_" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Cannot create backup folder: $_" }
    }

    Write-Log -Message "Starting backup of $($Browser.Name) - $ProfileName" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Source: $($profile.FullName)" -Level "INFO" -LogFile $LogFile
    Write-Log -Message "Destination: $backupFolder" -Level "INFO" -LogFile $LogFile

    $exitCode = 0
    $redirectFile = Join-Path $backupFolder "robocopy_output.txt"
    try {
        $exitCode = Invoke-RobocopyMirror -Source $profile.FullName `
            -Destination $backupFolder `
            -ExcludeDirs $ExcludeDirs `
            -Retries $RobocopyRetries `
            -Wait $RobocopyWait `
            -LogFile $LogFile `
            -RedirectOutput $redirectFile
    } catch {
        Write-Log -Message "Robocopy failed: $_" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Robocopy failed: $_"; Path = $backupFolder }
    }

    if ($exitCode -ge 8) {
        Write-Log -Message "Backup failed (robocopy exit code: $exitCode)" -Level "ERROR" -LogFile $LogFile
        return @{ Success = $false; Message = "Robocopy exit code $exitCode"; Path = $backupFolder; ExitCode = $exitCode }
    }
    elseif ($exitCode -ge 4) {
        Write-Log -Message "Backup completed with warnings (robocopy exit code: $exitCode)" -Level "WARN" -LogFile $LogFile
    }
    else {
        Write-Log -Message "Backup completed (robocopy exit code: $exitCode)" -Level "INFO" -LogFile $LogFile
    }

    $manifestPath = New-Manifest -BackupPath $backupFolder `
        -Browser $Browser `
        -ProfileName $ProfileName `
        -RobocopyExitCode $exitCode `
        -LogFile $LogFile `
        -CriticalFiles $CriticalFiles

    $totalSize = 0
    try {
        $totalSize = (Get-ChildItem -LiteralPath $backupFolder -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch { }
    if ($null -eq $totalSize) { $totalSize = 0 }

    Write-Log -Message "Backup complete: $backupFolder ($([math]::Round($totalSize / 1MB, 2)) MB)" -Level "INFO" -LogFile $LogFile

    return @{
        Success    = $true
        Path       = $backupFolder
        SizeMB     = [math]::Round($totalSize / 1MB, 2)
        Manifest   = $manifestPath
        ExitCode   = $exitCode
    }
}

Export-ModuleMember -Function New-Manifest, Test-BackupIntegrity, Invoke-RobocopyMirror, New-BrowserBackup
