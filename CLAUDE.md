# Rootine

Personal iPhone app with a companion Apple Watch app. Single developer (Dan), personal use only. Currently a stub: both apps launch and show a placeholder screen; no functionality yet.

## Project layout

```
project.yml          XcodeGen spec — source of truth for the Xcode project
Rootine/             iOS app target (SwiftUI)
RootineWatch/        watchOS app target (SwiftUI), embedded in the iOS app
.swiftlint.yml       lint rules
.swiftformat         format rules
```

- **`Rootine.xcodeproj` is generated and git-ignored.** Never edit it (or change settings in Xcode's UI — they are lost on regeneration). Change `project.yml`, then run `xcodegen generate`.
- Files added or removed on disk are picked up by `xcodegen generate`; run it after adding files.
- Shared code between the iPhone and Watch apps does not exist yet. When needed, add a `Shared/` directory and list it under `sources:` for both targets in `project.yml`.

## Identifiers

| | |
|---|---|
| iOS bundle ID | `com.danfoygel.rootine` |
| watchOS bundle ID | `com.danfoygel.rootine.watchkitapp` (companion = iOS app) |
| Signing team | `ZVU48K8YCD` (paid Apple Developer Program, individual account; automatic signing) |
| Deployment targets | iOS 26.0, watchOS 26.0 |
| Swift | 6.0 language mode (strict concurrency), toolchain 6.2.4 |
| UI | SwiftUI |

Info.plist files are generated from build settings (`INFOPLIST_KEY_*` in `project.yml`); there are no plist files to edit.

## Toolchain (this machine)

- Xcode 26.3, SDKs iOS 26.2 / watchOS 26.2; simulator runtimes iOS 26.3 / watchOS 26.2.
- Homebrew: `xcodegen`, `swiftlint`, `swiftformat`, `xcbeautify`.
- `gh` is signed in as `danfoygel`; remote is `github.com/danfoygel/rootine` (private).
- MCP: the `xcode` server (`xcrun mcpbridge`) exposes Xcode tools (build, diagnostics, previews, etc.). Xcode must be running with Settings → Intelligence → "Allow external agents to use Xcode tools" on, and the connection approved in Xcode. If the server shows 0 tools in a session, approve the dialog in Xcode and start a fresh session.
- `xcodebuildmcp` CLI and its skill are also installed.
- Real devices: iPhone 14 ("dan") and Apple Watch Series 8 are paired for device testing. The phone must be connected, unlocked and in Developer Mode to show as available (`xcrun devicectl list devices`).

## Commands

```bash
xcodegen generate                      # regenerate Rootine.xcodeproj after editing project.yml / adding files

# Build iPhone app (also builds and embeds the Watch app)
xcodebuild -project Rootine.xcodeproj -scheme Rootine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build | xcbeautify

# Build Watch app alone
xcodebuild -project Rootine.xcodeproj -scheme RootineWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  -derivedDataPath build build | xcbeautify

# Tests (once a test target exists)
xcodebuild -project Rootine.xcodeproj -scheme Rootine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test | xcbeautify

swiftformat .                          # format
swiftlint lint                         # lint (should report 0 violations)
```

Build output goes to `build/` (git-ignored). Available simulators: iPhone 17 / 17 Pro / 17 Pro Max / Air / 16 Pro / 16e / 14; Apple Watch Series 11 (42/46mm), Ultra 3, SE 3. No iPhone+Watch simulator pair exists yet; create one with `xcrun simctl pair <watch-udid> <phone-udid>` when testing watch connectivity in the simulator.

## Conventions

- Run `swiftformat .` and `swiftlint lint` before committing; keep lint at 0 violations.
- Prefer SwiftUI and Swift concurrency (`async`/`await`, actors); the project builds in Swift 6 mode, so fix concurrency warnings rather than suppressing them.
- Add capabilities/entitlements (HealthKit, notifications, etc.) via `project.yml` (`entitlements:` / `settings:`), not the Xcode UI. The signing team is a paid account, so CloudKit, HealthKit, push, etc. are available; capabilities may still need to be enabled on the App ID.
- Keep the iPhone and Watch targets building at all times — the iOS scheme builds both.
