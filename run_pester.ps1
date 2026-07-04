Set-Location $PSScriptRoot
Import-Module Pester -Force
Invoke-Pester -Path (Join-Path $PSScriptRoot 'Tests') -PassThru
