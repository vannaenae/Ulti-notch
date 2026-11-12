# Manual test checklist

Run before every release, and after any change to the shell. Record the Mac model, macOS version and display setup with each run.

## Shell and displays
- [ ] Notch MacBook, built-in only: collapsed island matches the notch exactly (no visible edge in classic black)
- [ ] External non-notch display: floating island at top centre
- [ ] Hot-plug external display while island is expanded: no crash, island appears/disappears on that display
- [ ] Change resolution / "More Space" scaling: island re-centres on the notch
- [ ] Clamshell mode (lid closed, external only)
- [ ] Mirror displays
- [ ] "Displays have separate Spaces" on and off
- [ ] Menu bar auto-hide on and off

## Spaces, full screen, Stage Manager
- [ ] Switch Spaces: island does not slide or flicker
- [ ] Native full-screen app: behaviour matches the per-display setting (hide / show / critical only)
- [ ] Split View full screen
- [ ] Browser video in full screen (not a native full-screen Space)
- [ ] Stage Manager on: island stays above, not part of any stage
- [ ] Mission Control and App Exposé: island not shown as a window
- [ ] Cmd-` and Cmd-Tab never focus the island

## Sleep, lock, wake
- [ ] Lock screen and unlock
- [ ] System sleep and wake (lid close/open) ×10
- [ ] Display sleep only (hot corner) and wake
- [ ] Wake with a different display set attached than at sleep

## Interaction
- [ ] Hover expands after the delay; brushing past the notch does not
- [ ] Leaving collapses after the grace period; re-entering cancels it
- [ ] Click expands; click outside and Escape close
- [ ] Two-finger swipe down/up walks collapsed → expanded → panel and back
- [ ] Keyboard shortcuts toggle expanded and panel
- [ ] Clicks on transparent window areas reach the menu bar and apps below
- [ ] Frontmost app keeps focus when the island is clicked
- [ ] Drag a file onto the island: opens shelf; stays open until drop

## Accessibility
- [ ] VoiceOver reads the live activity label
- [ ] Reduce Transparency switches to classic black
- [ ] Reduce Motion replaces springs with fades

## Performance (see PERF.md once written)
- [ ] Idle CPU < 1% over 5 min, core modules on
- [ ] Memory < 150 MB
- [ ] Animation Hitches template: no hitches over 50 expand/collapse cycles

## Battery
- [ ] Unplug: island shows battery % for ~3 s, then returns to what it showed before
- [ ] Plug in: green bolt + % for ~3 s
- [ ] Below 20% on battery: red battery stays in the island until plugged in
- [ ] Desktop Mac (no battery): module shows "No battery", nothing appears in the island
- [ ] Toggle off in Settings: no battery activity appears; Activity Monitor shows no CPU change
- [ ] Discovery: a first-time user sees it the first time they plug or unplug

## Now Playing
- [ ] Play in Music: equalizer appears beside the notch
- [ ] Play in Spotify: same
- [ ] Hover: expanded view shows title, artist, player name and controls
- [ ] First press of play/pause asks for Automation permission with the plain reason; controls work after allowing
- [ ] Deny Automation: track info still shows; controls do nothing, no crash
- [ ] Switch between Music and Spotify: island follows the one touched last
- [ ] Pause: compact activity disappears; expanded view still shows the track
- [ ] Toggle off: no activity, no CPU
- [ ] Discovery: appears on its own the first time music plays
