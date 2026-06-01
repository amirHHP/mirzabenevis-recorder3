#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Mirza Benevis Setup (Native) ==="

chmod +x "$ROOT_DIR/scripts/build_whisper.sh"
chmod +x "$ROOT_DIR/scripts/generate_xcode_project.sh"

echo ""
echo "1. Building whisper.cpp XCFramework..."
if command -v cmake &>/dev/null && xcodebuild -version &>/dev/null 2>&1; then
  bash "$ROOT_DIR/scripts/build_whisper.sh"
else
  echo "   SKIP: Install Xcode + cmake first, then run:"
  echo "   ./scripts/build_whisper.sh"
fi

echo ""
echo "2. Generating Xcode project..."
python3 "$ROOT_DIR/scripts/generate_xcode_project.py"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. open MacApp/MirzaBenevis.xcodeproj"
echo "  2. Build & Run (⌘R) — app lives in menu bar"
echo "  3. First launch downloads ggml-base.bin (~142 MB)"
echo "  4. Enter Gemini API key in Settings for summaries"
