# The Other Sock

A tiny, deeply unqualified desktop expedition searching for the other sock.

## Current prototype: phases one to seven

The native macOS shell draws one articulated, approximately 74-point shape explorer on a transparent SpriteKit overlay above normal windows. It breathes gently while idle, sways when held, and displays a parachute during controlled recovery. A hiking icon in the menu bar provides **Pause Expedition**, **Resume Expedition**, **Reset Expedition**, **Activities**, **Gentle Pace**, **Show Debug Guides**, **Animation Playground…** (Debug builds), and **Quit The Other Sock**. Pause, pace, and guide preferences survive relaunch.

The rendering overlay ignores mouse events and cannot become the key or main window. A separate 48 × 76 point, non-activating panel over the explorer accepts dragging. Grab anywhere inside that small character area, drag it aside, and release. The grab offset is preserved, and the explorer remains inside the primary display's usable area. All other overlay space passes mouse events through. Autonomous/dragging mode uses no keyboard monitor or permission prompts. Optional keyboard control uses a local event monitor only while its control window has focus. Optional desktop clicks require Accessibility permission; neither feature captures screen images.

While held, idle movement stops. Release carries recent drag momentum, so quick sideways or upward motions produce an arc. Holding still before release gives a normal drop. The explorer initially falls faster; its chute emerges from behind the backpack, opens overhead, and slows the descent and drift. It lands on the first suitable exposed top below its trajectory. Gentle placement within 16 points of a top snaps it directly onto the edge. It needs its full body width on the platform and 76 points of clear space above it. It follows that window when moved or resized. Losing support starts another recovery. It autonomously walks exposed tops, climbs reachable window sides, abseils from a window-relative rope, and steers parachutes towards safe landing areas. Window changes revalidate each transition; losing support or an invalid route starts recovery. A new grab cancels its route and mission immediately.

On landing, the explorer briefly crouches with planted feet and then rises. A settling interval prevents immediate autonomous movement. Occasional blinks have a tiny timing offset between the eyes. Dragging is still available when paused; pausing freezes visual clocks, settling, recovery, and automatic terrain polling. Resume refreshes geometry immediately. Releasing a dragged explorer refreshes geometry even while paused.

Bring the pointer near him and he notices it: his eyes follow first, with a small, slower head turn. Attention fades smoothly beyond about 220 points and returns to his normal expression. Blinking continues while he watches. This samples the current pointer position without capturing mouse events.

## Play with the keyboard

Choose hiking menu → **Control Explorer with Keyboard…**. A small control window takes focus and shows the keys. The explorer stops choosing adventures until you leave control mode.

| Key | Action |
| --- | --- |
| ← / → or A / D | Walk; steer while airborne; push a swing |
| ↑ / W | Grab/climb a nearby exposed side, or climb the attached rope |
| ↓ / S | Lower over a nearby window edge and abseil, or descend the attached rope |
| Space | Jump; jump off/release a rope |
| ↓ + Space | Drop through the current platform |
| G | Fire the hook from a supported position; Up then climbs its rope |
| E | Click the crosshair beside his hand |
| Esc | End control and return focus to the previous app |

Releasing Up/Down holds the current rope length, allowing a natural swing. Walking uses twice the normal cadence and matches its foot motion. There are no mid-air double jumps. Changing apps, pausing, dragging, resetting, sleeping, or leaving the desktop stops keyboard capture and clears held directions. Movement needs no Accessibility or Input Monitoring permission.

**E** targets the visible crosshair, first using an accessible control's Press action and otherwise sending one ordinary left click there. Choose **Allow Explorer Clicks…** in the hiking menu (or press E once), then enable The Other Sock under **System Settings → Privacy & Security → Accessibility**. Return to keyboard control afterward. Without that permission E performs no click. Native/custom controls that take focus end control mode, so you can type into the target app normally. Buttons and toggles can be pressed; this first version does not route text typing, double-clicks, right-clicks, or drag gestures through the explorer.

## Trigger an activity

Use the hiking menu → **Activities** → **Walk**, **Climb a window**, **Grappling hook**, **Abseil**, **Climb rope**, **Swing on rope**, **Release rope**, **Parachute**, or **Find the sock**. The explorer approaches suitable real terrain first, then performs the activity and rests. Unreachable choices are labelled and disabled. Requests made during a jump/corner/flight queue safely for the next support. **Automatic adventures** restores normal mission selection. Choosing an activity resumes a paused expedition.

Climbs now pull over the lip into a planted-foot standing pose; rope descents crouch and back over the lip; parachute trips crouch and jump clear before deploying. The rope pins on the top edge, follows an estimated 10-point rounded window corner, and leaves along the mathematical tangent towards the hands. Both straight-to-curve joins remain tangent as the explorer descends.

## Connected rope activities

**Grappling hook** aims a small spool launcher, fires a hook over a reachable window lip, takes up the line, swings under gravity, then climbs and mantles onto the destination. Shots reach up to 2,300 points (with a 2,400-point spool). He can hook the middle of an exposed top rim and climb vertically up the window's front, including windows whose side edges are off-screen. An aligned shot uses his current horizontal position; angled shots still swing naturally. At the rim he pulls himself over to stand on top. It can reach exposed windows that have no climbable route from the floor. Automatic adventures occasionally consider these grapple routes as well.

While attached, **Swing on rope**, **Climb rope**, and **Abseil** change the motor/holding mode of that same rope; they preserve the anchor, deployed length, position and existing momentum. Swing pushes off if the explorer is resting against the wall. A completed abseil keeps its line attached, so Climb rope can take him back up without refiring. **Release rope** keeps his current velocity and uses parachute recovery. Grabbing always cancels the line immediately.

The physical rope has gravity, tension, slack, damping, a controlled reel/payout rate, corner contact and window/floor contact. Swinging is simulated rather than played as a looping animation. Rendering keeps the rounded corner's tangent joins and shows slack in the free line. The body hangs from its harness and hands follow the line. Rope climbing lifts in time with the hand pulls.

The prototype models one massless line with either a straight front-rim attachment or one rounded corner guide on its supporting window. It does not yet wrap rope around arbitrary intervening windows, collide ropes with each other, or simulate rope elasticity. A missing/covered anchor releases into recovery. The 2,400-point spool covers supported descent routes; reaching its end also releases safely.

## The banana adventure

The explorer spots a supposed sock through binoculars, approaches a launch point, crosses to a reachable discovery, investigates, discovers a banana, plants a flag, marks its map, and rests before trying again. It prefers a valid parachute crossing; climbing and shorter walks provide alternatives. The prop follows its supporting window. Grabbing the explorer, losing support, or removing the destination cancels or replans the expedition. A sparse desktop permits short floor expeditions; no reachable route means a safe rest.

Movement uses a fixed 120 Hz simulation with at most 0.25 seconds of catch-up after a stall, presented at 30 fps. Walking follows the unchanged foot cycle (40 points/second on average at the default stride/cadence). Climbing follows alternating 12-point arm pulls (24 points/second on average), and abseiling descends at 48 points/second; Gentle Pace runs the expedition at 65% speed. Planned wall climb/abseil transitions are limited to 1,200 points and need exposed wall contacts. Planned flights have a 65 points/second steering cap and land farther inside tops than ordinary dropped-character recovery. Windows are platforms, rather than solid boxes: rear windows can form the visual background behind a foreground climb, and the screen floor remains rescue terrain.

## Animation playground

Open **Animation Playground…** from the hiking menu, or quit the current app and run its executable with `--playground`. Preview every motion (including Landing), switch facing and background, pause/restart, slow playback, show joints, and tune stride, cadence, and bounce. **Preview time (pauses)** freezes an exact frame for inspection. Drag climbing handholds, the rope anchor, the grab pivot, or the body. A small actual-size explorer appears alongside the enlarged version. See [animation workflow and rig details](docs/ANIMATION_WORKFLOW.md).

The desktop and playground share the same articulated rig and animation controller. Knees bend towards the toes; elbow poles favour the back of the body. The desktop now drives those same movement poses from real surface routes. Final character artwork remains a later refinement.

The explorer now has a painted material finish with soft highlights, fabric/canvas detail, leather boots, warm skin shading, and contrasting coloured outlines. **Flat shading** in the playground compares it with simple fills. The existing silhouettes, proportions, and movement are preserved.

## Build and run

Requires Xcode with macOS developer support; deployment target is macOS 14 or later. Currently verified on the development Mac, not on every supported OS version.

```sh
./scripts/build.sh
open build/Build/Products/Debug/OtherSock.app
```

Or open `OtherSock.xcodeproj`, select the **OtherSock** scheme and **My Mac**, and run. If Xcode requests signing, select **Sign to Run Locally** for local development. The command-line build disables signing and is intended only for local use.

Look just above the Dock, near the horizontal centre of the primary display. The app has no Dock icon or ordinary application window. Use the hiking menu bar icon to control or quit it. Quit a running copy before launching a newly built version.

Debug guides show exposed window tops in green, sides in pink, rescue screen boundaries in teal, and the character's input bounds in yellow. The label reports character state, climbable window count, and visible edge count. Terrain refreshes at approximately 10 Hz and uses window stacking order to subtract covered edges. Guides and geometry remain in logical points on the primary display.

Window discovery reads IDs, owning process IDs, bounds, layer, and opacity metadata, without reading titles or capturing images. Normal layer-zero windows are terrain candidates; visible application panels can occlude them. The app's own windows, desktop background, and known shell helper windows are excluded. Rectangles approximate the visible shapes: rounded corners, shadows, and transparent regions within a window are not modelled. A window-detection failure reports `GEOMETRY UNAVAILABLE` and falls back to the screen floor. The expedition stays on the primary display. It hides and suspends during sleep, Space transitions, and detected full-screen Spaces, then refreshes geometry and resets its clock on return. These guards are conservative; full-screen traversal, Stage Manager, and multiple-display expeditions remain unsupported.

For a development launch with guides enabled, quit the running copy, then run:

```sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --debug-terrain
```

To inspect geometry availability without launching the overlay:

```sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --terrain-report
```

The report prints counts and existing screen-capture permission status, and never requests permission. The development context already has screen-capture access; behaviour with access denied has not yet been verified. Apple's [window metadata documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) describes the geometry API.

## Local release package

```sh
./scripts/package.sh
open build/Distribution/OtherSock.app
```

This produces a host-architecture Release app and `build/Distribution/TheOtherSock-local-arm64.zip` on Apple Silicon. It is an unsigned local prototype. Developer ID signing and notarisation are still needed before distributing it to other Macs. The app prevents a second expedition instance from launching; quit the existing copy before switching builds.

## Core checks

```sh
swift test --package-path Packages/ExpeditionCore
```

These tests cover input state, coordinates, terrain, IK, contacts, seeded routing, all travel modes, mission beats, interruption, route continuation after landing, changing-terrain soak scenarios, and runtime policy. Native focus, click-through, and window alignment still require the interactive checks in the manual checklist.

For native panel/lifecycle checks (Debug build, no real sleep or Space changes):

```sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --native-checks
```

For reproducible real-window fixtures, run `./scripts/terrain-fixture.sh`, then launch the printed app executable. `--exercise` makes the fixture move, narrow, cover, and close its own high window. The Debug explorer accepts `--fixture-terrain --start-on-window --trace-movement --performance-report` to isolate those real window records, begin on a top, and report state changes/frame timing. Add `--movement-only` to exercise wandering separately from the mission, or `--start-low --rope-demo --freeze-rope` for a paused rope-descent review. No titles or window images are read. `scripts/measure-process.py PID --seconds 30` reads local CPU time and RSS. See [prototype validation](docs/PROTOTYPE_VALIDATION.md) for results and limitations.

## Structure

- `OtherSock/App`: lifecycle and menu bar controls.
- `OtherSock/Overlay`: transparent, non-activating overlay and display layout.
- `OtherSock/Desktop`: window metadata discovery and platform filtering.
- `OtherSock/Rendering`: shared explorer rig, painted parts, mission props, ropes, and development guides.
- `OtherSock/Playground`: Debug-only clip controls, fake terrain, contact editing, and scale comparison.
- `Packages/ExpeditionCore`: platform-independent geometry, terrain construction, attachments, movement, route planning, mission rules, and runtime policy.
- [Implementation plan](IMPLEMENTATION_PLAN.md), [product plan](PLAN.md), and [manual checks](docs/MANUAL_TESTS.md).
