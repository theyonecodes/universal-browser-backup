@echo off
setlocal enabledelayedexpansion
title Universal Browser Backup v2.1.1

echo ==========================================
echo   Universal Browser Backup v2.1.1
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

REM No arguments = GUI mode. Show menu to choose GUI backend.
echo Starting GUI mode...
echo.
echo Choose GUI backend:
echo   [1] PowerShell WPF (native, no extra deps)
echo   [2] Python Qt (PySide6 - modern UI)
echo.
set /p choice="Enter choice [1/2] (default=1): "

if "%choice%"=="" set choice=1
if "%choice%"=="2" (
    echo Launching Python Qt GUI...
    where python >nul 2>&1
    if !errorlevel! equ 0 (
        cd /d "%~dp0"
        start "Universal Browser Backup" python main.py
        if !errorlevel! neq 0 (
            echo.
            echo WARNING: Python GUI failed to start. Trying PowerShell WPF instead...
            timeout /t 2 >nul
            goto :launch_ps_gui
        )
    ) else (
        echo ERROR: Python not found in PATH. Falling back to PowerShell WPF.
        timeout /t 2 >nul
        goto :launch_ps_gui
    )
) else (
:launch_ps_gui
    echo Launching PowerShell WPF GUI...
    where pwsh >nul 2>&1
    if !errorlevel! equ 0 (
        cd /d "%~dp0"
        start "Universal Browser Backup" pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1"
    ) else (
        where powershell >nul 2>&1
        if !errorlevel! equ 0 (
            cd /d "%~dp0"
            start "Universal Browser Backup" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1"
        ) else (
            echo ERROR: PowerShell not found. Please install PowerShell 7+ or Windows PowerShell.
            pause
            exit /b 1
        )
    )
)
endlocal