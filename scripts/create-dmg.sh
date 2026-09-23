#!/bin/bash
# Create DMG Installer for AmpX
# This script creates a distributable DMG with a nice layout

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="AmpX"

# Get version from command line argument or extract from Xcode project
if [ -n "$1" ]; then
    VERSION="$1"
else
    # Extract MARKETING_VERSION from Xcode project
    VERSION=$(grep -A 1 "MARKETING_VERSION" "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj" | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" | head -n 1)
    if [ -z "$VERSION" ]; then
        echo "❌ Could not determine version. Please provide version as argument or ensure MARKETING_VERSION is set in Xcode project."
        exit 1
    fi
fi

DMG_NAME="${PROJECT_NAME}-${VERSION}"
BUILD_DIR="${PROJECT_DIR}/dmg-build"
RELEASE_DIR="${PROJECT_DIR}/release"

echo "🎵 Creating AmpX DMG Installer..."
echo ""

# Clean up any previous build artifacts
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
fi

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"

# Step 1: Build the release version (skip if already built)
echo "🔨 Building release version..."
if [ "$SKIP_BUILD" != "true" ]; then
    xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
               -scheme "${PROJECT_NAME}" \
               -configuration Release \
               clean build

    if [ $? -ne 0 ]; then
        echo "❌ Build failed!"
        exit 1
    fi
else
    echo "⏭️  Skipping build (SKIP_BUILD=true)"
fi

# Step 2: Find and copy the built app
echo ""
echo "📦 Locating built application..."
# Use provided path or search in DerivedData
if [ -n "$BUILD_OUTPUT_DIR" ] && [ -d "$BUILD_OUTPUT_DIR" ]; then
    APP_PATH="$BUILD_OUTPUT_DIR"
    echo "✅ Using provided app path: $APP_PATH"
else
    # Resolve THIS project's product; other AmpX-* DerivedData folders may hold stale builds.
    BUILT_PRODUCTS_DIR=$(xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
        -scheme "${PROJECT_NAME}" \
        -configuration Release \
        -showBuildSettings 2>/dev/null \
        | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -n 1)
    APP_PATH="${BUILT_PRODUCTS_DIR}/${PROJECT_NAME}.app"
    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        echo "❌ Could not find built application!"
        echo "   Searched in: ~/Library/Developer/Xcode/DerivedData/"
        if [ -n "$BUILD_OUTPUT_DIR" ]; then
            echo "   And in: $BUILD_OUTPUT_DIR"
        fi
        exit 1
    fi
    echo "✅ Found build: $APP_PATH"
fi

echo ""
echo "📋 Copying to DMG staging area..."
cp -R "$APP_PATH" "$BUILD_DIR/"

# Step 3: Create Applications symlink
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$BUILD_DIR/Applications"

# Step 4: Create the DMG
echo ""
echo "💿 Creating DMG..."

# Remove any existing DMG with the same name
if [ -f "${RELEASE_DIR}/${DMG_NAME}.dmg" ]; then
    rm "${RELEASE_DIR}/${DMG_NAME}.dmg"
fi

# Create temporary DMG
TEMP_DMG="${RELEASE_DIR}/${DMG_NAME}-temp.dmg"
hdiutil create -volname "${PROJECT_NAME}" \
               -srcfolder "$BUILD_DIR" \
               -ov \
               -format UDRW \
               "$TEMP_DMG"

# Mount the temporary DMG
echo "📂 Mounting DMG for customization..."
MOUNT_DIR="/Volumes/${PROJECT_NAME}"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR"

# Give the system time to mount
sleep 2

# Customize the DMG appearance using AppleScript
echo "🎨 Customizing DMG appearance..."
osascript <<EOF
tell application "Finder"
    tell disk "${PROJECT_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 600, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set position of item "${PROJECT_NAME}.app" of container window to {120, 150}
        set position of item "Applications" of container window to {380, 150}
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Ensure changes are written
sync

# Unmount the DMG
echo "📤 Ejecting temporary DMG..."
hdiutil detach "$MOUNT_DIR"

# Convert to compressed, read-only DMG
echo "🗜️  Compressing final DMG..."
FINAL_DMG="${RELEASE_DIR}/${DMG_NAME}.dmg"
hdiutil convert "$TEMP_DMG" \
                -format UDZO \
                -o "$FINAL_DMG"

# Remove temporary DMG
rm "$TEMP_DMG"

# Clean up build directory
echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR"

# Get file size
DMG_SIZE=$(du -h "$FINAL_DMG" | cut -f1)

echo ""
echo "✅ DMG created successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 DMG Location: $FINAL_DMG"
echo "💾 Size: $DMG_SIZE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To test the installer:"
echo "  open '$FINAL_DMG'"
echo ""
echo "To distribute:"
echo "  1. Upload to your website/cloud storage"
echo "  2. Users download and mount the DMG"
echo "  3. Users drag AmpX.app to Applications folder"
echo ""

