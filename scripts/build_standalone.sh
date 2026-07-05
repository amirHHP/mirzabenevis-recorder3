#!/usr/bin/env bash
# Standalone macOS build & DMG installer generator for Mirza Benevis
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

BUILD_DIR="build_output"
APP_NAME="MirzaBenevis"
APP_DISPLAY_NAME="Mirza Benevis"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
MODULES_DIR="${BUILD_DIR}/modules"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Mirza Benevis — macOS Build Script     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── Step 1: Prepare Build Directories ───────────────────────────────────────

echo "=== 1/7 Preparing Build Directories ==="
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULES_DIR"

# ─── Step 2: Generate App Icon ───────────────────────────────────────────────

echo "=== 2/7 Generating App Icon ==="
ICON_SOURCE="installer/icon_1024_rgba.png"
ICNS_FILE="installer/AppIcon.icns"

if [ -f "$ICNS_FILE" ]; then
    echo "  Using pre-built icon: ${ICNS_FILE}"
    cp "$ICNS_FILE" "${RESOURCES_DIR}/AppIcon.icns"
elif [ -f "$ICON_SOURCE" ]; then
    echo "  Building .icns from ${ICON_SOURCE}..."
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${s}x${s}.png" > /dev/null 2>&1
    done

    cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    rm -f "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"

    iconutil -c icns "$ICONSET_DIR" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "  ✅ Icon generated"
else
    echo "  ⚠️ No icon source found, skipping"
fi

# ─── Step 3: Create whisper modulemap ────────────────────────────────────────

echo "=== 3/7 Creating whisper modulemap ==="
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

# ─── Step 4: Compile Swift ───────────────────────────────────────────────────

echo "=== 4/7 Compiling Swift Source Files ==="
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

echo "  SDK: ${SDK_PATH}"
echo "  Compiling..."

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

echo "  ✅ Compilation successful"

# ─── Step 5: Prepare App Bundle ──────────────────────────────────────────────

echo "=== 5/7 Preparing App Bundle ==="

# Copy and update Info.plist
cp MacApp/MirzaBenevis/Info.plist "${CONTENTS_DIR}/Info.plist"
sed -i '' "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" "${CONTENTS_DIR}/Info.plist"

# Add icon reference to Info.plist (inject before closing </dict>)
if ! grep -q "CFBundleIconFile" "${CONTENTS_DIR}/Info.plist"; then
    sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\
    <string>AppIcon</string>\
</dict>|' "${CONTENTS_DIR}/Info.plist"
    echo "  Added CFBundleIconFile to Info.plist"
fi

# Add PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Copy pre-downloaded models if they exist
if [ -d "models" ]; then
  echo "  Copying pre-downloaded models..."
  cp models/ggml-*.bin "${RESOURCES_DIR}/" 2>/dev/null || true
fi

echo "  ✅ App bundle ready"

# ─── Step 6: Code Signing ────────────────────────────────────────────────────

echo "=== 6/7 Code Signing ==="
SIGNING_IDENTITY="-"
if security find-identity -p codesigning | grep -q "MirzaBenevisLocalSign"; then
  SIGNING_IDENTITY="MirzaBenevisLocalSign"
  echo "  Using local code signing identity: ${SIGNING_IDENTITY}"
else
  echo "  ⚠️ MirzaBenevisLocalSign identity not found or not trusted. Falling back to ad-hoc signing."
fi

codesign --force \
  --options runtime \
  --entitlements MacApp/MirzaBenevis/MirzaBenevis.entitlements \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "  ✅ Signed (ad-hoc)"
else
  echo "  ✅ Signed with ${SIGNING_IDENTITY}"
fi

# ─── Step 7: Create DMG Installer ────────────────────────────────────────────

echo "=== 7/7 Creating DMG Installer ==="
DMG_TEMP="${BUILD_DIR}/dmg_staging"
DMG_FILE="${BUILD_DIR}/${APP_NAME}.dmg"
DMG_BG="installer/dmg_background.png"

rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy the app
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Remove old DMG if exists
rm -f "$DMG_FILE"

# Create read-write DMG first (so we can style it)
DMG_RW="${BUILD_DIR}/${APP_NAME}_rw.dmg"
hdiutil create \
  -volname "${APP_DISPLAY_NAME}" \
  -srcfolder "$DMG_TEMP" \
  -format UDRW \
  -fs HFS+ \
  "$DMG_RW" > /dev/null 2>&1

# Mount the DMG and apply styling
MOUNT_POINT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW" 2>/dev/null | grep -o '/Volumes/.*' | tail -1 || echo "")
VOLUME_NAME=$(basename "$MOUNT_POINT")

if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    echo "  Styling DMG window at: ${MOUNT_POINT} (Volume: ${VOLUME_NAME})"

    # Copy background image
    mkdir -p "${MOUNT_POINT}/.background"
    if [ -f "$DMG_BG" ]; then
        cp "$DMG_BG" "${MOUNT_POINT}/.background/background.png"
    fi

    # Set volume icon
    if [ -f "installer/AppIcon.icns" ]; then
        cp "installer/AppIcon.icns" "${MOUNT_POINT}/.VolumeIcon.icns"
        SetFile -c icnC "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
    fi

    # Use AppleScript to set DMG window appearance
    osascript << APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 540}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "${APP_NAME}.app" of container window to {160, 200}
        set position of item "Applications" of container window to {500, 200}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    # Unmount
    sync
    hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true
else
    echo "  ⚠️ Could not style DMG (mount point not found)"
fi

# Convert to compressed DMG
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_FILE" > /dev/null 2>&1
rm -f "$DMG_RW"

# Clean up
rm -rf "$DMG_TEMP"

echo "  ✅ DMG created"

# ─── Done ────────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "$DMG_FILE" | cut -f1)
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          ✅ Build Successful!             ║"
echo "╠══════════════════════════════════════════╣"
echo "║  App:  ${APP_BUNDLE}"
echo "║  DMG:  ${DMG_FILE} (${DMG_SIZE})"
echo "║  Size: ${APP_SIZE}"
echo "╚══════════════════════════════════════════╝"
echo ""
