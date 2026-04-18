#!/bin/bash
set -e

echo "🔥 DARKFORGE-X // NATIVE BUILD INITIATED"
echo "──────────────────────────────────────────"

APP_NAME="HingeAngleForge"
BUNDLE_ID="com.darkforge.hingeangle"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SRC_DIR/build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos12.0"
    echo "🖥  Architecture: Apple Silicon (arm64)"
elif [ "$ARCH" = "x86_64" ]; then
    TARGET="x86_64-apple-macos12.0"
    echo "🖥  Architecture: Intel (x86_64)"
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

# Clean
rm -rf "$OUTPUT_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
echo "📦 Bundle structure created"

# Copy Info.plist
cp "$SRC_DIR/Info.plist" "$CONTENTS/Info.plist"
echo "📋 Info.plist injected"

# Compile Swift
echo "⚙️  Compiling Swift sources (swiftc -O)..."
swiftc -O -whole-module-optimization \
    -target "$TARGET" \
    -framework SwiftUI -framework Combine -framework IOKit \
    "$SRC_DIR/LidAngleMonitor.swift" \
    "$SRC_DIR/ContentView.swift" \
    "$SRC_DIR/HingeAngleApp.swift" \
    -o "$MACOS_DIR/$APP_NAME"

echo "✅ Compilation successful"

# Codesign
echo "✍️  Codesigning with entitlements..."
codesign --force --deep --sign - \
    --entitlements "$SRC_DIR/App.entitlements" \
    --options runtime \
    "$APP_BUNDLE"

# Verify
echo "🔍 Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE" 2>&1

echo "──────────────────────────────────────────"
echo "✅ BUILD COMPLETE: $APP_BUNDLE"
echo "🚀 Launch: open $APP_BUNDLE"
echo ""
echo "⚠️  First launch: Grant Input Monitoring in"
echo "   System Settings > Privacy & Security > Input Monitoring"
