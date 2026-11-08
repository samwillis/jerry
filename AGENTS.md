# Developer guide

Instructions for coding agents and contributors working on Jerry. Run commands from the repository root. The [README](README.md) introduces the app; keep build commands, debugging instructions and implementation details here or in `docs/`.

## Working on the app

The bundle identifier and Keychain service are persistent compatibility identifiers. Keep them stable when changing the app’s public name, so existing preferences and credentials remain available. Keychain items must have explicit Jerry display labels; relabel legacy entries without replacing secrets or showing background authentication dialogs.

- Use Swift, AppKit and SpriteKit for the native macOS app. Keep platform-independent terrain, movement and mission logic in `Packages/ExpeditionCore`.
- Jerry is the single explorer. AI actions reach controls through his physical movement and interaction; preserve this behavior when changing task execution.
- Preserve click-through desktop behavior and non-activating dragging. Keyboard capture belongs to manual control and the task input, not idle exploration.
- Keep local terrain capture separate from AI image sharing. Preserve the explicit permission and sharing settings; store credentials in Keychain. Never commit credentials or local account data.
- Welcome, Settings and the journal share the notebook theme and native macOS window controls. Reuse the existing rig for character artwork and icons. Keep the menu to at most two levels.
- Use the plans as design context; dated status notes describe earlier increments. Check current code and validation before treating historical requirements as unfinished work.
- Run checks relevant to the change. Interactive focus, dragging, native chrome and permission behavior need manual verification; automated geometry checks do not establish those behaviors. Documentation-only edits need link and diff checks, not an app rebuild.
- Update the relevant docs when behavior or workflows change. Do not claim public distribution readiness for an unsigned local build.

## Build and run

Requires Xcode with macOS developer support; deployment target is macOS 14 or later. Currently verified on the development Mac, not on every supported OS version.

```sh
./scripts/build.sh
open build/Build/Products/Debug/Jerry.app
```

Or open `Jerry.xcodeproj`, select the **Jerry** scheme and **My Mac**, and run. If Xcode requests signing, select **Sign to Run Locally** for local development. The command-line build disables signing and is intended only for local use.

Look just above the Dock, near the horizontal centre of the primary display. The app has no Dock icon; its primary interface is the menu bar and desktop overlay. Use the Jerry menu bar icon to control or quit it. Quit a running copy before launching a newly built version.

Debug guides show exposed window tops in green, sides in pink, rescue screen boundaries in teal, and the character's input bounds in yellow. The label reports character state, climbable window count, and visible edge count. Terrain refreshes at approximately 10 Hz and uses window stacking order to subtract covered edges. Guides and geometry remain in logical points on the primary display.

Window discovery reads IDs, owning process IDs, bounds, layer, and opacity metadata, without reading titles or capturing images. Normal layer-zero windows are terrain candidates; visible application panels can occlude them. The transparent rendering/input panels and prompt, desktop background, and known shell helpers are excluded. Substantial titled Jerry windows, including the journal, are climbable terrain and occlude edges behind them; do not exclude the whole application PID. Terrain occlusion uses rectangles: shadows and transparent regions within a window are not modelled. Rope contact additionally uses a per-window corner radius. A window-detection failure reports `GEOMETRY UNAVAILABLE` and falls back to the screen floor. The expedition stays on the primary display. It hides and suspends during sleep, Space transitions, and detected full-screen Spaces, then refreshes geometry and resets its clock on return. These guards are conservative; full-screen traversal, Stage Manager, and multiple-display expeditions remain unsupported.

For a development launch with guides enabled, quit the running copy, then run:

```sh
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry --debug-terrain
```

To inspect geometry availability without launching the overlay:

```sh
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry --terrain-report
```

The report prints counts and existing screen-capture permission status, and never requests permission. Permission behavior depends on the local machine; do not assume screen-capture access is granted. Consult the validation notes for tested and untested cases. Apple's [window metadata documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) describes the geometry API.

## Checks

```sh
swift test --package-path Packages/ExpeditionCore
```

These tests cover input state, coordinates, terrain, IK, contacts, seeded routing, all travel modes, mission beats, interruption, route continuation after landing, changing-terrain soak scenarios, and runtime policy. Native focus, click-through, and window alignment still require the interactive checks in the manual checklist.

Quit the running app before native checks to avoid global-shortcut conflicts. For native panel/lifecycle checks (Debug build, no real sleep or Space changes):

```sh
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry --native-checks
```

For AI integration and journal/settings checks (Debug build):

```sh
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry --agent-checks
```

For reproducible real-window fixtures, run `./scripts/terrain-fixture.sh`, then launch the printed app executable. `--exercise` makes the fixture move, narrow, cover, and close its own high window. The Debug explorer accepts `--fixture-terrain --start-on-window --trace-movement --performance-report` to isolate those real window records, begin on a top, and report state changes/frame timing. Add `--movement-only` to exercise wandering separately from the mission, or `--start-low --rope-demo --freeze-rope` for a paused rope-descent review. No titles or window images are read. `scripts/measure-process.py PID --seconds 30` reads local CPU time and RSS. See [prototype validation](docs/PROTOTYPE_VALIDATION.md) for results and limitations.

## Local release package

```sh
./scripts/package.sh
open build/Distribution/Jerry.app
```

This produces a host-architecture Release app and `build/Distribution/Jerry-local-arm64.zip` on Apple Silicon. It is an unsigned local prototype. Developer ID signing and notarisation are still needed before distributing it to other Macs. The app prevents a second expedition instance from launching; quit the existing copy before switching builds.

## Developer ID signing and notarisation

Sign in through **Xcode → Settings → Apple Accounts**; signing in to the Apple Developer app alone does not add an Xcode account. Select the distribution team and install a **Developer ID Application** certificate with its private key. An active membership and suitable team permissions are required. Do not change the existing bundle identifier when selecting a team.

```sh
./scripts/package-signed.sh "Developer ID Application: Company (TEAMID)" TEAMID
```

The script checks the local identity, builds a fresh host-architecture Release app with Hardened Runtime and a secure timestamp, omits the debugger entitlement, and verifies its signature. Signed app bundles stay in `~/Library/Developer/Jerry/SignedRelease` rather than synced Documents folders, where Finder metadata can invalidate strict signature verification. Direct-distribution builds run outside App Sandbox because Jerry interacts with other applications; Accessibility and Screen Recording permissions remain required where applicable. The local unsigned build workflow is unchanged.

For notarisation, first store credentials using `xcrun notarytool store-credentials jerry-notary` in a user-controlled Terminal session, or configure a suitable App Store Connect API key. Keep passwords, keys and certificates outside the repository. Then pass the Keychain profile as the third argument:

```sh
./scripts/package-signed.sh "Developer ID Application: Company (TEAMID)" TEAMID jerry-notary
```

The script submits to Apple, staples and validates the ticket, checks Gatekeeper, then recreates the ZIP in `build/SignedDistribution`. A signature-only ZIP is labelled as not notarised and should not replace the notarised download. For interactive notarisation without separate credentials, archive with the same signing settings (and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`), then use Xcode Organizer’s direct-distribution workflow. Do not pass `SKIP_INSTALL=NO` globally: it also installs the Swift package object and turns the archive into a generic archive. The equivalent command-line export uses `method=developer-id`, `destination=upload`, `teamID`, and manual signing in an export-options plist, then `xcodebuild -exportArchive -allowProvisioningUpdates`. After Apple finishes processing, `xcodebuild -exportNotarizedApp -archivePath … -exportPath …` exports the notarised app. Verify the staple and Gatekeeper result before packaging. An unsigned local build does not validate this workflow. Test desktop permissions, Keychain access, AI sign-in and physical interactions with the signed build before publishing it.

## Structure

- `Jerry/App`: lifecycle, menu bar controls and the shared desktop permission/setup flow.
- `Jerry/Overlay`: transparent, non-activating overlay and display layout.
- `Jerry/Desktop`: window metadata discovery and platform filtering.
- `Jerry/Agent`: AI providers, credentials, computer interaction, Settings and the journal.
- `Jerry/Rendering`: shared explorer rig, painted parts, mission props, ropes, and development guides.
- `Jerry/Playground`: Debug-only clip controls, fake terrain, contact editing, and scale comparison.
- `Packages/ExpeditionCore`: platform-independent geometry, terrain construction, attachments, movement, route planning, mission rules, and runtime policy.
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md), [product plan](docs/PLAN.md), and [manual checks](docs/MANUAL_TESTS.md).

## Journal persistence

The journal saves to `~/Library/Application Support/Jerry/Expeditions/<UUID>/journal.jsonl`. Preserve the versioned append-only records and per-expedition directories. Journal photographs are local JPEG assets referenced by optional UUID filenames on entries; never automatically attach them to AI requests. Keep writes off the main thread, preserve streaming deltas and flush task/shutdown boundaries. A restored task must remain paused until the user gives a direction; never replay saved computer actions automatically. Credentials and opaque provider transcripts do not belong in journal files. Tests must pass `journalDirectory: nil` / `storageDirectory: nil` or use disposable directories, never the real history. See [journal storage](docs/JOURNAL_STORAGE.md).

## Global shortcuts

**Settings → Controls → Global shortcuts** records the Take/release control and Ask Jerry bindings. Each can be cleared with Delete while recording; Escape cancels, and Restore defaults resets both. Custom combinations require Command, Option or Control and are saved in UserDefaults. The menu and welcome guide reflect the current bindings.

`Jerry/App/GlobalShortcuts.swift` owns the shortcut value, preferences, local recorder and Carbon registration. Rebinding must retain the previous registration on conflict. Recording temporarily unregisters both global shortcuts and intercepts keys only in the Settings key window; commit/probe happens after key-up. Cancel, focus loss, section changes and closing Settings must restore registrations. No global keyboard monitor or extra Accessibility permission is needed for configuration. Native checks use an isolated preferences domain for persistence tests and exercise registration changes, conflicts, held-key suppression and clearing.

## Trigger an activity

Enable **Developer Tools** in **Settings → Advanced**, then use Jerry menu → **Developer Tools** for walking, climbing, grappling, rope actions, parachuting or looking for the sock. The explorer approaches suitable real terrain first, then performs the activity and returns to the idle-exploration setting. Unreachable choices are labelled and disabled. Requests made during a jump/corner/flight queue safely for the next support. **Enable Idle Exploration** controls automatic wandering after the action finishes.

Climbs now pull over the lip into a planted-foot standing pose; rope descents crouch and back over the lip; parachute trips crouch and jump clear before deploying. The rope pins on the top edge, follows its window’s rounded corner (12 points for notebook windows, an estimated 16 on macOS 26+ or 10 on older macOS for external windows), and leaves along the mathematical tangent towards the hands. Both straight-to-curve joins remain tangent as the explorer descends.

Aiming shows a green snapped rim when it is reachable, or an orange marker when no valid anchor is selected. Starting aim suggests a nearby rim; holding G redirects the arrows from movement/swinging to aiming. Release G to fire and return the arrows to movement. The mouse does not steer the aim. Refiring while hanging keeps the old rope attached while the new hook flies. The explorer transfers to the new line only after it latches; a failed shot leaves the old line intact. Left/right applies force along the rope tangent, with a 260 pt/s drive cap; opposite input brakes the swing.

## Animation playground

Enable Developer Tools in **Settings → Advanced**, then open **Developer Tools → Animation Playground…** from the Jerry menu, or quit the current app and run its executable with `--playground`. Preview every motion (including Landing), switch facing and background, pause/restart, slow playback, show joints, and tune stride, cadence, and bounce. **Preview time (pauses)** freezes an exact frame for inspection. Drag climbing handholds, the rope anchor, the grab pivot, or the body. A small actual-size explorer appears alongside the enlarged version. See [animation workflow and rig details](docs/ANIMATION_WORKFLOW.md).

The desktop and playground share the same articulated rig and animation controller. Knees bend towards the toes; elbow poles favour the back of the body. The desktop now drives those same movement poses from real surface routes. Use the shared rig rather than introducing separate desktop and playground artwork.

The explorer now has a painted material finish with soft highlights, fabric/canvas detail, leather boots, warm skin shading, and contrasting coloured outlines. **Flat shading** in the playground compares it with simple fills. The existing silhouettes, proportions, and movement are preserved.

## Application icon

The app icon uses Jerry’s actual rig on a warm paper tile. The master is `Jerry/Resources/AppIcon.png`; both builds bundle `AppIcon.icns`. Run `./scripts/render-app-icon.sh` to regenerate the master and native macOS sizes after character artwork changes. The exporter bakes geometry at icon resolution and leaves normal desktop rendering unchanged.

## Internal-window capture checks

For repeatable development checks, run the Debug executable with `--feature-checks` (uses existing Screen Recording access and creates its own disposable capture window). `scripts/terrain-fixture.sh` builds a scrollable test window; launch its executable with `--internal-terrain`, then launch Debug Jerry with `--inside-windows --fixture-terrain --debug-terrain`. These flags do not persist the opt-in setting.

## Documentation

- [Product plan and future ideas](docs/PLAN.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Detailed prototype behavior](docs/PROTOTYPE_GUIDE.md)
- [Computer-task integration](docs/AGENT_PROTOTYPE.md)
- [Animation and rig workflow](docs/ANIMATION_WORKFLOW.md)
- [Manual test checklist](docs/MANUAL_TESTS.md)
- [Validation evidence and known limits](docs/PROTOTYPE_VALIDATION.md)
