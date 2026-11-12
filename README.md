# Ulti Notch

Free, open source (MIT) macOS app that turns the MacBook notch into a Dynamic Island style command surface. Live activities, widgets and utilities in one quiet, fast app. Non-notch displays get a floating island.

## Download

Free. Download the DMG from the [Releases page](https://github.com/vannaenae/Ulti-notch/releases), open it and drag Ulti Notch to Applications.

Preview builds are not notarised yet. The first time you open the app, macOS will block it: go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Build from source

```bash
brew install xcodegen
xcodegen generate
open UltiNotch.xcodeproj
```

**Status:** Phase 1 in progress. Working now: island on every display, Battery, Now Playing (Music and Spotify), Settings.

| Doc | What it covers |
|---|---|
| [`docs/SCOPE.md`](docs/SCOPE.md) | Scope, assumptions, open questions |
| [`docs/PHASE1_PLAN.md`](docs/PHASE1_PLAN.md) | Phase 1 features: Droppy parity, simpler (awaiting approval) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture, module protocol, folder structure |
| [`docs/RISKS.md`](docs/RISKS.md) | Technical risk research (Now Playing, HUD, windows, glass, permissions) |
| [`docs/TECH_DEBT.md`](docs/TECH_DEBT.md) | Running technical debt list |
| [`docs/testing/MANUAL_TEST_CHECKLIST.md`](docs/testing/MANUAL_TEST_CHECKLIST.md) | Manual UI test checklist |
| [`CHANGELOG.md`](CHANGELOG.md) | Changes |

## Build and test the core

Requires macOS 14.6+ and Xcode 16 or later.

```bash
cd Packages/UltiNotchKit
swift test
```

## Requirements

macOS 14.6 or later. Apple silicon first.
