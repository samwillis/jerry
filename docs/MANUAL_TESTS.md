# Phase one manual checks

Build and launch using the README. These are interactive acceptance checks, not claims of automated coverage.

- [ ] An explorer appears above the Dock on the primary display; the remaining overlay is transparent.
- [ ] Launching does not change the frontmost app or interrupt typing.
- [ ] Click and select text underneath the explorer, and elsewhere on the desktop.
- [ ] Scroll an underlying window with the pointer over the explorer.
- [ ] Move and resize an underlying window without input interference.
- [ ] Pause from the menu bar: breathing stops; Resume is enabled and Pause disabled.
- [ ] Resume: breathing continues; Pause is enabled and Resume disabled.
- [ ] Toggle debug guides while running and paused; only guides change, and clicks still pass through.
- [ ] Switch between ordinary applications: overlay stays visible without gaining focus.
- [ ] Quit from the menu: explorer, overlay, guides, and status item disappear; no process remains.
- [ ] Relaunch: exactly one explorer and one status item appear.

Real window terrain, full-screen behaviour, and multiple-display support are outside these first two phases.

## Phase two manual checks

- [ ] Hover over the explorer: an open-hand cursor appears within its small hit area.
- [ ] Grab at the head or backpack: the character does not snap its centre to the pointer.
- [ ] Drag a long distance and release: the explorer follows and stays in its new position.
- [ ] Drag beyond a screen edge and back before releasing: the character stays visible and follows when the pointer returns.
- [ ] Release and immediately grab again: the new drag interrupts settling cleanly.
- [x] Leave a text field focused in another app, drag the explorer, then type without reactivating the other app: text still goes to that field. Confirmed by the user on 5 November 2026.
- [ ] Click, select text, scroll, and drag an underlying window just outside the explorer's input area.
- [ ] Pause, drag, and release: placement updates while breathing stays paused. Resume completes settling before breathing starts again.
- [ ] Toggle debug guides: the yellow input bounds follow the explorer.
- [ ] Change display layout during a drag: capture ends, the character is kept on the primary display, and the hand cursor is restored.
- [ ] Quit: both rendering and input panels disappear; relaunch creates only one explorer.

Phase two intentionally leaves the explorer at its drop location. Platform attachment and parachute recovery are later work.

## Validation record — 5 November 2026

- Xcode 27.2 Debug build succeeded on macOS 27.2, Apple Silicon, using the local ExpeditionCore package.
- Launched the built app through native app automation; its overlay and explorer rendered successfully.
- Opened a new Finder window and navigated to the project folder by typing while the overlay was running.
- Menu-bar inspection through system UI automation timed out. Pause/resume, debug toggling, and quit/relaunch remain manual checks.
- The overlay-only screenshot confirms character rendering, but does not establish composited desktop transparency. Direct click-through over the character, scrolling, focus retention on launch, and window dragging also remain manual checks.
- No screen capture or Accessibility permission was requested by the app. Automation itself uses the host's existing computer-use access.

## Phase two validation record — 5 November 2026

- The Debug app build passed after selecting the host architecture explicitly for the local build script.
- Six core interaction tests passed, covering grab offsets, out-of-bounds pointer movement and release, settling, re-grabbing, display changes, and invalid clock values.
- The new app launched and rendered. Native automation did not establish a successful drag: the overlay tree stayed unchanged and one coordinate attempt returned `AXError.notImplemented`.
- The user then tested the running prototype and confirmed that dragging and typing both work. This establishes basic native dragging and retained keyboard focus; the remaining edge cases above are still unchecked.
