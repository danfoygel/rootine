# Rootine

Personal iPhone app with a companion Apple Watch app. Single developer (Dan), personal use only. Requirements are in `REQUIREMENTS.md`. The iPhone app has the Today list and item editor; the Watch app has today's list and to-do quick-add. Sync is CloudKit (SwiftData's private database) plus a WatchConnectivity relay overlay; see `Shared/Sync/` and section 12 of `REQUIREMENTS.md`.

## Project layout

```
project.yml          XcodeGen spec — source of truth for the Xcode project
Rootine/             iOS app target (SwiftUI)
RootineWatch/        watchOS app target (SwiftUI), embedded in the iOS app
Shared/              code compiled into both apps: Model/ (SwiftData), Scheduling/ (pure, Sendable logic), Presentation/ (colors, symbols, formatting)
RootineTests/        hostless Swift Testing unit tests; Shared/ is compiled straight into the bundle
.swiftlint.yml       lint rules
.swiftformat         format rules
```

- **`Rootine.xcodeproj` is generated and git-ignored.** Never edit it (or change settings in Xcode's UI — they are lost on regeneration). Change `project.yml`, then run `xcodegen generate`.
- Files added or removed on disk are picked up by `xcodegen generate`; run it after adding files.
- `Shared/` is listed under `sources:` for both app targets and the test target. SwiftData models must stay CloudKit-compatible: every stored property defaulted or optional, no unique constraints, optional relationships with inverses.

## Identifiers

| | |
|---|---|
| iOS bundle ID | `com.danfoygel.rootine` |
| watchOS bundle ID | `com.danfoygel.rootine.watchkitapp` (companion = iOS app) |
| Signing team | `ZVU48K8YCD` (paid Apple Developer Program, individual account; automatic signing) |
| Deployment targets | iOS 26.0, watchOS 26.0 |
| Swift | 6.0 language mode (strict concurrency), toolchain 6.2.4 |
| UI | SwiftUI |

Info.plist files are generated from build settings (`INFOPLIST_KEY_*` in `project.yml`). Keys with no `INFOPLIST_KEY_` setting (e.g. background modes) go under the target's `info: properties:`, and entitlements under `entitlements: properties:`; XcodeGen writes those `Info.plist` / `.entitlements` files, which are git-ignored. Never edit them by hand.

## Toolchain (this machine)

- Xcode 26.3, SDKs iOS 26.2 / watchOS 26.2; simulator runtimes iOS 26.3 / watchOS 26.2.
- Homebrew: `xcodegen`, `swiftlint`, `swiftformat`, `xcbeautify`.
- `gh` is signed in as `danfoygel`; remote is `github.com/danfoygel/rootine` (private).
- MCP: the `xcode` server (`xcrun mcpbridge`) exposes Xcode tools (build, diagnostics, previews, etc.). Xcode must be running with Settings → Intelligence → "Allow external agents to use Xcode tools" on, and the connection approved in Xcode. If the server shows 0 tools in a session, approve the dialog in Xcode and start a fresh session.
- `xcodebuildmcp` CLI and its skill are also installed.
- Real devices: iPhone 17 ("Big Green Phone", iOS 26.6) and Apple Watch Series 8 (watchOS 26.6), both registered to the team and in the provisioning profiles. Each must be unlocked and in Developer Mode to show as available (`xcrun devicectl list devices`); Xcode reaches the Watch through the iPhone, which is most reliable with the phone on a cable. A newly connected device needs one build with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` (the Watch via the `RootineWatch` scheme) to be added to the profiles. If the Watch is re-paired to a new phone, unpair it in Xcode's Devices window and let it reconnect.

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

# Unit tests
xcodebuild -project Rootine.xcodeproj -scheme Rootine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test | xcbeautify

swiftformat .                          # format
swiftlint lint                         # lint (should report 0 violations)
```

Build output goes to `build/` (git-ignored). Available simulators: iPhone 17 / 17 Pro / 17 Pro Max / Air / 16 Pro / 16e / 14; Apple Watch Series 11 (42/46mm), Ultra 3, SE 3. iPhone 17 Pro and Apple Watch Series 11 (46mm) are paired (`xcrun simctl list pairs`), so WatchConnectivity works between them; install each app on its own simulator. The simulators have no iCloud account, so CloudKit sync itself can only be tested on the real devices.

## Parallel worktrees

Several git worktrees (under `.claude/worktrees/`) can be worked on at once; each is an independent copy of the project.

- A fresh worktree has no `Rootine.xcodeproj` — run `xcodegen generate` in it first.
- Build with `-derivedDataPath build` so output stays in that worktree's own `build/`.
- Simulators and devices are shared, and every worktree installs the same bundle ID. Use a different simulator per worktree (e.g. iPhone 17 Pro in one, iPhone 17 in another); don't run tests on the same simulator from two worktrees at once. Only one worktree at a time can use the paired iPhone 17 Pro / Watch Series 11 (46mm) for WatchConnectivity work; another needs its own pair (`xcrun simctl pair`). Only one build can be on the real iPhone/Watch at a time.
- The `xcode` MCP server drives whichever Xcode windows are open, and every window is titled "Rootine". Keep only the active worktree open in Xcode; other worktrees build and test with `xcodebuild`.
- `.swiftformat` excludes `.claude` so `swiftformat .` in the main checkout doesn't touch worktrees; SwiftLint only includes the source directories listed in `.swiftlint.yml`.

## Conventions

- Run `swiftformat .` and `swiftlint lint` before committing; keep lint at 0 violations.
- Testing strategy, coverage rules and the on-device checklist are in `TESTING.md`; logic changes in `Shared/` ship with tests.
- Prefer SwiftUI and Swift concurrency (`async`/`await`, actors); the project builds in Swift 6 mode, so fix concurrency warnings rather than suppressing them.
- Add capabilities/entitlements (HealthKit, notifications, etc.) via `project.yml` (`entitlements:` / `settings:`), not the Xcode UI. The signing team is a paid account, so CloudKit, HealthKit, push, etc. are available; capabilities may still need to be enabled on the App ID.
- Keep the iPhone and Watch targets building at all times — the iOS scheme builds both.
