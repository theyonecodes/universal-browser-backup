# BrowserDetection.psm1 — discovers installed Chromium and Gecko browsers + their profiles.

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
                # Pick the one with the newest LastWriteTime as a deterministic tiebreaker.
                $candidates = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                return $candidates.FullName
            }
        }
    }
    return $null
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

    foreach ($browserPath in $Config.chromiumPaths.local) {
        if ([string]::IsNullOrWhiteSpace($localAppData)) { continue }
        $basePath = Join-Path $localAppData $browserPath
        if (-not (Test-Path -LiteralPath $basePath)) { continue }

        $userDataPath = $null
        foreach ($variant in @("User Data", "User Data V2")) {
            $candidate = Join-Path $basePath $variant
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $userDataPath = $candidate
                break
            }
        }

        if (-not $userDataPath) { continue }

        $localStatePath = Join-Path $userDataPath "Local State"
        if (-not (Test-Path -LiteralPath $localStatePath -PathType Leaf)) { continue }

        $browserName = ($browserPath -split '\\') | Select-Object -Last 1
        $safeName = ($browserName -replace '[^a-zA-Z0-9]', '')

        $searchRoots = @($programFiles, $programFilesX86)
        $exePath = Resolve-Executable -SearchRoots $searchRoots -RelativeDirs ($Config.chromiumPaths.programFiles | ForEach-Object { "$_\Application" })

        $processName = Get-ProcessNameForBrowser -BrowserRawName $browserName -Config $Config

        $version = "Unknown"
        if ($exePath -and (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            try {
                $info = (Get-Item -LiteralPath $exePath).VersionInfo
                if ($info -and $info.ProductVersion) { $version = $info.ProductVersion }
            } catch { $version = "Unknown" }
        }

        $browsers.Add([PSCustomObject]@{
            Name        = if ($safeName) { "$safeName (Chromium)" } else { "$browserName (Chromium)" }
            Type        = "Chromium"
            ProfilePath = $userDataPath
            ExePath     = $exePath
            ProcessName = $processName
            Version     = $version
            RawName     = $browserName
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
    if ([string]::IsNullOrWhiteSpace($appData)) { return $result.ToArray() }

    $firefoxPath = Join-Path $appData $Config.geckoPaths.appData
    $profilesIni = Join-Path $firefoxPath "profiles.ini"
    if (-not (Test-Path -LiteralPath $profilesIni -PathType Leaf)) { return $result.ToArray() }

    try {
        $iniContent = Get-Content -LiteralPath $profilesIni -Raw -ErrorAction Stop
    } catch {
        Write-Verbose "Could not read profiles.ini: $_"
        return $result.ToArray()
    }

    $hasProfile = $false
    foreach ($line in ($iniContent -split "`r?`n")) {
        if ($line -match '^Path=') { $hasProfile = $true; break }
    }
    if (-not $hasProfile) { return $result.ToArray() }

    $searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    $exePath = Resolve-Executable -SearchRoots $searchRoots -RelativeDirs @("Mozilla Firefox")

    $version = "Unknown"
    if ($exePath -and (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        try {
            $v = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
            if ($v) { $version = $v }
        } catch { }
    }

    $result.Add([PSCustomObject]@{
        Name        = "Firefox (Gecko)"
        Type        = "Gecko"
        ProfilePath = $firefoxPath
        ExePath     = $exePath
        ProcessName = "firefox"
        Version     = $version
        RawName     = "Firefox"
    })

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

    # Deduplicate by (Type, ProfilePath), keep order, prefer the one with an ExePath.
    $seen = @{}
    $deduped = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($b in $all) {
        $key = "$($b.Type)|$($b.ProfilePath.ToString().ToLowerInvariant())"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $deduped.Add($b)
        }
        elseif ($b.ExePath -and -not $seen["__preferred__:$key"]) {
            # Replace the prior entry with this richer one.
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

    if ($Browser.Type -eq "Chromium") {
        $userDataPath = $Browser.ProfilePath
        if (Test-Path -LiteralPath $userDataPath -PathType Container) {
            $dirs = @()
            try {
                $dirs = Get-ChildItem -LiteralPath $userDataPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' }
            } catch { }

            foreach ($dir in $dirs) {
                $size = 0
                try {
                    $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                } catch { }
                if ($null -eq $size) { $size = 0 }
                $profiles.Add([PSCustomObject]@{
                    Name      = $dir.Name
                    FullName  = $dir.FullName
                    SizeMB    = [math]::Round($size / 1MB, 2)
                    IsDefault = $dir.Name -eq 'Default'
                })
            }
        }
    }
    elseif ($Browser.Type -eq "Gecko") {
        $firefoxPath = $Browser.ProfilePath
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
            $defaultEncodedPath = $null

            foreach ($line in ($iniContent -split "`r?`n")) {
                $line = $line.Trim()
                if ($line -match '^\[(Profile\d*)\]$') {
                    # Close out the previous profile entry.
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
                            if ($currentSection -eq "Profile0" -and -not $defaultEncodedPath) {
                                $defaultEncodedPath = $profilePath
                            }
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
                elseif ($line -match '^Default=(.+)$' -and $currentSection -eq "Profile0") {
                    # captured but not needed beyond validation
                }
            }

            # Flush last entry.
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
