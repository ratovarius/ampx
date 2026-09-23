# Releasing AmpX

1. Bump the version (`patch`, `minor` or `major`):
   ```bash
   ./scripts/bump-version.sh patch
   ```
2. Run the tests:
   ```bash
   ./scripts/run-tests.sh
   ```
3. Build the DMG:
   ```bash
   ./scripts/create-dmg.sh
   ```
   This makes a release build and writes `release/AmpX-<version>.dmg`. To reuse an existing build, run `SKIP_BUILD=true BUILD_OUTPUT_DIR=/path/to/AmpX.app ./scripts/create-dmg.sh`.
4. Commit, tag `v<version>`, push, and attach the DMG to a GitHub release.

The DMG is ad-hoc signed and not notarized. On first launch Gatekeeper may block a normal double-click:

1. Click **Done** (or dismiss the warning).
2. In Finder, **Control-click** the app → **Open**, then confirm **Open**.
3. Or open **System Settings → Privacy & Security** and choose **Open Anyway**.

Runtime requires macOS 26.0+ (`MACOSX_DEPLOYMENT_TARGET`).

Bundle ID: `com.ampx.macos`.
