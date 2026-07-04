# GUI/App.ps1 — WPF PowerShell GUI for Universal Browser Backup v2.1.1
# This is the GUI entry point called by UniversalBrowserBackup.ps1

<# 
.SYNOPSIS
    WPF-based GUI for Universal Browser Backup
.DESCRIPTION
    Provides a graphical interface for backup, restore, and browser management
    using the new 46-browser detection schema (v2.1.1).
.PARAMETER Config
    Hashtable configuration from Config.psm1
.PARAMETER LogFile
    Path to the log file for this session
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [hashtable]$Config,
    [Parameter(Mandatory)] [string]$LogFile
)

# Add required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# Import modules
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptRoot

Import-Module (Join-Path $rootDir 'Modules\Config.psm1')          -Force -DisableNameChecking
Import-Module (Join-Path $rootDir 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $rootDir 'Modules\Logging.psm1')          -Force -DisableNameChecking
Import-Module (Join-Path $rootDir 'Modules\BackupEngine.psm1')     -Force -DisableNameChecking
Import-Module (Join-Path $rootDir 'Modules\RestoreEngine.psm1')    -Force -DisableNameChecking

# Global state
$script:browsers = @()
$script:selectedBrowser = $null
$script:selectedProfile = $null

# Initialize logging
Write-Log -Message "Starting GUI" -Level "INFO" -LogFile $LogFile

# ---------------------------------------------------------------------------
# XAML DEFINITION
# ---------------------------------------------------------------------------
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Universal Browser Backup v2.1.1"
    Height="720" Width="1000"
    WindowStartupLocation="CenterScreen"
    Background="#FF1E1E2E"
    Foreground="#FFCDD6F4"
    FontFamily="Segoe UI"
    FontSize="13"
>

    <Window.Resources>
        <ResourceDictionary>
            <Style x:Key="DarkButton" TargetType="Button">
                <Setter Property="Background" Value="#FF313244"/>
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
                <Setter Property="BorderBrush" Value="#FF45475A"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Padding" Value="12,6"/>
                <Setter Property="Margin" Value="4"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="border" Background="{TemplateBinding Background}" 
                                    BorderBrush="{TemplateBinding BorderBrush}" 
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>

            <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource DarkButton}">
                <Setter Property="Background" Value="#FF89B4FA"/>
                <Setter Property="Foreground" Value="#FF1E1E2E"/>
                <Setter Property="BorderBrush" Value="#FF89B4FA"/>
            </Style>

            <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource DarkButton}">
                <Setter Property="Background" Value="#FFF38BA8"/>
                <Setter Property="Foreground" Value="#FF1E1E2E"/>
                <Setter Property="BorderBrush" Value="#FFF38BA8"/>
            </Style>

            <Style TargetType="ListBox">
                <Setter Property="Background" Value="#FF181825"/>
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
                <Setter Property="BorderBrush" Value="#FF313244"/>
                <Setter Property="BorderThickness" Value="1"/>
            </Style>

            <Style TargetType="ListBoxItem">
                <Setter Property="Padding" Value="8,4"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ListBoxItem">
                            <Border Background="Transparent" 
                                    BorderBrush="Transparent" BorderThickness="0"
                                    SnapsToDevicePixels="True">
                                <ContentPresenter/>
                            </Border>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>

            <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
            </Style>

            <Style TargetType="Label">
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
            </Style>

            <Style TargetType="TextBox">
                <Setter Property="Background" Value="#FF181825"/>
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
                <Setter Property="BorderBrush" Value="#FF313244"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Padding" Value="6,4"/>
                <Setter Property="CaretBrush" Value="#FF89B4FA"/>
            </Style>

            <Style TargetType="ProgressBar">
                <Setter Property="Background" Value="#FF181825"/>
                <Setter Property="Foreground" Value="#FF89B4FA"/>
                <Setter Property="BorderBrush" Value="#FF313244"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Height" Value="16"/>
            </Style>

            <Style TargetType="CheckBox">
                <Setter Property="Foreground" Value="#FFCDD6F4"/>
            </Style>

            <Style TargetType="GroupBox">
                <Setter Property="BorderBrush" Value="#FF313244"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Margin" Value="4"/>
                <Setter Property="Padding" Value="8"/>
            </Style>
        </ResourceDictionary>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
            <TextBlock Text="Universal Browser Backup" FontSize="24" FontWeight="Bold" 
                       Foreground="#FF89B4FA" VerticalAlignment="Center"/>
            <TextBlock Text="v2.1.1" FontSize="14" Foreground="#FF6C7086" 
                       VerticalAlignment="Center" Margin="12,0,0,4"/>
            <TextBlock Text=" • " FontSize="14" Foreground="#FF6C7086" VerticalAlignment="Center"/>
            <TextBlock x:Name="StatusText" Text="Ready" FontSize="12" 
                       Foreground="#FFA6E3A1" VerticalAlignment="Center" Margin="8,0,0,4"/>
        </StackPanel>

        <!-- MAIN CONTENT -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="360"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT PANEL: BROWSER LIST -->
            <GroupBox Grid.Column="0" Header="Detected Browsers (46 browsers supported)">
                <DockPanel LastChildFill="True">
                    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
                        <Button x:Name="RefreshBtn" Content="↻ Refresh" Style="{StaticResource DarkButton}" 
                                Width="100"/>
                        <Button x:Name="SelectAllBtn" Content="☑ Select All" Style="{StaticResource DarkButton}" 
                                Width="100" Margin="8,0,0,0"/>
                        <Button x:Name="ClearAllBtn" Content="☐ Clear All" Style="{StaticResource DarkButton}" 
                                Width="100" Margin="8,0,0,0"/>
                    </StackPanel>

                    <ListBox x:Name="BrowserList" DockPanel.Dock="Top" SelectionMode="Multiple">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Border Background="Transparent" Padding="4" Margin="2">
                                    <StackPanel Orientation="Horizontal" Margin="4">
                                        <TextBlock x:Name="BrowserIcon" Text="{Binding Icon}" 
                                                   FontSize="18" Width="28" Height="28" 
                                                   VerticalAlignment="Center" HorizontalAlignment="Center"
                                                   Background="#FF313244" Foreground="#FFCDD6F4"
                                                   FontFamily="Segoe UI Symbol"/>
                                        <StackPanel Orientation="Vertical" Margin="8,0,0,0" VerticalAlignment="Center">
                                            <TextBlock x:Name="BrowserName" Text="{Binding Name}" 
                                                       FontWeight="SemiBold" FontSize="13" Foreground="#FFCDD6F4"/>
                                            <TextBlock x:Name="BrowserDetails" FontSize="11" Foreground="#FF6C7086">
                                                <Run Text="{Binding Type}"/>
                                                <Run Text=" • "/>
                                                <Run Text="{Binding EngineFamily}"/>
                                                <Run Text=" • v"/>
                                                <Run Text="{Binding Version}"/>
                                                <Run Text=" • "/>
                                                <Run Text="{Binding DetectStrategy}"/>
                                            </TextBlock>
                                            <TextBlock x:Name="BrowserPath" Text="{Binding ProfilePath}" 
                                                       FontSize="10" Foreground="#FF6C7086" 
                                                       TextTrimming="CharacterEllipsis" MaxWidth="280"/>
                                            <TextBlock x:Name="BrowserExe" FontSize="10" Foreground="#FF6C7086">
                                                <Run Text="Exe: "/>
                                                <Run Text="{Binding ExePath}"/>
                                            </TextBlock>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </DockPanel>
            </GroupBox>

            <!-- RIGHT PANEL: DETAILS & ACTIONS -->
            <Grid Grid.Column="1" Margin="12,0,0,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel x:Name="DetailsPanel">
                        <GroupBox Header="Browser Details">
                            <StackPanel>
                                <TextBlock x:Name="DetailName" FontSize="16" FontWeight="Bold" 
                                           Foreground="#FF89B4FA" TextWrapping="Wrap"/>
                                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                                    <TextBlock Text="Type: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailType" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Engine: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailEngine" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Detection: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailDetect" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Version: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailVersion" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Process: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailProcess" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Executable: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailExe" FontSize="12" Foreground="#FFCDD6F4" TextWrapping="Wrap" MaxWidth="400"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Profile Root: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailProfileRoot" FontSize="12" Foreground="#FFCDD6F4"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
                                    <TextBlock Text="Profile Path: " FontSize="12" Foreground="#FF6C7086"/>
                                    <TextBlock x:Name="DetailProfilePath" FontSize="12" Foreground="#FFCDD6F4" TextWrapping="Wrap" MaxWidth="400"/>
                                </StackPanel>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Profiles" Margin="0,12,0,0">
                            <StackPanel>
                                <TextBlock x:Name="NoProfileText" Text="Select a browser to view profiles" 
                                           Foreground="#FF6C7086" FontStyle="Italic" Margin="4"/>
                                <ListBox x:Name="ProfileList" Visibility="Collapsed" 
                                         SelectionMode="Multiple" Height="200">
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <Border Background="Transparent" Padding="4" Margin="2">
                                                <StackPanel Orientation="Horizontal" Margin="4">
                                                    <StackPanel Width="160">
                                                        <TextBlock Text="{Binding Name}" FontWeight="SemiBold" 
                                                                   Foreground="#FFCDD6F4" FontSize="12"/>
                                                        <TextBlock Foreground="#FF89B4FA" FontSize="11" Margin="0,1,0,0">
                                                            <TextBlock.Style>
                                                                <Style TargetType="TextBlock">
                                                                    <Setter Property="Text" Value="{Binding DisplayName, Mode=OneWay}"/>
                                                                    <Style.Triggers>
                                                                        <DataTrigger Binding="{Binding DisplayName, Mode=OneWay}" Value="">
                                                                            <Setter Property="Visibility" Value="Collapsed"/>
                                                                        </DataTrigger>
                                                                    </Style.Triggers>
                                                                </Style>
                                                            </TextBlock.Style>
                                                        </TextBlock>
                                                        <TextBlock Foreground="#FFA6E3A1" FontSize="10" Margin="0,1,0,0">
                                                            <TextBlock.Style>
                                                                <Style TargetType="TextBlock">
                                                                    <Setter Property="Text" Value="{Binding Email, Mode=OneWay}"/>
                                                                    <Style.Triggers>
                                                                        <DataTrigger Binding="{Binding Email, Mode=OneWay}" Value="">
                                                                            <Setter Property="Visibility" Value="Collapsed"/>
                                                                        </DataTrigger>
                                                                    </Style.Triggers>
                                                                </Style>
                                                            </TextBlock.Style>
                                                        </TextBlock>
                                                    </StackPanel>
                                                    <TextBlock Text="{Binding SizeMB}" 
                                                               StringFormat="{}{0:F1} MB" 
                                                               Foreground="#FF6C7086" Width="80"
                                                               VerticalAlignment="Center"/>
                                                    <StackPanel VerticalAlignment="Center" Margin="8,0,0,0">
                                                        <TextBlock FontSize="11">
                                                            <TextBlock.Style>
                                                                <Style TargetType="TextBlock">
                                                                    <Setter Property="Foreground" Value="#FFA6E3A1"/>
                                                                    <Style.Triggers>
                                                                        <DataTrigger Binding="{Binding CriticalBacked, Mode=OneWay}" Value="">
                                                                            <Setter Property="Text" Value="Checking..."/>
                                                                        </DataTrigger>
                                                                    </Style.Triggers>
                                                                </Style>
                                                            </TextBlock.Style>
                                                            <Run Text="{Binding CriticalBacked, Mode=OneWay, StringFormat='{}{0}'}"/><Run Text="/"/><Run Text="{Binding CriticalTotal, Mode=OneWay, StringFormat='{}{0}'}"/><Run Text=" critical"/>
                                                        </TextBlock>
                                                        <TextBlock Text="{Binding ExcludedSizeMB, StringFormat='{}-{0:F1} MB cache excluded'}" 
                                                                   Foreground="#FF6C7086" FontSize="10"/>
                                                    </StackPanel>
                                                    <TextBlock Text="{Binding IsDefault}" 
                                                               StringFormat="Default: {0}" 
                                                               Foreground="#FFA6E3A1" FontSize="11"
                                                               VerticalAlignment="Center"/>
                                                </StackPanel>
                                            </Border>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Backup Options" Margin="0,12,0,0">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Label Content="Destination:" Width="100"/>
                                    <TextBox x:Name="DestTextBox" Width="400" 
                                             Text="{Binding Defaults.BackupDestination, Mode=TwoWay}"/>
                                    <Button x:Name="BrowseDestBtn" Content="Browse..." Style="{StaticResource DarkButton}" 
                                            Width="80" Margin="8,0,0,0"/>
                                </StackPanel>
                                <CheckBox x:Name="ExcludeCacheCheck" Content="Exclude cache/temp directories" 
                                          IsChecked="True" Margin="0,4,0,0"/>
                                <CheckBox x:Name="ForceCheck" Content="Force close running browsers" 
                                          IsChecked="False" Margin="0,4,0,0"/>
                                <CheckBox x:Name="AllProfilesCheck" Content="Backup all profiles (not just selected)" 
                                          IsChecked="False" Margin="0,4,0,0"/>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>

                <!-- ACTION BUTTONS -->
                <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
                    <Button x:Name="BackupBtn" Content="⬇ Backup Selected" Style="{StaticResource AccentButton}" 
                            Width="150" IsEnabled="False"/>
                    <Button x:Name="RestoreBtn" Content="⬆ Restore" Style="{StaticResource DarkButton}" 
                            Width="100" Margin="8,0,0,0" IsEnabled="False"/>
                    <Button x:Name="ListBtn" Content="📋 List All" Style="{StaticResource DarkButton}" 
                            Width="100" Margin="8,0,0,0"/>
                </StackPanel>
            </Grid>
        </Grid>

        <!-- STATUS BAR -->
        <StatusBar Grid.Row="2" Background="#FF181825" BorderBrush="#FF313244" BorderThickness="0,1,0,0" Margin="-12,0,-12,-12">
            <StatusBarItem>
                <TextBlock x:Name="StatusBarText" Text="Ready" FontSize="11" Foreground="#FFA6E3A1"/>
            </StatusBarItem>
            <Separator Style="{StaticResource {x:Static ToolBar.SeparatorStyleKey}}" 
                       Background="#FF313244" Width="1" Margin="8,0"/>
            <StatusBarItem>
                <ProgressBar x:Name="ProgressBar" Width="200" Height="16" Visibility="Collapsed" 
                             Minimum="0" Maximum="100" Value="0"/>
            </StatusBarItem>
            <StatusBarItem>
                <TextBlock x:Name="ProgressText" FontSize="11" Foreground="#FFCDD6F4" Visibility="Collapsed"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
'@

# ---------------------------------------------------------------------------
# PARSE XAML & CONNECT EVENTS
# ---------------------------------------------------------------------------
$reader = [System.Xml.XmlNodeReader] ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Set icon from file if available (not embedded)
$icoPath = Join-Path $scriptRoot "..\UniversalBrowserBackup.ico"
if (-not (Test-Path $icoPath)) { $icoPath = Join-Path $scriptRoot "..\icon.ico" }
if (Test-Path $icoPath) {
    try { $window.Icon = [System.Windows.Media.Imaging.BitmapImage]::new([Uri]::new($icoPath)) } catch {}
}

# Find controls
$BrowserList = $window.FindName("BrowserList")
$ProfileList = $window.FindName("ProfileList")
$NoProfileText = $window.FindName("NoProfileText")
$DetailName = $window.FindName("DetailName")
$DetailType = $window.FindName("DetailType")
$DetailEngine = $window.FindName("DetailEngine")
$DetailDetect = $window.FindName("DetailDetect")
$DetailVersion = $window.FindName("DetailVersion")
$DetailProcess = $window.FindName("DetailProcess")
$DetailExe = $window.FindName("DetailExe")
$DetailProfileRoot = $window.FindName("DetailProfileRoot")
$DetailProfilePath = $window.FindName("DetailProfilePath")
$RefreshBtn = $window.FindName("RefreshBtn")
$SelectAllBtn = $window.FindName("SelectAllBtn")
$ClearAllBtn = $window.FindName("ClearAllBtn")
$BackupBtn = $window.FindName("BackupBtn")
$RestoreBtn = $window.FindName("RestoreBtn")
$ListBtn = $window.FindName("ListBtn")
$BrowseDestBtn = $window.FindName("BrowseDestBtn")
$DestTextBox = $window.FindName("DestTextBox")
$ExcludeCacheCheck = $window.FindName("ExcludeCacheCheck")
$ForceCheck = $window.FindName("ForceCheck")
$AllProfilesCheck = $window.FindName("AllProfilesCheck")
$ProgressBar = $window.FindName("ProgressBar")
$ProgressText = $window.FindName("ProgressText")
$StatusBarText = $window.FindName("StatusBarText")
$StatusText = $window.FindName("StatusText")

# Set default destination
$DestTextBox.Text = Get-BackupDestination -CustomDestination "" -Config $Config

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------
function Update-StatusBar($message, $color = "#FFA6E3A1") {
    $StatusBarText.Text = $message
    $StatusBarText.Foreground = [System.Windows.Media.Brushes]::new() | Out-Null
    $StatusBarText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromString($color))
    $StatusText.Text = $message
    $StatusText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromString($color))
}

function Set-Progress($value, $text, $visible = $true) {
    $ProgressBar.Dispatcher.Invoke([action]{
        $ProgressBar.Value = $value
        $ProgressBar.Visibility = if ($visible) { 'Visible' } else { 'Collapsed' }
        $ProgressText.Text = $text
        $ProgressText.Visibility = if ($visible) { 'Visible' } else { 'Collapsed' }
    })
}

function Update-BrowserDetails($browser) {
    if (-not $browser) {
        $DetailName.Text = "Select a browser..."
        $DetailType.Text = ""
        $DetailEngine.Text = ""
        $DetailDetect.Text = ""
        $DetailVersion.Text = ""
        $DetailProcess.Text = ""
        $DetailExe.Text = ""
        $DetailProfileRoot.Text = ""
        $DetailProfilePath.Text = ""
        $NoProfileText.Visibility = 'Visible'
        $ProfileList.Visibility = 'Collapsed'
        $BackupBtn.IsEnabled = $false
        $RestoreBtn.IsEnabled = $false
        return
    }

    $DetailName.Text = $browser.Name
    $DetailType.Text = $browser.Type
    $DetailEngine.Text = $browser.EngineFamily
    $DetailDetect.Text = $browser.DetectStrategy
    $DetailVersion.Text = $browser.Version
    $DetailProcess.Text = $browser.ProcessName
    $DetailExe.Text = if ($browser.ExePath) { $browser.ExePath } else { "Not found" }
    $DetailProfileRoot.Text = if ($browser.ProfileRoot) { $browser.ProfileRoot } else { "N/A" }
    $DetailProfilePath.Text = $browser.ProfilePath

    $NoProfileText.Visibility = 'Collapsed'
    $ProfileList.Visibility = 'Visible'
    $BackupBtn.IsEnabled = $true
    $RestoreBtn.IsEnabled = $true

    # Load profiles
    $profiles = @(Get-BrowserProfiles -Browser $browser)
    $ProfileList.ItemsSource = $profiles
}

function Refresh-BrowserList {
    Update-StatusBar "Scanning for browsers..." "#FF89B4FA"
    $script:browsers = @(Get-InstalledBrowsers -Config $Config)
    
    # Bind to ListBox
    $BrowserList.ItemsSource = $script:browsers
    
    if ($script:browsers.Count -eq 0) {
        Update-StatusBar "No browsers found" "#FFF38BA8"
    } else {
        Update-StatusBar ("Found {0} browser(s)" -f $script:browsers.Count) "#FFA6E3A1"
    }
}

# ---------------------------------------------------------------------------
# EVENT HANDLERS
# ---------------------------------------------------------------------------

# Refresh button
$RefreshBtn.Add_Click({
    Refresh-BrowserList
    Update-BrowserDetails $null
})

# Select All
$SelectAllBtn.Add_Click({
    $BrowserList.SelectAll()
})

# Clear All
$ClearAllBtn.Add_Click({
    $BrowserList.UnselectAll()
    Update-BrowserDetails $null
})

# Browser selection changed
$BrowserList.Add_SelectionChanged({
    $selected = $BrowserList.SelectedItems
    if ($selected.Count -eq 1) {
        Update-BrowserDetails $selected[0]
        $script:selectedBrowser = $selected[0]
    } elseif ($selected.Count -gt 1) {
        $DetailName.Text = "Multiple browsers selected ({0})" -f $selected.Count
        $DetailType.Text = ""
        $DetailEngine.Text = ""
        $DetailDetect.Text = ""
        $DetailVersion.Text = ""
        $DetailProcess.Text = ""
        $DetailExe.Text = ""
        $DetailProfileRoot.Text = ""
        $DetailProfilePath.Text = ""
        $NoProfileText.Visibility = 'Visible'
        $ProfileList.Visibility = 'Collapsed'
        $BackupBtn.IsEnabled = $true
        $RestoreBtn.IsEnabled = $true
        $script:selectedBrowser = $selected
    } else {
        Update-BrowserDetails $null
        $script:selectedBrowser = $null
    }
})

# Backup button
$BackupBtn.Add_Click({
    $selected = $BrowserList.SelectedItems
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one browser.", "No Selection", 'OK', 'Warning')
        return
    }

    $dest = $DestTextBox.Text
    if ([string]::IsNullOrWhiteSpace($dest)) {
        [System.Windows.MessageBox]::Show("Please specify a backup destination.", "Missing Destination", 'OK', 'Warning')
        return
    }

    if (-not (Test-Path -LiteralPath $dest)) {
        try { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        catch {
            [System.Windows.MessageBox]::Show("Cannot create destination: $_", "Error", 'OK', 'Error')
            return
        }
    }

    $excludes = if ($ExcludeCacheCheck.IsChecked) { @(Get-ExcludedDirectories -Config $config) } else { @() }
    $force = $ForceCheck.IsChecked
    $allProfiles = $AllProfilesCheck.IsChecked

    # Run backup in background
    $BackupBtn.IsEnabled = $false
    Set-Progress 0 "Starting backup..." $true

    $job = Start-Job -ScriptBlock {
        param($SelectedBrowsers, $Dest, $Excludes, $Force, $AllProfiles, $ConfigPath, $LogFile)
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\Config.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\Logging.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\BackupEngine.psm1') -Force -DisableNameChecking
        
        $config = Get-BrowserConfig -ConfigPath $ConfigPath
        $results = @()
        
        foreach ($browser in $SelectedBrowsers) {
            if ($AllProfiles) {
                $profiles = @(Get-BrowserProfiles -Browser $browser)
                foreach ($p in $profiles) {
                    $result = New-BrowserBackup -Browser $browser -ProfileName $p.Name `
                        -Destination $Dest -ExcludeDirs $Excludes -Force:$Force `
                        -LogFile $LogFile -RobocopyRetries $config.defaults.robocopyRetries `
                        -RobocopyWait $config.defaults.robocopyWait -CriticalFiles $config.defaults.checksumCriticalFiles
                    $label = $p.Name
                    if ($p.DisplayName -and $p.DisplayName -ne $p.Name) { $label = "$($p.Name) ($($p.DisplayName))" }
                    if ($p.Email) { $label = "$label <$($p.Email)>" }
                    $results += @{ Browser = $browser.Name; Profile = $label; Result = $result }
                }
            } else {
                $profiles = @($browser | Where-Object { $_.Name -in ($selected | ForEach-Object { $_.Name }) })
                # Simplified: just backup the default profile for multi-select
                $result = New-BrowserBackup -Browser $browser -ProfileName "Default" `
                    -Destination $Dest -ExcludeDirs $Excludes -Force:$Force `
                    -LogFile $LogFile -RobocopyRetries $config.defaults.robocopyRetries `
                    -RobocopyWait $config.defaults.robocopyWait -CriticalFiles $config.defaults.checksumCriticalFiles
                $results += @{ Browser = $browser.Name; Profile = "Default"; Result = $result }
            }
        }
        return $results
    } -ArgumentList @($selected, $dest, $excludes, $force, $allProfiles, (Join-Path $rootDir 'Config\browsers.json'), $LogFile)

    # Monitor job
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq 'Completed') {
            $timer.Stop()
            $results = Receive-Job $job
            $BackupBtn.IsEnabled = $true
            Set-Progress 0 "" $false
            
            $success = 0
            $total = $results.Count
            foreach ($r in $results) {
                if ($r.Result.Success) { $success++ }
            }
            Update-StatusBar "Backup complete: $success/$total succeeded" "#FFA6E3A1"
            $lines = @()
            foreach ($r in $results) {
                $status = if ($r.Result.Success) { "OK - $($r.Result.Path) ($($r.Result.SizeMB) MB)" } else { "FAILED: $($r.Result.Message)" }
                $lines += "$($r.Browser) - $($r.Profile): $status"
            }
            [System.Windows.MessageBox]::Show(($lines -join "`n"), "Backup Results", 'OK', 'Information')
        } else {
            Set-Progress (($job.Id % 100)) "Backing up..." $true
        }
    })
    $timer.Start()
})

# Restore button
$RestoreBtn.Add_Click({
    $selected = $BrowserList.SelectedItems
    if ($selected.Count -ne 1) {
        [System.Windows.MessageBox]::Show("Please select exactly one browser for restore.", "Selection Required", 'OK', 'Warning')
        return
    }

    $browser = $selected[0]
    $profiles = @(Get-BrowserProfiles -Browser $browser)
    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No profiles found for this browser.", "No Profiles", 'OK', 'Warning')
        return
    }

    $backupPath = [System.Windows.Forms.FolderBrowserDialog]::new()
    $backupPath.Description = "Select backup folder to restore from"
    if ($backupPath.ShowDialog() -ne 'OK') { return }

    $profileName = "Default"
    if ($profiles.Count -gt 1) {
        $dialog = [System.Windows.Window]::new()
        $dialog.Title = "Select Profile"
        $dialog.SizeToContent = 'WidthAndHeight'
        $dialog.WindowStartupLocation = 'CenterOwner'
        $dialog.Owner = $window
        $dialog.ResizeMode = 'NoResize'
        
        $stack = [System.Windows.Controls.StackPanel]::new()
        $stack.Margin = "20"
        foreach ($p in $profiles) {
            $label = $p.Name
            if ($p.DisplayName -and $p.DisplayName -ne $p.Name) {
                $label = "$($p.Name) - $($p.DisplayName)"
            }
            if ($p.Email) { $label = "$label <$($p.Email)>" }
            $label = "$label [{0:N1} MB]" -f $p.SizeMB
            if ($null -ne $p.CriticalFiles) { $label = "$label | $($p.CriticalFiles) critical files" }
            $rb = [System.Windows.Controls.RadioButton]::new()
            $rb.Content = $label
            $rb.GroupName = "ProfileSelect"
            $rb.Tag = $p.Name
            $stack.Children.Add($rb)
        }
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Content = "OK"
        $btn.Width = 80
        $btn.Margin = "0,12,0,0"
        $btn.Add_Click({ $dialog.DialogResult = $true; $dialog.Close() })
        $stack.Children.Add($btn)
        $dialog.Content = $stack
        if ($dialog.ShowDialog() -eq $true) {
            $selectedRb = $stack.Children | Where-Object { $_.IsChecked -eq $true } | Select-Object -First 1
            if ($selectedRb) { $profileName = $selectedRb.Tag }
        }
    }

    # Read manifest for restore context
    $manifestFile = Join-Path $backupPath.SelectedPath "manifest.json"
    $restoreLabel = $browser.Name
    if (Test-Path -LiteralPath $manifestFile -PathType Leaf) {
        try {
            $mf = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
            if ($mf.profileDisplayName -and $mf.profileDisplayName -ne $mf.profile) {
                $restoreLabel = "$($mf.browser.name) - $($mf.profileDisplayName)"
            }
            if ($mf.profileEmail) { $restoreLabel = "$restoreLabel <$($mf.profileEmail)>" }
        } catch { }
    }

    Set-Progress 0 "Restoring $restoreLabel..." $true
    $RestoreBtn.IsEnabled = $false

    $job = Start-Job -ScriptBlock {
        param($Browser, $BackupPath, $ProfileName, $ConfigPath, $LogFile)
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\Config.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\BrowserDetection.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\Logging.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path (Split-Path $ConfigPath) 'Modules\RestoreEngine.psm1') -Force -DisableNameChecking
        
        $config = Get-BrowserConfig -ConfigPath $ConfigPath
        $result = Restore-BrowserProfile -Browser $Browser -BackupPath $BackupPath `
            -ProfileName $ProfileName -Force:$true -LogFile $LogFile `
            -RobocopyRetries $config.defaults.robocopyRetries -RobocopyWait $config.defaults.robocopyWait
        return $result
    } -ArgumentList @($browser, $backupPath.SelectedPath, $profileName, (Join-Path $rootDir 'Config\browsers.json'), $LogFile)

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if ($job.State -eq 'Completed') {
            $timer.Stop()
            $result = Receive-Job $job
            $RestoreBtn.IsEnabled = $true
            Set-Progress 0 "" $false
            
            if ($result.Success) {
                Update-StatusBar "Restore completed: $restoreLabel" "#FFA6E3A1"
                $msg = "Restore completed successfully!`n`nRestored: $restoreLabel`nRollback: $($result.Rollback)"
                [System.Windows.MessageBox]::Show($msg, "Success", 'OK', 'Information')
            } else {
                Update-StatusBar "Restore failed: $($result.Message)" "#FFF38BA8"
                [System.Windows.MessageBox]::Show("Restore failed: $($result.Message)", "Error", 'OK', 'Error')
            }
        } else {
            Set-Progress (($job.Id % 100)) "Restoring $restoreLabel..." $true
        }
    })
    $timer.Start()
})

# List button
$ListBtn.Add_Click({
    $allBrowsers = @(Get-InstalledBrowsers -Config $Config)
    $msg = "Installed Browsers:`n`n"
    foreach ($b in $allBrowsers) {
        $running = if (Test-BrowserRunning -Browser $b) { " [RUNNING]" } else { "" }
        $msg += "{0} v{1}{2}`n  Type: {3}`n  Profile: {4}`n  Exe: {5}`n`n" -f $b.Name, $b.Version, $running, $b.Type, $b.ProfilePath, (if ($b.ExePath) { $b.ExePath } else { "Not found" })
    }
    if ($allBrowsers.Count -eq 0) { $msg = "No browsers found." }
    [System.Windows.MessageBox]::Show($msg, "All Browsers", 'OK', 'Information')
})

# Browse destination
$BrowseDestBtn.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Select backup destination folder"
    $dialog.SelectedPath = $DestTextBox.Text
    if ($dialog.ShowDialog() -eq 'OK') {
        $DestTextBox.Text = $dialog.SelectedPath
    }
})

# Window loaded
$window.Add_Loaded({
    Refresh-BrowserList
    Update-BrowserDetails $null
})

# ---------------------------------------------------------------------------
# RUN THE WINDOW
# ---------------------------------------------------------------------------
$window.ShowDialog() | Out-Null