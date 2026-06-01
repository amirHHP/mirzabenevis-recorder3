#!/usr/bin/env bash
# Standalone macOS build & DMG generator for Mirza Benevis
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

BUILD_DIR="build_output"
APP_NAME="MirzaBenevis"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${contents_dir:-$APP_BUNDLE/Contents}/MacOS"
RESOURCES_DIR="${contents_dir:-$APP_BUNDLE/Contents}/Resources"
MODULES_DIR="${BUILD_DIR}/modules"

echo "=== 1. Preparing Build Directories ==="
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULES_DIR"

echo "=== 2. Creating whisper modulemap ==="
# Copy required headers from whisper.cpp
cp vendor/whisper.cpp/include/whisper.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-alloc.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-backend.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-metal.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-cpu.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-blas.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/gguf.h "$MODULES_DIR/"

cat > "$MODULES_DIR/module.modulemap" << 'EOF'
module whisper {
    header "whisper.h"
    export *
}
EOF

echo "=== 3. Compiling Swift Source Files ==="
# Get list of all Swift files in the MacApp directory
SWIFT_FILES=$(find MacApp/MirzaBenevis -name "*.swift")

SDK_PATH=""
for sdk in "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk" "/Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk"; do
  if [ -d "$sdk" ]; then
    SDK_PATH="$sdk"
    break
  fi
done

if [ -z "$SDK_PATH" ]; then
  SDK_PATH=$(xcrun --show-sdk-path)
fi

echo "Compiling swift files..."
swiftc -sdk "$SDK_PATH" \
  -I "$MODULES_DIR" \
  -O \
  -target arm64-apple-macosx14.0 \
  -o "${MACOS_DIR}/${APP_NAME}" \
  $SWIFT_FILES \
  -L build_whisper/src \
  -L build_whisper/ggml/src \
  -L build_whisper/ggml/src/ggml-metal \
  -L build_whisper/ggml/src/ggml-blas \
  -lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas \
  -lc++ \
  -framework Accelerate -framework Metal -framework Foundation -framework AVFoundation -framework ScreenCaptureKit -framework SwiftUI -framework Combine -framework Security

echo "=== 4. Preparing App Metadata ==="
# Copy and update Info.plist
cp MacApp/MirzaBenevis/Info.plist "${CONTENTS_DIR}/Info.plist"
# Replace $(EXECUTABLE_NAME) with the actual app name
sed -i '' "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" "${CONTENTS_DIR}/Info.plist"

# Add standard PkgInfo file
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "=== 5. Code Signing ==="
# Ad-hoc sign the app bundle with the app entitlements
codesign --force \
  --options runtime \
  --entitlements MacApp/MirzaBenevis/MirzaBenevis.entitlements \
  --sign - \
  "$APP_BUNDLE"

echo "=== 6. Packaging into DMG ==="
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy the app to the DMG staging folder
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create symlink to /Applications inside the DMG folder
ln -s /Applications "$DMG_TEMP/Applications"

# Generate the DMG disk image using hdiutil
DMG_FILE="${BUILD_DIR}/${APP_NAME}.dmg"
rm -f "$DMG_FILE"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$DMG_TEMP" \
  -ov \
  -format UDZO \
  "$DMG_FILE"

echo "=== Build & Package Success! ==="
echo "DMG output created at: ${DMG_FILE}"
