function Initialize-Log {
    [CmdletBinding()]
    param(
        [string]$LogDirectory,
        [int]$MaxLogFiles = 30
    )

    if (-not $LogDirectory) {
        $LogDirectory = Join-Path $env:APPDATA "UniversalBrowserBackup\logs"
    }

    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogDirectory "backup_$timestamp.log"

    if (-not (Test-Path $logFile)) {
        New-Item -ItemType File -Path $logFile -Force | Out-Null
    }

    $existingLogs = Get-ChildItem -Path $LogDirectory -Filter "backup_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if ($existingLogs.Count -gt $MaxLogFiles) {
        $existingLogs | Select-Object -Skip $MaxLogFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    return $logFile
}

function Write-Log {
    [CmdletBinding()]
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [string]$LogFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    if ($LogFile -and (Test-Path (Split-Path $LogFile -Parent))) {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }

    switch ($Level) {
        "INFO"  { Write-Host $logEntry -ForegroundColor Cyan }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
    }
}

function Get-LogPath {
    [CmdletBinding()]
    param()

    $logDir = Join-Path $env:APPDATA "UniversalBrowserBackup\logs"
    $latest = Get-ChildItem -Path $logDir -Filter "backup_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    return $latest.FullName
}

Export-ModuleMember -Function Initialize-Log, Write-Log, Get-LogPath
