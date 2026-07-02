# Logging.psm1 — thread-safe-ish structured logging with rotation.

Set-StrictMode -Version Latest

function Get-LogDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$LogDirectory
    )
    if (-not $LogDirectory) {
        $LogDirectory = Join-Path $env:APPDATA "UniversalBrowserBackup\logs"
    }
    return $LogDirectory
}

function Initialize-Log {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$LogDirectory,
        [int]$MaxLogFiles = 30
    )

    $LogDirectory = Get-LogDirectory -LogDirectory $LogDirectory

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        try {
            New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "Cannot create log directory '$LogDirectory': $_"
            return $null
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogDirectory "backup_$timestamp.log"

    try {
        if (-not (Test-Path -LiteralPath $logFile)) {
            New-Item -ItemType File -Path $logFile -Force -ErrorAction Stop | Out-Null
        } else {
            # Touch file so writers don't get a race on first access.
            (Get-Item -LiteralPath $logFile).LastWriteTime = Get-Date
        }
    } catch {
        Write-Warning "Cannot create log file '$logFile': $_"
        return $null
    }

    # Rotate: delete oldest files when count exceeds MaxLogFiles.
    try {
        $existingLogs = @(Get-ChildItem -LiteralPath $LogDirectory -Filter "backup_*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($existingLogs.Count -gt $MaxLogFiles) {
            $existingLogs | Select-Object -Skip $MaxLogFiles | ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { }
            }
        }
    } catch { }

    return $logFile
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")] [string]$Level = "INFO",
        [string]$LogFile,
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    if ($LogFile -and (Test-Path -LiteralPath (Split-Path -Parent $LogFile) -PathType Container)) {
        try {
            Add-Content -LiteralPath $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Silent fallback: never let logging kill the caller.
            if (-not $NoConsole) { Write-Warning "Log write failed: $_" }
        }
    }

    if (-not $NoConsole) {
        $color = switch ($Level) {
            "INFO"  { "Cyan" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            default { "Gray" }
        }
        try { Write-Host $logEntry -ForegroundColor $color } catch { }
    }
}

function Get-LogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $logDir = Get-LogDirectory
    if (-not (Test-Path -LiteralPath $logDir)) { return $null }
    $latest = Get-ChildItem -LiteralPath $logDir -Filter "backup_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

Export-ModuleMember -Function Initialize-Log, Write-Log, Get-LogPath, Get-LogDirectory
