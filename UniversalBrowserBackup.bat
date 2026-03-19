@echo off
title Universal Browser Backup Tool
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UniversalBrowserBackup.ps1"
exit /b %errorlevel%
