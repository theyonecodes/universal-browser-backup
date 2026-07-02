@echo off
setlocal enabledelayedexpansion
title Universal Browser Backup v2.1

echo ==========================================
echo   Universal Browser Backup v2.1
echo ==========================================
echo.

REM Check if any arguments were passed (if so, run in console mode)
if not "%~1"=="" (
    where pwsh >nul 2>&1
    if !errorlevel! equ 0 (
        pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1" %*
    ) else (
        where powershell >nul 2>&1
        if !errorlevel! equ 0 (
            powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1" %*
        ) else (
            echo ERROR: PowerShell not found. Please install PowerShell 7+ or Windows PowerShell.
            pause
            exit /b 1
        )
    )
    exit /b %errorlevel%
)

REM No arguments = GUI mode. Launch in a new window.
echo Starting GUI mode...
where pwsh >nul 2>&1
if !errorlevel! equ 0 (
    start "Universal Browser Backup" pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1"
) else (
    start "Universal Browser Backup" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1"
)
endlocal