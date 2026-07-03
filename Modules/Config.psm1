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

            # Determine format: new "browsers" array vs legacy chromiumPaths dict.
            # Use PSObject.Properties to avoid strict-mode PropertyNotFoundException.
            $hasNewFormat    = $null -ne ($parsed.PSObject.Properties['browsers'])
            $hasLegacyFormat = $null -ne ($parsed.PSObject.Properties['chromiumPaths'])

            # If the new "browsers" array format is present, validate and build
            # a config that also exposes chromiumPaths/geckoPaths for backward compat.
            if ($hasNewFormat -and -not $hasLegacyFormat) {
                $browsersList = @()
                foreach ($b in $parsed.browsers) {
                    $browserEntry = @{
                        name             = [string]$b.name
                        alias           = [string]$b.alias
                        type             = [string]$b.type
                        engineFamily     = [string]$b.engineFamily
                        icon             = [string]$b.icon
                        processName      = [string]$b.processName
                        profileRoot      = if ($b.profileRoot) { [string]$b.profileRoot } else { $null }
                        detectStrategy   = [string]$b.detectStrategy
                        localPath        = [string]$b.localPath
                        programFilesPath = if ($b.programFilesPath) { [string]$b.programFilesPath } else { $null }
                    }
                    $browsersList += $browserEntry
                }

                $legacyChromium = @()
                $legacyGeckoPaths = @{ appData = $null; localAppData = $null }

                foreach ($b in $browsersList) {
                    if ($b.engineFamily -eq 'Chromium') {
                        if ($b.localPath) { $legacyChromium += $b.localPath }
                    } elseif ($b.engineFamily -eq 'Gecko' -and $b.localPath) {
                        if (-not $legacyGeckoPaths.appData) {
                            $legacyGeckoPaths.appData = $b.localPath
                            $legacyGeckoPaths.localAppData = $b.localPath
                        }
                    }
                }

                $config = @{
                    version        = [string]$parsed.version
                    defaults       = @{
                        backupDestination    = if ($parsed.defaults.backupDestination) { [string]$parsed.defaults.backupDestination } else { "$env:USERPROFILE\Desktop" }
                        excludeFromBackup    = $exclude
                        robocopyRetries       = [int]$parsed.defaults.robocopyRetries
                        robocopyWait          = [int]$parsed.defaults.robocopyWait
                        maxLogFiles           = [int]$parsed.defaults.maxLogFiles
                        checksumCriticalFiles = $critical
                    }
                    chromiumPaths  = @{ local = $legacyChromium; programFiles = @() }
                    geckoPaths     = $legacyGeckoPaths
                    processNames   = $processNames
                    browsers       = $browsersList
                }
                Write-Verbose "Loaded config version: $($config.version) (browsers array format)"
                return $config
            }

            # Legacy JSON format with explicit chromiumPaths / geckoPaths
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
