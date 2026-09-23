#!/usr/bin/env bash
# Claude Code PostToolUse hook: silently SwiftFormat any .swift file just written.
#
# Formatting is fully deterministic, so having a model reason about it — or having CI
# fail a PR over it — is wasted effort. The harness runs this, so it costs zero tokens.
#
# Registered in .claude/settings.json for the Edit|Write tools. Always exits 0: a
# formatter problem must never block an edit.
set -uo pipefail

payload="$(cat)"

extract_file_path() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null && return 0
    fi
    printf '%s' "$payload" | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' \
        2>/dev/null || true
}

file_path="$(extract_file_path)"

[[ -n "$file_path" ]] || exit 0
[[ "$file_path" == *.swift ]] || exit 0
[[ -f "$file_path" ]] || exit 0
command -v swiftformat >/dev/null 2>&1 || exit 0

swiftformat "$file_path" >/dev/null 2>&1 || true
exit 0
