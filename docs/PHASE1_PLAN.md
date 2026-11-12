# Phase 1 plan: Droppy parity, less to learn

**Status: awaiting your approval.** Nothing here gets built until you say go.

The "Droppy" column comes from your brief and public listings. It is not verified on a device.

"Simpler" names the specific thing the user no longer has to learn, set or remember.

## One gesture vocabulary (applies to every row)

| Gesture | Means everywhere |
|---|---|
| Hover | Peek |
| Click | Expand |
| Two-finger swipe left/right | Switch module page |
| Swipe down/up | Full shelf / back |
| Drag | Drop in or out |
| Long-press | Actions for the thing under the pointer |
| ⌘⇧Space (rebindable) | Command palette, the only shortcut anyone needs |

## Features

| # | Feature | Droppy (per listings) | Ulti Notch: simpler how | First-time discovery |
|---|---|---|---|---|
| 1 | Island shell + non-notch fallback | Notch shelf; also menu bar, window or floating shelf on any Mac | One surface on every display, top centre. No choice of placement mode to make. | It's just there |
| 2 | States and gestures | Hover opens the shelf; many feature-specific shortcuts | The fixed gesture table above, the same in every module. No per-module gestures. | Onboarding screen 2 shows hover, click and drag |
| 3 | Priority engine | Live activities; which one shows depends on settings | Automatic: call > meeting starting soon > finishing download > music > ambient. A pin is the only override, via long-press → "Keep showing". | Never needed; pin appears in the long-press menu |
| 4 | Appearance | Dynamic Glass, Liquid Glass, solid in low battery; highlight colour, shape | Three styles with a live preview. Accent follows the system accent colour. Solid in Low Power Mode is automatic. No shape editor in Phase 1. | Settings → Appearance, preview updates live |
| 5 | Now Playing | Animated artwork, beat-following waveform, many players | One module, auto-follows the player you touched last. No source picker unless two are actually playing. Waveform is animated, not beat-following; the real one needs a screen-audio permission. | Starts the first time music plays |
| 6 | Playing Next queue | Queue with reorder | **Proposed to move to Phase 2.** Apple Music and Spotify don't expose queue reorder to other apps (RISKS R1). | — |
| 7 | Synced lyrics | Line and word level | **Proposed to move to Phase 2.** Needs a network lyrics source (opt-in) and timing alignment. | — |
| 8 | File tray | Drag files to top of screen, hold them, drag out later | Drag anything toward the notch and it opens. Drag out to use, and the item leaves the tray. "Keep" is a long-press option, not a mode. Removing an item can be undone. | The island visibly reacts the first time a drag starts |
| 9 | Transform | Drop a file, choose what it becomes | Long-press a tray item shows only conversions that make sense for that file type, with output size shown before converting. Native frameworks only, no FFmpeg. | Long-press hint on the first tray item |
| 10 | Clipboard history | Text, links, colours, code, images; search, pin | Same content types. Palette search covers it. Items copied from password managers are never stored. "Clear" can be undone for 10 s. | Palette: type "clip"; first-use tip after the 3rd copy |
| 11 | HUDs | Redesigned volume, brightness, keyboard backlight | The HUD *is* the island: it grows from the notch, no separate overlay. Opt-in, because it needs Accessibility. | Offered once, the first time the user presses a volume key |
| 12 | Calendar & Reminders | Natural-language task entry | One input field: type "dentist fri 3pm". Text with a date or time becomes an event, text without becomes a reminder. Uses native date parsing. | Next-meeting countdown appears on its own once Calendar access is granted |
| 13 | Command palette | Launcher is Phase 3 in your brief | **Phase 1, because it's the discoverability backbone.** One shortcut finds every module action, setting and toggle, including for modules that are off ("Enable Clipboard?"). | Onboarding screen 3 teaches the one shortcut |
| 14 | Settings, search, presets | Many settings | Every setting has a one-line description and a live preview. Search box at the top. Four presets: Minimal, Creator, Developer, Everything. A preset only toggles modules; nothing hidden changes. | The palette finds settings too |
| 15 | Onboarding | — | 3 screens: what it is → the 3 gestures → the one shortcut. Asks for no permissions. | — |
| 16 | Signing, notarisation, Sparkle | Native updater | Same, from GitHub Releases. Updates install on quit, with no prompt by default. | — |

## Learn from use (principle 6) in Phase 1

On-device counters only:

- Modules the user never opens for 14 days are offered for hiding, never hidden automatically.
- Context suggestions are offered once, then never again if dismissed. Examples: a meeting app starting offers the meeting module, a copy streak offers Clipboard.

## Acceptance per module (added to MANUAL_TEST_CHECKLIST)

- A first-time user finds and uses it without docs.
- Toggle off → zero CPU in Activity Monitor.
- Report covers: what works, what doesn't, performance numbers, permissions used, how it's discovered.
