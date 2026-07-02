<# 
.SYNOPSIS
    Universal Browser Backup GUI - WPF frontend
.DESCRIPTION
    Accepts -Config and -LogFile from the CLI host so logging stays in one file.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] $Config,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:config = $Config
$script:logFile = $LogFile
$script:jobRunning = $false
$script:cancelRequested = $false
$script:psInstance = $null
$script:runspace = $null
$script:dispatcherTimer = $null

# Load modules in this runspace
Import-Module (Join-Path $script:ModuleRoot 'Modules\Config.psm1')          -Force -DisableNameChecking
Import-Module (Join-Path $script:ModuleRoot 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:ModuleRoot 'Modules\Logging.psm1')          -Force -DisableNameChecking
Import-Module (Join-Path $script:ModuleRoot 'Modules\BackupEngine.psm1')     -Force -DisableNameChecking
Import-Module (Join-Path $script:ModuleRoot 'Modules\RestoreEngine.psm1')    -Force -DisableNameChecking

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
$xaml = Get-Content -LiteralPath $xamlPath -Raw -ErrorAction Stop
# Strip code-behind artifacts
$xaml = $xaml -replace 'x:Class="[^"]*"', ''
$xaml = $xaml -replace 'mc:Ignorable="d"', ''

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)
if (-not $window) { throw 'Failed to load XAML' }

# Resolve named elements once
function Find($name) { $window.FindName($name) }

$txtDestination = Find 'txtDestination'
$lstBrowsers    = Find 'lstBrowsers'
$txtLog         = Find 'txtLog'
$progressBar    = Find 'progressBar'
$txtProgress    = Find 'txtProgress'
$txtStatus      = Find 'txtStatus'
$btnAction      = Find 'btnAction'
$btnCancel      = Find 'btnCancel'
$btnRefresh     = Find 'btnRefresh'
$btnBrowse      = Find 'btnBrowse'
$chkSelectAll   = Find 'chkSelectAll'
$radBackup      = Find 'radBackup'
$radRestore     = Find 'radRestore'

$txtDestination.Text = [System.Environment]::ExpandEnvironmentVariables($script:config.defaults.backupDestination)

# ---------- UI Helpers ----------
function Write-GUI {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'INFO'  { '[INFO]' }
        'WARN'  { '[WARN]' }
        'ERROR' { '[FAIL]' }
        'OK'    { '[ OK ]' }
    }
    $txtLog.Dispatcher.Invoke([action]{
        $txtLog.Text += "[$timestamp] $prefix $Message`r`n"
        $txtLog.ScrollToEnd()
    })
}

function Set-Progress {
    param([int]$Percent, [string]$Text = '')
    $progressBar.Dispatcher.Invoke([action]{
        $progressBar.Value = [math]::Max(0, [math]::Min(100, $Percent))
        if ($Text) { $txtProgress.Text = $Text }
    })
}

function Set-Status {
    param([string]$Text, [string]$Color = 'SecondaryColor')
    $txtStatus.Dispatcher.Invoke([action]{
        $txtStatus.Text = $Text
        if ($Color) { $txtStatus.Foreground = $window.TryFindResource($Color) }
    })
}

function Set-Running {
    param([bool]$Running)
    $script:jobRunning = $Running
    $window.Dispatcher.Invoke([action]{
        $btnAction.IsEnabled = -not $Running
        $btnCancel.Visibility = if ($Running) { 'Visible' } else { 'Collapsed' }
        $btnRefresh.IsEnabled = -not $Running
        $lstBrowsers.IsEnabled = -not $Running
        $radBackup.IsEnabled = -not $Running
        $radRestore.IsEnabled = -not $Running
    })
}

# ---------- Browser List ----------
function Refresh-BrowserList {
    $lstBrowsers.Dispatcher.Invoke([action]{ $lstBrowsers.Items.Clear() })
    Write-GUI 'Detecting installed browsers...'

    try {
        $browsers = @(Get-InstalledBrowsers -Config $script:config)
        foreach ($browser in $browsers) {
            $profiles = @(Get-BrowserProfiles -Browser $browser)
            $totalSize = ($profiles | Measure-Object -Property SizeMB -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -eq $totalSize) { $totalSize = 0 }

            $item = [PSCustomObject]@{
                Browser           = $browser
                Name              = $browser.Name
                ProfileCount      = $profiles.Count
                ProfileCountLabel = "$($profiles.Count) profiles - $([math]::Round($totalSize, 1)) MB"
                SizeMB            = [math]::Round($totalSize, 2)
                Profiles          = $profiles
            }
            $lstBrowsers.Dispatcher.Invoke([action]{ $lstBrowsers.Items.Add($item) | Out-Null })
        }
        Write-GUI "Found $($browsers.Count) browser(s)" 'OK'
    } catch {
        Write-GUI "Detection failed: $_" 'ERROR'
    }
    Update-ModeUI
}

function Update-ModeUI {
    $isBackup = $radBackup.IsChecked
    $window.Dispatcher.Invoke([action]{
        $btnAction.Content = if ($isBackup) { 'Start Backup' } else { 'Start Restore' }
    })
}

# ---------- Selection Helpers ----------
function Select-All-Browsers {
    $selectAll = $chkSelectAll.IsChecked
    $window.Dispatcher.Invoke([action]{
        if ($selectAll) {
            for ($i = 0; $i -lt $lstBrowsers.Items.Count; $i++) {
                $lstBrowsers.SelectedItems.Add($lstBrowsers.Items[$i]) | Out-Null
            }
        } else {
            $lstBrowsers.SelectedItems.Clear()
        }
    })
}

function Browse-Destination {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select backup destination'
    $dialog.SelectedPath = $txtDestination.Text
    $dialog.ShowNewFolderButton = $true

    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $window.Dispatcher.Invoke([action]{ $txtDestination.Text = $dialog.SelectedPath })
    }
}

# ---------- Action Dispatch ----------
function Invoke-SelectedAction {
    $selected = @()
    $window.Dispatcher.Invoke([action]{ $selected = @($lstBrowsers.SelectedItems) })

    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Please select at least one browser.', 'No Selection', 'OK', 'Warning')
        return
    }

    $destination = $txtDestination.Text
    if (-not $destination -or -not (Test-Path -LiteralPath $destination)) {
        [System.Windows.MessageBox]::Show('Please select a valid destination folder.', 'Invalid Destination', 'OK', 'Warning')
        return
    }

    $isBackup = $radBackup.IsChecked
    Set-Running $true
    $script:cancelRequested = $false
    Set-Progress 0 ''
    Set-Status 'Processing...' 'PrimaryColor'

    $action = if ($isBackup) { 'Backup' } else { 'Restore' }
    Write-GUI "Starting $action of $($selected.Count) browser(s)..."

    # Runspace setup
    $script:runspace = [runspacefactory]::CreateRunspace()
    $script:runspace.ApartmentState = 'STA'
    $script:runspace.ThreadOptions = 'ReuseThread'
    $script:runspace.Open()

    # Share variables
    $script:runspace.SessionStateProxy.SetVariable('selected', $selected)
    $script:runspace.SessionStateProxy.SetVariable('destination', $destination)
    $script:runspace.SessionStateProxy.SetVariable('isBackup', $isBackup)
    $script:runspace.SessionStateProxy.SetVariable('config', $script:config)
    $script:runspace.SessionStateProxy.SetVariable('logFile', $script:logFile)
    $script:runspace.SessionStateProxy.SetVariable('cancelRef', [ref]$script:cancelRequested)
    $script:runspace.SessionStateProxy.SetVariable('ModuleRoot', $script:ModuleRoot)

    $script:psInstance = [powershell]::Create()
    $script:psInstance.Runspace = $script:runspace

    [void]$script:psInstance.AddScript({
        # Import modules inside the runspace
        Import-Module (Join-Path $using:ModuleRoot 'Modules\Config.psm1')          -Force -DisableNameChecking
        Import-Module (Join-Path $using:ModuleRoot 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $using:ModuleRoot 'Modules\Logging.psm1')          -Force -DisableNameChecking
        Import-Module (Join-Path $using:ModuleRoot 'Modules\BackupEngine.psm1')     -Force -DisableNameChecking
        Import-Module (Join-Path $using:ModuleRoot 'Modules\RestoreEngine.psm1')    -Force -DisableNameChecking

        $totalOps = 0
        foreach ($item in $selected) { $totalOps += $item.Profiles.Count }
        $completed = 0
        $errors = 0
        $results = @()

        foreach ($item in $selected) {
            if ($cancelRef.Value) { break }
            $browser = $item.Browser
            $profiles = $item.Profiles

            foreach ($profile in $profiles) {
                if ($cancelRef.Value) { break }
                $completed++

                try {
                    if ($isBackup) {
                        $result = New-BrowserBackup -Browser $browser -ProfileName $profile.Name `
                            -Destination $destination -ExcludeDirs $config.defaults.excludeFromBackup `
                            -Force -LogFile $logFile `
                            -RobocopyRetries $config.defaults.robocopyRetries `
                            -RobocopyWait $config.defaults.robocopyWait `
                            -CriticalFiles $config.defaults.checksumCriticalFiles
                        if (-not $result.Success) { $errors++ }
                        $results += $result
                    } else {
                        # Restore: need a backup source folder from user — not implemented in multi-select yet.
                        # For now, skip with warning.
                        Write-Log -Message "Restore not yet supported in multi-select GUI mode" -Level 'WARN' -LogFile $logFile
                        $errors++
                    }
                } catch {
                    $errors++
                    Write-Log -Message "Operation error: $_" -Level 'ERROR' -LogFile $logFile
                }
            }
        }

        return @{ Completed = $completed; Errors = $errors; Total = $totalOps; Results = $results }
    })

    $handle = $script:psInstance.BeginInvoke()

    # UI polling timer
    $script:dispatcherTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:dispatcherTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:dispatcherTimer.Add_Tick({
        if ($handle.IsCompleted) {
            $script:dispatcherTimer.Stop()
            try {
                $result = $script:psInstance.EndInvoke($handle)
            } catch {
                $result = @{ Errors = 1; Completed = 0; Total = 0 }
                Write-GUI "Background job failed: $_" 'ERROR'
            } finally {
                if ($script:psInstance) { $script:psInstance.Dispose(); $script:psInstance = $null }
                if ($script:runspace) { $script:runspace.Close(); $script:runspace = $null }
            }

            Set-Running $false
            Set-Progress 100 'Complete'

            if ($script:cancelRequested) {
                Set-Status 'Cancelled' 'WarningColor'
                Write-GUI 'Operation cancelled by user' 'WARN'
            } elseif ($result.Errors -gt 0) {
                Set-Status "Completed with $($result.Errors) error(s)" 'WarningColor'
                Write-GUI "Completed with $($result.Errors) error(s)" 'WARN'
            } else {
                Set-Status "All operations completed successfully" 'SecondaryColor'
                Write-GUI "All $($result.Completed) operation(s) completed successfully" 'OK'
            }
        } else {
            $window.Dispatcher.Invoke([action]{ $txtProgress.Text = 'Working...' })
        }
    })
    $script:dispatcherTimer.Start()
}

# ---------- Event Handlers ----------
$btnAction.Add_Click({ Invoke-SelectedAction })
$btnCancel.Add_Click({ 
    if ($script:jobRunning) { 
        $script:cancelRequested = $true
        Write-GUI 'Cancelling...' 'WARN'
    }
})
$btnRefresh.Add_Click({ Refresh-BrowserList })
$btnBrowse.Add_Click({ Browse-Destination })
$chkSelectAll.Add_Click({ Select-All-Browsers })
$radBackup.Add_Click({ Update-ModeUI })
$radRestore.Add_Click({ Update-ModeUI })

# Initial load
Refresh-BrowserList

# Cleanup on window close
$window.Add_Closed({
    if ($script:dispatcherTimer) { $script:dispatcherTimer.Stop() }
    if ($script:psInstance) { try { $script:psInstance.Dispose() } catch { } }
    if ($script:runspace) { try { $script:runspace.Close() } catch { } }
})

$window.ShowDialog() | Out-Null