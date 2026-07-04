@echo off
title Universal Browser Backup - Setup
color 0B

echo ==========================================
echo   Universal Browser Backup - Setup
echo ==========================================
echo.

python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python not found. Please install Python 3.12+ from python.org
    pause
    exit /b 1
)

echo [1/3] Upgrading pip...
python -m pip install --upgrade pip || py -m pip install --upgrade pip

echo [2/3] Installing dependencies...
python -m pip install -r requirements.txt || py -m pip install -r requirements.txt

echo [3/3] Finalizing...
echo.
echo ==========================================
echo   Setup Complete!
echo   You can now run the app with: python main.py
echo ==========================================
echo.
pause
