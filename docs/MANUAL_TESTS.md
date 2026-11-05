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

Full-screen behaviour and multiple-display support remain outside the current prototype.

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

Phase two originally left the explorer at its drop location; phase three adds top-edge attachment and temporary controlled recovery.

## Phase three manual checks

- [ ] Enable debug guides: green tops and pink sides match exposed rectangular window bounds; teal lines mark rescue screen boundaries.
- [ ] Overlap two windows: the nearer window hides covered portions of the rear window's terrain.
- [ ] Drag a window partly beyond the screen: no artificial top platform appears at the screen ceiling.
- [x] Drop the explorer with its feet near an exposed green top: it snaps onto the top. Confirmed by the user on 5 November 2026.
- [x] Move the supporting window: the explorer stays on its top. Confirmed by the user on 5 November 2026. Resize edge cases remain unchecked.
- [ ] Move and resize that supporting window: the explorer keeps its window-relative horizontal offset while the foothold remains valid.
- [ ] Split another part of its supporting edge with a foreground window: the explorer stays attached if its own foothold and body are still clear.
- [ ] Close, minimise, cover, or narrow away its supporting window: the explorer descends visibly to the desktop floor rather than remaining suspended.
- [ ] Grab during recovery: descent stops and the explorer follows the pointer; keyboard focus remains in the other app.
- [ ] Drop above an exposed window top: controlled descent lands on the highest suitable top below the explorer, settles, and resumes breathing. Drop outside all platform widths to descend to the screen floor.
- [ ] Pause: geometry polling and recovery stop. Resume refreshes terrain; user dragging still works while paused.
- [ ] Quit and relaunch: no stale terrain timer, overlay, or input panel remains.
- [ ] On a separate test account or machine without screen-capture access, check geometry availability without granting new permissions. Do not change the user's permissions just for this check.

## Phase three validation record — 5 November 2026

- Native Debug build passed. Core tests cover coordinate conversion, overlaps, clipping, non-climbable occluders, relative anchors, body clearance, moving/resizing support, and controlled recovery.
- The geometry-only report read 9 windows, 8 climbable windows, and 8 edge segments in the development launch context. Existing screen-capture permission reported true; no permission was requested. This does not establish denied-permission behaviour.
- Launched with debug guides enabled; native UI inspection confirmed live window/edge counts and visible coloured terrain lines. The user confirmed guides are visible, near-edge drops attach, and moving a supporting window carries the explorer along.
- The user reported that dropping farther above a top continued to the desktop floor. Recovery originally ignored intermediate platforms. Added a vertical sweep against current exposed tops to land on the first suitable platform, with regression tests for large steps, platform ordering, horizontal misses, and windows moving during descent. Native verification of this improvement and support-loss recovery remains pending.

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
