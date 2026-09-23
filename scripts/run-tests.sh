#!/usr/bin/env bash
# Generate fixtures, then run the test suite.
#
# Quiet by default: the full xcodebuild log goes to /tmp/ampx_tests.log and only
# failures plus a one-line summary reach stdout. A green run of several hundred
# tests should print ~3 lines, not several thousand — reading those thousands of
# "Test case ... passed" lines is pure cost for an agent and pure scrollback for you.
# Pass --verbose to stream the raw log instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG=/tmp/ampx_tests.log
VERBOSE=false
XCODEBUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: ./scripts/run-tests.sh [--verbose] [-- <xcodebuild args>]"
            echo ""
            echo "Options:"
            echo "  --verbose   Stream the full xcodebuild log to stdout"
            echo "  --help      Show this help message"
            echo ""
            echo "Full log is always written to ${LOG}"
            exit 0
            ;;
        --)
            shift
            XCODEBUILD_ARGS=("$@")
            break
            ;;
        *)
            XCODEBUILD_ARGS+=("$1")
            shift
            ;;
    esac
done

"$ROOT_DIR/scripts/generate-fixtures.sh" >/tmp/ampx_fixtures.log 2>&1 \
    || { echo "❌ fixture generation failed — see /tmp/ampx_fixtures.log"; tail -20 /tmp/ampx_fixtures.log; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported macOS architecture for tests: $ARCH" >&2
        exit 1
        ;;
esac

run_tests() {
    xcodebuild test \
        -project AmpX.xcodeproj \
        -scheme AmpX \
        -destination "platform=macOS,arch=${ARCH}" \
        ONLY_ACTIVE_ARCH=YES \
        ${XCODEBUILD_ARGS[@]+"${XCODEBUILD_ARGS[@]}"}
}

if [[ "$VERBOSE" == true ]]; then
    run_tests 2>&1 | tee "$LOG"
    exit "${PIPESTATUS[0]}"
fi

STATUS=0
run_tests >"$LOG" 2>&1 || STATUS=$?

# Surface the signal: failing tests, compile errors, and the pass/fail tally.
if [[ $STATUS -ne 0 ]]; then
    echo "❌ tests failed — full log: $LOG"
    echo ""
    grep -E "error:|failed on|Test Case .* failed|Testing failed" "$LOG" | sort -u | head -40 || true
    echo ""
    echo "--- last 20 lines ---"
    tail -20 "$LOG"
    exit "$STATUS"
fi

PASSED=$(grep -c "' passed on " "$LOG" || true)
echo "✅ tests passed (${PASSED:-0} cases) — full log: $LOG"
