<#
.SYNOPSIS
    Universal Browser Backup Tool - Backup and restore browser profiles easily.
.DESCRIPTION
    A GUI utility to backup and restore browser profiles on Windows.
    Supports Chrome, Edge, Firefox, Brave, Opera, Vivaldi, and Thorium.
.VERSION
    1.0.0
.AUTHOR
    theyonecodes
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:SelectedBrowser = $null
$script:ProfileMap = @{}

# ==================== BROWSER CONFIGURATION ====================
$BrowserDefs = @(
    @{Name="Thorium";       Path="$env:LOCALAPPDATA\Thorium\User Data";         Exe="$env:LOCALAPPDATA\Thorium\Application\thorium.exe";       R=58;   G=66;  B=77;  Proc="thorium"}
    @{Name="Google Chrome"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data"; Exe="${env:ProgramFiles}\Google\Chrome\Application\chrome.exe";  R=234;  G=67;  B=53;  Proc="chrome"}
    @{Name="Microsoft Edge"; Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data";  Exe="${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"; R=0;    G=120; B=212; Proc="msedge"}
    @{Name="Brave";         Path="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Exe="${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"; R=255; G=103; B=6; Proc="brave"}
    @{Name="Mozilla Firefox";Path="$env:APPDATA\Mozilla\Firefox\Profiles";       Exe="${env:ProgramFiles}\Mozilla Firefox\firefox.exe";       R=255;  G=121; B=0;   Proc="firefox"}
    @{Name="Opera";         Path="$env:APPDATA\Opera Software\Opera Stable";    Exe="${env:ProgramFiles}\Opera\launcher.exe";              R=255;  G=59;  B=48;  Proc="opera"}
    @{Name="Vivaldi";       Path="$env:LOCALAPPDATA\Vivaldi\User Data";         Exe="${env:ProgramFiles}\Vivaldi\Application\vivaldi.exe";   R=165;  G=25;  B=130; Proc="vivaldi"}
)

# ==================== ICON DRAWING ====================
function Draw-BrowserIcon {
    param($Def, [int]$Size=48)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::FromArgb($Def.R, $Def.G, $Def.B))
    $fs = [int]($Size * 0.45)
    if ($fs -lt 8) { $fs = 8 }
    $f = New-Object System.Drawing.Font("Segoe UI", $fs, [System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::White
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
    $g.DrawString($Def.Name[0], $f, $brush, $rect, $sf)
    $g.Dispose()
    $f.Dispose()
    return $bmp
}

# ==================== UTILITY FUNCTIONS ====================
function Show-Msg {
    param([string]$Msg, [string]$Type="Info")
    $iconMap = @{Error=16; Warning=48; Info=64}
    [System.Windows.Forms.MessageBox]::Show($Msg, "Browser Backup Tool", "OK", $iconMap[$Type])
}

function Get-FolderSizeMB {
    param([string]$Path)
    try {
        $bytes = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return [math]::Round($bytes / 1MB, 1)
    } catch { return 0 }
}

# ==================== BROWSER DETECTION ====================
function Get-InstalledBrowsers {
    $found = @()
    foreach ($b in $BrowserDefs) {
        if (Test-Path $b.Path) {
            $profiles = Get-ChildItem $b.Path -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -eq "Default" -or $_.Name -match "^Profile\s*\d+$" -or $_.Name -match "^\d+$" -or $_.Name -match "\.default"
            }
            if ($profiles) {
                $ver = "Unknown"
                try { if (Test-Path $b.Exe) { $ver = (Get-Item $b.Exe).VersionInfo.ProductVersion } } catch {}
                $found += @{
                    Name = $b.Name
                    Path = $b.Path
                    Exe = $b.Exe
                    R = $b.R; G = $b.G; B = $b.B
                    Proc = $b.Proc
                    Count = $profiles.Count
                    Version = $ver
                }
            }
        }
    }
    return $found
}

function Get-ProfileList {
    param($Browser)
    $list = @()
    try {
        Get-ChildItem $Browser.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.Name
            $valid = $n -eq "Default" -or $n -match "^Profile\s*\d+$" -or $n -match "^\d+$" -or $n -match "\.default"
            if ($valid) {
                $list += @{Name=$n; Size=(Get-FolderSizeMB $_.FullName)}
            }
        }
    } catch {}
    return $list
}

# ==================== BACKUP OPERATION ====================
function Backup-Profile {
    param($Browser, $Profile, $DestPath)
    
    $proc = Get-Process -Name $Browser.Proc -ErrorAction SilentlyContinue
    if ($proc) {
        Show-Msg "$($Browser.Name) is running. Please close it first." "Warning"
        return $false
    }
    
    try {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $safeName = $Browser.Name -replace " ", ""
        $dest = Join-Path $DestPath "${safeName}_Backup_$ts"
        New-Item -Path $dest -ItemType Directory -Force | Out-Null
        
        $profiles = if ($Profile -eq "All") { (Get-ProfileList $Browser) | Select-Object -ExpandProperty Name } else { @($Profile) }
        
        foreach ($p in $profiles) {
            $src = Join-Path $Browser.Path $p
            if (Test-Path $src) {
                $log = Join-Path $dest "robocopy_$p.log"
                robocopy $src $dest /MIR /NP /R:3 /W:2 /LOG:$log 2>&1 | Out-Null
            }
        }
        
        $manifest = @{
            version = "1.0.0"
            browser = $Browser.Name
            browserVersion = $Browser.Version
            profile = $Profile
            profiles = $profiles
            backupTime = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 3
        Set-Content -Path (Join-Path $dest "manifest.json") -Value $manifest -Encoding UTF8
        
        $size = Get-FolderSizeMB $dest
        Show-Msg "Backup Complete!`n`nBrowser: $($Browser.Name)`nProfiles: $($profiles -join ', ')`nSize: $size MB`n`nSaved to:`n$dest" "Info"
        return $true
    } catch {
        Show-Msg "Backup failed: $_" "Error"
        return $false
    }
}

# ==================== RESTORE OPERATION ====================
function Restore-Profile {
    param($Browser, $SrcPath, $Profile, $LaunchAfter)
    
    $manifestPath = Join-Path $SrcPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Show-Msg "Invalid backup folder.`n`nmanifest.json not found." "Error"
        return $false
    }
    
    $proc = Get-Process -Name $Browser.Proc -ErrorAction SilentlyContinue
    if ($proc) {
        Show-Msg "$($Browser.Name) is running. Please close it first." "Warning"
        return $false
    }
    
    try {
        $src = Join-Path $SrcPath $Profile
        if (-not (Test-Path $src)) {
            Show-Msg "Profile '$Profile' not found in backup." "Error"
            return $false
        }
        
        $dst = Join-Path $Browser.Path $Profile
        if (Test-Path $dst) {
            Move-Item -Path $dst -Destination "$dst.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force
        }
        if (-not (Test-Path $dst)) {
            New-Item -Path $dst -ItemType Directory -Force | Out-Null
        }
        
        robocopy $src $dst /MIR /PURGE /R:3 /W:2 2>&1 | Out-Null
        
        if ($LaunchAfter -and (Test-Path $Browser.Exe)) {
            Start-Sleep -Milliseconds 500
            Start-Process $Browser.Exe
        }
        
        Show-Msg "Restore Complete!`n`nBrowser: $($Browser.Name)`nProfile: $Profile`n`nYour profile has been restored." "Info"
        return $true
    } catch {
        Show-Msg "Restore failed: $_" "Error"
        return $false
    }
}

# ==================== BUILD MAIN FORM ====================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Universal Browser Backup Tool"
$form.Size = New-Object System.Drawing.Size(900, 750)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 242, 245)

# --- TOP HEADER ---
$hdr = New-Object System.Windows.Forms.Panel
$hdr.Size = New-Object System.Drawing.Size(900, 90)
$hdr.Dock = 'Top'
$hdr.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)

$hdrIcon = Draw-BrowserIcon @{Name="B"; R=0; G=120; B=212} 50
$hdrPic = New-Object System.Windows.Forms.PictureBox
$hdrPic.Image = $hdrIcon
$hdrPic.SizeMode = 'StretchImage'
$hdrPic.Size = New-Object System.Drawing.Size(50, 50)
$hdrPic.Location = New-Object System.Drawing.Point(20, 20)
$hdr.Controls.Add($hdrPic)

$hdrTitle = New-Object System.Windows.Forms.Label
$hdrTitle.Text = "Universal Browser Backup Tool"
$hdrTitle.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$hdrTitle.ForeColor = 'White'
$hdrTitle.Location = New-Object System.Drawing.Point(85, 18)
$hdr.Controls.Add($hdrTitle)

$hdrSub = New-Object System.Windows.Forms.Label
$hdrSub.Text = "Backup and restore browser profiles in one click"
$hdrSub.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$hdrSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 255)
$hdrSub.Location = New-Object System.Drawing.Point(87, 55)
$form.Controls.Add($hdr)
$hdr.Controls.Add($hdrSub)

# --- SECTION 1: BROWSER SELECTION ---
$sec1Lbl = New-Object System.Windows.Forms.Label
$sec1Lbl.Text = "1. Select Browser"
$sec1Lbl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$sec1Lbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$sec1Lbl.Location = New-Object System.Drawing.Point(20, 105)
$form.Controls.Add($sec1Lbl)

$browserPanel = New-Object System.Windows.Forms.Panel
$browserPanel.Location = New-Object System.Drawing.Point(20, 135)
$browserPanel.Size = New-Object System.Drawing.Size(860, 160)
$browserPanel.BackColor = 'White'
$browserPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($browserPanel)

$script:BrowserCards = @()
$CardW = 110; $CardH = 80; $CardGap = 10; $PerRow = 7

function New-BrowserCard {
    param($Browser, [int]$Idx)
    $row = [Math]::Floor($Idx / $PerRow)
    $col = $Idx % $PerRow
    $x = 15 + ($col * ($CardW + $CardGap))
    $y = 15 + ($row * ($CardH + $CardGap))
    
    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size($CardW, $CardH)
    $card.Location = New-Object System.Drawing.Point($x, $y)
    $card.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $card.BorderStyle = 'FixedSingle'
    $card.Cursor = 'Hand'
    $card.Tag = $Browser
    $card.Name = "Card_$($Browser.Name)"
    
    $icon = Draw-BrowserIcon $Browser 44
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Image = $icon
    $pic.SizeMode = 'StretchImage'
    $pic.Size = New-Object System.Drawing.Size(44, 44)
    $pic.Location = New-Object System.Drawing.Point(33, 6)
    $card.Controls.Add($pic)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Browser.Name
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.AutoSize = $false
    $lbl.Size = New-Object System.Drawing.Size(106, 14)
    $lbl.Location = New-Object System.Drawing.Point(2, 54)
    $card.Controls.Add($lbl)
    
    $badge = New-Object System.Windows.Forms.Label
    $badge.Text = "$($Browser.Count) profile(s)"
    $badge.Font = New-Object System.Drawing.Font("Segoe UI", 7)
    $badge.ForeColor = 'Gray'
    $badge.TextAlign = 'MiddleCenter'
    $badge.AutoSize = $false
    $badge.Size = New-Object System.Drawing.Size(106, 12)
    $badge.Location = New-Object System.Drawing.Point(2, 68)
    $card.Controls.Add($badge)
    
    $card.Add_MouseEnter({ param($s) $s.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 255) })
    $card.Add_MouseLeave({ param($s) $s.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250) })
    $card.Add_Click({ param($s, $e) Select-Card $s.Tag })
    
    $browserPanel.Controls.Add($card)
    return $card
}

function Select-Card {
    param($Browser)
    foreach ($c in $script:BrowserCards) {
        $c.BorderStyle = 'FixedSingle'
        $c.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    }
    $sel = $browserPanel.Controls | Where-Object { $_.Name -eq "Card_$($Browser.Name)" }
    if ($sel) {
        $sel.BorderStyle = 'Fixed3D'
        $sel.BackColor = [System.Drawing.Color]::FromArgb(220, 235, 255)
    }
    $script:SelectedBrowser = $Browser
    
    $infoLbl.Text = "$($Browser.Name) v$($Browser.Version)"
    $infoLbl.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0)
    
    $script:ProfileMap = @{}
    $profileBox.Items.Clear()
    $profiles = Get-ProfileList $Browser
    foreach ($p in $profiles) {
        $display = "$($p.Name) ($($p.Size) MB)"
        $profileBox.Items.Add($display)
        $script:ProfileMap[$display] = $p.Name
    }
    if ($profileBox.Items.Count -gt 0) { $profileBox.SelectedIndex = 0 }
    $profileBox.Items.Add("All Profiles")
    
    $detailsPnl.Visible = $true
    $startBtn.Enabled = $true
}

# --- SECTION 2: OPERATION CONFIG ---
$sec2Lbl = New-Object System.Windows.Forms.Label
$sec2Lbl.Text = "2. Configure Operation"
$sec2Lbl.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$sec2Lbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$sec2Lbl.Location = New-Object System.Drawing.Point(20, 310)
$form.Controls.Add($sec2Lbl)

$opPnl = New-Object System.Windows.Forms.Panel
$opPnl.Location = New-Object System.Drawing.Point(20, 340)
$opPnl.Size = New-Object System.Drawing.Size(860, 220)
$opPnl.BackColor = 'White'
$opPnl.BorderStyle = 'FixedSingle'
$form.Controls.Add($opPnl)

# Mode Radio Buttons
$modeLbl = New-Object System.Windows.Forms.Label
$modeLbl.Text = "Mode:"
$modeLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$modeLbl.Location = New-Object System.Drawing.Point(20, 18)
$opPnl.Controls.Add($modeLbl)

$script:BackupRadio = New-Object System.Windows.Forms.RadioButton
$script:BackupRadio.Text = "Backup"
$script:BackupRadio.Location = New-Object System.Drawing.Drawing.Point(75, 16)
$script:BackupRadio.Checked = $true
$script:BackupRadio.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:BackupRadio.Add_CheckedChanged({ Update-Mode-UI })
$opPnl.Controls.Add($script:BackupRadio)

$script:RestoreRadio = New-Object System.Windows.Forms.RadioButton
$script:RestoreRadio.Text = "Restore"
$script:RestoreRadio.Location = New-Object System.Drawing.Drawing.Point(150, 16)
$script:RestoreRadio.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$script:RestoreRadio.Add_CheckedChanged({ Update-Mode-UI })
$opPnl.Controls.Add($script:RestoreRadio)

function Update-Mode-UI {
    $script:ProfileMap = @{}
    $profileBox.Items.Clear()
    if ($script:SelectedBrowser) {
        $profiles = Get-ProfileList $script:SelectedBrowser
        foreach ($p in $profiles) {
            $display = "$($p.Name) ($($p.Size) MB)"
            $profileBox.Items.Add($display)
            $script:ProfileMap[$display] = $p.Name
        }
        if ($profileBox.Items.Count -gt 0) { $profileBox.SelectedIndex = 0 }
        if ($script:BackupRadio.Checked) { $profileBox.Items.Add("All Profiles") }
    }
    $folderLbl.Text = if ($script:RestoreRadio.Checked) { "Backup Folder:" } else { "Save Location:" }
    $launchChk.Visible = $script:RestoreRadio.Checked
    $startBtn.Text = if ($script:BackupRadio.Checked) { "START BACKUP" } else { "START RESTORE" }
}

# Profile Dropdown
$profLbl = New-Object System.Windows.Forms.Label
$profLbl.Text = "Profile:"
$profLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$profLbl.Location = New-Object System.Drawing.Point(20, 55)
$opPnl.Controls.Add($profLbl)

$profileBox = New-Object System.Windows.Forms.ComboBox
$profileBox.DropDownStyle = 'DropDownList'
$profileBox.Location = New-Object System.Drawing.Drawing.Point(90, 52)
$profileBox.Size = New-Object System.Drawing.Size(280, 25)
$opPnl.Controls.Add($profileBox)

# Browser Info
$infoLbl = New-Object System.Windows.Forms.Label
$infoLbl.Text = "Select a browser above"
$infoLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$infoLbl.ForeColor = 'Gray'
$infoLbl.Location = New-Object System.Drawing.Drawing.Point(390, 55)
$opPnl.Controls.Add($infoLbl)

# Folder Path
$folderLbl = New-Object System.Windows.Forms.Label
$folderLbl.Text = "Save Location:"
$folderLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$folderLbl.Location = New-Object System.Drawing.Point(20, 95)
$opPnl.Controls.Add($folderLbl)

$folderTxt = New-Object System.Windows.Forms.TextBox
$folderTxt.Location = New-Object System.Drawing.Drawing.Point(130, 92)
$folderTxt.Size = New-Object System.Drawing.Size(580, 25)
$folderTxt.Text = [Environment]::GetFolderPath("Desktop")
$opPnl.Controls.Add($folderTxt)

$folderBtn = New-Object System.Windows.Forms.Button
$folderBtn.Text = "Browse..."
$folderBtn.Location = New-Object System.Drawing.Drawing.Point(720, 90)
$folderBtn.Size = New-Object System.Drawing.Size(100, 28)
$folderBtn.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$folderBtn.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Select folder"
    $d.SelectedPath = $folderTxt.Text
    if ($d.ShowDialog() -eq "OK") { $folderTxt.Text = $d.SelectedPath }
})
$opPnl.Controls.Add($folderBtn)

# Launch After Restore
$launchChk = New-Object System.Windows.Forms.CheckBox
$launchChk.Text = "Launch browser after restore"
$launchChk.Location = New-Object System.Drawing.Drawing.Point(130, 130)
$launchChk.Visible = $false
$launchChk.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$opPnl.Controls.Add($launchChk)

# Info Panel
$detailsPnl = New-Object System.Windows.Forms.Panel
$detailsPnl.Location = New-Object System.Drawing.Drawing.Point(20, 165)
$detailsPnl.Size = New-Object System.Drawing.Size(800, 40)
$detailsPnl.BackColor = [System.Drawing.Color]::FromArgb(240, 248, 255)
$detailsPnl.BorderStyle = 'FixedSingle'
$detailsPnl.Visible = $false
$opPnl.Controls.Add($detailsPnl)

$infoIcon = New-Object System.Windows.Forms.PictureBox
$infoIcon.Image = [System.Drawing.SystemIcons]::Information
$infoIcon.SizeMode = 'Normal'
$infoIcon.Size = New-Object System.Drawing.Size(20, 20)
$infoIcon.Location = New-Object System.Drawing.Drawing.Point(10, 10)
$detailsPnl.Controls.Add($infoIcon)

$infoTxt = New-Object System.Windows.Forms.Label
$infoTxt.Text = "Browser will be closed automatically if running during backup/restore."
$infoTxt.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$infoTxt.Location = New-Object System.Drawing.Drawing.Point(35, 10)
$detailsPnl.Controls.Add($infoTxt)

# --- START BUTTON ---
$startBtn = New-Object System.Windows.Forms.Button
$startBtn.Text = "START BACKUP"
$startBtn.Size = New-Object System.Drawing.Size(220, 50)
$startBtn.Location = New-Object System.Drawing.Drawing.Point(340, 580)
$startBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$startBtn.ForeColor = 'White'
$startBtn.FlatStyle = 'Flat'
$startBtn.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$startBtn.Enabled = $false
$startBtn.Add_Click({
    if (-not $script:SelectedBrowser) { Show-Msg "Select a browser first." "Warning"; return }
    if ([string]::IsNullOrWhiteSpace($folderTxt.Text)) { Show-Msg "Select a folder." "Warning"; return }
    if (-not $profileBox.SelectedItem) { Show-Msg "Select a profile." "Warning"; return }
    
    $profDisplay = $profileBox.SelectedItem.ToString()
    $prof = if ($profDisplay -eq "All Profiles") { "All" } else { $script:ProfileMap[$profDisplay] }
    
    $startBtn.Text = "WORKING..."
    $startBtn.Enabled = $false
    $form.Refresh()
    
    try {
        if (-not (Test-Path $folderTxt.Text)) {
            New-Item -Path $folderTxt.Text -ItemType Directory -Force | Out-Null
        }
        if ($script:BackupRadio.Checked) {
            Backup-Profile $script:SelectedBrowser $prof $folderTxt.Text
        } else {
            Restore-Profile $script:SelectedBrowser $folderTxt.Text $prof $launchChk.Checked
        }
    } catch {
        Show-Msg "Error: $_" "Error"
    }
    
    $startBtn.Text = if ($script:BackupRadio.Checked) { "START BACKUP" } else { "START RESTORE" }
    $startBtn.Enabled = $true
})
$form.Controls.Add($startBtn)

# --- STATUS BAR ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLbl = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLbl.Text = "Ready"
$statusStrip.Items.Add($statusLbl)
$form.Controls.Add($statusStrip)

# --- FOOTER ---
$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Universal Browser Backup Tool v1.0.0 | by theyonecodes"
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$footer.ForeColor = 'Gray'
$footer.Location = New-Object System.Drawing.Drawing.Point(640, 645)
$form.Controls.Add($footer)

# --- INIT: DETECT BROWSERS ---
$installed = Get-InstalledBrowsers

if ($installed.Count -eq 0) {
    $noBrowserLbl = New-Object System.Windows.Forms.Label
    $noBrowserLbl.Text = "No supported browsers found!`n`nPlease install: Chrome, Edge, Firefox, Brave, Opera, Vivaldi, or Thorium"
    $noBrowserLbl.TextAlign = 'MiddleCenter'
    $noBrowserLbl.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $noBrowserLbl.Location = New-Object System.Drawing.Drawing.Point(150, 50)
    $noBrowserLbl.Size = New-Object System.Drawing.Size(550, 80)
    $noBrowserLbl.ForeColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
    $browserPanel.Controls.Add($noBrowserLbl)
    $statusLbl.Text = "No browsers detected"
} else {
    $i = 0
    foreach ($b in $installed) {
        $card = New-BrowserCard $b $i
        $script:BrowserCards += $card
        $i++
    }
    $statusLbl.Text = "Detected $($installed.Count) browser(s)"
}

# --- RUN ---
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
