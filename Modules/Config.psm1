# Config.psm1
# Browser configuration loader with AppData → script fallback.

Set-StrictMode -Version Latest

function Get-ScriptRoot {
    # When loaded as a module, $PSScriptRoot points to the module folder.
    # When loaded via dot-source or wrapper, fall back to the caller's location.
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation -and $MyInvocation.MyCommand.Path) {
        return Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    return (Get-Location).Path
}

function Get-ConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ConfigName = "browsers.json"
    )

    $moduleRoot = Get-ScriptRoot
    $resolvedRoot = $moduleRoot
    $guard = 0
    # Walk upward looking for a sibling "Config" directory (max 5 levels).
    while ($resolvedRoot -and $guard -lt 5) {
        $candidate = Join-Path $resolvedRoot "Config"
        if (Test-Path -LiteralPath $candidate -PathType Container) { break }
        $parent = Split-Path -Parent $resolvedRoot
        if (-not $parent -or $parent -eq $resolvedRoot) { break }
        $resolvedRoot = $parent
        $guard++
    }

    $appDataRoot = $env:APPDATA
    $appDataPath = if ($appDataRoot) {
        Join-Path $appDataRoot "UniversalBrowserBackup\$ConfigName"
    } else { $null }

    $scriptPath = if ($resolvedRoot) {
        Join-Path $resolvedRoot "Config\$ConfigName"
    } else { $null }

    if ($appDataPath -and (Test-Path -LiteralPath $appDataPath -PathType Leaf)) {
        Write-Verbose "Using AppData config: $appDataPath"
        return $appDataPath
    }

    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Verbose "Using script config: $scriptPath"
        return $scriptPath
    }

    Write-Warning "No config file '$ConfigName' found in AppData or script directory. Using built-in defaults."
    return $null
}

function Get-DefaultConfig {
    return @{
        version = "2.1.0"
        defaults = @{
            backupDestination       = "$env:USERPROFILE\Desktop"
            excludeFromBackup       = @(
                "Cache", "Code Cache", "Service Worker", "cache2",
                "startupCache", "GPUCache", "Thumbnails", "blob_storage",
                "Network", "Session Storage", "File System", "Storage",
                "ShaderCache", "GrShaderCache", "GraphiteDawnCache",
                "DawnWebGPUCache", "Local Storage", "IndexedDB", "Visited Links"
            )
            robocopyRetries          = 3
            robocopyWait             = 2
            maxLogFiles              = 30
            checksumCriticalFiles    = @(
                "Bookmarks", "Bookmarks.bak", "History", "Login Data",
                "Preferences", "Secure Preferences", "Cookies", "Web Data"
            )
        }
        chromiumPaths = @{
            local         = @(
                "Google\Chrome", "Microsoft\Edge", "BraveSoftware\Brave-Browser",
                "Vivaldi", "Opera Software\Opera Stable", "Opera Software\Opera GX Stable",
                "Arc\User Data", "Floorp", "Zen Browser", "Thorium", "Ladybird",
                "Iron", "SRWare Iron", "Epic Privacy Browser", "Comodo Dragon",
                "Yandex\YandexBrowser", "Samsung\Internet", "Avast Browser",
                "AVG Secure Browser", "CCleaner Browser", "UC Browser", "Chromium"
            )
            programFiles  = @(
                "Google\Chrome", "Microsoft\Edge", "BraveSoftware\Brave-Browser",
                "Vivaldi", "Opera\Opera stable", "Opera Software\Opera GX Stable",
                "Thorium", "Ladybird"
            )
        }
        geckoPaths    = @{
            appData       = "Mozilla\Firefox"
            localAppData  = "Mozilla\Firefox"
        }
        processNames  = @{
            "Chrome"               = "chrome"
            "Edge"                 = "msedge"
            "Brave-Browser"        = "brave"
            "Vivaldi"              = "vivaldi"
            "Opera Stable"         = "opera"
            "Opera GX Stable"      = "opera"
            "Arc"                  = "Arc"
            "Floorp"               = "floorp"
            "Zen Browser"          = "zen"
            "Thorium"              = "thorium"
            "Ladybird"             = "ladybird"
            "Iron"                 = "iron"
            "SRWare Iron"          = "iron"
            "Epic Privacy Browser" = "epic"
            "Comodo Dragon"        = "dragon"
            "YandexBrowser"        = "browser"
            "Internet"             = "browser"
            "Avast Browser"        = "avast"
            "AVG Secure Browser"   = "avg"
            "CCleaner Browser"     = "ccleaner"
            "UC Browser"           = "ucbrowser"
            "Chromium"             = "chromium"
        }
    }
}

function Get-BrowserConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$ConfigPath
    )

    if (-not $ConfigPath) { $ConfigPath = Get-ConfigPath }

    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

            $processNames = @{}
            if ($parsed.processNames) {
                foreach ($p in $parsed.processNames.PSObject.Properties) {
                    $processNames[$p.Name] = [string]$p.Value
                }
            }

            $exclude = @()
            if ($parsed.defaults.excludeFromBackup) {
                $exclude = @($parsed.defaults.excludeFromBackup | ForEach-Object { [string]$_ })
            }

            $critical = @()
            if ($parsed.defaults.checksumCriticalFiles) {
                $critical = @($parsed.defaults.checksumCriticalFiles | ForEach-Object { [string]$_ })
            }

            $config = @{
                version        = [string]$parsed.version
                defaults       = @{
                    backupDestination    = [string]$parsed.defaults.backupDestination
                    excludeFromBackup    = $exclude
                    robocopyRetries       = [int]$parsed.defaults.robocopyRetries
                    robocopyWait          = [int]$parsed.defaults.robocopyWait
                    maxLogFiles           = [int]$parsed.defaults.maxLogFiles
                    checksumCriticalFiles = $critical
                }
                chromiumPaths  = @{
                    local         = @($parsed.chromiumPaths.local | ForEach-Object { [string]$_ })
                    programFiles  = @($parsed.chromiumPaths.programFiles | ForEach-Object { [string]$_ })
                }
                geckoPaths     = @{
                    appData      = [string]$parsed.geckoPaths.appData
                    localAppData = [string]$parsed.geckoPaths.localAppData
                }
                processNames   = $processNames
            }
            Write-Verbose "Loaded config version: $($config.version)"
            return $config
        }
        catch {
            Write-Warning "Failed to parse config at '$ConfigPath': $_ . Falling back to defaults."
        }
    }

    return (Get-DefaultConfig)
}

function Get-BackupDestination {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$CustomDestination,
        [Parameter(Mandatory)]
        $Config
    )

    if ($CustomDestination) { return $CustomDestination }

    $dest = [string]$Config.defaults.backupDestination
    if (-not [string]::IsNullOrWhiteSpace($dest)) {
        $dest = [System.Environment]::ExpandEnvironmentVariables($dest)
    }
    return $dest
}

function Get-ExcludedDirectories {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        $Config,
        [string[]]$AdditionalExcludes
    )

    $excludes = @($Config.defaults.excludeFromBackup)
    if ($AdditionalExcludes) {
        $excludes += $AdditionalExcludes
    }
    # Deduplicate, strip nulls/whitespace, remove empties.
    return @($excludes |
        Where-Object { $_ -and (-not [string]::IsNullOrWhiteSpace($_)) } |
        ForEach-Object { [string]$_ } |
        Sort-Object -Unique)
}

function Get-ProcessNameForBrowser {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$BrowserRawName,
        [Parameter(Mandatory)]
        $Config
    )

    $map = $Config.processNames
    if ($map -and $map.ContainsKey($BrowserRawName)) {
        return [string]$map[$BrowserRawName]
    }
    # Safe fallback: lower-case alphanumeric only.
    $safe = ($BrowserRawName -replace '[^a-zA-Z0-9]', '').ToLower()
    if ([string]::IsNullOrWhiteSpace($safe)) { return "browser" }
    return $safe
}

Export-ModuleMember -Function `
    Get-ConfigPath, `
    Get-BrowserConfig, `
    Get-DefaultConfig, `
    Get-BackupDestination, `
    Get-ExcludedDirectories, `
    Get-ProcessNameForBrowser, `
    Get-ScriptRoot
