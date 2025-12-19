#!/bin/bash
# create-dmg.sh - Create MacGuard DMG for distribution
# Usage: ./scripts/create-dmg.sh VERSION
# Example: ./scripts/create-dmg.sh 1.2.0
set -e

APP_NAME="MacGuard"
VERSION="${1:-1.2.0}"
BUNDLE_ID="com.shenglong.macguard"

if [ -z "$1" ]; then
    echo "Usage: ./scripts/create-dmg.sh VERSION"
    echo "Example: ./scripts/create-dmg.sh 1.2.0"
    exit 1
fi

# Paths
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "Creating app bundle..."

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Sparkle.framework
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "Bundling Sparkle.framework..."
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    # Update binary to find framework in bundle
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

# Copy resources - the entire bundle must be copied for SPM resource access
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>${VERSION//./}</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/shenglong209/MacGuard/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>I7s26R56gqkm2GqhPOLdjcyK4YGcuEbSWsRBTEumlb8=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUShowReleaseNotes</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MacGuard uses Bluetooth to detect your trusted devices for auto-disarm.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Convert PNG to icns for app icon
if [ -f "Resources/AppIcon.png" ]; then
    echo "Creating app icon..."
    ICONSET="$DIST_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16 Resources/AppIcon.png --out "$ICONSET/icon_16x16.png" 2>/dev/null
    sips -z 32 32 Resources/AppIcon.png --out "$ICONSET/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32 Resources/AppIcon.png --out "$ICONSET/icon_32x32.png" 2>/dev/null
    sips -z 64 64 Resources/AppIcon.png --out "$ICONSET/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128 Resources/AppIcon.png --out "$ICONSET/icon_128x128.png" 2>/dev/null
    sips -z 256 256 Resources/AppIcon.png --out "$ICONSET/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256 Resources/AppIcon.png --out "$ICONSET/icon_256x256.png" 2>/dev/null
    sips -z 512 512 Resources/AppIcon.png --out "$ICONSET/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512 Resources/AppIcon.png --out "$ICONSET/icon_512x512.png" 2>/dev/null
    sips -z 1024 1024 Resources/AppIcon.png --out "$ICONSET/icon_512x512@2x.png" 2>/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
fi

# Code sign the app bundle (ad-hoc signing for Sparkle compatibility)
echo "Code signing app bundle..."
# Sign frameworks first (Sparkle contains nested frameworks/helpers)
if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
fi
# Sign the main app bundle
codesign --force --sign - "$APP_BUNDLE"
echo "✓ App bundle code signed"

echo "App bundle created: $APP_BUNDLE"

# Create DMG
echo "Creating DMG..."
rm -f "$DIST_DIR/$DMG_NAME"

# Create temporary DMG folder
DMG_TEMP="$DIST_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DIST_DIR/$DMG_NAME"

# Cleanup
rm -rf "$DMG_TEMP"

echo ""
echo "✓ DMG created: $DIST_DIR/$DMG_NAME"
ls -lh "$DIST_DIR/$DMG_NAME"
