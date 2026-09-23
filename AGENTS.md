---
description: 
alwaysApply: true
---

## AmpX

Modern macOS music player with Winamp's UX spirit — compact floating window, playlist, EQ,
visualizer — plus lossless audio, modern codecs, and a native macOS feel.

Branch flow: `feature/*` → `develop` → `main`.

---

## Quality checks run in CI, not locally

`.github/workflows/quality.yml` gates PRs into `develop` and `main` with SwiftFormat,
SwiftLint, ShellCheck, Ruff, actionlint, and the test suite. Only error-severity findings
fail; warnings become PR annotations.

**Do not run `./build.sh`, `./scripts/run-tests.sh`, `./scripts/lint-swift.sh`, or
`xcodebuild` to verify your own work** — that output is the largest avoidable context cost
in this repo and CI reads it for free. Hand work over unverified and let CI report; run them
locally only to debug a specific failure you cannot read from CI.

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
