#!/bin/bash
# Build → relaunch → screenshot the AmpX window(s) for UI iteration.
# Usage: ./scripts/shoot.sh [--no-build | --capture-only] [--index <n>]
#                           [--output-prefix <path>] [-- <open-args>]
#   Captures each on-screen AmpX window by window ID (works even when occluded)
#   to /tmp/ampx_shot*.png. Prints the paths so an agent can read them, labeled
#   with each window's pixel size so you can tell them apart.
#
#   --index <n> captures only the nth window (0-based). The default stacked layout is
#   a single window, so this only matters once modules are detached — but then each
#   extra PNG an agent reads costs ~1.5k tokens, so grab just the one you changed.
#   (Selection is by index, not title: AmpX's windows are borderless and report an
#   empty CGWindowName, so there is no title to match on.)
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="Debug"
ARCH="$(uname -m)"
DESTINATION="platform=macOS,arch=${ARCH}"
NO_BUILD=false
CAPTURE_ONLY=false
OUTPUT_PREFIX=/tmp/ampx_shot
WINDOW_INDEX=""
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
        --index)
            [[ $# -ge 2 ]] || { echo "--index requires a 0-based window number"; exit 1; }
            case "$2" in
                ''|*[!0-9]*) echo "--index must be a non-negative integer"; exit 1 ;;
            esac
            WINDOW_INDEX="$2"
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

# Enumerate AmpX's on-screen windows (layer 0 = normal) as "<id> <width>x<height>" lines.
# Size is the only reliable discriminator: these windows are borderless and carry no title.
WINDOWS=$(swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String ?? "").contains("AmpX") {
    if (w[kCGWindowLayer as String] as? Int ?? 0) == 0 {
        let id = w[kCGWindowNumber as String] as? Int ?? -1
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = Int(bounds["Width"] as? Double ?? 0)
        let height = Int(bounds["Height"] as? Double ?? 0)
        print("\(id) \(width)x\(height)")
    }
}
SWIFT
)

found=0
captured=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="${line%% *}"
    size="${line#* }"
    index=$found
    found=$((found + 1))

    if [[ -n "$WINDOW_INDEX" && "$index" != "$WINDOW_INDEX" ]]; then
        continue
    fi

    out="${OUTPUT_PREFIX}${index}.png"
    screencapture -x -o -l"$id" "$out"
    echo "📸 $out  [window ${index}, ${size}]"
    captured=$((captured + 1))
done <<<"$WINDOWS"

if [[ $found -eq 0 ]]; then
    echo "⚠️  no AmpX windows found on screen"
elif [[ $captured -eq 0 ]]; then
    echo "⚠️  --index ${WINDOW_INDEX} out of range: ${found} AmpX window(s) on screen (0..$((found - 1)))"
fi
