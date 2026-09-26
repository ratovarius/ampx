---
description: 
alwaysApply: true
---

## AmpX

Modern macOS music player with Winamp's UX spirit — compact floating window, playlist, EQ,
visualizer — plus lossless audio, modern codecs, and a native macOS feel.

Branch flow: `feature/*` → `develop` → `main`.

---

## Quality checks: targeted locally, full in CI

`.github/workflows/quality.yml` gates PRs at two weights. Into `develop`: build and the test
suite only. Into `main`: adds SwiftFormat, SwiftLint, ShellCheck, Ruff and actionlint. Only
error-severity findings fail; warnings become PR annotations.

Locally, run only the suites for the code you changed, filtered to failures:
`xcodebuild test -project AmpX.xcodeproj -scheme AmpX -destination "platform=macOS,arch=$(uname -m)"
-only-testing:AmpXTests/<Suite> 2>&1 | grep -E 'error: |failed \(|TEST (SUCCEEDED|FAILED)'`
(run `./scripts/generate-fixtures.sh` once first). Leave the full suite to CI.

Swift formatting is automatic via a `PostToolUse` hook
(`scripts/hooks/format-edited-swift.sh`). Never run `swiftformat` or fix formatting by hand.

Read CI results cheaply: `gh pr checks`, `gh run view --log-failed`. Never whole logs.

---

## Commands

```bash
./build.sh --run                # debug build + launch (log: /tmp/ampx_build.log)
./scripts/run-tests.sh          # fixtures + suite, quiet (log: /tmp/ampx_tests.log)
./scripts/shoot.sh --no-build   # relaunch + screenshot → /tmp/ampx_shot<n>.png
cd scripts && uv sync           # all Python runs via uv
```

`shoot.sh` captures by window ID, so occluded windows work — no focus fighting. Each PNG
costs ~1.5k tokens; once modules are detached, add `--index <n>` to grab only what changed.

---

## Gotchas

- Other Claude sessions edit this worktree concurrently. Before debugging an unexpected test
  failure, check `git status` and file mtimes — it may not be yours. Never bare `git stash`.
- NEVER add `Co-Authored-By:` to commits, PRs, or comments.
