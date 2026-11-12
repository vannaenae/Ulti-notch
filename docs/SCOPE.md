# Scope, assumptions and open questions

## Scope (restated)

**Product.** A native macOS utility that turns the notch into a Dynamic Island-style command surface. It sits collapsed at the notch, expands on hover, click, swipe or shortcut, and hosts live activities, widgets and utilities. On Macs without a notch and on external displays, it becomes a floating island at the top centre of each screen.

**Positioning.** One quiet, fast, native app that replaces a dock full of utilities.

**Phase 1 (MVP) delivers:**

- Island shell on every display, with hardware notch detection and a floating fallback.
- State machine: hidden, collapsed, peek, expanded, panel.
- Appearance: classic black, Dynamic Glass, Liquid Glass.
- Media: Now Playing (Apple Music, Spotify, YouTube Music, any Now Playing source) with artwork, scrubbing, controls, a visualizer and source choice.
- HUD replacement: volume, brightness, keyboard backlight.
- Battery and charging live activity.
- File shelf: drag in and out, AirDrop, Quick Look.
- Calendar and Reminders: today view, month grid, next-meeting countdown.
- Settings window, onboarding, permission flow.
- Signing, notarisation, Sparkle updates.

**Phases 2–4 and the parked spikes** are out of scope until Phase 1 meets its definition of done.

**Definition of done (per phase):**

- Runs on a notch MacBook and a non-notch external display.
- Each module toggles off with no residual CPU.
- No crashes across sleep, wake, display changes and Space switches.
- Performance targets met and measured in Instruments.
- Settings persist across launches.

## Assumptions

Each assumption is reversible unless marked ⚠︎.

1. **Single developer account, outside the Mac App Store.** You have, or will get, an Apple Developer Program membership for Developer ID signing and notarisation. Notarisation isn't possible without one.
2. ⚠︎ **Not sandboxed.** Event taps, Apple Events, the Now Playing adapter and later window management all conflict with App Sandbox. MAS is already excluded, so this costs nothing.
3. **Apple silicon only for Phase 1.** Intel is untested and gets no special code. Phase 1 has no Apple-silicon-only API, so an Intel build may work. That isn't promised.
4. **macOS 14.6 minimum, built with the Xcode 26 SDK** so native Liquid Glass is available on macOS 26+.
5. **SwiftPM for all logic, a thin app target, XcodeGen** for the project file. Reviewable diffs, no hand-edited `.pbxproj`.
6. **Swift Testing** for unit tests. Requires Xcode 16+.
7. **Free, permanently** (decided). No licensing, trial or payment code. Distributed from GitHub Releases with Sparkle auto-updates.
8. **No analytics, no telemetry.** Crash reports only via Apple's opt-in system reports, unless you decide otherwise.
9. **Agent-built code is verified by CI and by you on hardware.** This session can't run macOS. Anything UI, permission or performance related is "built, not verified" until you run it.
10. **English only** until Phase 4. Strings go through `String(localized:)` from day one, so localisation later is mechanical.
11. **YouTube Music means the website** in Safari or Chrome, not a third-party desktop wrapper.
12. **Default-on modules at first launch:** Battery, Media (read-only), Shelf. Everything that needs a permission is opt-in.

## Open questions (blocking Phase 1)

**Q1. Private API policy.** Universal Now Playing (anything a browser plays, including YouTube Music) needs the private MediaRemote framework through a community workaround. Built-in display brightness and keyboard backlight need private DisplayServices and CoreBrightness. Without them, Media covers only Apple Music and Spotify, and the HUD covers volume only.
*Proposal:* allow them, quarantined in one target, loaded at runtime with a self-test, labelled "Experimental" in Settings, with a kill switch and automatic fallback. *Yes / no / per item?*

**Q2. Identity** (hard to reverse once shipped). ~~Update hosting~~ answered: GitHub Releases.
(a) Do you have, or will you get, an Apple Developer Program membership? A free app still needs it to install without Gatekeeper warnings and to keep permissions across updates (ARCHITECTURE §12).
(b) Bundle ID. Proposal: `io.github.vannaenae.UltiNotch`. Changing it later resets every user's permissions and settings. OK?

**Q3. Test hardware and tooling.**
(a) Which notch MacBook, and which macOS versions can you test on?
(b) Do you have a non-notch external display?
(c) Is Xcode 26 installed?
(d) The repo had no branches, so this work branch is currently its only branch, which makes it the default. May I create `main` from it as the base for pull requests?
(e) The repo is **public**. That means free macOS CI minutes, but also that everything committed is visible, including these docs. Intended?

**Q4. "Dynamic Glass".** What do you mean by it?
*Proposal:* glass tinted live from the current artwork, or the wallpaper when nothing plays. Liquid Glass is Apple's macOS 26 material (native on 26+, approximated on 14–15). Confirm, or describe what you want.

**Q5. Licence.** ~~Business model~~ answered: free, downloaded from GitHub.
Free to download is not the same as open source. The repo is public but has no licence, which legally means "look, don't reuse". Options:
- **MIT or Apache-2.0:** anyone can use, fork, even sell it. Best for contributors and the Phase 4 plugin ecosystem. *Recommended.*
- **GPL-3.0:** forks must stay open source.
- **No licence:** source visible, all rights reserved.
Publishing code under an open licence can't be withdrawn for versions already released, so I won't add one without your call.
