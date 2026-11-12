# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow SemVer once the first build ships.

## [Unreleased]

### Added
- Architecture doc, scope and assumptions, technical risk research.
- `UltiNotchKit` Swift package:
  - `NotchCore`: module descriptor and permission model, live activity model and arbitration (`ActivityBoard`), island state machine, notch geometry, reference-counted `ServiceRegistry`, `ModuleHost` lifecycle.
  - `NotchModuleKit`: SwiftUI `NotchModule` protocol.
  - Unit tests for all of the above (Swift Testing).
- CI: build and test on a GitHub-hosted macOS runner.
