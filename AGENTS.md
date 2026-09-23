---
description: 
alwaysApply: true
---

## Project Overview

**AmpX** — *Modern audio player. Classic spirit.*

**Goal:** a production-quality, modern macOS music player that preserves the Winamp UX spirit while using best-in-class audio engineering, high quality visualizations.

Target users are music collectors and audiophiles who remember Winamp fondly and want that workflow — compact floating window, playlist, EQ, visualizer — but with lossless audio quality, modern codec support, and a native macOS feel.

---

## Build & Test

### Quick build (command line)
```bash
./build.sh --run        # debug build + launch
./build.sh --release    # release build
```

### Iterating on UI (see the rendered app)
```bash
./scripts/shoot.sh            # build + relaunch + screenshot each window
./scripts/shoot.sh --no-build # skip the build; just relaunch + screenshot (fast)
```
Screenshots land in `/tmp/ampx_shot0.png`, `…shot1.png`, etc. Captures **by window ID**
(`screencapture -l<id>`) so it grabs the real window pixels even when occluded — no need to
fight window focus. Essential for UI fidelity work: edit views → `shoot.sh` → compare
to the reference screenshot → repeat.

### Clean build
```bash
xcodebuild -project AmpX.xcodeproj -scheme AmpX clean
# or in Xcode: ⌘⇧K
```

### Running tests
Use the project script — it generates the required fixtures first, then runs the suite:
```bash
./scripts/run-tests.sh
```

### Python (`scripts/`)

Fixture generation and any other Python in this repo run using uv.

```bash
cd scripts
uv sync
uv run generate-fixtures
uv run python -c "import ampx_fixtures"   # ad-hoc checks
```

NEVER add ` Co-Authored-By: ` to commits, PRs or comments in github.