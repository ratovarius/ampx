#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        echo "Install with: brew install $2" >&2
        exit 1
    fi
}

FORMAT_REPORTER=()
LINT_REPORTER=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --github)
            # Emit GitHub Actions annotations so warnings land on the PR diff.
            FORMAT_REPORTER=(--reporter github-actions-log)
            LINT_REPORTER=(--reporter github-actions-logging)
            shift
            ;;
        --help)
            echo "Usage: ./scripts/lint-swift.sh [--github]"
            echo ""
            echo "Options:"
            echo "  --github   Report findings as GitHub Actions annotations"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run './scripts/lint-swift.sh --help' for usage information" >&2
            exit 1
            ;;
    esac
done

require_cmd swiftformat swiftformat
require_cmd swiftlint swiftlint

PATHS=(Sources Tests)

echo "==> SwiftFormat (lint)"
swiftformat "${PATHS[@]}" --lint "${FORMAT_REPORTER[@]+"${FORMAT_REPORTER[@]}"}"

# --quiet suppresses the per-file "Linting 'File.swift' (n/247)" progress spam,
# leaving only actual violations. Findings are the point; progress bars are not.
echo "==> SwiftLint"
swiftlint lint --quiet "${LINT_REPORTER[@]+"${LINT_REPORTER[@]}"}"
