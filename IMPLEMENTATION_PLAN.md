# The Other Sock: implementation plan

## Objective and scope

Deliver a runnable macOS prototype with one draggable explorer that climbs real windows, parachutes towards a supposed sock, and discovers a banana. The user must be able to continue working normally throughout.

The product concept and later ideas live in [PLAN.md](PLAN.md). This document describes the build order. Do not start with three characters, finished artwork, a journal, or Windows support.

## Current status

Phases 1–7 are implemented for the local, single-display macOS prototype. The latest increment connects real desktop travel, the repeating banana adventure, saved menu preferences, lifecycle guards, and Release packaging. Verification and practical limits are recorded in [prototype validation](docs/PROTOTYPE_VALIDATION.md); this does not claim full-screen traversal, a Windows port, or public distribution readiness.

## Initial technical decisions

- Use Swift, AppKit for desktop integration, and SpriteKit for animation.
- Create a native macOS app target and a small, platform-independent Swift package for geometry, simulation, and mission rules. Select the minimum macOS version after checking the available SDK and test machines.
- Use a menu bar app with explicit pause, resume, reset expedition, and quit actions.
- Render the world in a transparent, mouse-ignoring overlay. Prototype small non-activating input panels around explorers for direct dragging. Do not assume returning nil from a view hit test forwards clicks to another app.
- Start with one display and placeholder shapes. Use desktop coordinates in logical points, with one explicit conversion boundary between Core Graphics, AppKit, and scene coordinates.
- Use a deterministic simulation with a seeded random source. SpriteKit presents simulation state rather than independently deciding character movement.
- Read window geometry and order, not window titles or captured images. Verify which metadata is available without permissions on supported macOS versions before committing to a permission model.
- Keep behaviour and animation definitions portable. Decide how to share executable code with Windows when planning that port; a Swift package alone does not guarantee an inexpensive Windows implementation.

## Proposed repository structure

```text
OtherSock.xcodeproj
OtherSock/
  App/                 # Entry point, menu bar, settings, lifecycle
  Desktop/             # Window discovery, coordinate conversion, display tracking
  Overlay/             # Rendering panels, character input panels, drag handling
  Rendering/           # SpriteKit scene, explorer nodes, ropes, parachutes
    Rig/               # Character hierarchy, joint constraints, pose blending
    Animation/         # Clips, timing, contact targets, animation events
  Playground/          # Development-only animation preview and fake terrain
  Resources/           # Assets and animation definitions
Packages/
  ExpeditionCore/
    Sources/ExpeditionCore/
      Geometry/        # Points, rectangles, visible edge subtraction
      Terrain/         # Surfaces, attachment anchors, terrain snapshots
      Simulation/      # Explorer state, motion, collision, simulation clock
      Navigation/      # Reachable transitions and route selection
      Missions/        # Mission stages and expedition events
    Tests/ExpeditionCoreTests/
docs/
  MANUAL_TESTS.md
```

Create directories as their implementation becomes necessary, rather than adding empty scaffolding upfront.

## 1. Establish a runnable shell

1. Inspect the installed Xcode/Swift toolchain and choose a supported deployment target.
2. Create the app target, the core package, and a short README with build and launch instructions.
3. Implement the menu bar controls and one transparent overlay on the main display.
4. Draw a placeholder explorer and verify that the overlay does not activate the app or capture keyboard focus.
5. Add a development-only terrain/debug toggle.

Acceptance: launch and quit reliably; type, scroll, select text, and drag underlying windows normally while the placeholder is visible. Pause stops animation; quit removes every app-owned panel.

Implementation status (5 November 2026): app shell, local core package, Xcode target/shared scheme, click-through overlay, placeholder idle animation, menu controls, and debug guides are implemented. The Debug build and initial launch/rendering passed. See [manual checks](docs/MANUAL_TESTS.md) for remaining interactive acceptance checks.

## 2. Prove dragging before adding movement

1. Create a small non-activating input panel that follows the explorer's body. Keep ropes, flags, parachutes, and empty overlay space non-interactive.
2. Handle mouse down, dragged, and up locally in that panel. Preserve the grab offset so the character does not jump to the cursor centre.
3. Enter a `held` simulation state on mouse down; autonomous movement must stop.
4. Keep receiving the drag until release even when the cursor leaves the original character bounds.
5. On release, enter a short settling state; later connect this to platform attachment or parachute recovery.
6. Verify focus remains with the user's application. Start without global input hooks or Accessibility access; reassess only if the prototype demonstrates a need.

Acceptance: repeatedly pick up and move the character without activating the toy, losing a drag, or blocking clicks away from its small hit area. If input panels are unreliable, resolve the approach here before proceeding.

Implementation status (5 November 2026): a small non-activating character input panel, grab-offset handling, held/settling/idle states, screen bounds, display-change cancellation, and paused dragging are implemented. Six core tests and the native Debug build passed. The user confirmed that actual dragging and typing in another app both work. Remaining native edge-case checks are listed in docs/MANUAL_TESTS.md; core tests alone are not proof of window-server input behaviour.

## 3. Discover windows and derive terrain

1. Implement a `WindowProvider` that supplies immutable snapshots containing window ID, frame, and front-to-back order.
2. Exclude the toy's own windows, invisible/minimised windows, and unsuitable system surfaces. Keep classification rules isolated and inspectable in debug mode.
3. Begin with a geometry refresh around 10 Hz, independent of the rendering rate. Measure responsiveness before increasing it.
4. Convert all frames to the simulation coordinate system.
5. Subtract areas covered by nearer windows from candidate top and side edges. Treat screen boundaries as fallback terrain.
6. Assign surface IDs from window ID, edge, and segment. Store attachments as window ID, edge, and local offset so splitting a visible edge does not lose the character's anchor unnecessarily.
7. Translate attached characters with their supporting window. If their support disappears or becomes occluded, enter recovery rather than teleporting or remaining suspended.

Acceptance: debug lines match exposed window edges, including overlapping and resized windows. Moving or closing a supporting window updates the character predictably. Confirm basic terrain works with the actual permission state on the target Mac.

Implementation status (5 November 2026): metadata discovery at 10 Hz, explicit coordinate conversion, visible-edge subtraction, window-relative top attachments, debug terrain, and placeholder controlled descent on support loss are implemented. The user confirmed near-edge drops attach and supporting-window movement carries the explorer. Recovery now sweeps downward against exposed tops so drops from farther above can land, rather than passing through to the desktop. The native build and geometry/attachment tests pass, and live metadata and terrain rendering have been inspected. The launch context already has screen-capture permission, so denied-permission behaviour remains unverified. Remaining native landing/close acceptance checks are recorded separately in docs/MANUAL_TESTS.md. Climbing, side attachments, and real parachute recovery remain later work.

## 4. Build the animation playground and character rig

Build a development-only preview window before connecting full movement to real windows. Keep it separate from the non-activating desktop overlay so preview controls can accept normal input.

1. Construct one explorer from simple coloured shapes: head, torso, upper/lower arms, hands, upper/lower legs, feet, and backpack. Use a parent-child joint hierarchy with explicit shoulder, elbow, hip, and knee pivots.
2. Add controls for idle, walking, climbing, abseiling, parachuting, being held, and investigating. Include pause, restart, slow playback, facing direction, and a joint/contact debug view.
3. Provide fake window edges, draggable handholds, a rope anchor, and a grab point. Make every preview repeatable without relying on the live desktop.
4. Implement parameterised poses and animation clips. Start with joint rotations and pose blending; add a small two-segment limb solver where necessary to keep hands and feet on contact targets. Handle unreachable targets without snapping or invalid joint positions.
5. Add body bobbing, backpack bounce, limb sway while held, and anticipation before a jump. Test an initial character height of 60–80 logical points and adjust for readability.
6. Keep world position, collision, and mission decisions in the simulation. The rig consumes position, facing, movement phase, contact targets, and events; its visual offsets must not change terrain collision or drag anchors.
7. Support clean interruption and pose blending when grabbed, dropped, or deprived of a handhold. Remove stale animation callbacks before another state starts.
8. Reuse the same rig and animation controller in the playground and the desktop scene.

Acceptance: preview every movement at actual desktop scale; hands and feet stay attached during contact, limbs bend consistently in both facing directions, and dragging interrupts any pose cleanly. The first comic sequence is an explorer walking to an edge, looking down, changing its mind, and being picked up by the user.

Implementation status (5 November 2026): phase four is implemented with a shared shape rig, two-bone IK, anatomical bend poles, numeric pose blending, idle/walk/climb/abseil/parachute/held/investigation clips, and a looping edge-hesitation comic sequence. The Debug-only playground includes an actual-size comparison, 1–3× zoom, 0.1–1× playback, pause/restart, facing/background controls, joint/contact debugging, tunable cadence/stride/bounce, and draggable contacts, anchor, pivot, and body. The desktop reuses the rig for resting, held, and recovery states. Debug and Release builds pass; 34 core tests pass. Native previews and interaction checks are documented in docs/MANUAL_TESTS.md. The user's knee/foot-direction feedback was addressed by consistent knee and elbow pole targets. [Animation workflow](docs/ANIMATION_WORKFLOW.md) documents the rig and future drawing/integration tasks. Finished bitmap artwork and real climbing routes remain subsequent work.

### Agent workflow for animation and drawing

Implement in small, reviewable tasks. Each task should produce a runnable preview and a screenshot or short recording, with a brief account of what changed and any remaining visual problems. Use agent-created previews for verification and user feedback for subjective style and comic timing; continue technical work that does not depend on an unanswered art preference.

1. **Rig and playground task:** ask a coding agent to build the shape-based explorer, fake terrain, and preview controls described above. No external artwork is needed.
2. **Movement refinement task:** tune joint placement, contacts, timing, dangling, and secondary motion. Expose tunable parameters so feedback such as "slower footsteps" or "more backpack bounce" can be applied without rewriting the rig.
3. **Character design task:** use an image-generation agent/tool to draw a reference character with a clear silhouette, oversized equipment, and a consistent style. Review at actual desktop size before producing all the parts.
4. **Body-part artwork task:** generate artwork and prepare separate transparent parts using the reference and a documented neutral pose. Record each asset's dimensions, pivot, attachment points, overlap, and layer order in a rig manifest. Inspect and clean up alignment, transparent edges, missing areas behind joints, and consistency of clothing and proportions; generation alone does not guarantee rig-ready assets.
5. **Artwork integration task:** replace placeholder shapes with the prepared parts without changing the movement system. Check every preview pose in both directions and on light and dark backgrounds. Keep the shape rig available for debugging.
6. **Personality task:** add facial expressions and bespoke poses for binoculars, the upside-down map, the kettle, and the banana reveal. Add the leader's forward lean, the rope expert's careful contact checks, and the holidaymaker's heavy backpack when those characters enter scope.

Prefer one consistent articulated rig over independently generated full-frame sprite sheets. Use occasional hand-authored or generated-and-cleaned special frames where articulation cannot express a comic pose well. Finished art and the other two characters remain subsequent increments; this stage establishes the workflow with one explorer.

Suggested first agent task:

> Build a development-only animation playground in Swift and SpriteKit for one explorer made from simple shapes with articulated arms and legs. Add selectable previews for idle, walking, climbing, abseiling, parachuting, being held, and investigating. Include a fake window edge, draggable handholds, a grab point, slow playback, and joint visualisation. Keep the rig separate from desktop integration and world simulation. Use no external artwork yet. Verify the preview at actual desktop scale and provide a screenshot or recording of the result.

## 5. Implement movement and recovery

Implement a state machine with explicit entry, update, and exit behaviour:

| State | Purpose | Typical exit |
| --- | --- | --- |
| Idle | Rest or await a route | Route selected |
| Walking | Follow a horizontal surface | Edge or destination reached |
| Climbing | Move along a reachable vertical edge | Top reached or support lost |
| Abseiling | Descend from an anchored rope | Landing or anchor lost |
| Falling | Short unsupported movement | Landing or parachute deployment |
| Parachuting | Controlled descent with limited steering | Landing |
| Held | User controls position | Mouse release |
| Settling | Brief pause after being placed | Resume or deploy parachute |
| Investigating | Perform discovery animation | Mission event emitted |

1. Use a fixed simulation step with an accumulator and a limit on catch-up work after stalls.
2. Implement walking and climbing first, then falling and landing, then parachuting and abseiling.
   Feed the resulting state and contact targets into the rig established in stage 4; use the playground to reproduce and tune animation issues.
3. Use swept landing checks so a character cannot pass through a thin platform between updates.
4. Build a small graph of traversable surfaces with walk, climb, abseil, and parachute transitions. Reject transitions beyond the current movement limits.
5. Revalidate the next transition when terrain changes. If a route becomes impossible, wait, replan, or recover safely.
6. If the user drops an explorer away from a surface, open the parachute and find a safe landing. Do not immediately route it back to its previous position.
7. Keep characters within usable display bounds and provide a reset action if no valid route remains.

Acceptance: walk to an edge, climb, abseil, parachute, and land on real windows. Repeat while moving, closing, and covering windows, and while dragging the explorer during each movement type.

Implementation status (5 November 2026): fixed 120 Hz stepping with bounded catch-up, seeded surface routing, real top walking, side climbing, window-anchored abseiling, steered parachuting, swept landing, and route continuation after landing are implemented. Current and upcoming transitions are revalidated against fresh terrain. Grabbing cancels navigation immediately, including while paused. The shared rig receives facing and world-stable climbing contacts; recovery retains release momentum. Reset Expedition provides an escape hatch. The `recovering` movement state contains the initial falling/deployment and open-canopy subphases; investigation is controlled by the mission stage rather than a second movement controller. See the focused movement tests and native evidence in [prototype validation](docs/PROTOTYPE_VALIDATION.md).

Refinement (6 November 2026): added phase-synchronised walking and climbing, a stable knee branch with lower climbing contacts, explicit mantle/lower/launch beats, a top-pinned rope that follows rounded corners with tangent joins, and a menu for requesting specific real-terrain activities. Manual requests queue through unsafe interruptions and rest when complete; automatic adventures can be restored from the same submenu.

Rope increment (6 November 2026): grappling, swinging, rope climbing and abseiling now share a physical line/session. Hook acquisition adds reachable graph transitions; gravity, slack/tension, reeling/payout, contacts and momentum govern hanging movement. Menu mode changes keep the existing line, and a landed abseiler can climb back up it. Native and numerical verification is in the latest rope section of the validation record.

## 6. Assemble the banana adventure

1. Implement mission stages: select destination, spot suspected sock, approach launch point, cross, investigate, reveal banana, update map, rest.
2. Place the discovery prop on a reachable surface. Tie its location to its supporting window and reselect if that location disappears.
3. Prefer parachuting when a valid launch and landing pair exists; use climbing or a nearer destination when the desktop layout does not permit it.
4. Add binoculars, a flag, a parachute, a rope, and a banana using simple temporary art.
5. Coordinate movement and animation through events. Cancel stale animation completions when the user grabs a character or its route changes.
6. Add small pauses for anticipation, disappointment, and misplaced confidence.

Acceptance: the entire sequence runs unattended on a suitable desktop layout, and interruption by dragging or window changes does not strand the mission. A sparse desktop still permits safe wandering and rest.

Implementation status (5 November 2026): the deterministic mission director selects a reachable discovery, prefers parachute routes when available, and runs spotting, approach, crossing, investigation, banana reveal, map update, and rest beats. Simple binoculars, a sock silhouette, banana, flag, map, canopy, and anchored rope render in the click-through layer. Window-relative props follow their supports; missing destinations and grabs invalidate the old mission. Tests cover unattended repetition on sparse and suitable desktops, interruption, moving/removing destinations, and landing continuations.

## 7. Package and evaluate the first prototype

1. Add minimal settings and persist them. Mission persistence can wait until the longer expedition exists.
2. Pause simulation and terrain polling when explicitly paused; rebuild terrain and reset the simulation clock after sleep/wake.
3. For the one-display prototype, recover or pause if its display disappears. Hide the expedition during unsupported full-screen or desktop transitions until support is verified.
4. Measure idle and active CPU, memory, and animation smoothness on the development Mac. Start with a 30 fps render target; document measurements and adjust based on results.
5. Add a manual test checklist and a runnable development app build. Signing and notarisation become required when distributing outside the development machine.

Acceptance: use the prototype during an ordinary work session without input interference, stuck characters, or accumulating panels. Document known limitations instead of claiming unsupported display or Space behaviour works.

Implementation status (5 November 2026): Pause, Gentle Pace, and guide preferences persist. Pause suspends simulation and routine geometry polling, with dragging still available. Sleep/Space/foreground-app notifications drive visibility guards; return refreshes terrain and resets clocks while preserving explicit pause. The explorer remains on the primary display and resets safely after display changes. Duplicate app instances are prevented. `scripts/package.sh` produces a local Release app/archive. Automated core/soak tests, native AppKit lifecycle checks, runtime observations, performance samples, and known OS limitations are recorded in [prototype validation](docs/PROTOTYPE_VALIDATION.md). Signing/notarisation remains a distribution increment, as scoped above.

## Verification

Use automated tests where the algorithm has meaningful failure cases:

- Coordinate conversion for non-zero display origins and different axis directions.
- Visible-edge subtraction for overlapping, touching, and fully covered windows.
- Moving attachments and recovery after support removal.
- Swept landing, unreachable routes, and bounded simulation catch-up.
- Drag interruption and mission recovery using deterministic terrain snapshots.

Use native manual checks for click-through, drag capture, focus retention, window stacking, pause/quit, sleep/wake, and desktop changes. These cannot be established by core unit tests. Run relevant checks after each milestone; do not defer interaction checks until the final build.

Use the animation playground for actual-size visual review, contact accuracy, facing changes, pose interruption, and artwork alignment. Add focused numerical tests for limb reach constraints if a limb solver is introduced; visual quality still requires reviewing the rendered animation.

## Subsequent increments

1. Complete the character drawing and integration workflow from stage 4, replacing temporary art and refining readable character scale and animation timing.
2. Add the other two explorers, shared traversal coordination, rescue scenes, and personality-specific decisions.
3. Add multiple displays, mixed scaling, and verified Spaces/full-screen behaviour.
4. Add the scene director, persistent expedition progress, and selected later ideas from PLAN.md.
5. Complete distribution signing/notarisation, packaging, and release testing.
6. Plan the Windows host using the established behaviour contracts, assets, and test fixtures; choose a shared implementation strategy based on the working Mac prototype.

## Platform references

- [Apple: onscreen window enumeration](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly)
- [Apple: ignoring mouse events](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents)
- [Apple: non-activating panels](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)

These APIs support the proposed approach; the first two implementation stages must establish the combined interaction behaviour on the target system.


## Optional player-control increment — 6 November 2026

Implemented explicit local keyboard control through a separate key-capable HUD, keeping the world renderer and drag panel non-activating. Arrows/WASD walk, steer, grab/climb sides, and climb/descend the shared rope; Space jumps or releases a rope; Down+Space drops through a platform; G fires a supported grapple. Holding no directional key pauses climbing/payout while keeping physical swing motion. Esc, loss of focus and lifecycle interruptions clear input and stop capture. Keyboard movement matches doubled walking cadence and uses fixed-step gravity for jumps.

E targets a visible hand crosshair. Accessibility access gates an AXPress attempt with a single native-click fallback for custom controls. The app requests access only from the explicit click/permission command. It does not monitor global keys. Core/native input checks and live keyboard checks pass; granted-permission external clicks are still an interactive acceptance check. Text entry, right-clicks, double-clicks and explorer-driven dragging remain later work.


## Idle exploration and manual interaction follow-up — 6 November 2026

The user-facing idle setting now controls wandering/mission selection without suspending gravity, recovery, pointer attention or dragging. It persists and is respected after manual control. The hiking menu is organized into idle exploration, Take/Release Control, Actions, Settings and Controls & Tips, with developer options confined to Debug builds. Control–Option–Space is registered as a system hotkey without a global keyboard monitor.

Holding G aims a visible rim marker; release fires from standing, in flight or from another rope. Refiring carries momentum and continues free flight until latch. Left/right pumps/brakes the rope tangent. E preserves the manual session and attached line across AXPress or fallback click; the key window is restored after the action and held movement is reconciled. Native/custom disposable controls were exercised on the floor and while hanging. Cross-app physical shortcut use remains an explicit manual check because targeted computer-use key injection did not traverse the OS hotkey path.
