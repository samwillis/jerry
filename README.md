# The Other Sock

A tiny, deeply unqualified desktop expedition searching for the other sock.

## Current prototype: phases one to four

The native macOS shell draws one articulated, approximately 74-point shape explorer on a transparent SpriteKit overlay above normal windows. It breathes gently while idle, sways when held, and displays a parachute during controlled recovery. A hiking icon in the menu bar provides **Pause Expedition**, **Resume Expedition**, **Show Debug Guides**, **Animation Playground…** (Debug builds), and **Quit The Other Sock**.

The rendering overlay ignores mouse events and cannot become the key or main window. A separate 48 × 76 point, non-activating panel over the explorer accepts dragging. Grab anywhere inside that small character area, drag it aside, and release. The grab offset is preserved, and the explorer remains inside the primary display's usable area. All other overlay space passes mouse events through. There are no global keyboard shortcuts, input monitors, screen capture, or permission prompts.

While held, idle movement stops. Release carries recent drag momentum, so quick sideways or upward motions produce an arc. Holding still before release gives a normal drop. The explorer initially falls faster; its chute emerges from behind the backpack, opens overhead, and slows the descent and drift. It lands on the first suitable exposed top below its trajectory. Gentle placement within 16 points of a top snaps it directly onto the edge. It needs its full body width on the platform and 76 points of clear space above it. It follows that window when moved or resized. Losing support starts another recovery. Autonomous routes and full movement behaviours remain later work.

On landing, the explorer briefly crouches with planted feet and then rises. A settling interval prevents immediate autonomous movement. Occasional blinks have a tiny timing offset between the eyes. Dragging is still available when paused; pausing freezes visual clocks, settling, recovery, and automatic terrain polling. Resume refreshes geometry immediately. Releasing a dragged explorer refreshes geometry even while paused.

## Animation playground

Open **Animation Playground…** from the hiking menu, or quit the current app and run its executable with `--playground`. Preview every motion (including Landing), switch facing and background, pause/restart, slow playback, show joints, and tune stride, cadence, and bounce. **Preview time (pauses)** freezes an exact frame for inspection. Drag climbing handholds, the rope anchor, the grab pivot, or the body. A small actual-size explorer appears alongside the enlarged version. See [animation workflow and rig details](docs/ANIMATION_WORKFLOW.md).

The desktop and playground share the same articulated rig and animation controller. Knees bend towards the toes; elbow poles favour the back of the body. Finished character artwork and autonomous window climbing remain later work.

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

Window discovery reads IDs, owning process IDs, bounds, layer, and opacity metadata, without reading titles or capturing images. Normal layer-zero windows are terrain candidates; visible application panels can occlude them. The app's own windows, desktop background, and known shell helper windows are excluded. Rectangles approximate the visible shapes: rounded corners, shadows, and transparent regions within a window are not modelled. A window-detection failure reports `GEOMETRY UNAVAILABLE` and falls back to the screen floor. Full-screen and multi-display expedition behaviour remain unsupported.

For a development launch with guides enabled, quit the running copy, then run:

```sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --debug-terrain
```

To inspect geometry availability without launching the overlay:

```sh
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --terrain-report
```

The report prints counts and existing screen-capture permission status, and never requests permission. The development context already has screen-capture access; behaviour with access denied has not yet been verified. Apple's [window metadata documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) describes the geometry API.

## Core checks

```sh
swift test --package-path Packages/ExpeditionCore
```

These tests cover input state, coordinate conversion, edge subtraction and clipping, window-relative attachments, and support-loss recovery. Native focus, click-through, and window alignment still require the interactive checks in the manual checklist.

## Structure

- `OtherSock/App`: lifecycle and menu bar controls.
- `OtherSock/Overlay`: transparent, non-activating overlay and display layout.
- `OtherSock/Desktop`: window metadata discovery and platform filtering.
- `OtherSock/Rendering`: placeholder explorer and development guides.
- `OtherSock/Playground`: Debug-only clip controls, fake terrain, contact editing, and scale comparison.
- `Packages/ExpeditionCore`: platform-independent geometry, terrain construction, attachments, and interaction state.
- [Implementation plan](IMPLEMENTATION_PLAN.md), [product plan](PLAN.md), and [manual checks](docs/MANUAL_TESTS.md).
