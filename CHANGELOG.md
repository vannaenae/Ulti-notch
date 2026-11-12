# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow SemVer once the first build ships.

## [Unreleased]

### Added
- First runnable app: island on every display (hardware notch or floating), hover/click/swipe, Battery and Now Playing (Music, Spotify) modules, menu bar item, Settings with per-module toggles.
- Release workflow: pushing a `v*` tag publishes an ad-hoc signed DMG to GitHub Releases.
- Architecture doc, scope and assumptions, technical risk research.
- `UltiNotchKit` Swift package:
  - `NotchCore`: module descriptor and permission model, live activity model and arbitration (`ActivityBoard`), island state machine, notch geometry, reference-counted `ServiceRegistry`, `ModuleHost` lifecycle.
  - `NotchModuleKit`: SwiftUI `NotchModule` protocol, with shelf widgets and command palette actions (`CommandDescriptor`).
  - Unit tests for all of the above (Swift Testing).
- CI: build and test on a GitHub-hosted macOS runner.

### Decided
- Open source under MIT.
- v2 brief adopted: Droppy parity, intuitiveness first. Phase 1 plan in `docs/PHASE1_PLAN.md` (awaiting approval).
- Ulti Notch is free and distributed from GitHub Releases, with Sparkle auto-updates and a Homebrew tap. Distribution plan in `docs/ARCHITECTURE.md` §12.
