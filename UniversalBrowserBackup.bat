@echo off
title Universal Browser Backup v2.0
color 0B

echo ==========================================
echo   Universal Browser Backup v2.0
echo ==========================================
echo.

where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1" %*
) else (
    where powershell >nul 2>&1
    if %errorlevel% equ 0 (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1" %*
    ) else (
        echo ERROR: PowerShell not found. Please install PowerShell 7+ or Windows PowerShell.
        pause
        exit /b 1
    )
)
