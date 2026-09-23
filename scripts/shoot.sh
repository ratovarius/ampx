#!/bin/bash
# Build → relaunch → screenshot the AmpX window(s) for UI iteration.
# Usage: ./scripts/shoot.sh [--no-build | --capture-only] [--output-prefix <path>] [-- <open-args>]
#   Captures each on-screen AmpX window by window ID (works even when occluded)
#   to /tmp/ampx_shot*.png. Prints the paths so an agent can read them.
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="Debug"
ARCH="$(uname -m)"
DESTINATION="platform=macOS,arch=${ARCH}"
NO_BUILD=false
CAPTURE_ONLY=false
OUTPUT_PREFIX=/tmp/ampx_shot
APP_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --capture-only)
            NO_BUILD=true
            CAPTURE_ONLY=true
            shift
            ;;
        --output-prefix)
            [[ $# -ge 2 ]] || { echo "--output-prefix requires a path"; exit 1; }
            OUTPUT_PREFIX="$2"
            shift 2
            ;;
        --)
            shift
            APP_ARGS=("$@")
            break
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$NO_BUILD" == false ]]; then
    xcodebuild -project "${PROJECT_DIR}/AmpX.xcodeproj" -scheme AmpX \
        -configuration "${CONFIG}" \
        -destination "${DESTINATION}" \
        ONLY_ACTIVE_ARCH=YES \
        build >/tmp/ampx_build.log 2>&1 \
        || { echo "❌ build failed — see /tmp/ampx_build.log"; tail -20 /tmp/ampx_build.log; exit 1; }
fi

if [[ "$CAPTURE_ONLY" == false ]]; then
    # Resolve THIS project's product via build settings (not find|head across DerivedData).
    BUILT_PRODUCTS_DIR=$(xcodebuild -project "${PROJECT_DIR}/AmpX.xcodeproj" \
        -scheme AmpX \
        -configuration "${CONFIG}" \
        -destination "${DESTINATION}" \
        ONLY_ACTIVE_ARCH=YES \
        -showBuildSettings 2>/dev/null \
        | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -n 1)
    APP_PATH="${BUILT_PRODUCTS_DIR}/AmpX.app"
    if [[ ! -d "$APP_PATH" ]]; then
        echo "❌ AmpX.app not found at: $APP_PATH"
        exit 1
    fi

    # Relaunch fresh so the screenshot reflects the new build.
    # Without -n, Launch Services reactivates a running instance from another checkout.
    osascript -e 'tell application "AmpX" to quit' >/dev/null 2>&1 || true
    killall AmpX >/dev/null 2>&1 || true
    pkill -x AmpX >/dev/null 2>&1 || true
    sleep 0.5
    echo "🚀 $APP_PATH"
    if [[ ${#APP_ARGS[@]} -gt 0 ]]; then
        open -n "$APP_PATH" --args "${APP_ARGS[@]}"
    else
        open -n "$APP_PATH"
    fi
    sleep 2.5
fi

# Enumerate AmpX's on-screen windows (layer 0 = normal) and capture each by ID.
IDS=$(swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("AmpX") {
    if (w[kCGWindowLayer as String] as? Int ?? 0) == 0 {
        print(w[kCGWindowNumber as String] as? Int ?? -1)
    }
}
SWIFT
)

i=0
for id in $IDS; do
    out="${OUTPUT_PREFIX}${i}.png"
    screencapture -x -o -l"$id" "$out" && echo "📸 $out"
    i=$((i + 1))
done
if [[ $i -eq 0 ]]; then echo "⚠️  no AmpX windows found on screen"; fi
