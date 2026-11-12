# Scope, assumptions and open questions (v2 brief)

## The brief, restated

Ulti Notch is a Dynamic Island for the Mac that matches Droppy feature for feature and beats it on intuitiveness. **Feature parity is the floor. Intuitiveness is the product.** A new user gets value within 30 seconds without opening Settings.

The 10 intuitiveness principles override feature requests:

1. Zero-config first run
2. Context over configuration
3. One gesture vocabulary
4. Progressive disclosure
5. Discoverable, not memorised (command palette)
6. Learn from use
7. Settings that explain themselves (search, presets)
8. Calm by default
9. Everything undoable
10. Fast (expand < 100 ms, idle CPU < 1%)

Every feature passes them before it ships.

Phase 1 is the shell plus "the 80%":

- Shell, state machine, priority engine, appearance styles, non-notch fallback
- Now Playing with queue and lyrics
- File tray with transform
- Clipboard history
- HUDs
- Calendar and Reminders
- Command palette
- Settings with search and presets
- Onboarding
- Signing and Sparkle

Feature-by-feature plan and proposed cuts: [`PHASE1_PLAN.md`](PHASE1_PLAN.md). **Needs your approval before any feature code.**

**Added by you:** a meeting helper that screen sharing can't see. Planned for Phase 2 alongside Meetings and Teleprompter. The technical limits are in [`RISKS.md`](RISKS.md) R9.

## Decided

| Topic | Decision |
|---|---|
| Price | Free |
| Distribution | GitHub Releases, Sparkle auto-update, Homebrew tap (ARCHITECTURE §12) |
| Licence | Open source, **MIT**. Switching licence is still cheap before the first release, because only you hold copyright so far. |
| Dynamic Glass | Per the v2 brief: solid black at the notch, melting into glass below. Liquid Glass is Apple's native material on macOS 26+, with a fallback on 14 and 15. Solid style in Low Power Mode. |
| Extensions | Called **modules**, first-party or third-party. We don't reuse Droppy's term "Droplets". |

## Assumptions

1. **Not sandboxed, outside the App Store.** The feature set (event taps, Apple Events, window snapping, terminal) rules out the sandbox.
2. **Apple silicon first**, macOS 14.6 minimum, built with the Xcode 26 SDK.
3. **Droppy behaviour comes from public listings, reviews and your brief.** I haven't used it on a device. Each "how Droppy does it" line is marked accordingly. Installing Droppy and checking those lines is a cheap step before approving the plan.
4. **No Droppy code, assets or wording is used.** It's a closed product, and its older open-source versions are not used either. Behaviour is studied, the code is original.
5. **Native frameworks before dependencies.**
   - AVFoundation for video and audio transforms. FFmpeg only if a format gap appears.
   - ImageIO for images; `ditto` / Apple Archive for zip; `NSDataDetector` for natural-language dates.
   - Carbon hotkeys for shortcuts, which need no permission.
6. **No telemetry.** "Learn from use" (principle 6) is computed and stored on device only.
7. **The agent can't run macOS.** Code is verified by CI (`swift test` on a macOS runner) and by you on hardware.

## Open questions (blocking Phase 1)

**Q1. Private APIs.** Should I use private APIs, behind an off switch with automatic fallback, for:
- Universal Now Playing (YouTube Music in a browser, any player)
- Built-in display brightness and keyboard backlight

Without them, Media covers Apple Music and Spotify only, and the HUD covers volume only. Droppy almost certainly relies on similar routes. My recommendation is yes.

**Q2. Apple Developer membership and bundle ID.**
- A free app still needs the membership to install cleanly, and to keep permissions across updates.
- Bundle ID proposal: `io.github.vannaenae.UltiNotch`. It's permanent once shipped. OK?

**Q3. Hardware and branch.**
- Which notch MacBook, which macOS versions, and is there an external display?
- Is Xcode 26 installed?
- May I create `main` so work goes through pull requests?

**Q4. Phase 1 cuts.** Two Phase 1 items can't be built well with supported APIs today. My proposal is to move them to Phase 2. See `PHASE1_PLAN.md`.
- **Reordering the music queue:** neither Apple Music nor Spotify exposes it to other apps.
- **Synced lyrics:** they need a network lyrics source, which means an opt-in.

**Q5. Meeting helper.**
- **What it shows:** your own notes and talking points? An agenda with a timer? Live transcription?
- **Limit to accept:** it will be hidden when you share a single window, and from older capture methods. It **can't** be guaranteed hidden when you share your entire screen on macOS 15 or later. Details in RISKS R9.
