function Get-ChromiumBrowsers {
    [CmdletBinding()]
    param(
        [object]$Config
    )

    $browsers = @()
    $localAppData = $env:LOCALAPPDATA
    $programFiles = $env:ProgramFiles
    $programFilesX86 = ${env:ProgramFiles(x86)}

    foreach ($browserPath in $Config.chromiumPaths.local) {
        $basePath = Join-Path $localAppData $browserPath
        # Check for both "User Data" (old) and "User Data V2" (Chromium 120+)
        $userDataPath = @(
            Join-Path $basePath "User Data",
            Join-Path $basePath "User Data V2"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if ($userDataPath) {
            $localStatePath = Join-Path $userDataPath "Local State"
            if (Test-Path $localStatePath) {
                $browserName = $browserPath -split '\\' | Select-Object -Last 1
                $exePaths = @()
                foreach ($pf in @($programFiles, $programFilesX86)) {
                    if ($pf) {
                        foreach ($exePath in $Config.chromiumPaths.programFiles) {
                            $exe = Join-Path $pf "$exePath\Application\*.exe"
                            $found = Get-ChildItem -Path $exe -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -notmatch 'uninstall|setup|installer' } |
                                Select-Object -First 1 -ExpandProperty FullName
                            if ($found) { $exePaths += $found }
                        }
                    }
                }

                $processName = switch ($browserName) {
                    "Chrome"         { "chrome" }
                    "Edge"           { "msedge" }
                    "Brave-Browser"  { "brave" }
                    "Vivaldi"        { "vivaldi" }
                    "Opera stable"   { "opera" }
                    "Opera GX Stable"{ "opera" }
                    "Arc"            { "Arc" }
                    "Floorp"         { "floorp" }
                    "Zen Browser"    { "zen" }
                    default          { $browserName.ToLower() }
                }

                $browsers += [PSCustomObject]@{
                    Name          = "$browserName (Chromium)"
                    Type          = "Chromium"
                    ProfilePath   = $userDataPath
                    ExePath       = $exePaths | Select-Object -First 1
                    ProcessName   = $processName
                    Version       = if ($exePaths.Count -gt 0) {
                        (Get-Item ($exePaths | Select-Object -First 1)).VersionInfo.ProductVersion
                    } else { "Unknown" }
                }
            }
        }
    }

    return $browsers
}

function Get-GeckoBrowsers {
    [CmdletBinding()]
    param(
        [object]$Config
    )

    $browsers = @()
    $appData = $env:APPDATA
    $localAppData = $env:LOCALAPPDATA

    $profilesIni = Join-Path $appData "Mozilla\Firefox\profiles.ini"
    if (Test-Path $profilesIni) {
        $iniContent = Get-Content -Path $profilesIni -Raw
        $profileDirs = @()

        foreach ($line in ($iniContent -split "`n")) {
            $line = $line.Trim()
            if ($line -match '^Path=(.+)$') {
                $path = $matches[1]
                $fullPath = Join-Path $appData "Mozilla\Firefox\$path"
                if (Test-Path $fullPath) {
                    $profileDirs += $fullPath
                }
            }
        }

        $exePath = $null
        $pfPaths = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
        foreach ($pf in $pfPaths) {
            if ($pf) {
                $found = Get-ChildItem -Path "$pf\Mozilla Firefox\firefox.exe" -ErrorAction SilentlyContinue |
                    Select-Object -First 1 -ExpandProperty FullName
                if ($found) { $exePath = $found; break }
            }
        }

        if ($profileDirs.Count -gt 0) {
            $browsers += [PSCustomObject]@{
                Name          = "Firefox (Gecko)"
                Type          = "Gecko"
                ProfilePath   = Join-Path $appData "Mozilla\Firefox"
                ExePath       = $exePath
                ProcessName   = "firefox"
                Version       = if ($exePath) {
                    (Get-Item $exePath).VersionInfo.ProductVersion
                } else { "Unknown" }
            }
        }
    }

    return $browsers
}

function Get-InstalledBrowsers {
    [CmdletBinding()]
    param(
        [object]$Config
    )

    $chromium = Get-ChromiumBrowsers -Config $Config
    $gecko = Get-GeckoBrowsers -Config $Config
    return $chromium + $gecko
}

function Get-BrowserProfiles {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Browser
    )

    $profiles = @()

    if ($Browser.Type -eq "Chromium") {
        $userDataPath = $Browser.ProfilePath
        $profileDirs = Get-ChildItem -Path $userDataPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' }

        foreach ($dir in $profileDirs) {
            $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $profiles += [PSCustomObject]@{
                Name      = $dir.Name
                FullName  = $dir.FullName
                SizeMB    = [math]::Round($size / 1MB, 2)
                IsDefault = $dir.Name -eq 'Default'
            }
        }
    }
    elseif ($Browser.Type -eq "Gecko") {
        $firefoxPath = $Browser.ProfilePath
        $profilesIni = Join-Path $firefoxPath "profiles.ini"
        if (Test-Path $profilesIni) {
            $iniContent = Get-Content -Path $profilesIni -Raw
            $currentSection = ""
            $profileName = ""
            $profilePath = ""

            foreach ($line in ($iniContent -split "`n")) {
                $line = $line.Trim()
                if ($line -match '^\[Profile(.*)\]$') {
                    if ($profilePath) {
                        $fullPath = Join-Path $firefoxPath $profilePath
                        if (Test-Path $fullPath) {
                            $size = (Get-ChildItem -Path $fullPath -Recurse -File -ErrorAction SilentlyContinue |
                                Measure-Object -Property Length -Sum).Sum
                            $profiles += [PSCustomObject]@{
                                Name      = if ($profileName) { $profileName } else { $currentSection }
                                FullName  = $fullPath
                                SizeMB    = [math]::Round($size / 1MB, 2)
                                IsDefault = $currentSection -eq "Profile0"
                            }
                        }
                    }
                    $currentSection = $matches[1]
                    $profileName = ""
                    $profilePath = ""
                }
                elseif ($line -match '^Name=(.+)$') {
                    $profileName = $matches[1]
                }
                elseif ($line -match '^Path=(.+)$') {
                    $profilePath = $matches[1]
                }
            }

            if ($profilePath) {
                $fullPath = Join-Path $firefoxPath $profilePath
                if (Test-Path $fullPath) {
                    $size = (Get-ChildItem -Path $fullPath -Recurse -File -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                    $profiles += [PSCustomObject]@{
                        Name      = if ($profileName) { $profileName } else { $currentSection }
                        FullName  = $fullPath
                        SizeMB    = [math]::Round($size / 1MB, 2)
                        IsDefault = $currentSection -eq "Profile0"
                    }
                }
            }
        }
    }

    return $profiles
}

function Test-BrowserRunning {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Browser
    )

    $processes = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    return ($null -ne $processes -and $processes.Count -gt 0)
}

function Get-BrowserVersion {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Browser
    )

    if ($Browser.ExePath -and (Test-Path $Browser.ExePath)) {
        return (Get-Item $Browser.ExePath).VersionInfo.ProductVersion
    }
    return "Unknown"
}

function Stop-BrowserGracefully {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Browser,
        [switch]$Force
    )

    $processes = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    if (-not $processes) {
        Write-Verbose "$($Browser.Name) is not running."
        return $true
    }

    Write-Verbose "Attempting graceful shutdown of $($Browser.Name)..."
    $processes | ForEach-Object {
        try {
            $_.CloseMainWindow() | Out-Null
        } catch {
            Write-Verbose "Could not close window for PID $($_.Id): $_"
        }
    }

    Start-Sleep -Seconds 3

    $stillRunning = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    if ($stillRunning -and $Force) {
        Write-Verbose "Force stopping $($Browser.Name)..."
        $stillRunning | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $stillRunning = Get-Process -Name $Browser.ProcessName -ErrorAction SilentlyContinue
    return (-not $stillRunning -or $stillRunning.Count -eq 0)
}

Export-ModuleMember -Function Get-ChromiumBrowsers, Get-GeckoBrowsers, Get-InstalledBrowsers, Get-BrowserProfiles, Test-BrowserRunning, Get-BrowserVersion, Stop-BrowserGracefully
