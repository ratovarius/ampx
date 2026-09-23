# Building AmpX

## Requirements

- macOS 26.0+ (run) / 26.4+ recommended for building
- Xcode 26.4+ (`xcode-select --install` for command line tools)
- [uv](https://docs.astral.sh/uv/) to generate test fixtures

## Build and run

```bash
./build.sh --run        # debug build + launch
./build.sh --release    # release build
./build.sh --clean      # clean first (combine with the flags above)
```

Or open `AmpX.xcodeproj`, pick the **AmpX** scheme and **My Mac**, then press ⌘R.

## Test

```bash
./scripts/run-tests.sh
```

This generates fixtures in `Tests/Fixtures/` and then runs `xcodebuild test`. Running `xcodebuild test` on its own fails the fixture-based suites.

## Format and lint

```bash
./scripts/format-swift.sh   # SwiftFormat
./scripts/lint-swift.sh     # SwiftLint
```

## UI screenshots

```bash
./scripts/shoot.sh              # build, relaunch, screenshot each window
./scripts/shoot.sh --no-build   # relaunch + screenshot only
```

Images are saved to `/tmp/ampx_shot*.png`.

## Troubleshooting

- **Old app launches:** `build.sh --run` quits running copies first. If Xcode still opens an old build, remove `~/Library/Developer/Xcode/DerivedData/AmpX-*`.
- **Code signing fails:** set Signing to *Sign to Run Locally* in the AmpX target.
