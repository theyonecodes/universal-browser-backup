Import-Module (Join-Path $PSScriptRoot 'Modules\Config.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\BrowserDetection.psm1') -Force

$config = Get-BrowserConfig -ConfigPath (Join-Path $PSScriptRoot 'Config\browsers.json')
$browsers = Get-InstalledBrowsers -Config $config

foreach ($b in $browsers) {
    Write-Host "Browser: $($b.Name)" -ForegroundColor Cyan
    $profiles = Get-BrowserProfiles -Browser $b
    Write-Host "  Profiles found: $($profiles.Count)" -ForegroundColor Yellow
    foreach ($p in $profiles) {
        Write-Host "    - $($p.Name) ($($p.DisplayName)) <$($p.Email)> - $($p.SizeMB) MB"
    }
}
