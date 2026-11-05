# The Other Sock

A tiny, deeply unqualified desktop expedition searching for the other sock.

## Current prototype: phases one to three

The native macOS shell draws one 72-point placeholder explorer on a transparent SpriteKit overlay above normal windows. It breathes gently while idle. A hiking icon in the menu bar provides **Pause Expedition**, **Resume Expedition**, **Show Debug Guides**, and **Quit The Other Sock**.

The rendering overlay ignores mouse events and cannot become the key or main window. A separate 48 × 76 point, non-activating panel over the explorer accepts dragging. Grab anywhere inside that small character area, drag it aside, and release. The grab offset is preserved, and the explorer remains inside the primary display's usable area. All other overlay space passes mouse events through. There are no global keyboard shortcuts, input monitors, screen capture, or permission prompts.

While held, idle animation stops. Drop the explorer above an exposed window top: it descends and lands on the first suitable platform below it. Placing its feet within 16 points of the top snaps it directly onto the edge. It needs its full body width on the platform and 76 points of clear space above it. It follows that window when moved or resized. If the window closes, minimises, or is covered at the foothold or body, the explorer enters a temporary controlled descent to another exposed top or the desktop floor. Unsupported drops also descend. Full falling physics and parachute animation come in the movement stage.

On release or after recovery, the explorer settles for 0.8 seconds before breathing again. Dragging is still available when paused; pausing freezes settling, recovery, and automatic terrain polling. Resume refreshes geometry immediately. Releasing a dragged explorer refreshes geometry even while paused. The articulated dangling animation belongs to the animation playground stage.

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
- `Packages/ExpeditionCore`: platform-independent geometry, terrain construction, attachments, and interaction state.
- [Implementation plan](IMPLEMENTATION_PLAN.md), [product plan](PLAN.md), and [manual checks](docs/MANUAL_TESTS.md).
