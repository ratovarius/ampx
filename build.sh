#!/bin/bash
# AmpX macOS Build Script

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="AmpX"

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported macOS architecture: $ARCH" >&2
        exit 1
        ;;
esac
DESTINATION="platform=macOS,arch=${ARCH}"
BUILD_LOG=/tmp/ampx_build.log

echo "🎵 Building AmpX macOS..."
echo ""

# Parse arguments
CONFIGURATION="Debug"
RUN_AFTER_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --run)
            RUN_AFTER_BUILD=true
            shift
            ;;
        --clean)
            echo "🧹 Cleaning build folder..."
            xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
                       -scheme "${PROJECT_NAME}" \
                       -configuration "${CONFIGURATION}" \
                       -destination "${DESTINATION}" \
                       ONLY_ACTIVE_ARCH=YES \
                       -quiet \
                       clean >/tmp/ampx_clean.log 2>&1
            echo "✅ Clean complete"
            echo ""
            shift
            ;;
        --help)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  --release    Build release configuration (default: debug)"
            echo "  --run        Run the app after building"
            echo "  --clean      Clean before building"
            echo "  --help       Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run './build.sh --help' for usage information"
            exit 1
            ;;
    esac
done

# Build
echo "🔨 Building ${CONFIGURATION} configuration..."
# Quiet by default: full log to /tmp/ampx_build.log, only failures reach stdout.
# Matches scripts/shoot.sh — raw xcodebuild output is thousands of lines nobody reads.
if ! xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
                -scheme "${PROJECT_NAME}" \
                -configuration "${CONFIGURATION}" \
                -destination "${DESTINATION}" \
                ONLY_ACTIVE_ARCH=YES \
                -quiet \
                build >"${BUILD_LOG}" 2>&1; then
    echo ""
    echo "❌ Build failed! — full log: ${BUILD_LOG}"
    echo ""
    grep -E "error:|warning: .*(deprecated|unused)" "${BUILD_LOG}" | sort -u | head -30 || true
    echo ""
    echo "--- last 20 lines ---"
    tail -20 "${BUILD_LOG}"
    exit 1
fi

echo ""
echo "✅ Build succeeded! (log: ${BUILD_LOG})"
echo ""

# Resolve THIS project's product — never `find | head` across DerivedData
# (multiple AmpX-* folders exist; alphabetical order launches a stale checkout).
BUILT_PRODUCTS_DIR=$(xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${PROJECT_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination "${DESTINATION}" \
    ONLY_ACTIVE_ARCH=YES \
    -showBuildSettings 2>/dev/null \
    | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -n 1)
if [ -z "$BUILT_PRODUCTS_DIR" ]; then
    echo "⚠️  Could not resolve BUILT_PRODUCTS_DIR for this project — refusing to guess."
    exit 1
fi
APP_PATH="${BUILT_PRODUCTS_DIR}/${PROJECT_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "⚠️  Build succeeded but app not found at: $APP_PATH"
    exit 1
fi

echo "📦 Built application: $APP_PATH"
echo "   (project: ${PROJECT_DIR})"

if [ "$RUN_AFTER_BUILD" = true ]; then
    echo ""
    echo "🚀 Launching AmpX..."
    # Same bundle ID can be registered from multiple DerivedData checkouts.
    # `open` without -n reactivates a *running* instance (often the stale one).
    osascript -e 'tell application "AmpX" to quit' >/dev/null 2>&1 || true
    killall AmpX >/dev/null 2>&1 || true
    pkill -x AmpX >/dev/null 2>&1 || true
    sleep 0.5
    # -n = new instance of *this* path; -W omitted so the script returns.
    open -n "$APP_PATH"
    echo "   binary: ${APP_PATH}/Contents/MacOS/AmpX"
    ls -la "${APP_PATH}/Contents/MacOS/AmpX" 2>/dev/null || true
fi
