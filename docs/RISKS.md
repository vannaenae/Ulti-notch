# Known technical risks

Research date: 12 Nov 2026. Sources are listed per risk. Where something could not be verified, it says so. Re-check R1 and R2 against each macOS beta. Both depend on behaviour Apple doesn't document.

Confidence key: **High** = documented public API or well established. **Medium** = consistent community reports, not documented by Apple. **Low** = single source or inferred.

---

## R1. Now Playing data (highest risk)

### Current state

- **There is no public API to read another app's Now Playing info on macOS.** `MPNowPlayingInfoCenter` only lets an app *publish* its own. (High)
- **Since macOS 15.4, the private `MediaRemote` framework only returns Now Playing data to Apple-signed processes.** Third-party apps calling `MRMediaRemoteGetNowPlayingInfo` directly get nothing. Community reports say this is still true on macOS 26. (Medium)
- **The working community path is to load a small framework into `/usr/bin/perl`.** That binary is Apple-signed and still allowed, and the framework streams Now Playing as JSON lines to the parent app. This is the approach of `ungive/mediaremote-adapter`, and it's used by nowplaying-cli 2.x, LyricFever, boring.notch and Music Presence on 15.4 through 26.x. (Medium)
- **Fragility:** it depends on Apple not closing the `/usr/bin/perl` allowance. At least one project reports the adapter's self-test failing on some system version. (Medium)
- **Control is weaker than reading.** An open upstream issue reports that commands go to whichever app macOS has elected as "now playing", not a chosen app. (Low: one report, and it references a macOS 27 build I could not verify.)
- **I could not verify behaviour on the current macOS 27 betas.** Treat this as unknown until tested.

### Options

| Path | Covers | API status | Permission | Durability |
|---|---|---|---|---|
| **A. Per-app, supported**: Music.app and Spotify distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) for state, plus ScriptingBridge/AppleScript for artwork, position and controls | Apple Music, Spotify | Public (notifications are undocumented but long-standing; AppleScript dictionaries are public) | Automation per app, needed for controls and artwork only | High |
| **B. Universal, private**: MediaRemote via the perl adapter | Anything that publishes Now Playing, including browsers (YouTube Music in Safari or Chrome), Podcasts, VLC | Private framework, workaround | None | Medium–low; can break in any macOS update |
| **C. Browser extension** | YouTube Music and other web players | Public | Extension install | High, but heavy: three browsers, three stores |
| **D. App-specific APIs** | e.g. desktop YouTube Music wrappers with a local API | Third party | None | Varies |

### Recommendation

1. Build `NowPlayingService` as a **composite of sources** with a common `NowPlayingSnapshot` model. The source-selection policy (most recent, preferred app, manual) lives in the service, which gives "choose which source to follow when two play".
2. **Ship A as the baseline.** It is supported and always available.
3. **Ship B in `PlatformBridges` behind a runtime self-test and a user kill switch.** It's the only path that covers YouTube Music in a browser, and it needs **zero permissions**, which also makes Media viable as an on-by-default module. **This needs your sign-off (Q1).** It's a private-API dependency, and the adapter's licence must be checked before vendoring. My understanding is that it's permissive, but that is not yet verified.
4. Defer C to Phase 2 unless YouTube Music usage proves to be high.
5. **Automated canary:** a manual-checklist item to run the adapter self-test on every macOS beta. In app, if the self-test fails, the service drops to A and shows a one-line notice in Media settings.

**Artwork.** A delivers artwork via AppleScript. Spotify gives a URL, which is a network fetch, so it is only done because the user enabled Spotify artwork, and it is cached. B delivers artwork bytes.

**Audio visualizer.** Real spectrum data needs system-audio capture: Core Audio process taps (macOS 14.2+) or ScreenCaptureKit, both behind the Screen & System Audio Recording permission. Default to a procedural, beat-free animation driven by play state. Offer the real visualizer as an opt-in with its own permission. That keeps first launch at zero permissions.

Sources: [cmux PR on bundling the MediaRemote adapter](https://github.com/manaflow-ai/cmux/pull/21695) · [mediaremote-adapter issue #41](https://github.com/ungive/mediaremote-adapter/issues/41) · [Browser Now Playing issue listing adapter users](https://github.com/lucacadalora/oyenza-studio/issues/116) · [AppleScript/JXA Now Playing scripts for 15.4+](https://gist.github.com/SKaplanOfficial/f9f5bdd6455436203d0d318c078358de)

---

## R2. HUD replacement (suppressing the system OSD)

### Current state

- **On macOS 26 Tahoe, Apple redesigned the volume and brightness indicator and moved it to the top menu bar area.** That puts it right next to where our island lives, so leaving it visible would look like a collision. (Medium: user reports)
- **The old trick of killing or reverse-engineering `OSDUIHelper` no longer works on Tahoe.** Developers report that the process is gone, and Apple's forum thread asking what replaced it has no answer. (Medium)
- MonitorControl reports limited native OSD integration on Tahoe. (Medium)

### Recommended approach: own the keys, don't fight the HUD

1. `MediaKeyService` installs a `CGEventTap` for system-defined events (media keys: volume, mute, brightness, keyboard backlight) and **consumes** them. The system never handles the key, so it never draws its HUD. Version-independent, because no system process is touched.
2. We then apply the change ourselves:
   - **Volume / mute:** CoreAudio on the default output device. Public API. (High) Respect devices without a volume control: some USB and HDMI outputs report it as not settable. In that case let the event pass through.
   - **Built-in display brightness on Apple silicon:** no public API. The established route is private `DisplayServices` (`DisplayServicesGetBrightness` / `SetBrightness`), in `PlatformBridges` with a probe. (Medium)
   - **External display brightness:** DDC/CI, private and hardware dependent. **Out of Phase 1.** Let those keys pass through to the system.
   - **Keyboard backlight:** private `CoreBrightness`. Note that MacBook keyboards since 2021 have no backlight function keys (F5 and F6 are Dictation and Focus), so this HUD mostly matters for ambient changes and older Macs. (Medium)
3. Also replicate the modifier behaviour users rely on: Option+Shift for fine steps, and Option+key to open the matching System Settings pane.
4. **Permission:** an event tap that *modifies or swallows* events needs **Accessibility**. HUD is therefore **opt-in**, with the reason "Replace the system volume and brightness indicator with the island".
5. **Failure mode:** if the tap is disabled by the system (timeout or user input), re-enable it on `tapDisabledByTimeout`. If Accessibility is revoked, uninstall the tap so keys reach the system again. A key must never be swallowed without being applied.

Sources: [Apple Developer Forums: OSDUIHelper on Tahoe](https://developer.apple.com/forums/thread/804054) · [MonitorControl README](https://github.com/MonitorControl/MonitorControl) · [Many Tricks: Hudlum blog post](https://manytricks.com/blog/?p=6623) · [MacRumors thread on new indicators](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210)

---

## R3. Window level, full screen, Spaces, Stage Manager

- Approach and settings are in ARCHITECTURE §3.2 and §3.4: `NSPanel` above the menu bar level, `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`, and a fixed envelope frame. (High: public API; exact level to validate on hardware)
- **Risk:** the macOS 26 transparent menu bar and new HUD placement may change how the island looks over the menu bar. Test on 14, 15 and 26.
- **Risk:** detecting full screen for *other* apps has no direct API. Using window-list bounds avoids Screen Recording permission, but has edge cases: split view, and full-screen video in a browser tab that isn't a native full-screen Space. Each gets a checklist entry.
- **Risk:** several displays with "Displays have separate Spaces" turned off. Test both settings.
- **Mitigation:** every case is a row in `docs/testing/MANUAL_TEST_CHECKLIST.md`. The shell's state machine is unit tested independently of AppKit.

---

## R4. Liquid Glass on older macOS

- Native Liquid Glass (SwiftUI `glassEffect`, `GlassEffectContainer`; AppKit `NSGlassEffectView`) is macOS 26+ and needs the Xcode 26 SDK to build. (High)
- **Fallback for 14.6–15:** `NSVisualEffectView` behind-window blur plus a drawn rim highlight and inner shadow. It isn't refractive, so we label it "Glass" in Settings on those systems, not "Liquid Glass". Details are in ARCHITECTURE §9.
- **Risk:** building with the Xcode 26 SDK changes default system control styling on macOS 26. Review Settings window appearance on both.
- **Risk:** glass over a hardware notch shows the camera cut-out. Mitigation: the top band is always opaque black.

---

## R5. Permission sprawl

- Rule enforced in code: `ModuleDescriptor.validationIssues` rejects any module that is on by default but has a *required* permission. Unit tested.
- Default-on set for first launch: **Battery, Media (path A metadata + path B if approved), Shelf**. Zero permission prompts.
- Permission-gated and opt-in: HUD (Accessibility), Calendar and Reminders, media controls (Automation, requested on first Play press), real visualizer (screen and system audio recording).
- Revocation is handled: re-check on app activation, deactivate the module and badge it in Settings.

---

## R6. Build and verification environment (process risk)

- The cloud session this work is produced in runs Linux with no Swift toolchain and no route to download one. **Nothing here has been compiled locally.**
- Mitigation: GitHub Actions on `macos-15` builds and tests `UltiNotchKit` on every push. UI, shell, permissions and performance can only be verified on your Mac. The checklist and Instruments steps are written for that.
- Cost note: on a private repo, macOS runner minutes are billed at a multiple of Linux minutes. The workflow is path-filtered and cancels superseded runs to keep usage low.
