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

## Phase four checks and validation — 5 November 2026

- [x] Open the Debug playground as a separate, focusable window.
- [x] Preview idle, walking, climbing, abseiling, parachuting, held, investigating, and the comic clip, with an actual-size explorer beside the enlarged one.
- [x] Switch facing and light/dark background; inspect joint directions and readability.
- [x] Move a climbing handhold within reach, then beyond reach: the arm follows and then clamps without invalid geometry. Restart restores contacts.
- [x] Drag the body away from its climbing grips: the window and grips stay fixed, and the released pose reports unreachable contacts rather than stretching its limbs.
- [x] Move the rope anchor and held grab point: native screenshots confirm the anchor/rope and pivot move to the edited positions.
- [x] Pause/resume and restart the preview; set slow playback using the native slider.
- [x] Inspect parachute canopy clearance and the comic sequence's lifted pose.
- [ ] Close/reopen the playground through the menu and confirm rendering stops while closed.
- [ ] Exercise the complete range of all tuning sliders and resize the preview while manipulating contacts.

The user's observation that knees and feet pointed inconsistently exposed arbitrary per-limb bend signs. Replaced those signs with anatomical pole targets: knees towards the toes, elbows behind the body, mirrored together. Corrected boots to have level soles and added a neck beneath the head. Native screenshots were inspected during development, including corrected right-facing idle/walking/abseiling/held and left-facing climbing/investigation poses, across the light/dark checks. Placeholder shapes remain deliberate; this is not a final-art review.

Debug and Release builds passed. All 34 core tests passed, including segment lengths, unreachable and coincident targets, mirrored joints and anatomical poles, fixed climbing contacts, finite clip poses, interruption, clock pause, and deterministic restart. Release excludes the playground; desktop terrain, input, and rendering remain in the app. Earlier unresolved operating-system edge cases and denied-permission checks remain listed above.

## Walking-direction correction — 5 November 2026

The user spotted a mismatch between walking direction and backpack placement. The original lifted-foot phase travelled backwards, and the backpack was on the positive-x (front) side. Reversed the foot sweep, moved the backpack to the back, and gave the face a small forward nose and offset eyes so its direction agrees with the toes. The playground status now includes a facing arrow. Native screenshots confirmed right- and left-facing backpack/face placement; the updated preview is running at half speed. The Debug build and all 35 core tests passed, including a regression checking forward swing and backward stance for both feet.

The user's follow-up identified the eye-height nose block and reversed shoulder occlusion. Replaced the nose block with a small protrusion in one continuous face outline below the eyes, swapped arm layering, and kept the near leg consistent with the near arm. The far sleeve is slightly darker. The Debug build passed, and native screenshots were reviewed in both facings at enlarged and actual size. This follow-up changes rendering only; the gait and solver are unchanged.

The user preferred the earlier rounded nose shape, so restored that shape below the eyes. Also separated the rendered ankle from the sole contact: the shin now ends three points inside the boot, preventing it from showing below the sole while keeping platform contact at the same height. The Debug build passed; native screenshots were reviewed for right-facing idle and left-facing walking at enlarged and actual size.

Removed the nose at the user's subsequent request. Shortened both upper and lower leg segments from 15 to 13.5 points to reduce the slouched knee bend in standing and walking. The Debug build passed; native idle and walking previews were inspected with planted soles and zero clamped contacts at default gait settings. The walking preview was left running at half speed.

Corrected the parachute's asymmetric three-cord layout to four balanced suspension cords, two per hand. Inner attachments now follow the curved lower canopy edge, and cords render behind the fabric so they cannot cross its face. The Debug build passed and a native parachute screenshot confirmed all four lines at enlarged and actual size.

## Expressions and release motion — 5 November 2026

- Added varied blinks with an 18 ms offset between eyes; a paused native preview at 2.46 seconds confirmed different eyelid closure amounts.
- Added planted-foot landing compression and recovery, triggered after descent and gentle placement. The Landing clip provides a repeatable preview.
- Animated the canopy emerging from the backpack and inflating behind the explorer; deployment timing also eases downward speed from 270 to 140 points/second.
- Raised standing hips and adjusted walking hip height to planted-leg reach. Native idle inspection confirmed the straighter stance. Abseiling has its own elbow pole direction.
- Added filtered drag-release velocity, air resistance, display bounds, and diagonal platform sweeps. Automated cases cover sideways and upward throws, stale velocity, re-grabbing, and crossing-point landings. Full native throw/landing feel remains a manual check.
- Added a preview-time slider for deterministic visual inspection. The user accepted the current version for commit.

Final Debug and Release builds passed, all 42 core tests passed, and whitespace checks passed. Earlier OS-specific manual checks remain open; this validation does not claim they were completed.

## Painted finish — 5 November 2026

Replaced flat shape fills with cached 4× material paintings while preserving part silhouettes, rig positions, contacts, and animation. Added soft lighting, warm cheek/brim shading, quiet cloth folds, canvas weave/flap detail, felt bands, and leather highlights/soles. The playground's Flat shading checkbox switches the same rig back to solid fills for comparison. Native screenshots were reviewed in enlarged and actual-size idle/walking, on light and dark backgrounds, including mirroring and finish toggling.

The user liked the shading but requested more silhouette contrast. Increased the painted outlines to 0.7 points and a darker, more opaque material-derived colour. This pass changes rendering only; existing core motion tests were not repeated solely for a visual change.

Follow-up feedback reduced arm/leg gradients and replaced individually outlined limb segments with a continuous cloth silhouette across elbows and knees. The Debug build passed after this change; final visual acceptance of the continuous joints remains with the user.

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

## Phases five to seven — 5 November 2026

The latest requirement-by-requirement evidence, native lifecycle checks, real-window fixture observations, simulated soak tests, package details and remaining OS limits are in [prototype validation](PROTOTYPE_VALIDATION.md). Earlier unchecked OS cases above remain historical open coverage, not claims that this increment tested every macOS configuration. No overnight user testing was requested.


## Movement feedback — 6 November 2026

Updated walking and climbing to follow stance/pull clocks, fixed climbing knee branch changes, added lip/rope/jump transitions and manual Activities controls, and routed the rope over rounded corners with tangent joins. See [the latest validation](PROTOTYPE_VALIDATION.md#movement-and-activity-refinement--6-november-2026) and [animation workflow](ANIMATION_WORKFLOW.md) for coverage and the preview controls.


## Connected rope activity checks — 6 November 2026

- Choose Activities → Grappling hook: launcher aims, hook flies and latches, line takes weight, explorer swings, climbs and mantles.
- During the swing, select Climb rope / Abseil / Swing on rope: confirm the line stays on the same window and motion continues through each mode change.
- After abseiling onto a floor or lower window, select Climb rope: he uses the deployed line without firing again.
- Release rope or grab during any rope phase: momentum/recovery or direct dragging replaces the rope immediately.
- Move/cover/close the anchor window; remove a landing window while the line remains attached: the line follows, catches or releases appropriately.

Automated equivalents and native observations are in [prototype validation](PROTOTYPE_VALIDATION.md#grapple-and-unified-rope-simulation--6-november-2026). These checks supplement earlier user-confirmed focus/dragging behaviour; no new input hooks or permissions are introduced.

### Front-rim grappling

- From below the middle of a window, trigger Grappling hook: fire upward, climb in front of the window, pull over its top, and stand at the same horizontal position.
- Repeat on a top more than 550 points above him, and on a window touching both display edges.
- While hanging in front, switch between Abseil, Climb rope and Swing on rope; retain the same attachment and momentum. Move/close the supporting window.
- A side approach must still preserve tangent joins around its rounded corner.
- Developer fixture: `TerrainFixture --front-only` shows one high window for the upward-shot check.

### Keyboard and desktop interaction

- [x] Open Keyboard Control and use Right/A/D: movement starts and stops on key release; the control window owns focus.
- [x] Use G then Up/Down to control one physical rope. Space jumps off it. Esc closes control mode.
- [ ] From a roof, walk to its edge and Down to lower into abseiling; release Down to hold the line.
- [ ] Jump onto a low platform; Down + Space drops through it; repeated Space cannot double jump.
- [ ] Switch apps while holding a movement key: control ends and normal typing works; no stuck movement on re-entry.
- [ ] Grant Accessibility to the final app via Allow Explorer Clicks. Place the visible crosshair over a disposable button and press E once. Verify one action; holding E must not repeat it.
- [ ] Developer fixture `TerrainFixture --click-target` exposes a counter button. Check AXPress on that button, and check fallback mouse clicking on an appropriate custom canvas control.
- [ ] After clicking a text field that takes focus, type in the target app normally. Re-enter keyboard control explicitly to move again.
- [x] Native checks verify denied permission sends no click. Granted-permission clicks remain unverified in the current context.


### Manual control and idle exploration follow-up

- [x] E presses the disposable native fixture button without ending control, both on the floor and on a rope.
- [x] The custom fixture canvas receives a fallback mouse click and the control window regains focus; repeated the check while swinging.
- [x] G press/release fires a suggested aimed rim; arrow input and E still work on the attached line.
- [ ] Hold G and use the arrows to choose a different exposed top rim, including while jumping or attached to a rope. Move the pointer and confirm it does not steer the aim.
- [ ] Physically press Control–Option–Space from another app to take/release control. The native test verifies registration, event callback dispatch, repeat suppression and cleanup; computer-use targeted key injection did not exercise the OS-wide shortcut path.
- [ ] Disable Enable Idle Exploration: leave him alone, drag/drop him onto a window, move the window, and bring the pointer near. He should settle and watch, without starting a sock hunt.
- [ ] Re-enable exploration and verify wandering/sock hunting returns. Disable it before manual control and verify Escape leaves him resting afterward.


### Welcome and keyboard-only aiming

- [x] The redesigned non-modal guide shows the actual explorer, idle checkbox, key rows and current click-access status.
- [x] Take Control closes the guide; actual Right-key input moves him without a visible controls window.
- [x] Native input routing: hold G and Right/Up directs the aim only; releasing G fires once and restores arrows to movement/swinging. Mouse position is no longer read by grapple aiming.
- [x] Native first-run check: absent completion marker opens the guide; closing records completion. Tests restore the prior marker afterward.
- [ ] On a smaller screen, scroll the guide if needed; footer buttons must remain reachable.


### Optional fast pace

- [x] Shift+Right moves the desktop explorer in the running state and key release returns to idle, without a controls window.
- [x] Running preview has visible arm pumps and a brief airborne stride, with zero clamped contacts.
- [ ] Hold Shift while rope climbing/descending, then release; the same rope must remain attached and hand motion must match the work rate.
- [ ] Enable Run When Exploring and Faster Rope Work in Settings, relaunch, and verify both remain enabled. Disable Idle Exploration and verify these settings do not start wandering.
