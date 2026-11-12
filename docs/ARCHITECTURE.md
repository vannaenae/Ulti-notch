# Ulti Notch: Architecture

Status: **Draft for review.** Nothing past `NotchCore` is built yet. Items marked **[Decision]** are proposals awaiting sign-off (see `docs/SCOPE.md`, open questions).

---

## 1. Principles → mechanisms

Each non-negotiable maps to a structural mechanism, not a convention.

| Non-negotiable | How the architecture enforces it |
|---|---|
| Every feature is a module that can be switched off | `ModuleHost` owns lifecycle. Modules are registered as a *descriptor + factory*; nothing else in the app references a module type. |
| Disabled modules use zero resources | Disabled modules are **never constructed**. Settings reads descriptors only, and settings views are `static`. On disable the host calls `deactivate()`, invalidates the module's context, returns its service leases and withdraws its activities. A stray task can't publish through a dead context. Covered by `ModuleHostTests`. |
| Modules never call system APIs directly | Modules depend only on `NotchModuleKit` and the service *protocols*. The dependency graph makes direct calls a build error once services are split into `ServicesAPI` and `ServicesLive` targets (§5). |
| Shared services, no duplicate work | `ServiceRegistry` is reference counted. A service starts on the first lease and stops on the last. |
| Permissions only when needed | Descriptors declare `PermissionRequirement`s with a reason. `validationIssues` fails any module that is on by default but needs a required permission, so first launch needs zero permissions. Unit tested. |
| Data stays on device | `usesNetwork` modules can't be on by default (validation rule). No analytics SDK. Crash reporting is opt-in only, if we add it at all. |
| Idle CPU < 1% | No polling anywhere. Event-driven services (notifications, KVO, IOKit run-loop sources, distributed notifications). The activity board gives the single next expiry time (`nextChange`), so the host arms one timer, not a ticker. Views animate only while visible. |
| Expand under 16 ms/frame | Window never resizes during animation (fixed envelope frame, §3.2). Only the SwiftUI shape animates. Expanded views are built lazily. Artwork is decoded off-main and cached at display size. |
| No GPL code | Clean-room. Behaviour is studied from running apps and public docs. Every third-party dependency's licence is recorded in `docs/THIRD_PARTY.md` (created with the first dependency). |
| Future third-party plugins | Live-activity content is a declarative, `Codable` value (`ActivityContent`/`Glyph`), so an out-of-process plugin can drive the island without shipping views into our process (§9). |

---

## 2. System overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│ App target (UltiNotch.app)                                                │
│  AppDelegate · composition root · menu bar item · Sparkle · onboarding    │
├───────────────┬───────────────────────────────┬───────────────────────────┤
│ Shell         │ Modules (one target each)     │ Settings UI               │
│ IslandPanel   │ Media · HUD · Battery · Shelf │ SwiftUI Settings scene    │
│ per display   │ Calendar · …                  │ per-module sections       │
│ DisplayMgr    │   depend on NotchModuleKit    │ layout + appearance       │
│ Suppression   │   + ServicesAPI only          │ import / export           │
├───────────────┴───────────────┬───────────────┴───────────────────────────┤
│ NotchModuleKit (SwiftUI)      │ NotchUI (shared components, materials)    │
├───────────────────────────────┴───────────────────────────────────────────┤
│ NotchCore (pure Swift, Foundation only, fully unit tested)                │
│ IslandStateMachine · ActivityBoard · ModuleHost · ServiceRegistry ·       │
│ NotchGeometry · ModuleDescriptor · Permission · Settings schema           │
├───────────────────────────────────────────────────────────────────────────┤
│ ServicesAPI (protocols + value types)                                     │
│ NowPlaying · SystemAudio · Display · Power · Calendar · Files · …         │
├───────────────────────────────────────────────────────────────────────────┤
│ ServicesLive (implementations)            │ PlatformBridges (quarantine)  │
│ CoreAudio · IOKit · EventKit · AppKit     │ MediaRemote adapter · Display │
│ ScriptingBridge · CGEventTap              │ Services · CoreBrightness     │
└───────────────────────────────────────────┴───────────────────────────────┘
```

Data flow, one direction:

```
system event → Service (AsyncStream / callback) → Module (state) → ModuleContext.publish
   → ModuleHost.board → ActivityResolution → Shell (per display) → IslandStateMachine → SwiftUI
user input  → Shell → IslandEvent → IslandStateMachine → state + timer effects → SwiftUI
```

---

## 3. Island shell

### 3.1 One panel per display

- `DisplayManager` listens to `NSApplication.didChangeScreenParametersNotification` and to `CGDisplayRegisterReconfigurationCallback` for finer events. It diffs screens by **display UUID** (`CGDisplayCreateUUIDFromDisplayID`). That UUID stays stable across reboots and reconnects. `NSScreen` identity and `CGDirectDisplayID` don't.
- Each display gets one `IslandController`: an `NSPanel`, an `NSHostingView`, and its own `IslandStateMachine`. Live activity resolution is shared, so every island shows the same activity. Expansion is per display.
- The user chooses which displays show an island: all, built-in only, or the main display only. Per-display notch tuning is keyed by UUID.

### 3.2 Window

| Property | Value | Why |
|---|---|---|
| Class | `NSPanel` subclass, `.borderless`, `.nonactivatingPanel` | Clicking the island must not steal focus from the frontmost app. |
| Level | Above `.mainMenu`, starting at `.statusBar` | Must draw over the menu bar and the notch area. Validated on hardware in Phase 1, and checked against the menu bar on macOS 26 where it is transparent by default. |
| Collection behaviour | `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle` | Visible on every Space. Doesn't slide with Space switches. Can appear over full-screen apps when the user allows it. Excluded from Cmd-` and Mission Control. |
| `hidesOnDeactivate` | false | |
| `canBecomeKey` | true only in `.panel` state with text input | Keyboard shortcuts and Escape without stealing focus otherwise. |
| Shadow / opaque | no / no | The shape draws its own shadow. |
| Frame | **Fixed** to `NotchGeometry.windowFrame` (union of all state frames) | Resizing an NSWindow every frame stutters. The window stays put and SwiftUI animates the shape. |
| Hit testing | Custom `hitTest` returns nil outside the current island rect | The transparent parts of the envelope pass clicks through to the menu bar and apps underneath. |

### 3.3 Pointer, gestures, drag

- Pointer tracking: an `NSTrackingArea` sized to the current island rect plus a small hysteresis margin, updated on state change. No global mouse monitor, so no permission is needed.
- Swipes: `scrollWheel` events on the panel (two-finger swipe over the island) are converted to `.swipedDown` and `.swipedUp` with a distance threshold.
- File drags: the panel registers for `.fileURL` drag types, and `draggingEntered` sends `.dragEntered`. This only fires once the drag is over the island's window. **Open item:** expanding when a drag *approaches* the notch, before it is over the window, needs a global drag monitor. Prototype in Phase 1: a listen-only `NSEvent` global monitor for `.leftMouseDragged`, which requires Accessibility. If that's needed it becomes an optional permission of the Shelf module.

### 3.4 Suppression (hidden state)

`SuppressionMonitor` emits `.suppressionChanged(Bool)` per display:

- **Full screen:** active-Space change notifications, then `CGWindowListCopyWindowInfo` checks for a layer-0 window covering the whole display. Bounds and owner need no Screen Recording permission; only window *titles* do, and we don't read them. Behaviour per display is configurable: hide, keep showing, or show only for `.critical` activities.
- **Screen locked:** `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications.
- **Display sleep / system sleep:** `NSWorkspace.screensDidSleepNotification`, `willSleepNotification`, and their wake counterparts. On sleep every service is told to pause (§5.3), and on wake the displays are rebuilt from scratch rather than patched.
- **Stage Manager:** no special handling expected because of `.stationary` and `.ignoresCycle`. Listed in the manual test checklist.

### 3.5 Notch geometry

`NotchGeometry` (NotchCore, unit tested) works from a `DisplayGeometry` snapshot:

- A hardware notch exists when `safeAreaInsets.top > 0` and both `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` exist. Width = screen width − left area − right area. Height = top safe-area inset.
- Otherwise the island is virtual: a floating pill at the top centre, sized by `IslandLayout`.
- Per-display `NotchTuning` covers width, height and horizontal offset. The top edge stays pinned.
- Every state's frame grows down and outwards from the notch's centre and is clamped on screen.

---

## 4. State machine

`IslandStateMachine` is a pure reducer: `handle(event) -> [IslandEffect]`. It has no clock and no AppKit. The shell owns the timers and feeds `.timerFired` back in. Stale timers are ignored by guards, so a cancel that races a fire is harmless. Covered by 19 unit tests plus a seeded fuzz test that checks the invariants over 12,000 random events.

States: `hidden`, `collapsed`, `peek`, `expanded`, `panel`. `hidden` was added to the four in the brief. Full-screen and lock-screen behaviour need a real state rather than a flag.

| From | Event | To | Notes |
|---|---|---|---|
| collapsed/peek | pointerEntered | — | starts `hoverIntent` timer (default 150 ms) |
| collapsed/peek | timerFired(hoverIntent), pointer still inside | expanded | |
| collapsed/peek | clicked / swipedDown / shortcut(toggleExpanded) | expanded | |
| any visible | shortcut(togglePanel) | panel | |
| expanded | swipedDown | panel | |
| expanded | pointerExited | — | starts `collapseGrace` (default 400 ms) unless dragging |
| expanded | timerFired(collapseGrace), pointer outside, not dragging | resting | |
| panel | pointerExited | panel | the panel never auto-collapses |
| panel | swipedUp | expanded | |
| expanded/panel | escape / clickedOutside / toggle shortcut | resting | |
| collapsed/peek | dragEntered | expanded | the shelf is the drop target; collapse is blocked until the drag ends |
| peek | activityRequestedAttention | peek (enlarged) | `peekSettle` timer; never interrupts an open island |
| any | suppressionChanged(true) | hidden | all timers cancelled, input ignored |
| hidden | suppressionChanged(false) | resting | |

*Resting* = `peek` if any live activity exists, otherwise `collapsed`. All timings and triggers live in `IslandBehavior`. They are user settable, persisted and exportable.

---

## 5. Services layer

### 5.1 Contracts

Each service is a protocol in `ServicesAPI`, exposes state as an `AsyncStream` or `@Observable` snapshot, and is registered under a `ServiceKey`:

| Service | Phase 1 consumers | Live implementation |
|---|---|---|
| `NowPlayingService` | Media | Composite of sources (see `docs/RISKS.md` R1). Music.app and Spotify via distributed notifications plus ScriptingBridge. Universal source via the quarantined MediaRemote adapter. |
| `SystemAudioService` | HUD, Media | CoreAudio default output device volume and mute, with property listeners. |
| `DisplayBrightnessService` | HUD | Built-in display brightness. Private `DisplayServices` behind a capability check (R2). |
| `KeyboardBacklightService` | HUD | Private `CoreBrightness`. Hidden when the hardware has no backlight keys (R2). |
| `MediaKeyService` | HUD | `CGEventTap` on system-defined events, which consumes the event to suppress the system HUD. Needs Accessibility. |
| `PowerService` | Battery | IOKit `IOPSNotificationCreateRunLoopSource`. Event driven, no permission. |
| `CalendarService` | Calendar | EventKit, with `requestFullAccessToEvents` and `requestFullAccessToReminders` (macOS 14+). `EKEventStoreChanged` drives updates. |
| `FileShelfService` | Shelf | App-support storage. Copies or references, plus security-scoped bookmarks if we are ever sandboxed. |
| `SharingService` | Shelf | `NSSharingService(named: .sendViaAirDrop)`, Quick Look `QLPreviewPanel`. |
| `PermissionService` | all | Status and request per `PermissionKind`. Status changes are re-checked on app activation, because TCC has no change notifications. |

### 5.2 Lifecycle

`ServiceRegistry` creates a service on its first `acquire`, calls `start()`, and calls `stop()` and drops it on the last release. Modules never hold leases directly. `ModuleContext.acquire` records them, and the host returns all of them on deactivate.

### 5.3 Concurrency (Swift 6 strict mode)

- UI, shell, `ModuleHost`, modules: `@MainActor`.
- Services do blocking or chatty work (ScriptingBridge calls, artwork decoding, the MediaRemote adapter subprocess, EventKit queries) inside their own `actor` or on a private serial executor, and publish to the main actor.
- Cross-boundary payloads are `Sendable` value types. No `@unchecked Sendable` without a written justification in the code.

### 5.4 Private API quarantine

Everything unsupported lives in one target, `PlatformBridges`, behind protocols from `ServicesAPI`:

1. **Capability probe at runtime**, never an OS version check alone. If the symbol is missing or the self-test fails, the bridge reports `unavailable` and the service falls back.
2. **Kill switch:** a per-bridge setting under Settings → Advanced → Compatibility.
3. **Descriptor flag:** `usesPrivateAPI = true` is shown in Settings.
4. `dlopen`/`dlsym` only. No linking against private frameworks, so a removed framework can't crash at launch.

---

## 6. Module protocol

Two layers: `ModuleLifecycle` lives in NotchCore so it can be tested without UI, and `NotchModule` in NotchModuleKit adds the SwiftUI surfaces.

```swift
// NotchCore
@MainActor public protocol ModuleLifecycle: AnyObject {
    func activate(context: ModuleContext) async throws   // start work here, never in init
    func deactivate() async                                // idempotent; must leave nothing running
}

public struct ModuleDescriptor: Codable, Sendable {      // readable without constructing the module
    id, name, summary, symbolName, surfaces, permissions, services,
    defaultPriority, enabledByDefault, usesNetwork, usesPrivateAPI
}

// NotchModuleKit
@MainActor public protocol NotchModule: ModuleLifecycle {
    func compactView(for: LiveActivity, side: CompactSide) -> AnyView?  // nil → host renders ActivityContent
    func expandedView() -> AnyView?
    func panelView() -> AnyView?
    func lockScreenView() -> AnyView?          // Phase 3
    static func settingsView() -> AnyView?     // static: shown while the module is disabled
}

// What a module can do. Scoped to that module and invalidated on deactivate.
ModuleContext.publish(key:content:priority:lifetime:requestsPeek:)
ModuleContext.withdraw(key:)
ModuleContext.acquire(ServiceKey<S>) -> S?
```

Mapping to the brief: *id, name, permissions, compact view, expanded view, optional lock screen view, settings view, priority* are all present. *Priority* is `defaultPriority` on the descriptor, overridable per activity.

Module rules (also in the protocol's doc comment):

1. No work in `init`.
2. All system access goes through services.
3. Views read module state. No polling inside views.
4. `TimelineView` and animation only while on screen.
5. Return a view only for a surface declared in the descriptor.

---

## 7. Live activity arbitration

`ActivityBoard` (pure value type) holds every activity from every module. `resolve(now:policy:)` returns a **primary**, an optional **secondary** (split island, always from a different module) and `nextChange`.

Ordering, most important first:

1. `.critical` (calls, agent approvals) beats everything, including a pin.
2. The user-pinned module.
3. Priority class: background < low < normal < high < critical.
4. Transient beats ongoing within a class. Examples: AirPods connected, charger plugged in, a HUD change.
5. User module ranking. This is the Settings layout editor, and it only reorders *within* a class.
6. Most recently started.
7. ID, so ties never flicker.

Worked examples. Music + download: music primary, download secondary. Music + charger plugged in (transient): charging for 3 s, then music again. Music + incoming call: call primary, music secondary, even with music pinned.

**Media source choice is a separate concern.** "Which player does the Media module follow when two are playing?" is decided inside `NowPlayingService` by policy: most recent, a preferred app, or manual. The Media module publishes one activity.

---

## 8. Settings and persistence

- `SettingsStore` is a typed, `Codable` `AppSettings` document with a `schemaVersion`, stored in `UserDefaults` under one key. Writes are debounced.
- Sections: `behavior: IslandBehavior`, `layout: IslandLayout`, `appearance`, `arbitration: ArbitrationPolicy`, `modules: [ModuleID: ModuleSettings]`, `displays: [DisplayUUID: DisplaySettings]` (tuning, visibility, full-screen behaviour), `shortcuts`, `bridges` (private-API kill switches).
- Module-specific settings are namespaced (`modules[id].values`) so a module can't overwrite another's.
- Import/export uses the same JSON. Decoding is tolerant: unknown keys are ignored and missing keys take defaults. Migrations are keyed by `schemaVersion`. Exports never contain shelf files, notes or clipboard content, only preferences.
- Keyboard shortcuts: a Carbon `RegisterEventHotKey` wrapper, which needs no permission. Avoid a third-party dependency unless it is MIT.

---

## 9. Appearance

| Style | macOS 26+ | macOS 14.6–15 |
|---|---|---|
| **Classic black** | Solid black, continuous-corner shape that matches the hardware notch | Same |
| **Liquid Glass** | Native SwiftUI `glassEffect` / `GlassEffectContainer` (AppKit `NSGlassEffectView`), behind `if #available(macOS 26, *)` | Fallback: `NSVisualEffectView` (behind-window blur, `.hudWindow` material) plus a drawn specular rim gradient and inner shadow. It reads as glass but isn't refractive. Documented as an approximation. |
| **Dynamic Glass** | **[Decision — Q4]** Proposed: glass tinted live by a palette from current artwork, or from the wallpaper when nothing plays. The tint is computed once per track off-main. | Same, on the fallback glass |

Rules:

- On a hardware notch, the top band of the island stays opaque black whatever the style, so the camera housing never shows through glass.
- Respect *Reduce Transparency*: switch to classic black. Respect *Reduce Motion*: cross-fade instead of spring.
- Building with the Xcode 26 SDK needs Xcode 26 on the build machine and CI. Deployment target stays at 14.6.

---

## 10. Permissions model

- First launch: **zero** permissions. Defaults are Battery, Media (read-only path) and the Shelf, none of which need one.
- Enabling a module that needs permissions opens an in-app sheet with the reason from the descriptor, then triggers the system prompt. The module activates only on grant. On deny, the module stays off and shows a "Open System Settings" deep link.
- Optional permissions (`isRequired: false`) are requested inline the first time the user touches the feature. Example: pressing Play when Automation for Spotify is needed.
- `PermissionService` re-checks on `NSApplication.didBecomeActiveNotification`. If a permission is revoked, the dependent module is deactivated and badged in Settings.

Phase 1 permission map:

| Module | Permission | Required? |
|---|---|---|
| Media | Automation → Music, Spotify (controls) | Optional |
| Media | none for the universal source (adapter) | — |
| HUD | Accessibility (event tap that consumes media keys) | Required |
| Battery | none | — |
| Shelf | none (Accessibility only if the global drag monitor ships) | Optional |
| Calendar | Calendars, Reminders (full access) | Required |

---

## 11. Performance budget and measurement

| Metric | Target | How measured |
|---|---|---|
| Idle CPU, core modules on, nothing playing | < 1% | Activity Monitor "% CPU" averaged over 5 min, plus Instruments Time Profiler. Run in CI-like manual script `docs/testing/PERF.md` (Phase 1). |
| Idle CPU, music playing, island collapsed | < 1% | Same. Visualizer paused when not visible. |
| Memory, core modules on | < 150 MB | Instruments Allocations, physical footprint (`footprint` CLI) |
| Expand animation | < 16 ms per frame, no hitches | Instruments *Animation Hitches* template on a 120 Hz ProMotion display, 50 expand/collapse cycles |
| Cold launch to island visible | < 500 ms (proposed) | `os_signpost` intervals |

Every service and the shell emit `os_signpost` intervals under the subsystem matching the bundle ID (D9). Performance numbers are reported per module, as the brief asks.

---

## 12. Distribution

**Decided:** free, downloaded from GitHub. No paywall, no licence keys, no trial code.

### Channel

| What | Where |
|---|---|
| App download | GitHub Releases. Each release has `UltiNotch-x.y.z.dmg` (drag to Applications) and `UltiNotch-x.y.z.zip` (used by Sparkle). |
| Download link in README | `https://github.com/vannaenae/Ulti-notch/releases/latest`, a stable link that always points at the newest release |
| Auto-updates | Sparkle 2 (MIT). Feed URL baked into the app: `https://github.com/vannaenae/Ulti-notch/releases/latest/download/appcast.xml`. GitHub redirects that URL to the newest release's asset, so there's nothing extra to host. **This URL is permanent once a build ships**; renaming or moving the repo means older installs stop seeing updates unless the redirect holds. |
| One-line install (later in Phase 1) | Own Homebrew tap: `brew install --cask vannaenae/tap/ulti-notch`. The release workflow updates the cask. The official homebrew-cask repo can come later once the project meets its notability rules. |

### Release pipeline (`.github/workflows/release.yml`, built with the Phase 1 signing step)

Triggered by pushing a tag `vX.Y.Z`, on a GitHub macOS runner:

1. Build and archive with Xcode 26 (Release, hardened runtime).
2. Sign with the Developer ID Application certificate, imported into a throwaway keychain from a repo secret.
3. Notarise with `notarytool` using an App Store Connect API key (secret), then staple.
4. Package: DMG via `hdiutil`, zip via `ditto`.
5. Sign the update with Sparkle's `sign_update` (EdDSA private key from a secret) and generate `appcast.xml`.
6. Create the GitHub Release with DMG, zip, appcast and notes taken from `CHANGELOG.md`.
7. Bump the Homebrew cask.

Repo secrets needed (you add them; they never appear in code or logs):

- `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`
- `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`
- `SPARKLE_ED_PRIVATE_KEY`

### Why the Apple Developer Program still matters for a free app

"Free and easy to download" depends on it:

- **Gatekeeper.** Un-notarised apps downloaded from the internet are blocked on open. On recent macOS the user has to go to System Settings → Privacy & Security → Open Anyway. That's a hard stop for most people.
- **Permissions survive updates.** macOS ties Accessibility and Automation grants to the app's code signature. With a stable Developer ID, an update keeps them. With ad-hoc signing, the identity changes every build, so users would have to re-grant Accessibility (needed by the HUD module) after **every** update.
- **Cost:** the Apple Developer Program is a paid annual membership. That's the only running cost of this distribution model; GitHub Releases and Actions are free on a public repo.

Fallback if there's no account at first: ad-hoc signed builds, with a README section explaining Open Anyway, labelled "preview". Sparkle still works because it verifies with EdDSA, not Apple signing. Not recommended beyond early testers.

### Other

- **Not sandboxed.** **[Decision]** Event taps that consume events, Apple Events to other apps, launching the MediaRemote adapter, and Phase 3 window management and terminal all conflict with App Sandbox. App Store distribution is already out of scope.
- Hardened runtime entitlements, minimal set: `com.apple.security.automation.apple-events` (Music and Spotify control). Nothing else is planned for Phase 1. The adapter runs as a child process under `/usr/bin/perl` and needs no entitlement on our side.
- Signing material and the Sparkle private key never enter the repo (`.gitignore` covers common files).

---

## 13. Extension system (Phase 4) — what we design for now

- **Out of process.** Third-party code never runs inside our address space. The candidate host technology is **ExtensionKit** (macOS 13+): the app defines an extension point, and plugins ship as signed app extensions. Fallback: an XPC service per plugin. A spike in Phase 4 decides.
- **Data, not views, by default.** Plugins send `ActivityContent` (Codable) and declarative expanded layouts built from host-owned components. ExtensionKit's remote view hosting is an option for richer UI, but it's an opt-in tier.
- **Same descriptor.** Plugins ship a `ModuleDescriptor` as a manifest. `ModuleID.isWellFormed` already accepts third-party reverse-DNS prefixes.
- **Capability-scoped services.** Plugins request services by `ServiceKey` and the host checks the declared `services` list. Nothing undeclared is reachable.

---

## 14. Folder structure

```
Ulti-notch/
├── README.md
├── CHANGELOG.md
├── project.yml                      # XcodeGen spec (Phase 1). The .xcodeproj is generated, not committed. [Decision]
├── App/                             # Phase 1
│   ├── UltiNotchApp.swift           # composition root: registers services and modules
│   ├── AppDelegate.swift
│   ├── Info.plist                   # usage descriptions, LSUIElement
│   ├── UltiNotch.entitlements
│   └── Assets.xcassets
├── Packages/
│   └── UltiNotchKit/
│       ├── Package.swift
│       ├── Sources/
│       │   ├── NotchCore/           # ✅ built: contracts, state machine, arbitration, geometry, host
│       │   ├── NotchModuleKit/      # ✅ built: NotchModule SwiftUI protocol
│       │   ├── NotchUI/             # Phase 1: island shape, materials, glyph renderer, components
│       │   ├── NotchShell/          # Phase 1: IslandPanel, IslandController, DisplayManager, Suppression
│       │   ├── ServicesAPI/         # Phase 1: service protocols + value types
│       │   ├── ServicesLive/        # Phase 1: system implementations
│       │   ├── PlatformBridges/     # Phase 1: private-API quarantine (dlopen only)
│       │   ├── Settings/            # Phase 1: SettingsStore, schema, migrations, Settings UI
│       │   └── Modules/
│       │       ├── MediaModule/
│       │       ├── HUDModule/
│       │       ├── BatteryModule/
│       │       ├── ShelfModule/
│       │       └── CalendarModule/
│       └── Tests/
│           ├── NotchCoreTests/      # ✅ built
│           ├── ServicesTests/       # services against fakes
│           └── ModuleTests/         # descriptor rules for every first-party module
├── Resources/
│   └── MediaRemoteAdapter/          # only if Q1 = yes; vendored with licence
├── scripts/                         # release.sh (build, sign, notarise, staple, DMG, appcast)
├── docs/
│   ├── ARCHITECTURE.md              # this file
│   ├── SCOPE.md                     # scope, assumptions, open questions
│   ├── RISKS.md                     # technical risk research
│   ├── TECH_DEBT.md
│   ├── THIRD_PARTY.md               # licences (from first dependency)
│   ├── spikes/                      # parked-feature feasibility reports
│   └── testing/
│       ├── MANUAL_TEST_CHECKLIST.md
│       └── PERF.md
└── .github/workflows/ci.yml         # macOS runner: swift build + swift test
```

Each module is its own SwiftPM target. That gives four things:

1. The compiler enforces the dependency rules (modules → `NotchModuleKit` + `ServicesAPI` only).
2. Incremental builds stay fast.
3. A module can be deleted without touching the others.
4. The same boundaries become the plugin SDK later.

---

## 15. Testing strategy

- **Unit (CI):** NotchCore today. Then services against injected fakes (e.g. a fake `IOPS` snapshot provider, a fake EventKit store), settings migrations and import/export round-trips, and a descriptor-rules test over every first-party module.
- **Manual (per release):** `docs/testing/MANUAL_TEST_CHECKLIST.md` covers display hot-plug, sleep/wake, Spaces, full screen, Stage Manager, and each module.
- **Performance:** a scripted Instruments pass per module, with results logged per module in the CHANGELOG entry.

## 16. Decision log

| # | Decision | Status |
|---|---|---|
| D1 | SwiftPM package for all logic, thin app target, XcodeGen for the project file | Proposed |
| D2 | Not sandboxed; Developer ID + notarisation | Proposed (follows from feature set) |
| D3 | Window is fixed-size envelope; SwiftUI animates the shape | Adopted |
| D4 | `hidden` added as a fifth island state | Adopted |
| D5 | Private APIs only in `PlatformBridges`, dlopen + runtime probe + kill switch | Proposed — Q1 |
| D6 | Plugins out of process; activities are declarative data | Adopted for protocol design; tech choice in Phase 4 |
| D7 | Swift Testing for new tests | Adopted |
| D8 | Free app; distributed via GitHub Releases; Sparkle feed at `releases/latest/download/appcast.xml` | Decided (owner) |
| D9 | Bundle ID `io.github.vannaenae.UltiNotch` (standard reverse-DNS for a GitHub-hosted project without its own domain) | Proposed — confirm before first signed build |
| D10 | Release automation via tagged GitHub Actions workflow; Homebrew tap | Proposed |
