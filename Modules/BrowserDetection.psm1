# BrowserDetection.psm1 - discovers installed browsers + their profiles using browsers.json v2.1.1

Set-StrictMode -Version Latest

function Resolve-Executable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string[]]$SearchRoots,
        [string[]]$RelativeDirs,
        [string]$ExePattern = "*.exe"
    )

    foreach ($root in ($SearchRoots | Where-Object { $_ })) {
        foreach ($rel in $RelativeDirs) {
            $search = Join-Path $root $rel
            if (-not (Test-Path -LiteralPath $search)) { continue }
            $candidates = @()
            try {
                $candidates = Get-ChildItem -LiteralPath $search -Filter $ExePattern -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch 'uninstall|setup|installer|update|helper|crashpad' }
            } catch { continue }
            if ($candidates.Count -gt 0) {
                $candidates = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                return $candidates.FullName
            }
        }
    }
    return $null
}

function Get-ProcessNameForBrowser {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$BrowserAlias,
        [hashtable]$Config
    )

    $processNames = $Config.processNames
    if ($processNames -and $processNames.ContainsKey($BrowserAlias)) {
        return $processNames[$BrowserAlias]
    }
    return $BrowserAlias.ToLowerInvariant()
}

function Get-ChromiumBrowsers {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $browsers = [System.Collections.Generic.List[PSCustomObject]]::new()
    $localAppData = $env:LOCALAPPDATA
    $programFiles = $env:ProgramFiles
    $programFilesX86 = ${env:ProgramFiles(x86)}

    $browserDefs = $Config.browsers | Where-Object { $_.type -eq "Chromium" }

    foreach ($browserDef in $browserDefs) {
        if ([string]::IsNullOrWhiteSpace($localAppData)) { continue }

        $localPath = $browserDef.localPath
        if (-not $localPath) { continue }

        $basePath = Join-Path $localAppData $localPath
        if (-not (Test-Path -LiteralPath $basePath)) { continue }

        $userDataPath = $null
        $profileRoot = if ($browserDef.profileRoot) { $browserDef.profileRoot } else { "Default" }

        # Check basePath itself first — most Chromium browsers' localPath
        # already ends in "User Data", so basePath IS the data folder.
        $localStateInBase = Join-Path $basePath "Local State"
        if (Test-Path -LiteralPath $localStateInBase -PathType Leaf) {
            $userDataPath = $basePath
        } else {
            $variants = @($profileRoot, "Default", "User Data", "User Data V2", "$profileRoot V2")
            $variants = $variants | Select-Object -Unique

            foreach ($variant in $variants) {
                $candidate = Join-Path $basePath $variant
                if (Test-Path -LiteralPath $candidate -PathType Container) {
                    $userDataPath = $candidate
                    break
                }
            }
        }

        if (-not $userDataPath) { continue }

        $localStatePath = Join-Path $userDataPath "Local State"
        if (-not (Test-Path -LiteralPath $localStatePath -PathType Leaf)) { continue }

        $safeName = $browserDef.alias
        if (-not $safeName) { $safeName = ($localPath -split '\\') | Select-Object -Last 1 }

        $searchRoots = @($programFiles, $programFilesX86)
        $relativePath = $browserDef.programFilesPath
        $exePath = $null
        if ($relativePath) {
            $exePath = Resolve-Executable -SearchRoots $searchRoots -RelativeDirs @("$relativePath\Application")
        }

        $processName = Get-ProcessNameForBrowser -BrowserAlias $browserDef.alias -Config $Config
        if (-not $processName) { $processName = $browserDef.processName }

        $version = "Unknown"
        if ($exePath -and (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            try {
                $info = (Get-Item -LiteralPath $exePath).VersionInfo
                if ($info -and $info.ProductVersion) { $version = $info.ProductVersion }
            } catch { $version = "Unknown" }
        }

        $engineFamily = if ($browserDef.engineFamily) { $browserDef.engineFamily } else { "Chromium" }

        $browsers.Add([PSCustomObject]@{
            Name           = if ($safeName) { "$safeName ($engineFamily)" } else { "$($browserDef.name) (Chromium)" }
            Type           = "Chromium"
            EngineFamily   = $engineFamily
            ProfilePath    = $userDataPath
            ExePath        = $exePath
            ProcessName    = $processName
            Version        = $version
            RawName        = $safeName
            Icon           = if ($browserDef.icon) { $browserDef.icon } else { $safeName.ToLowerInvariant() }
            DetectStrategy = if ($browserDef.detectStrategy) { $browserDef.detectStrategy } else { "localState" }
        })
    }

    return $browsers.ToArray()
}

function Get-GeckoBrowsers {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()
    $appData = $env:APPDATA
    $localAppData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($appData)) { return $result.ToArray() }

    $browserDefs = $Config.browsers | Where-Object { $_.type -eq "Gecko" }

    foreach ($browserDef in $browserDefs) {
        $localPath = $browserDef.localPath
        if (-not $localPath) { continue }

        $detectStrategy = if ($browserDef.detectStrategy) { $browserDef.detectStrategy } else { "profilesIni" }
        $firefoxPath = $null

        if ($detectStrategy -eq "localProfilesDir") {
            # Zen-style: profiles live in LOCALAPPDATA\{localPath}\Profiles\
            $localRoot = Join-Path $localAppData $localPath
            $profilesDir = Join-Path $localRoot "Profiles"
            if (Test-Path -LiteralPath $profilesDir -PathType Container) {
                $firefoxPath = $localRoot
            } else {
                continue
            }
        } else {
            # Standard Firefox-style: profiles.ini in APPDATA
            $firefoxPath = Join-Path $appData $localPath
            $profilesIni = Join-Path $firefoxPath "profiles.ini"
            if (-not (Test-Path -LiteralPath $profilesIni -PathType Leaf)) { continue }

            try {
                $iniContent = Get-Content -LiteralPath $profilesIni -Raw -ErrorAction Stop
            } catch {
                Write-Verbose "Could not read profiles.ini: $_"
                continue
            }

            $hasProfile = $false
            foreach ($line in ($iniContent -split "`r?`n")) {
                if ($line -match '^Path=') { $hasProfile = $true; break }
            }
            if (-not $hasProfile) { continue }
        }

        $searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
        $relativePath = $browserDef.programFilesPath
        $exePath = $null
        if ($relativePath) {
            $exePath = Resolve-Executable -SearchRoots $searchRoots -RelativeDirs @($relativePath)
        }

        $safeName = $browserDef.alias
        if (-not $safeName) { $safeName = $browserDef.name }

        $processName = Get-ProcessNameForBrowser -BrowserAlias $browserDef.alias -Config $Config
        if (-not $processName) { $processName = $browserDef.processName }

        $version = "Unknown"
        if ($exePath -and (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            try {
                $v = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
                if ($v) { $version = $v }
            } catch { }
        }

        $engineFamily = if ($browserDef.engineFamily) { $browserDef.engineFamily } else { "Firefox" }

        $result.Add([PSCustomObject]@{
            Name           = "$safeName (Gecko)"
            Type           = "Gecko"
            EngineFamily   = $engineFamily
            ProfilePath    = $firefoxPath
            ExePath        = $exePath
            ProcessName    = $processName
            Version        = $version
            RawName        = $safeName
            Icon           = if ($browserDef.icon) { $browserDef.icon } else { $safeName.ToLowerInvariant() }
            DetectStrategy = $detectStrategy
        })
    }

    return $result.ToArray()
}

function Get-InstalledBrowsers {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $chromium = @(Get-ChromiumBrowsers -Config $Config)
    $gecko    = @(Get-GeckoBrowsers    -Config $Config)

    $all = @($chromium + $gecko)

    $seen = @{}
    $deduped = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($b in $all) {
        $key = "$($b.Type)|$($b.ProfilePath.ToString().ToLowerInvariant())"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $deduped.Add($b)
        }
        elseif ($b.ExePath -and -not $seen["__preferred__:$key"]) {
            $idx = $deduped.FindIndex({ param($x) "$($x.Type)|$($x.ProfilePath.ToString().ToLowerInvariant())" -eq $key })
            if ($idx -ge 0) { $deduped[$idx] = $b }
            $seen["__preferred__:$key"] = $true
        }
    }
    return $deduped.ToArray()
}

function Get-BrowserProfiles {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser
    )

    $profiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    $btype = $Browser.Type
    $detectStrategy = $Browser.DetectStrategy

    # Files that preserve your login state, bookmarks, history
    $criticalFileNames = @("Login Data", "Cookies", "Preferences", "Secure Preferences",
                           "Bookmarks", "Bookmarks.bak", "History", "Web Data")

    # Default exclusions from config
    $defaultExcludes = @("Cache", "Code Cache", "Service Worker", "cache2",
                         "startupCache", "GPUCache", "Thumbnails", "blob_storage",
                         "Network", "Session Storage", "File System", "Storage",
                         "ShaderCache", "GrShaderCache", "GraphiteDawnCache",
                         "DawnWebGPUCache", "Local Storage", "IndexedDB", "Visited Links")

    if ($btype -eq "Chromium" -or $detectStrategy -eq "localState") {
        $userDataPath = $Browser.ProfilePath
        if (Test-Path -LiteralPath $userDataPath -PathType Container) {
            # Read profile metadata from Local State info_cache
            $infoCache = @{}
            $localStatePath = Join-Path $userDataPath "Local State"
            if (Test-Path -LiteralPath $localStatePath -PathType Leaf) {
                try {
                    $lsData = Get-Content -LiteralPath $localStatePath -Raw | ConvertFrom-Json
                    if ($lsData.profile.info_cache) {
                        $lsData.profile.info_cache.PSObject.Properties | ForEach-Object {
                            $infoCache[$_.Name] = $_.Value
                        }
                    }
                } catch { }
            }

            # TRUTH SOURCE: iterate info_cache keys when available
            $profileDirs = @{}
            if ($infoCache.Count -gt 0) {
                foreach ($key in $infoCache.Keys) {
                    $candidate = Join-Path $userDataPath $key
                    if (Test-Path -LiteralPath $candidate -PathType Container) {
                        $profileDirs[$key] = $candidate
                    }
                }
            } else {
                # Fallback: scan directories if info_cache unavailable
                try {
                    Get-ChildItem -LiteralPath $userDataPath -Directory -ErrorAction SilentlyContinue |
                        Where-Object {
                            $_.Name -eq 'Default' -or
                            $_.Name -match '^Profile \d+$' -or
                            $_.Name -match '-release$' -or
                            $_.Name -match '-beta$'
                        } | ForEach-Object {
                            $profileDirs[$_.Name] = $_.FullName
                        }
                } catch { }
            }

            foreach ($key in $profileDirs.Keys) {
                $dirPath = $profileDirs[$key]
                $size = 0
                try {
                    $size = (Get-ChildItem -LiteralPath $dirPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                } catch { }
                if ($null -eq $size) { $size = 0 }

                # Get metadata from info_cache
                $displayName = ""
                $email = ""
                if ($infoCache.ContainsKey($key)) {
                    $cacheEntry = $infoCache[$key]
                    $displayName = if ($cacheEntry.name) { $cacheEntry.name } else { "" }
                    $email = if ($cacheEntry.gaia_name) { $cacheEntry.gaia_name }
                             elseif ($cacheEntry.user_name) { $cacheEntry.user_name }
                             elseif ($cacheEntry.gaia_email) { $cacheEntry.gaia_email }
                             elseif ($cacheEntry.signed_in_email) { $cacheEntry.signed_in_email }
                             else { "" }
                }

                # Count critical files
                $criticalBacked = 0
                $criticalTotal = $criticalFileNames.Count
                $criticalDetails = @()
                foreach ($cf in $criticalFileNames) {
                    $cfPath = Join-Path $dirPath $cf
                    $exists = Test-Path -LiteralPath $cfPath -PathType Leaf
                    if ($exists) { $criticalBacked++ }
                    $cfSize = 0
                    if ($exists) {
                        try { $cfSize = (Get-Item -LiteralPath $cfPath).Length } catch { }
                    }
                    $criticalDetails += [PSCustomObject]@{
                        Name = $cf
                        Exists = $exists
                        SizeKB = [math]::Round($cfSize / 1KB, 1)
                    }
                }

                # Estimate size after exclusions
                $excludedSize = 0
                try {
                    $excludedSize = (Get-ChildItem -LiteralPath $dirPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Where-Object {
                            $rel = $_.FullName.Substring($dirPath.Length + 1)
                            $excluded = $false
                            foreach ($excl in $defaultExcludes) {
                                if ($rel.StartsWith($excl + [IO.Path]::DirectorySeparatorChar) -or $rel.StartsWith($excl + "/")) {
                                    $excluded = $true
                                    break
                                }
                            }
                            $excluded
                        } | Measure-Object -Property Length -Sum).Sum
                } catch { }
                if ($null -eq $excludedSize) { $excludedSize = 0 }

                $profiles.Add([PSCustomObject]@{
                    Name           = $key
                    FullName       = $dirPath
                    SizeMB         = [math]::Round($size / 1MB, 2)
                    IsDefault      = $key -eq 'Default'
                    DisplayName    = $displayName
                    Email          = $email
                    CriticalBacked = $criticalBacked
                    CriticalTotal  = $criticalTotal
                    CriticalDetails = $criticalDetails
                    EstimatedSizeMB = [math]::Round(($size - $excludedSize) / 1MB, 2)
                    ExcludedSizeMB = [math]::Round($excludedSize / 1MB, 2)
                })
            }
        }
    }
    elseif ($btype -eq "Gecko" -or $detectStrategy -eq "profilesIni" -or $detectStrategy -eq "localProfilesDir") {
        $firefoxPath = $Browser.ProfilePath

        if ($detectStrategy -eq "localProfilesDir") {
            # Zen-style: profiles live in $firefoxPath\Profiles\<hash>.<name>
            $profilesDir = Join-Path $firefoxPath "Profiles"
            if (Test-Path -LiteralPath $profilesDir -PathType Container) {
                $profileDirs = Get-ChildItem -LiteralPath $profilesDir -Directory -Force -ErrorAction SilentlyContinue
                $isDefault = $true
                foreach ($dir in $profileDirs) {
                    $fullPath = $dir.FullName
                    $size = 0
                    try {
                        $size = (Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                    } catch { }
                    if ($null -eq $size) { $size = 0 }

                    $criticalBacked = 0
                    $criticalTotal = $criticalFileNames.Count
                    $criticalDetails = @()
                    foreach ($cf in $criticalFileNames) {
                        $cfPath = Join-Path $fullPath $cf
                        $exists = Test-Path -LiteralPath $cfPath -PathType Leaf
                        if ($exists) { $criticalBacked++ }
                        $cfSize = 0
                        if ($exists) {
                            try { $cfSize = (Get-Item -LiteralPath $cfPath).Length } catch { }
                        }
                        $criticalDetails += [PSCustomObject]@{
                            Name = $cf
                            Exists = $exists
                            SizeKB = [math]::Round($cfSize / 1KB, 1)
                        }
                    }

                    # Strip <hash>. prefix to get display name (e.g. "9pr8v7oq.Default Profile" -> "Default Profile")
                    $dirName = $dir.Name
                    $displayName = $dirName
                    $dotIdx = $dirName.IndexOf(".")
                    if ($dotIdx -gt 0) { $displayName = $dirName.Substring($dotIdx + 1) }

                    $profiles.Add([PSCustomObject]@{
                        Name           = $displayName
                        FullName       = $fullPath
                        SizeMB         = [math]::Round($size / 1MB, 2)
                        IsDefault      = $isDefault
                        DisplayName    = ""
                        Email          = ""
                        CriticalBacked = $criticalBacked
                        CriticalTotal  = $criticalTotal
                        CriticalDetails = $criticalDetails
                        EstimatedSizeMB = [math]::Round($size / 1MB, 2)
                        ExcludedSizeMB = 0
                    })
                    $isDefault = $false
                }
            }
        }
        else {
            # Standard Firefox-style: profiles.ini in APPDATA
            $profilesIni = Join-Path $firefoxPath "profiles.ini"
            if (Test-Path -LiteralPath $profilesIni -PathType Leaf) {
                try {
                    $iniContent = Get-Content -LiteralPath $profilesIni -Raw -ErrorAction Stop
                } catch {
                    Write-Verbose "Could not read profiles.ini: $_"
                    return $profiles.ToArray()
                }

                $currentSection = $null
                $profileName = $null
                $profilePath = $null

                foreach ($line in ($iniContent -split "`r?`n")) {
                    $line = $line.Trim()
                    if ($line -match '^\[(Profile\d*)\]$') {
                        if ($currentSection -and $profilePath) {
                            $fullPath = if ([System.IO.Path]::IsPathRooted($profilePath)) {
                                $profilePath
                            } else {
                                Join-Path $firefoxPath $profilePath
                            }
                            if (Test-Path -LiteralPath $fullPath -PathType Container) {
                                $size = 0
                                try {
                                    $size = (Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                        Measure-Object -Property Length -Sum).Sum
                                } catch { }
                                if ($null -eq $size) { $size = 0 }

                                $criticalBacked = 0
                                $criticalTotal = $criticalFileNames.Count
                                $criticalDetails = @()
                                foreach ($cf in $criticalFileNames) {
                                    $cfPath = Join-Path $fullPath $cf
                                    $exists = Test-Path -LiteralPath $cfPath -PathType Leaf
                                    if ($exists) { $criticalBacked++ }
                                    $cfSize = 0
                                    if ($exists) {
                                        try { $cfSize = (Get-Item -LiteralPath $cfPath).Length } catch { }
                                    }
                                    $criticalDetails += [PSCustomObject]@{
                                        Name = $cf
                                        Exists = $exists
                                        SizeKB = [math]::Round($cfSize / 1KB, 1)
                                    }
                                }

                                $profiles.Add([PSCustomObject]@{
                                    Name           = if ($profileName) { $profileName } else { $currentSection }
                                    FullName       = $fullPath
                                    SizeMB         = [math]::Round($size / 1MB, 2)
                                    IsDefault      = ($currentSection -eq "Profile0")
                                    DisplayName    = ""
                                    Email          = ""
                                    CriticalBacked = $criticalBacked
                                    CriticalTotal  = $criticalTotal
                                    CriticalDetails = $criticalDetails
                                    EstimatedSizeMB = [math]::Round($size / 1MB, 2)
                                    ExcludedSizeMB = 0
                                })
                            }
                        }
                        $currentSection = $matches[1]
                        $profileName = $null
                        $profilePath = $null
                    }
                    elseif ($line -match '^Name=(.+)$') {
                        $profileName = $matches[1]
                    }
                    elseif ($line -match '^Path=(.+)$') {
                        $profilePath = $matches[1]
                    }
                }

                if ($currentSection -and $profilePath) {
                    $fullPath = if ([System.IO.Path]::IsPathRooted($profilePath)) {
                        $profilePath
                    } else {
                        Join-Path $firefoxPath $profilePath
                    }
                    if (Test-Path -LiteralPath $fullPath -PathType Container) {
                        $size = 0
                        try {
                            $size = (Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                                Measure-Object -Property Length -Sum).Sum
                        } catch { }
                        if ($null -eq $size) { $size = 0 }
                        $profiles.Add([PSCustomObject]@{
                            Name      = if ($profileName) { $profileName } else { $currentSection }
                            FullName  = $fullPath
                            SizeMB    = [math]::Round($size / 1MB, 2)
                            IsDefault = ($currentSection -eq "Profile0")
                        })
                    }
                }
            }
        }
    }

    return $profiles.ToArray()
}

function Test-BrowserRunning {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser
    )
    if (-not $Browser.ProcessName) { return $false }
    $procs = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    return ($null -ne $procs -and @($procs).Count -gt 0)
}

function Get-BrowserVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser
    )
    if ($Browser.ExePath -and (Test-Path -LiteralPath $Browser.ExePath -PathType Leaf)) {
        try { return (Get-Item -LiteralPath $Browser.ExePath).VersionInfo.ProductVersion } catch { }
    }
    return "Unknown"
}

function Stop-BrowserGracefully {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Browser,
        [switch]$Force
    )

    $processes = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    if (-not $processes) {
        Write-Verbose "$($Browser.Name) is not running."
        return $true
    }

    foreach ($p in @($processes)) {
        try { $null = $p.CloseMainWindow() } catch { Write-Verbose "CloseMainWindow failed for PID $($p.Id): $_" }
    }

    $waited = 0
    while ($waited -lt 5) {
        Start-Sleep -Seconds 1
        $waited++
        $still = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
        if (-not $still) { return $true }
    }

    if ($Force) {
        Write-Verbose "Force stopping $($Browser.Name)..."
        $still = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
        if ($still) {
            $still | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    return ($null -eq (Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue))
}

Export-ModuleMember -Function `
    Get-ChromiumBrowsers, `
    Get-GeckoBrowsers, `
    Get-InstalledBrowsers, `
    Get-BrowserProfiles, `
    Test-BrowserRunning, `
    Get-BrowserVersion, `
    Stop-BrowserGracefully