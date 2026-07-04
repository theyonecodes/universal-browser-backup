#!/bin/bash

# Ensure script is executable
if [ ! -x "$0" ]; then
    chmod +x "$0"
fi


echo "=========================================="
echo "  Universal Browser Backup - Setup"
echo "=========================================="
echo ""

if ! command -v python3 &> /dev/null
then
    echo "ERROR: Python3 not found. Please install Python 3.12+."
    exit 1
fi

echo "[1/3] Upgrading pip..."
python3 -m pip install --upgrade pip

echo "[2/3] Installing dependencies..."
python3 -m pip install -r requirements.txt

echo "[3/3] Finalizing..."
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "  You can now run the app with: python3 main.py"
echo "=========================================="
echo ""
