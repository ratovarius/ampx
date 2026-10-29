# Process

`uv sync` and `npm install` at the repo root install everything, including a git pre-commit hook.

- Python: ruff (lint and format), pyright, and pytest with 80% coverage
- TypeScript: ESLint, Prettier, tsc, and vitest with 80% coverage
- Swift: SwiftLint, SwiftFormat, the Swift 6 compiler with complete strict concurrency, and XCTest with 80% coverage (`xcodebuild test -enableCodeCoverage YES`)

Swift tools come from Homebrew: `brew install swiftlint swiftformat`. Their configs are `.swiftlint.yml` and `.swiftformat`.

The pre-commit hook runs the format, lint, type and unit test checks on every commit.

## Rules

- Outside a plan, commit each change once you have checked it.
- Never use `git commit --no-verify`.
- Never lower a threshold, turn off a rule or exclude a file to get a green run. If a rule looks wrong, stop and ask.
- Never push.