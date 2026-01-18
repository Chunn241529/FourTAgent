#!/usr/bin/env bash
set -e

# Determine if a pre‑created virtual environment exists (created by setup.py)
VENV_DIR=".venv"
if [ -d "$VENV_DIR" ]; then
  echo "Using existing virtual environment at $VENV_DIR"
else
  echo "Creating new virtual environment in ./.venv"
  python -m venv $VENV_DIR
fi

# Activate the virtual environment
source "$VENV_DIR/bin/activate"

# Ensure requirements file exists
if [ ! -f "requirements.txt" ]; then
  echo "Error: requirements.txt not found in project root"
  exit 1
fi

# Install dependencies (including pyinstaller)
pip install -r requirements.txt pyinstaller

# Platform‑specific handling for --add-data (Linux uses ':' , Windows uses ';')
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "win"* ]]; then
  ADD_DATA_SEP=";"
else
  ADD_DATA_SEP=":"
fi

# Icon path – use the actual icon file present in the repository
ICON_PATH="ui/web/static/favicon_io/favicon.ico"
if [ ! -f "$ICON_PATH" ]; then
  echo "Warning: Icon file not found at $ICON_PATH – proceeding without custom icon"
  ICON_ARG=""
else
  ICON_ARG="-i \"$ICON_PATH\""
fi

# Build the executable with PyInstaller
pyinstaller --onefile --windowed \
  --add-data "ui/app${ADD_DATA_SEP}ui/app" \
  $ICON_ARG \
  ui/app/main.py

# Report success
if [ $? -eq 0 ]; then
  echo "✅ Build hoàn tất: dist/$(basename ui/app/main.py .py)$( [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win"* ]] && echo .exe)"
else
  echo "❌ Build thất bại"
  exit 1
fi
