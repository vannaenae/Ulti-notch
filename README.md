# Ulti Notch

Free, open source (MIT) macOS app that turns the MacBook notch into a Dynamic Island style command surface. Live activities, widgets and utilities in one quiet, fast app. Non-notch displays get a floating island.

## Download

Free. Builds will be published on the [Releases page](https://github.com/vannaenae/Ulti-notch/releases/latest) with automatic updates. No release yet.

**Status:** architecture and core contracts. Phase 1 has not started; open questions are in [`docs/SCOPE.md`](docs/SCOPE.md).

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
