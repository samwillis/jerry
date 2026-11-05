# The Other Sock

A tiny, deeply unqualified desktop expedition searching for the other sock.

## Current prototype: phases one and two

The native macOS shell draws one 72-point placeholder explorer on a transparent SpriteKit overlay above normal windows. It breathes gently while idle. A hiking icon in the menu bar provides **Pause Expedition**, **Resume Expedition**, **Show Debug Guides**, and **Quit The Other Sock**.

The rendering overlay ignores mouse events and cannot become the key or main window. A separate 48 × 76 point, non-activating panel over the explorer accepts dragging. Grab anywhere inside that small character area, drag it aside, and release. The grab offset is preserved, and the explorer remains inside the primary display's usable area. All other overlay space passes mouse events through. There are no global keyboard shortcuts, input monitors, screen capture, or permission prompts.

While held, idle animation stops. On release, the explorer settles for 0.8 seconds before breathing again. Dragging is still available when the expedition is paused, and pausing also freezes the settling interval. For now the explorer stays where you place it, including in mid-air: window attachment, falling, and parachute recovery come in later phases. The articulated dangling animation belongs to the animation playground stage.

## Build and run

Requires Xcode with macOS developer support; deployment target is macOS 14 or later. Currently verified on the development Mac, not on every supported OS version.

```sh
./scripts/build.sh
open build/Build/Products/Debug/OtherSock.app
```

Or open `OtherSock.xcodeproj`, select the **OtherSock** scheme and **My Mac**, and run. If Xcode requests signing, select **Sign to Run Locally** for local development. The command-line build disables signing and is intended only for local use.

Look just above the Dock, near the horizontal centre of the primary display. The app has no Dock icon or ordinary application window. Use the hiking menu bar icon to control or quit it. Quit a running copy before launching a newly built version.

Debug guides outline the usable screen and the character's input bounds, and report idle, held, or settling state. They do not represent discovered window terrain yet. The prototype uses only the primary display and does not promise full-screen support.

## Core checks

```sh
swift test --package-path Packages/ExpeditionCore
```

These tests cover grab offsets, bounds, release, interrupted settling, and display-change recovery. Native focus and click-through still require the interactive checks in the manual checklist.

## Structure

- `OtherSock/App`: lifecycle and menu bar controls.
- `OtherSock/Overlay`: transparent, non-activating overlay and display layout.
- `OtherSock/Rendering`: placeholder explorer and development guides.
- `Packages/ExpeditionCore`: platform-independent shared defaults; future simulation and terrain logic belong here.
- [Implementation plan](IMPLEMENTATION_PLAN.md), [product plan](PLAN.md), and [manual checks](docs/MANUAL_TESTS.md).
