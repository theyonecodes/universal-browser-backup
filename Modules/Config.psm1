function Get-ConfigPath {
    [CmdletBinding()]
    param(
        [string]$ConfigName = "browsers.json"
    )

    $appDataPath = Join-Path $env:APPDATA "UniversalBrowserBackup"
    $scriptPath = $PSScriptRoot
    while ($scriptPath -and !(Test-Path (Join-Path $scriptPath "Config"))) {
        $scriptPath = Split-Path $scriptPath -Parent
    }
    $scriptConfigPath = if ($scriptPath) { Join-Path $scriptPath "Config\$ConfigName" } else { $null }

    $appDataConfig = Join-Path $appDataPath $ConfigName
    if (Test-Path $appDataConfig) {
        Write-Verbose "Using AppData config: $appDataConfig"
        return $appDataConfig
    }

    if ($scriptConfigPath -and (Test-Path $scriptConfigPath)) {
        Write-Verbose "Using script config: $scriptConfigPath"
        return $scriptConfigPath
    }

    Write-Warning "No config file found. Using defaults."
    return $null
}

function Get-BrowserConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    if (-not $ConfigPath) {
        $ConfigPath = Get-ConfigPath
    }

    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $raw = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        $config = @{
            version = $raw.version
            defaults = @{
                backupDestination = $raw.defaults.backupDestination
                excludeFromBackup = @($raw.defaults.excludeFromBackup)
                robocopyRetries = $raw.defaults.robocopyRetries
                robocopyWait = $raw.defaults.robocopyWait
                maxLogFiles = $raw.defaults.maxLogFiles
            }
            chromiumPaths = @{
                local = @($raw.chromiumPaths.local)
                programFiles = @($raw.chromiumPaths.programFiles)
            }
            geckoPaths = @{
                appData = $raw.geckoPaths.appData
                localAppData = $raw.geckoPaths.localAppData
            }
        }
        Write-Verbose "Loaded config version: $($config.version)"
        return $config
    }

    return @{
        version = "2.0.0"
        defaults = @{
            backupDestination = "$env:USERPROFILE\Desktop"
            excludeFromBackup = @(
                "Cache", "Code Cache", "Service Worker", "cache2",
                "startupCache", "GPUCache", "Thumbnails", "blob_storage",
                "Network", "Session Storage"
            )
            robocopyRetries = 3
            robocopyWait = 2
            maxLogFiles = 30
        }
        chromiumPaths = @{
            local = @(
                "Google\Chrome", "Microsoft\Edge", "BraveSoftware\Brave-Browser",
                "Vivaldi", "Opera\Opera stable", "Opera Software\Opera GX Stable",
                "Arc", "Floorp", "Zen Browser", "Iron", "SRWare Iron",
                "Epic Privacy Browser", "Comodo Dragon", "Yandex\YandexBrowser",
                "Samsung\Internet", "Avast Browser", "AVG Secure Browser",
                "CCleaner Browser", "UC Browser"
            )
            programFiles = @(
                "Google\Chrome", "Microsoft\Edge", "BraveSoftware\Brave-Browser",
                "Vivaldi", "Opera\Opera stable", "Opera Software\Opera GX Stable"
            )
        }
        geckoPaths = @{
            appData = "Mozilla\Firefox"
            localAppData = "Mozilla\Firefox"
        }
    }
}

function Get-BackupDestination {
    [CmdletBinding()]
    param(
        [string]$CustomDestination,
        [object]$Config
    )

    if ($CustomDestination) {
        return $CustomDestination
    }

    $dest = $Config.defaults.backupDestination
    $dest = [System.Environment]::ExpandEnvironmentVariables($dest)
    return $dest
}

function Get-ExcludedDirectories {
    [CmdletBinding()]
    param(
        [object]$Config,
        [string[]]$AdditionalExcludes
    )

    $excludes = @($Config.defaults.excludeFromBackup)
    if ($AdditionalExcludes) {
        $excludes += $AdditionalExcludes
    }
    return $excludes
}

Export-ModuleMember -Function Get-ConfigPath, Get-BrowserConfig, Get-BackupDestination, Get-ExcludedDirectories
