#!/usr/bin/env bash
# Build whisper.cpp XCFramework (Metal + CoreML ready) for macOS/iOS
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="$ROOT/vendor/whisper.cpp"

if [[ ! -d "$WHISPER_DIR" ]]; then
  echo "Cloning whisper.cpp..."
  git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
fi

if ! command -v cmake &>/dev/null; then
  echo "ERROR: cmake required. Install with: brew install cmake"
  exit 1
fi

if ! xcodebuild -version &>/dev/null; then
  echo "ERROR: Xcode required (not just Command Line Tools)."
  echo "Run: sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "Building whisper.xcframework (may take several minutes)..."
cd "$WHISPER_DIR"
./build-xcframework.sh

echo ""
echo "Done: $WHISPER_DIR/build-apple/whisper.xcframework"
echo "Now run: python3 scripts/generate_xcode_project.py"
