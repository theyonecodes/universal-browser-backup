Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = Get-Content "$PSScriptRoot\..\GUI\App.ps1" -Raw
if ($xaml -match '(?s)@''\r?\n(.+?)\r?\n''@') {
    $xamlContent = $Matches[1]
    $lines = $xamlContent -split "`n"
    Write-Host "XAML has $($lines.Count) lines"
    # Show lines around 47
    for ($i = 44; $i -lt 50; $i++) {
        Write-Host ("Line {0}: {1}" -f ($i+1), $lines[$i].TrimEnd())
    }
    try {
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
        $null = [System.Windows.Markup.XamlReader]::Load($reader)
        Write-Host 'SUCCESS'
    } catch {
        Write-Host ('ERROR: ' + $_.Exception.InnerException.Message)
    }
}
