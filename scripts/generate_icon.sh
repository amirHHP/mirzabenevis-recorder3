#!/usr/bin/env bash
# Generate macOS .icns file from a 1024x1024 PNG
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

SOURCE_PNG="${ROOT_DIR}/installer/icon_1024.png"
ICONSET_DIR="${ROOT_DIR}/installer/AppIcon.iconset"
OUTPUT_ICNS="${ROOT_DIR}/installer/AppIcon.icns"

if [ ! -f "$SOURCE_PNG" ]; then
    echo "❌ Source icon not found: $SOURCE_PNG"
    exit 1
fi

echo "=== Generating .icns from ${SOURCE_PNG} ==="

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Generate all required sizes using sips
generate() {
    local name="$1" size="$2"
    echo "  → ${name} (${size}x${size})"
    sips -z "$size" "$size" "$SOURCE_PNG" --out "${ICONSET_DIR}/${name}" > /dev/null 2>&1
}

generate "icon_16x16.png"      16
generate "icon_16x16@2x.png"   32
generate "icon_32x32.png"      32
generate "icon_32x32@2x.png"   64
generate "icon_128x128.png"    128
generate "icon_128x128@2x.png" 256
generate "icon_256x256.png"    256
generate "icon_256x256@2x.png" 512
generate "icon_512x512.png"    512
generate "icon_512x512@2x.png" 1024

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# Clean up iconset directory
rm -rf "$ICONSET_DIR"

echo "✅ Icon created: ${OUTPUT_ICNS}"
echo "   Size: $(du -h "$OUTPUT_ICNS" | cut -f1)"
