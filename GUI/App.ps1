$script:ModuleRoot = Split-Path -Parent $PSScriptRoot

Import-Module "$script:ModuleRoot\Modules\Config.psm1" -Force
Import-Module "$script:ModuleRoot\Modules\BrowserDetection.psm1" -Force
Import-Module "$script:ModuleRoot\Modules\Logging.psm1" -Force
Import-Module "$script:ModuleRoot\Modules\BackupEngine.psm1" -Force
Import-Module "$script:ModuleRoot\Modules\RestoreEngine.psm1" -Force

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
$xaml = Get-Content -Path $xamlPath -Raw
$xaml = $xaml -replace 'x:Class="[^"]*"', ''
$xaml = $xaml -replace 'mc:Ignorable="d"', ''

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$script:config = Get-BrowserConfig
$script:logFile = Initialize-Log
$script:jobRunning = $false
$script:cancelRequested = $false

$controls = @{}
$window.FindName('txtDestination').Text = "$env:USERPROFILE\Desktop"
$window.FindName('btnAction').Add_Click({ Invoke-SelectedAction })
$window.FindName('btnCancel').Add_Click({ Request-Cancel })
$window.FindName('btnBrowse').Add_Click({ Browse-Destination })
$window.FindName('btnRefresh').Add_Click({ Refresh-BrowserList })
$window.FindName('chkSelectAll').Add_Click({ Select-All-Browsers })

function Write-GUI {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "INFO"  { "[INFO]" }
        "WARN"  { "[WARN]" }
        "ERROR" { "[FAIL]" }
        "OK"    { "[ OK ]" }
    }
    $window.FindName('txtLog').Text += "[$timestamp] $prefix $Message`r`n"
    $window.FindName('txtLog').ScrollToEnd()
}

function Refresh-BrowserList {
    $window.FindName('lstBrowsers').Items.Clear()
    Write-GUI "Detecting installed browsers..."

    $browsers = Get-InstalledBrowsers -Config $script:config
    foreach ($browser in $browsers) {
        $profiles = Get-BrowserProfiles -Browser $browser
        $totalSize = ($profiles | Measure-Object -Property SizeMB -Sum).Sum

        $item = [PSCustomObject]@{
            Browser      = $browser
            Name         = $browser.Name
            ProfileCount = $profiles.Count
            SizeMB       = [math]::Round($totalSize, 2)
            Profiles     = $profiles
        }

        $listBox = $window.FindName('lstBrowsers')
        $listBox.Items.Add($item) | Out-Null
    }

    Write-GUI "Found $($browsers.Count) browser(s)" "OK"
    Update-ModeUI
}

function Select-All-Browsers {
    $listBox = $window.FindName('lstBrowsers')
    $selectAll = $window.FindName('chkSelectAll').IsChecked
    if ($selectAll) {
        for ($i = 0; $i -lt $listBox.Items.Count; $i++) {
            $listBox.SelectedItems.Add($listBox.Items[$i]) | Out-Null
        }
    } else {
        $listBox.SelectedItems.Clear()
    }
}

function Browse-Destination {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select backup destination"
    $dialog.SelectedPath = $window.FindName('txtDestination').Text

    Add-Type -AssemblyName System.Windows.Forms
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.FindName('txtDestination').Text = $dialog.SelectedPath
    }
}

function Update-ModeUI {
    $isBackup = $window.FindName('radBackup').IsChecked
    $actionBtn = $window.FindName('btnAction')
    $actionBtn.Content = if ($isBackup) { "Start Backup" } else { "Start Restore" }
}

$window.FindName('radBackup').Add_Click({ Update-ModeUI })
$window.FindName('radRestore').Add_Click({ Update-ModeUI })

function Set-Progress {
    param([int]$Percent, [string]$Text = "")
    $window.FindName('progressBar').Value = $Percent
    if ($Text) { $window.FindName('txtProgress').Text = $Text }
}

function Set-Status {
    param([string]$Text, [string]$Color = "SecondaryColor")
    $window.FindName('txtStatus').Text = $Text
}

function Set-Running {
    param([bool]$Running)
    $script:jobRunning = $Running
    $window.FindName('btnAction').IsEnabled = -not $Running
    $window.FindName('btnCancel').Visibility = if ($Running) { "Visible" } else { "Collapsed" }
    $window.FindName('btnRefresh').IsEnabled = -not $Running
    $window.FindName('lstBrowsers').IsEnabled = -not $Running
}

function Request-Cancel {
    if ($script:jobRunning) {
        $script:cancelRequested = $true
        Write-GUI "Cancellation requested..." "WARN"
    }
}

function Invoke-SelectedAction {
    $listBox = $window.FindName('lstBrowsers')
    $selected = @($listBox.SelectedItems)

    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one browser.", "No Selection", "OK", "Warning")
        return
    }

    $destination = $window.FindName('txtDestination').Text
    if (-not $destination -or -not (Test-Path $destination)) {
        [System.Windows.MessageBox]::Show("Please select a valid destination folder.", "Invalid Destination", "OK", "Warning")
        return
    }

    $isBackup = $window.FindName('radBackup').IsChecked
    Set-Running $true
    $script:cancelRequested = $false
    Set-Progress 0 ""
    Set-Status "Processing..." "PrimaryColor"

    $action = if ($isBackup) { "Backup" } else { "Restore" }
    Write-GUI "Starting $action of $($selected.Count) browser(s)..."

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("selected", $selected)
    $runspace.SessionStateProxy.SetVariable("destination", $destination)
    $runspace.SessionStateProxy.SetVariable("isBackup", $isBackup)
    $runspace.SessionStateProxy.SetVariable("config", $script:config)
    $runspace.SessionStateProxy.SetVariable("cancelRef", [ref]$script:cancelRequested)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({
        $total = $selected.Count
        $completed = 0
        $errors = 0

        foreach ($item in $selected) {
            if ($cancelRef.Value) { break }

            $browser = $item.Browser
            $profiles = $item.Profiles

            foreach ($profile in $profiles) {
                if ($cancelRef.Value) { break }

                $completed++
                $percent = [math]::Round(($completed / ($total * $profiles.Count)) * 100)

                try {
                    if ($isBackup) {
                        $result = New-BrowserBackup -Browser $browser -ProfileName $profile.Name `
                            -Destination $destination -ExcludeDirs $config.defaults.excludeFromBackup `
                            -Force -ErrorAction Stop

                        if (-not $result.Success) { $errors++ }
                    } else {
                        # Restore logic would go here
                        Write-Host "Restore not yet implemented"
                    }
                } catch {
                    $errors++
                    Write-Host "ERROR: $_"
                }
            }
        }

        return @{ Completed = $completed; Errors = $errors; Total = $total }
    })

    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if ($handle.IsCompleted) {
            $timer.Stop()
            $result = $ps.EndInvoke($handle)
            $ps.Dispose()
            $runspace.Close()

            Set-Running $false
            Set-Progress 100 "Complete"

            if ($script:cancelRequested) {
                Set-Status "Cancelled" "WarningColor"
                Write-GUI "Operation cancelled by user" "WARN"
            } elseif ($result.Errors -gt 0) {
                Set-Status "Completed with $($result.Errors) error(s)" "WarningColor"
                Write-GUI "Completed with $($result.Errors) error(s)" "WARN"
            } else {
                Set-Status "All operations completed successfully" "SecondaryColor"
                Write-GUI "All $($result.Completed) operation(s) completed successfully" "OK"
            }
        } else {
            $window.FindName('txtProgress').Text = "Working..."
        }
    })
    $timer.Start()
}

function Request-Cancel {
    $script:cancelRequested = $true
    Write-GUI "Cancelling..." "WARN"
}

Refresh-BrowserList
$window.ShowDialog() | Out-Null
