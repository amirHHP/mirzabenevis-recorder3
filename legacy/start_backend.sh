#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")/backend"
VENV_DIR="$BACKEND_DIR/.venv"

cd "$BACKEND_DIR"

PYTHON=""
for candidate in python3.11 python3.12 python3.10 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Creating Python virtual environment with $PYTHON..."
  "$PYTHON" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install -q -r requirements.txt

MODEL="${WHISPER_MODEL:-base}"
echo "Starting transcription server on http://127.0.0.1:8765 (model: $MODEL)"
WHISPER_MODEL="$MODEL" python main.py
