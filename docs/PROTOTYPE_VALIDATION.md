# Phases 5–7: local prototype validation

## Delivered scope

One explorer on the primary macOS display can walk real window tops, climb exposed sides, descend an anchored rope, parachute with limited steering, recover and land, and run a repeating sock/banana adventure. The body remains draggable throughout, including while paused. This is a local prototype, version 0.1.0 (build 1), with an unsigned host-architecture Release app and archive.

The implementation uses window metadata, never titles or window images. Autonomous adventures require no new permissions, global input hooks, network service, or background agent. The later optional keyboard/desktop-click increment is documented below. The existing shape rig and painted finish are retained.

## Requirement audit

| Plan requirement | Implementation and evidence |
| --- | --- |
| 5.1 Fixed simulation and bounded catch-up | `ExplorerInteraction.advance` runs at 120 Hz, capped at 30 catch-up steps. `testFixedStepIsDeterministicAndCatchUpIsBounded` compares 30/60 Hz presentation and checks a 60-second stall. |
| 5.2 Walking, climbing, falling/landing, parachuting and abseiling | Surface state machine, `TravelStep`, shared rig, support-relative climbing grips/feet, canopy and anchored rope. Numerical tests verify every climbing stroke stays inside limb reach, remains planted during stance, and follows a moving support. `testAutonomousExplorerWalksClimbsAbseilsAndParachutes` covers all modes. The recovery state contains falling/deployment/open-chute subphases. Investigation is a mission stage. |
| 5.3 Swept landings | Existing horizontal/diagonal sweep tests, plus `testPlannedParachuteLandsOnItsWindowInsteadOfMissingTheEdge`. Planned flights aim at least 40 points inside window tops and respect available steering time. |
| 5.4 Traversable graph and limits | `NavigationGraph` joins exposed stand points and side contacts. Covered/gapped edges, insufficient headroom, excessive climb distance, and unreachable flights are rejected. Rear windows do not block foreground contacts. Screen floor remains rescue terrain. |
| 5.5 Terrain changes and revalidation | Current transitions revalidate on snapshots; future transitions revalidate before entry. Tests move a window during climbing, obscure a wall, remove a rope anchor, and remove discovery supports. Invalid support enters recovery. |
| 5.6 User drops and interruptions | Grab cancels the route, queued landing continuation, momentum and mission immediately, including without an intervening tick while paused. Release starts local attachment or fresh recovery, rather than returning to an old route. Tests interrupt all travel modes and mission beats. |
| 5.7 Bounds and reset | Origin bounds constrain walking, flight and user placement. Display changes cancel stale navigation/coordinates. Menu includes Reset Expedition. Changing-terrain soak tests keep every position finite and inside bounds. |
| 6.1 Mission stages | `BananaMission`: select, spot, approach, cross, investigate, reveal, update map, rest. Tests complete and repeat the sequence unattended. |
| 6.2 Reachable, window-relative discovery | Props use terrain anchors; stand points stop beside the prop. Tests move and remove destinations. Invalid targets cancel selection and permit a new expedition. |
| 6.3 Prefer valid parachute crossings, use alternatives | Mission selection usually prefers reachable routes containing a chute, with occasional rope routes for variety. Without one it chooses reachable climbs/walks, or rests safely. Sparse and suitable layout tests cover both. |
| 6.4 Props | Code-native binoculars, suspected sock silhouette, banana, flag, map, canopy and rope render in the click-through layer. Only the explorer's body has an input panel. |
| 6.5 Events and cancellation | Fixed-clock stages and motion state drive animation; no asynchronous completion callbacks can survive a grab. Queued route steps resume after a valid landing. A regression test covers flight → floor landing → climb → top. |
| 6.6 Comic timing | Timed spotting/anticipation, investigation, banana disappointment, map marking and rest, with small speech captions. Native runtime showed repeated reveals/map/rest cycles. |
| 7.1 Minimal saved settings | Pause, Gentle Pace and debug guides persist through UserDefaults. Mission persistence is intentionally deferred by the plan. |
| 7.2 Pause and sleep/wake | Runtime policy suspends scene updates and routine geometry polling. Native checks verify no timer reads while paused, paused drag callbacks, sleep hiding, preserved explicit pause, refresh/resume and cleanup. Wake resets scene timing; catch-up remains bounded. |
| 7.3 Display/desktop protection | Primary-display layout is rebuilt on display changes. Space transitions hide and pause before refreshing. A conservative front-window guard hides full-screen Spaces. Geometry/policy tests and native visibility checks exercise the guard path; real OS transition coverage is limited as described below. |
| 7.4 Performance | 30 fps presentation, fixed simulation, cached paint textures and stable node counts. Local frame/CPU/RSS measurements are below. |
| 7.5 Runnable package and checklist | Debug/Release builds, `scripts/package.sh`, native check command, disposable terrain fixture, process measurement script, README and this validation record. Public signing/notarisation remains later distribution work. |

## Verification performed

- **66 core tests pass**, including a simulated hour (216,000 presentation steps) of changing terrain, repeated grabs, recovery, bounds checks and mission progress. This is simulated time, not an hour of native UI observation.
- **15 native AppKit checks pass** through `--native-checks`: visible panels; click-through renderer/body-only input; panels cannot become key; 48×76 point hit area; pause; zero paused timer reads; paused drag callback placement; rendering during paused drag and the final release frame; sleep hiding; explicit pause survives wake; unsupported-desktop hiding; refresh/resume; unchanged frontmost app; panel/timer cleanup.
- A separate native rope tour also exercised abseiling to the floor. Native movement and mission runs used the ordinary window metadata provider with disposable windows from a separate fixture process. Debug `--fixture-terrain` filters to those real records for reproducibility. The stable run showed top walking, parachute landing on the lower window, continued walking after landing, repeated banana/map/rest cycles, floor recovery, and climbing from the floor onto the lower window.
- An exercising fixture moved, narrowed, covered and closed its own high window. Native traces showed route abandonment/recovery and a later completed expedition. Core tests provide the precise assertions for each of those changes during specific movement modes.
- Native screenshots/accessibility inspection showed the autonomous walking rig, live terrain guides, banana captions, and a frozen abseiling pose with its rope attached to the real window corner and its tail below the hands. Computer automation could inspect the explorer but could not reliably attach to the custom fixture controls or synthesize a successful explorer drag; the input bridge itself is unchanged from the user-confirmed dragging/focus behaviour earlier in this project. The new travel/mission interruption behaviour has focused core coverage, and native callback placement/focus is checked directly.
- Debug and Release builds pass. Release excludes the development playground, fixture filters and native-check entry point. Packaged executable is arm64 with minimum macOS 14 and version 0.1.0. Launching a second packaged copy while the development copy runs exits with an already-running message instead of adding panels.

## Performance samples

Development machine: Apple Silicon, macOS 27.2 / Xcode 27.2. One explorer, primary display, two real fixture windows. These are short local observations, not broad hardware benchmarks.

| Sample | Result |
| --- | --- |
| Debug active, initial 30.4 seconds | 9.56% of one CPU core on average; RSS 73.4–81.6 MiB, ending 74.6 MiB. Startup is included. |
| Debug frame timing, repeated 300-frame windows | 30.0 fps; p95 roughly 35.0–35.3 ms; observed maxima about 35.4 ms. |
| Release active, initial 30.4 seconds | 9.67% of one CPU core on average; RSS 79.7–81.1 MiB. Startup and unfiltered desktop geometry are included. |
| Release paused, 15.2 seconds | 0.07% of one CPU core; RSS 77.6–77.8 MiB. |
| Debug scene after repeated mission cycles | 87 attached scene nodes throughout sampled windows; later RSS remained around 71–80 MiB. No growing panel/scene-node population observed. |

Use `--performance-report` on Debug to repeat frame/node measurements, and `python3 scripts/measure-process.py PID --seconds 30` for read-only CPU/RSS samples. The 30 fps target is retained: sampled animation timing is steady and pausing removes almost all ongoing CPU work.

## Known limits

- Primary display only. Full-screen traversal, Stage Manager behaviour and multi-display expeditions are unsupported. The app hides during detected full-screen/Space transitions rather than claiming traversal support there. Actual physical sleep/wake and every macOS Space transition were not forced overnight; native checks exercise the real visibility/lifecycle methods without putting the user's machine to sleep.
- Geometry is rectangular and polled around 10 Hz. Rounded corners, shadows, transparent window regions and occlusion between samples remain approximations. There must be room for the explorer and a reachable exposed edge; otherwise it safely rests or uses floor terrain.
- Denied screen-capture permission has not been tested on a separate account. The app requests no permission and falls back to floor-only terrain when geometry discovery fails.
- Art and comic timing remain prototype-quality. A discovery repeats after rest; there is no saved expedition journal or team of explorers yet.
- The Release archive is for local use on this development architecture. Developer ID signing, notarisation, Intel packaging and wider macOS/hardware testing remain distribution work.

## Repeatable commands

```sh
swift test --package-path Packages/ExpeditionCore
./scripts/build.sh
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry --native-checks
./scripts/package.sh
```

For real-window test terrain:

```sh
./scripts/terrain-fixture.sh
build/TerrainFixture.app/Contents/MacOS/TerrainFixture --exercise
# In another terminal, with the normal explorer copy quit:
build/Build/Products/Debug/Jerry.app/Contents/MacOS/Jerry \
  --fixture-terrain --start-on-window --trace-movement --performance-report
```

Omit `--exercise` for a stable layout. Add `--start-low --rope-demo` to begin a reproducible rope descent from the lower window; `--freeze-rope` pauses it partway for visual review. Add `--movement-only` to the explorer to isolate traversal from mission selection. Quit the fixture after testing. These switches are development tools, not requirements for normal use.


## Movement and activity refinement — 6 November 2026

- 78 core tests pass. New coverage checks walking stance-foot cancellation in both directions, climbing pull distance/inverse phase, fixed contacts during stance, lower climbing boots and consistent knee branches, corner path endpoints/continuity, planted-boot weight transfer, all four manual travel activities, safe queuing, manual completion/rest, grabs/support loss during transitions, rounded-rope mirroring/clearance, and tangent directions at both curve joins over a range of hand positions.
- 19 native checks pass, including submenu construction, reachable-route enablement, dispatching Walk into the desktop actor, and returning to automatic adventures. The native menu test restores the saved pause preference after checking dispatch.
- Native playground review covered a lip pull, mirrored weight transfer, jump clearance and the tangent rounded-corner rope preview, all with zero clamped contacts. macOS status-item automation timed out, so menu dispatch was verified through the real NSMenu action mechanism in the native check harness.
- Debug and Release packages were rebuilt for these changes. Earlier performance measurements remain historical; this refinement did not rerun the hardware benchmark.


## Grapple and unified rope simulation — 6 November 2026

- 94 core tests pass. Added checks for slack free fall, pendulum period against `2π√(L/g)`, no spontaneous energy gain, conserved angular momentum while reeling without gravity/friction, 30/120 Hz equivalence, taut-length bounds, rope-pose reach at left/right angles, and complete mirrored grapple → swing → climb → mantle journeys.
- Integration tests switch climbing/descending/swinging on the same anchor without teleporting or clearing velocity; release retains velocity. A grounded abseiler can climb the same line without another shot. Moving/lost anchors, lost landing supports, simultaneous support loss, long descents and blocked mantle approaches are covered. Existing simulated-hour terrain/mission tests still pass.
- Native checks retain all 19 passes, including dynamic activity menu construction and dispatch. Native screenshots showed the launcher with its hook and trailing line in flight, then a latched harness/rope pose on real fixture geometry. The unfrozen live trace completed grappling → swinging → rope climbing → mantle → settling → idle on the lower real fixture window. Its sampled 300-frame windows held 30.0 fps, p95 roughly 33.8–34.3 ms, with a stable scene-node count.
- The rope is a massless unilateral constraint with 240 Hz substeps, controlled payout/reeling, damping and host-wall/platform/display contacts. Rendering models one rounded corner and a slack free span. This does not claim general rope/obstacle wrapping, elastic rope or rope-to-rope collisions.

### Higher and front-rim grapple — 6 November 2026

97 core tests and 19 native checks pass; Debug and packaged Release builds succeed. New coverage checks a 1,000-point-high aligned shot through the front of a window, an edge-to-edge window without exposed sides, and moving straight-span anchors. Existing angled rope constraints and overlapping-window mantle regressions pass. Native `--front-only` fixture run fired from (855, 2), climbed straight up the front, mantled at y≈654, and stood on the top at (855, 712). The rendered climb and final planted stance were inspected; frame reports held 30 fps with 91 nodes.

### Player control — 6 November 2026

108 core tests pass, including player-control scenarios: no autonomous drift, gait-matched movement/release, ballistic jumping and air steering, no double jump, ledge falls/drop-through, wall climb/hold/mantle, connected front-rope control, roof lowering/abseil, safe mode exit, changing terrain, takeover mid-walk without snapping, and safe corner completion on exit. 28 native checks pass, including local key routing, opposing/released directions, one-shot jump/click repeat suppression, modifier pass-through, Escape teardown, coordinate conversion, and the denied-Accessibility click gate.

Live native key input through the focused control window moved the explorer from x855 to x≈924 with Right; G fired; Up entered rope climbing; releasing held rope length; Down descended; Space jumped off; Escape closed the key window and returned to autonomous mode. Focused movement was checked interactively because command-line native checks can inspect routing and key-window capability but cannot establish actual activation under macOS focus-stealing rules.

Accessibility access is false in this build's test context. No permission was granted and no external control press/mouse click was executed. The untrusted path performs no click; the permitted AXPress/fallback-click path remains an interactive acceptance check once the user grants access. Only direct E presses request interaction, and repeated keyDown events cannot produce repeated clicks. Movement itself does not require access.


### Pointer awareness — 6 November 2026

Debug/Release builds and all 27 applicable native checks pass (the denied-permission check is skipped because Accessibility access is now granted). The shared rig's eye/head response was inspected in the playground, including mirrored facing. Coordinate diagnostics during development confirmed conversion from the current AppKit screen pointer through the window/view/scene into head space; those diagnostics were removed. Eyes lead the head and blend back to the base expression at distance, retaining asynchronous blinks. No simulation or input-panel geometry changed; current-pointer sampling requires no event monitor or extra permission. Visual timing remains subject to user preference.


### Player jump fluidity — 6 November 2026

114 core tests pass. New jump checks cover planted soles through preparation, lift beginning after extension, continuity into the airborne pose, reachable limbs throughout the full preview, coasting on release, one landing event, moving/removed support during preparation, and ceiling contact without hovering. All 27 applicable native checks pass (the denied-Accessibility case is skipped when permission is granted). Debug and packaged Release builds pass.

The crouch, fully extended take-off, airborne tuck and landing compression were inspected in the native playground at 3× and actual desktop scale. All inspected frames reported zero clamped contacts. Preparation remains a short fixed delay rather than a charged jump; jump height stays close to the previous height, with a slightly quicker airborne arc. Overall feel still benefits from the user's hands-on assessment.


### Rope-climbing elbows — 6 November 2026

116 core tests pass. New coverage sweeps two complete pulls at every five degrees from −80° to +80°: arm reach, shoulder-side constraints, fixed bend signs, and frame-to-frame joint continuity. Vertical loaded grips also remain fixed in world space against the shared reeling clock. Debug/Release builds and all applicable native checks pass. Native playground inspection checked opposite pulls and mirrored facing, both with zero clamped contacts.


### Idle exploration, aimed grapples and retained control — 6 November 2026

126 core tests pass, including resuming idle exploration after an explicit action, a single explicit sock search while idle exploration is off, disabling idle exploration mid-walk, passive drop/landing while idle exploration is off, respecting the preference after manual control, selecting/rejecting aimed rims, firing in flight, preserving momentum when replacing an attached line, and pumping/braking a swing tangentially. 35 native checks pass, covering G hold/release, click-induced focus loss, the simplified menu, idle checkbox behavior, and registering/dispatching/unregistering the system hotkey with repeat suppression.

Real disposable fixture runs received native AXPress clicks and custom-canvas fallback clicks, both from the floor and while attached to a rope. The control HUD remained active with focus after each click; G produced firing→swinging and arrows continued movement/climbing. Accessibility was already granted; no new permission was granted by these checks. The global shortcut registered successfully; native dispatch invokes its callback. Targeted computer-use keyboard injection did not trigger the OS-wide shortcut path, so physical cross-app shortcut use remains a manual acceptance check. Both Debug and packaged Release builds pass.


### Rope/arm visibility — 6 November 2026

Debug and packaged Release builds pass, with all 35 applicable native checks passing. A real high-window fixture climb was inspected: the formerly hidden arm is visible in front of the jacket, and the line remains visible across the body beneath the hands. This is a render-layer change; physics, rig endpoints and input bounds are unchanged.


### Welcome and keyboard-only aim — 6 November 2026

Debug and packaged Release builds and all 42 applicable native checks pass. The checks cover arrow/diagonal aiming while G is held, movement suppression during aim, firing once on release, restoring held movement, the transparent mouse-ignoring input target, and first-run guide presentation/completion with preference restoration. The real guide was inspected after layout refinement: all key rows, idle checkbox, permission state and footer buttons are visible at the tested display size. Take Control closed it; real Right input moved the explorer without a controls window. A combined G+Right computer-use injection could not be completed reliably; native input-routing checks cover that chord.

Manual mode now uses a 1×1 transparent, borderless keyboard target rather than the previous instructions panel. The welcome guide is shown on the first normal launch and remains available through Controls & Tips. Debug `--welcome` previews it without consuming first-run completion. No permission is requested just by opening the guide.


### Explorer shadow — 6 November 2026

The animated silhouette shadow was inspected against the welcome screen's light background. An initial compound-path render showed overlap artifacts; the final version uses opaque individual shapes composited through a blur, producing a clean, soft shadow. Debug and packaged Release builds and all 42 applicable native checks pass. This changes presentation only; the character's input area remains unchanged. With both the welcome illustration and desktop explorer rendering, a development frame report measured approximately 27–28 fps during inspection; this is not a claim of unchanged rendering cost.


### Running and faster rope work — 6 November 2026

132 core tests pass, including new running travel/animation synchronization, no planted-sole sliding, an airborne phase with reachable legs, Shift release, running jump momentum without extra height, optional idle-running behavior, faster ascent/descent on the same line, and unchanged gravity-driven swing timing. All 45 applicable native checks and Debug/packaged Release builds pass. The run was inspected enlarged and at desktop size with zero clamped contacts. Real Shift+Right input produced running then idle in the desktop trace without a controls window. Native checks cover modifier routing/reset and sprite-local shadow geometry.

Both faster options are off by default. The fast rope setting changes motor work only; it is not a simulation-wide time scale. Normal/fast locomotion blends through the existing rig transition rather than introducing a separate physics mode.

## Softer shadow behind ledges — 6 November 2026

The explorer casts a lighter, diffuse shadow below his body, using a slightly smaller silhouette and transparent padding so the blur has no hard rectangular boundary. A post-blur mask hides shadow pixels behind nearby supporting window tops, including when the rig faces the other direction. Hanging in front of a window retains the cast shadow. This uses window geometry as a visual approximation rather than inserting an overlay between other applications’ windows.

Debug and packaged Release builds pass, along with all 48 native checks. New checks cover support-lip clipping, mirrored facing and a front-of-window hang. The existing asynchronous final-frame pause check now polls to a bounded deadline to accommodate first-use rendering setup. Visual inspection in the light-background animation playground confirmed a soft downward shadow, no blur cutoff and a clean supporting window face. The body’s interaction bounds remain unchanged.


## Internal window features — 6 November 2026

140 core tests pass. The eight new feature tests cover colour-region versus hairline classification and text rejection, identity through a 60-point scroll, stale/missing feature expiry, swept internal-ledge landing, combined window/content motion, horizontal traversal and dropping, bidirectional vertical climbing and intersecting routes, foreground occlusion, rope-to-crack transfer, and a central drop that must not recatch its starting ledge. The former Down-to-abseil roof test now checks the requested step-off/parachute behaviour and held-key latch.

51 native checks pass, including the public terrain-guide menu, explicit internal-window opt-in setting, and 240 sampled crack/vertical poses without unreachable limb targets. Six separate live ScreenCaptureKit checks pass: block ledge, horizontal hairline, vertical crack, stable identity/attachment through a real 60-point content scroll, persistence on unchanged frames and hold removal when capture stops. These live checks used already-granted Screen Recording access; no permission was requested or changed.

Debug and packaged Release builds pass. Capture is limited to one prioritized window, a 20 fps stream, three queued buffers, reduced RGB resolution, serial background analysis and stale-frame rejection. Feature prediction is limited to 50 ms; hold freshness is limited to 250 ms. Geometry sample timing is kept separate from the faster feature/presentation updates, so moving rope anchors do not gain inflated support velocity. No desktop images are written to disk or sent over the network. The coloured internal guides were also observed on the running overlay. A scrollable disposable native fixture is available through `--internal-terrain` for interactive follow-up. Detection is conservative and straight-line only; rapid reflows or ambiguous untextured scrolling surfaces may lose a hold and recover rather than preserve an incorrect attachment.


## Faint boundaries and text rejection — 6 November 2026

Increased window capture from half-point resolution capped at 480 × 360 to point resolution capped at 960 × 720. Reduced RGB boundary contrast from 0.22 to 0.045 and thin-rule contrast to 0.03; retained a local transition check so gentle gradients do not turn into terrain. Minimum horizontal/vertical lengths are now 64/76 points, with a 24-pixel sample floor. Detector scans use two-pixel steps along each candidate, with early rejection of flat pixels to bound the additional work.

A local Vision fast text request runs on changed frames in the capture worker. Its recognised strings are discarded immediately; padded text rectangles exclude candidate edges and underlines. A positive text match also invalidates a previously tracked hold immediately, bypassing missed-frame grace. If text analysis fails, that frame publishes no holds rather than unfiltered text. Unchanged frames reuse the previous result without rerunning recognition or detection.

143 core tests pass, including faint single-pixel rules, low-contrast blocks, exclusion of a long text underline without excluding a nearby divider, immediate removal of a previously tracked text hold, and gradient rejection. The live capture harness now has ten checks: it identifies the actual rendered text region, accepts a faint one-point line and low-contrast block, rejects underlined text, and retains the existing scrolling/attachment checks. Native lifecycle/menu/rig checks and Debug/Release builds are also verified for this revision.


## Grapple attachment after internal-window exploration — 6 November 2026

Fixed a departure-support regression: capture prioritises the hook’s destination window, which can remove the source window’s detected ledge while a shot is still flying. Losing that source attachment now enables ballistic free flight while preserving the valid hook/target, rather than cancelling the shot. Hold transfers are also blocked during firing and for the first 250 ms after a rope mode change, so an internal hold cannot interrupt the latch.

A front-rim pin now validates its exposed window top and hanging-body clearance independently of standing room above the roof. Windows near the top of the usable display can be hooked. Reeling in keeps the body on screen; if there is no safe mantle, the explorer hangs on the attached line instead of discarding it. Moving that window lower permits the same rope to finish its mantle normally. Covered rims remain rejected.

146 core tests and 51 native checks pass; Debug and packaged Release builds pass. Three new regression cases exercise capture switching away from a departure ledge during firing, prevention of an in-flight transfer, and a hook/climb/hang/move-window/mantle sequence with no initial standing room above the roof.


## Toolbar crouch — 6 November 2026

149 core tests pass. New cases cover planted feet and an eased enter/exit, click-marker height, mirrored click reach, the 40-point/s crouched gait, Shift suppression, cleanup on control release and keeping crouch out of jumping/rope poses. Native checks cover holding/releasing C, clicking E without losing crouch/control, and sampled crouched-walking limb reach. The hold-C state is also reconciled from the physical key after desktop clicks. The playground Crouching clip was visually inspected at enlarged and actual desktop size with zero clamped contacts. Debug and packaged Release builds pass.

## Swift agent and helper prototype — 6 November 2026

- Core: 156 tests pass, including dependency scheduling, permanent leader, helper retirement, stale completion rejection and bounded SSE parsing without blank-line separators.
- Native regression checks: 55 pass.
- Agent checks: 10 pass, including rendered helper lifecycle, serial/parallel recruitment, binocular inspections, the native Foundation Models image/tool/result/final-response loop, JSON Schema encoding and PKCE vectors.
- Live ChatGPT: browser consent completed by the user; callback validation and Keychain persistence succeeded. Model catalog loaded eight models. A `gpt-6.1-sol` image/tool request queued three independent inspections, which completed and retired the helpers. Fixed listener handler ordering and retained streamed output items when the terminal response envelope omitted them.
- Debug and Release builds and local distribution packaging pass. `git diff --check` passes.
- API-key inference, expired-token refresh, revoked grants and cross-account sign-in are not live acceptance-tested. General desktop observation and computer operation are outside this survey increment.

## Task interface and inline prompt — 6 November 2026

- Native checks: 57 pass, including Return opening a single prompt, clearing held movement/pace and passing modified shortcuts through. Agent checks: 10 pass with a streamed Foundation Models image/tool/result/final-response round trip.
- Live UI: ChatGPT connection restored in Settings; Return opened the borderless input beside the explorer; Escape returned to manual control, verified by opening it again with Return. Typing and submitting from the bubble produced streamed model text in the right-hand journal. The physical survey completed and Stop disabled on completion.
- Reviewed connection Settings, the minimal input bubble and the journal at actual rendered scale. The bubble follows the explorer and clamps its placement to the usable display. Provider configuration and offline presets remain in Settings.
- Debug and local Release packaging pass. The underlying 156 core tests were unchanged by this interface increment. API-key inference remains untested with a live key.

## Single explorer, physical input and readable journal — 6 November 2026

This supersedes the earlier synthetic survey/helper prototype. Recruitment, companion rendering and flag jobs have been removed from the app and active plans.

- Core checks: 162 pass. Physical scenarios cover walking before an ascent, reaching menu-bar corners, top-edge hanging/traversing, connected rope descent into menus, crossing window roofs, retaining the old rope until a replacement latches, and preserving it after an invalid replacement shot. Key confirmation covers a missing final “o”, an already-registered letter, selected-text replacement, changed focus and autocorrection/user edits. Lowering the pointer leaves the crouch blend unchanged.
- Native checks: 58 pass, including character layering above the Dock. Agent checks: 11 pass, including one rendered explorer, a rendered-hand reach to the Dock edge after usable-frame changes, streamed native tool responses and journal history with technical data kept out of the readable entries.
- Live: the explorer used Finder/menu interaction to open TextEdit and pressed the system onscreen keyboard keys. The earlier attempt lost the final “o”; key holds and per-character destination verification were added. The latest run logged five verified key presses and the model inspected the result. An independent TextEdit accessibility observation then showed its complete text value as exactly `hello`.
- Live journal: reviewed its date heading, readable serif entries and collapsed Details. Expanded the typing entry and observed the complete tool request plus the five-key verification result; collapsed it again to restore the readable view. Opening Details disables automatic following. The trace remains exportable with Save Log.
- Dock repair: the drag panel no longer steals hover from the pointer parked over a system control. Offscreen target centres are clipped/rejected before travel, and geometry/focus/pointer changes are checked before input. Explicit AI operation remains visible in full-screen apps. User activity can defer a step; there is still one shared system pointer.
- Scope: primary display and English system keyboard are the initial acceptance target. Broader apps, custom layouts, uppercase via physical Shift and complicated window dragging need further live acceptance. No shell, clipboard text insertion, programmatic app launch or direct text injection is used by the computer tool.


## Ask shortcut and menu organisation — 6 November 2026

- 63 native checks pass. Both global shortcuts register together, route only their own event IDs, suppress held-key repeats, handle release and unregister cleanly. Menu checks confirm terrain guides and activity tests are inside Developer Tools and Ask advertises Control–Option–Return.
- Live UI: Control–Option–Return opened the small Ask explorer input beside the character; Escape dismissed it. Global Carbon event routing was checked natively; the live UI check exercised the application key equivalent.
- Debug and packaged Release builds pass. The updated Debug app remains running. Movement and computer-operation code are unchanged by this menu increment.


## Field notebook styling and prompt corners — 6 November 2026

The task bubble now draws its rounded background directly into a transparent panel, replacing the visual-effect backdrop that leaked a pale rectangle outside the corners. The send symbol is explicitly sized at 27 points with a 38-point button area.

The journal is now a borderless, resizable field notebook: warm paper, subtle fibres, stitched brown spine, red margin, ink serif writing and compact controls. Its custom close action hides the journal without discarding history. Expandable tool details, selectable text, following and log export are retained. Both floating panels can become key for input and text selection.

Debug and packaged Release builds pass; 63 native and 11 agent checks pass. Live review verified the clean rounded input and larger send symbol, the rendered notebook without a system title bar, menu reopening and the follow-latest control. The final Debug app is running with the journal open. No live model request or external computer action was needed for this visual change.


## Two-level menu limit — 6 November 2026

Movement preferences now sit directly in Settings. Activity commands sit directly in Developer Tools below a section heading, alongside terrain guides and the Debug animation playground. Neither submenu contains another submenu. Dynamic activity availability and checkbox states still refresh on opening.

64 native checks pass, including the two-level depth limit, direct developer activity commands, reachable-route availability and dispatch to the simulation. Debug and packaged Release builds pass; the updated Debug app is running.


## Hidden onscreen keyboard rejection — 6 November 2026

The keyboard process can outlive its visible window while retaining AX key geometry. The computer tool previously treated that geometry as visible and could click the app underneath. Inspection now prunes hidden subtrees and rejects keyboard windows absent from WindowServer’s onscreen list, including minimized/transparent or stale window geometry. Typing searches all actually visible keyboard windows rather than the first running keyboard process.

Immediately before a physical keyboard click (including direct tool clicks and a missed-character retry), the tool refreshes window visibility/stacking and AX hit-tests the point back to the intended control. If the keyboard is dismissed or covered during travel, it sends no click and returns a recovery message. Only the explorer’s own panels, withdrawn before input, are excluded from the stacking check.

18 agent checks pass, including seven cases for visible, hidden, transparent, wrong-process, moved and covered keyboard windows and the explorer-overlay exception. Debug and packaged Release builds pass. A live typing round trip with the new hit-test gate remains to be acceptance-tested; no external app input was sent during this repair.


## Restored terrain and onscreen-keyboard holds — 6 November 2026

Accessibility Keyboard had two transparent screen-sized helper windows at WindowServer levels 2996/2997, reported with alpha 1. Treating those rectangles as solid occluders removed every real window edge and internal hold. The provider now excludes only high-level, display-covering backdrops owned by the two system keyboard apps. The real floating keyboard panel remains an occluder and is also a climbable/capturable surface. Native cases cover both keyboard apps, actual panels, helper backdrops and unrelated overlays.

Up to two streams now cover the attached/working window and the visible keyboard, without duplicating a stream during transfers. The keyboard no longer takes the only capture slot from the front app. Capture is bounded at 800 × 600; pixel conversion uses a scoped buffer, and the detector normalizes each pixel once instead of repeatedly converting/clamping neighbours. Large-window Debug analysis dropped from about 330 ms to about 190 ms on this machine. Published-result freshness is measured from delivery (250 ms), so analysis time no longer consumes its entire lifetime; stale queued frames are still rejected before analysis and motion prediction remains capped at 50 ms.

- 162 core tests pass; detector thresholds and text-exclusion rules are unchanged.
- 72 native checks pass.
- 22 live ScreenCaptureKit checks pass across 720 × 520 and 1372 × 920 fixtures: faint rules, low-contrast blocks, vertical cracks, text/underline rejection, scroll grip identity and continuous holds during unrelated repaints.
- Debug and packaged Release builds pass. Live diagnostics show four keyboard holds alongside working-window holds, and 14 exposed terrain segments versus only three screen-rescue segments before the repair.
- The updated app remains running with the existing exploration/guide preferences. Internal capture is bounded to the working/attached window plus a supplementary window; it does not analyse every background window simultaneously.


## Patterned socks, matching sleeves and Jerry — 6 November 2026

Removed the banana artwork/reveal and discovery flag. The exploration sequence now finds the sock it spots, with four rotating designs: red/cream stripes, blue/cream spots, teal argyle and purple zigzags. Patterns, cuff ribbing, heels and toes are clipped to the sock silhouette. Native SpriteKit artwork for all four designs was rendered and visually reviewed. Core mission/activity names are now SockMission/sockSearch; routing, interruption and completion behaviour are retained.

Both arms now use the same jacket colour/material; the separate darker far-sleeve base was removed. The shared model instructions identify the explorer as Jerry and allow direct conversational answers without computer tools. Live ChatGPT acceptance: “What is your name?” returned “My name is Jerry.” with no computer tool action.

162 core tests, 72 native checks and 18 agent checks pass. Debug and packaged Release builds pass. The updated Debug app remains running.


## Stable sock designs — 6 November 2026

The renderer previously chose the design from the completion count, which advances before the sock disappears during the resting beat. The mission now selects and retains a pattern when it selects a target. Rendering and the discovery message use that retained pattern; only a new discovery advances the design.

163 core tests pass. A regression follows five successive discoveries, verifies a constant design throughout each visible mission including rest, and checks the stripes/spots/argyle/zigzags rotation and wraparound. Debug and packaged Release builds pass.


## Screen recorder overlays do not erase terrain — 6 November 2026

Reproduced with macOS Screenshot’s recording controls: its com.apple.screencaptureui overlay at level 24 and unbundled screencapture backdrop at level 1498 cover the display. They were treated as opaque occluders and removed all real edges, leaving only three screen-rescue segments. The terrain provider now excludes Screenshot UI and its exact unbundled helper owner, and does not treat the recorder’s foreground UI as an unsupported full-screen desktop. Ordinary QuickTime playback windows and unrelated unbundled windows retain their geometry.

76 native checks pass; Debug and packaged Release builds pass. With the recording toolbar and selection overlays still open, the live app reports 13 windows and 12 exposed edges, remains RUNNING and continues rope climbing. The recorder controls are left open for the user; no recording was started by this verification.


## Unified Settings and compact welcome — 6 November 2026

Replaced the long first-run reference with a permission-free Meet Jerry introduction, the two global shortcuts, Start Exploring, Try Controls and optional AI setup. The full reference now lives in Settings → Controls. Settings has five independently scrollable sections: General, AI, Privacy & Access, Controls and Advanced. The window adapts its initial height to the display, resizes down to a scrollable layout, and uses native dynamic text colours and appearance-aware cards.

Movement and exploration settings update UserDefaults and the running explorer immediately; menu changes refresh Settings. Login launch uses SMAppService with status/error reporting and an approval link when required. Accessibility and Screen Recording status refresh on returning to Settings. Local terrain analysis and optional AI image sharing have separate controls and explicit data-use copy.

AI setup defaults to a live connection method, loads the catalog automatically, preserves model selections per connection and rejects stale catalog responses after a provider switch. Disconnect removes only the selected credential. Browser sign-in can be cancelled and provider changes invalidate pending sign-in. An unfinished request survives the setup detour and closing Settings. The ordinary menu opens Settings directly, exposes Stop Task while model work is running, and hides Developer Tools until enabled under Advanced. Terrain guides remain available in Advanced without enabling developer tools.

- 78 native checks pass, including direct Settings navigation, two-level menu depth, Developer Tools opt-in and inactive Stop Task state.
- 24 agent checks pass, including five scrollable sections, exclusive section selection, hidden offline picker entry, separate privacy preferences, preserved drafts and immediate preference callbacks.
- Live UI reviewed the welcome, General, AI, Privacy & Access, Controls and Advanced. ChatGPT loaded eight models automatically. A missing-model request opened setup; restoring the model returned the exact request to the bubble, then the model replied “My name is Jerry.” Stop was available during the pending request and disabled after completion.
- Debug and packaged Release builds pass. Existing movement/core behaviour is unchanged; the baseline 163 core tests remain the prior validation.
- Login registration, scoped real-account disconnection, fresh/denied/revoked OS permissions, expired/revoked sign-in and dark-mode rendering still need dedicated acceptance on a signed installation. No permissions were granted or revoked, credentials disconnected, or login item registered during UI verification.


## Shared notebook styling and simpler Settings — 6 November 2026

Welcome and Settings now share the journal’s paper/ink/leather palette, paper fibres, red margin, stitched spine and serif headings. Their borderless notebook windows retain keyboard focus, resizing where appropriate, draggable headers and accessible custom close controls. Button titles have explicit foreground colours for legible contrast. Sidebar navigation has 12-point internal text padding, a wider column and no duplicated branding beneath the single notebook header.

The welcome illustration has a larger canvas and a small floor edge. Its drop shadow is masked behind the floor using the same occlusion logic as real window ledges, rather than clipped accidentally by the illustration bounds.

Reviewed and shortened all five Settings sections. General contains preferences and a save-status note. AI combines connection/account state into one card and removes sign-in instructions after connection. Privacy uses concise permission rows and distinct local-terrain/AI-sharing copy. Controls presents every documented key in three compact, always-visible groups: From any app, Movement, and Tools & tasks. Advanced keeps only diagnostics and short explanations. Text wrapping uses each card’s actual inner width so descriptions cannot lose their final line.

78 native and 25 agent checks pass, including a new regression that every documented control is visible without expanding a section. Debug and packaged Release builds pass. Live review covered the styled welcome, floor/shadow, all five Settings pages, close/reopen controls, sidebar padding, model loading and the complete controls reference. The final app is left running on Controls with the single top heading.


## Unified binoculars — 6 November 2026

Removed the separate scene-level binocular prop from idle sock spotting. Both idle spotting and AI screen reading now use the same head-mounted rig component, mirrored with the explorer and following head movement. The design uses shaded dark-green barrels, muted brass rims, blue-green glass and small reflections. Both modes share a two-hand grip with downward elbow poles; pointer attention eases away during reading so it does not turn the optics away from the task. Held explorers put them away.

78 native and 28 agent checks pass. Three mode regressions exercise idle spotting, reuse of the exact same binocular node for AI reading with no clamped contacts, and hiding it when reading ends. A native SpriteKit preview was rendered and reviewed at enlarged size in both directions. Debug and packaged Release builds pass; the updated app is running.


## Jerry application icon — 6 November 2026

Added a 1024-pixel Jerry portrait on the warm paper tile, preserving his original idle hand pose and keeping the entire hat clear of the tile edge. The icon uses the real rig, with high-resolution material textures and magnification baked into every sprite, shape and crop-mask geometry. This avoids enlarged low-resolution SpriteKit stroke/mask caches. Desktop material rendering retains its existing 4× scale and cache sizes.

The reproducible scripts/render-app-icon.sh exporter creates the PNG master and all ten standard macOS iconset representations, then packages AppIcon.icns. Debug and Release bundle the ICNS and reference it through the explicit Info.plist icon key. Verified all ten PNG dimensions, matching bundled ICNS bytes and preserved bundle identity/menu-bar-only metadata in both products. Both builds and 78 native checks pass. Large and 128-pixel previews were visually reviewed.


## Sleeve caps inside the hands — 6 November 2026

Retracted each sleeve’s rounded stroke endpoint 1.6 points along the forearm, so its cap ends inside the palm rather than protruding past it. Hand placement, IK/contact targets and boots are unchanged. Regenerated the icon from the corrected rig and visually reviewed both wrists. Debug/Release builds and 78 native checks pass.


## About panel icon — 6 November 2026

The About panel now explicitly loads the bundled AppIcon.icns instead of relying on the system-provided application image. Startup also sets the runtime application icon from that resource. About is available in the regular application menu as well as the hiking menu. Debug/Release builds pass; live review of the opened native About panel confirmed Jerry’s icon replaces the placeholder. The panel remains open for review.


## Jerry’s monochrome menu-bar icon — 6 November 2026

Replaced the generic hiking SF Symbol with an 18-point monochrome template generated directly from the real rig’s silhouette paths and eye geometry. Hat, backpack, arms, hands, legs and boots retain their original proportions and pose. It is vector-drawn at the requested backing resolution and uses native template tinting for light/dark/highlighted menu-bar states. No separate approximation of the character is used.

79 native checks pass, including status-item template mode and size. The actual geometry was previewed at menu-bar size on light and dark backgrounds. Debug and packaged Release builds pass; the updated app is running.


## Native notebook controls and head icon — 6 November 2026

Welcome, Settings and the journal use native macOS close/minimise/zoom controls in transparent full-content title bars, retaining the paper, binding and typography. Controls sit 36 points from the left edge, clear of the stitching, and share a 16-point header centreline with the notebook caption. Journal paper extends into the title bar instead of leaving the controls above a separate paper surface. Its caption row has an explicit height to match the native controls. Native close preserves the reusable windows and journal entries.

The menu-bar template now uses only Jerry’s actual head/hat paths and eye cutouts, in a 22-point image with 20-point artwork (25% larger than the first head-only version). It keeps native template tinting and vector drawing.

Debug and packaged Release builds pass, with 79 native and 28 agent checks passing. Live accessibility review confirmed native controls on all three windows and native welcome close behavior. User visual review confirmed Welcome and Settings alignment and journal paper extending behind the controls; the journal caption was subsequently aligned with an explicit 16-point row. The updated Debug app remains running.


## Manual falls deploy the parachute — 7 November 2026

Manual walking off an unsupported ledge and Down + Space drop-through now enter the shared parachute recovery path. Manual control no longer converts an ongoing recovery into a jump, so taking control during a descent, losing a support, and released ropes retain the chute deployment clock. Sideways steering and deliberate Up transfers to nearby internal holds remain available. Ordinary short jumps keep their existing arc and landing; a jump falling beyond that arc transitions into recovery. The drop-through interval prevents immediately landing back on the roof.

166 core tests pass, including regressions for walking off with terrain refreshes during deployment, steering under the canopy, dropping through without re-catching the roof, taking control mid-descent, and a long jump becoming a parachute descent. The lost-support windup expectation now checks recovery instead of a non-deploying jump. The Debug build, 79 native checks and 28 agent checks pass. No new permissions or keyboard capture changes are involved.


## Jerry application name — 7 November 2026

Renamed the public app, menu and About panel, window titles, notebook headings, accessibility labels, permission guidance and sign-in copy to Jerry. The source directory, application entry point, Xcode project/target/shared scheme, build scripts, icon exporter and local archive names now use Jerry too. Documentation and image paths follow the new layout. Sock exploration and the core simulation are unchanged.

The persistent bundle identifier and Keychain namespace remain stable for existing preferences and saved connections; they are compatibility identifiers rather than public branding. Fixture and capture-queue names use the new app name.

Debug and packaged Release builds pass, with 79 native and 28 agent checks passing. Verified Jerry display name, executable, bundle name and retained identifier in all three generated app bundles, plus the Jerry executable in the local archive. Local Markdown/image references resolve. Live UI review confirms Jerry as the running app, with About Jerry / Quit Jerry and Jerry’s existing icon and sock tagline in About. The renamed app remains running.


## Guided desktop permission repair — 7 November 2026

Added a shared macOS permission monitor and notebook setup guide. Startup reads actual Accessibility/Screen Recording grants without prompting. Missing access for configured AI tasks, previously used desktop clicks, enabled internal terrain or image sharing opens the guide; fresh installs keep the permission-free welcome. Privacy & Access status refreshes while setup is open and on app activation. A ScreenCaptureKit user-declined error can invalidate an otherwise-positive preflight result and reopen repair; a successful stream clears that failure.

Set up / Manage, manual click access and blocked AI inspection route to the same guide. It opens the matching System Settings page, offers the running Bundle.main.bundleURL as an NSURL drag item, stays beside Settings using window metadata, and provides Finder, Check again, Restart Jerry and a next-required-permission action. The drag permits copy/link/generic operations, never move. macOS 27 uses the observed Device Control and Data Access page name. Existing grants, preference choices and Keychain contents are not reset.

Debug and packaged Release builds pass. All 79 native and 34 agent checks pass. Six new regressions cover optional fresh installs, enabled terrain, both missing grants, valid grants, a lost prior grant and the exact running-app pasteboard URL. Actual ScreenCaptureKit capture passes all 22 checks across two fixture sizes when run with the normal app stopped. An initial run alongside another active Jerry instance missed the large-fixture repaint-continuity timing check; the isolated run passes, so this remains load-sensitive rather than evidence of denied capture.

Live UI review covered startup repair, the compact layout, the exact app-path tile, both deep links, Settings permission rows, the next-permission transition and returning to the guide after Restart Jerry. System Settings currently shows Jerry enabled for Screen & System Audio Recording and disabled for Device Control and Data Access. No macOS permission switches were changed. Actual drop acceptance and authenticated enabling remain user-driven checks in the manual checklist; native pasteboard content is verified automatically. The updated app is running with the missing-control-access guide ready.


## Stable access-guide positioning — 7 November 2026

Removed window positioning from permission status refreshes. The access guide now uses the normal window level and makes one placement attempt when Settings is opened, selecting its largest normal window rather than transient panels. Placement only succeeds if the helper fits fully beside Settings without overlap; no-space cases keep the current position. Manual window moves disable automatic placement, and the next-permission transition retains the previous top-left position. A capture rejection no longer reopens another guide over an already-visible setup window. Opening the guide while System Settings is frontmost avoids activating Jerry over it.

Debug and packaged Release builds pass, with 79 native and 37 agent checks. Three placement regressions verify right-side placement, left-side fallback and preserving position when neither side fits. Live review confirmed both grants are now allowed, reopening setup reaches the correct macOS page, and System Settings remains the active interface. No permission switches were changed during this review. The updated app is running. Manual drag-position retention remains in the interactive checklist.


## Expedition conversations and compact journal — 7 November 2026

The journal now groups separate expeditions in a selectable sidebar. An expedition stays open between responses until Finish or New expedition; the explorer’s prompt continues the active conversation, and the journal composer can explicitly resume a selected older one. Stop preserves the conversation. New instructions cancel and drain the previous execution before a new one starts, retaining completed native transcripts and provider reasoning per expedition. Unfinished tool exchanges and stale response placeholders are removed, new target IDs require a fresh inspection, and callbacks are scoped to their execution. Old screen attachments are omitted when image sharing is off. Histories remain in memory until quitting; export includes all expeditions and metadata.

The journal uses an ordinary NSWindow at normal level, stays where the user placed it, and returns behind other apps after physical input. Its native compact toolbar provides the animated sidebar toggle, New and Save, with contextual Finish/Stop. There is one chronological scroll area in the right pane: date, entries and progress all scroll, while only the composer stays fixed. Following is implicit within 80 points of the bottom and pauses while reading earlier entries. A geometry/phase-based implementation handles modern macOS, with a geometry preference fallback on macOS 14. Parent clipping keeps scrolling text below the toolbar. Redundant headings, repeated status labels, the Follow latest switch and footer actions were removed.

The default window is 620 × 540 points, with 13-point entries, a 12-point composer, a 176-point sidebar and reduced padding. Minimum size is 560 × 380 with the sidebar, or 360 × 380 without it; reopening the sidebar keeps the expanded window on screen. The divider belongs to the sliding sidebar, extends to the window top and does not fade independently. Toolbar glyphs use small padded vector templates so AppKit does not enlarge them. Native traffic-light controls share the paper’s 25-point margin alignment across notebook windows.

Window discovery now includes substantial titled app-owned UI, preserving front-to-back occlusion and exposed edges for the journal, Settings and welcome. Transparent rendering/input/prompt panels remain excluded. A real floating journal fixture is discovered in native checks after WindowServer registration.

Debug and packaged Release builds pass. All 82 native and 51 agent checks pass, covering native session continuation, interrupted transcript repair, image-sharing context, expedition lifecycle/history isolation, stale callbacks, automatic window focus, native toolbar/sidebar behavior and app-owned terrain discovery. Live ChatGPT checks remembered a codeword through both composer routes, Finish produced a separate second expedition, and selecting history did not merge its entries. Live review covered long entries, reading-earlier state, normal window ordering, both sidebar layouts, compact sizing, full-height divider and smaller toolbar icons. No external app controls were operated by the conversational test prompts. Physical interruption during an external computer action and export-to-file remain interactive checklist cases. The compact journal is left running for review.

Traffic-light follow-up: the native toolbar was resetting the journal controls after content layout. Alignment now runs after toolbar layout and window updates, with the first control 12 points inside the paper margin. A native integration check verifies all three controls after opening and resizing (52 agent checks pass). The screen-sharing indicator obscures the controls during CUA screenshot inspection; the coordinate check does not replace a human visual check without that indicator.

### GitHub v0.1.0 preview — 7 November 2026

Packaged the current arm64 Release build (version 0.1.0, build 1) for a GitHub prerelease, with a SHA-256 checksum. The archive includes the app executable and native icon. All 166 core tests, 82 native checks and 52 agent checks pass; the packaged Release executable also completes `--terrain-report`. This is an unsigned, unnotarised Apple Silicon preview, not a signed public distribution build. No valid signing identity is installed on the development Mac. Other macOS versions and Intel Macs have not been validated.

### Flutterbox Developer ID and notarisation — 8 November 2026

Created a new Flutterbox Ltd. Developer ID Application certificate through the Account Holder website and installed it with its matching private key in the local login Keychain. The pre-existing certificate was left unchanged. Temporary private-key and PKCS#12 import files were removed after successful import. No signing credentials are stored in the repository.

The Developer ID build uses Hardened Runtime, a secure signing timestamp and no debugger entitlement. The signed app runs outside App Sandbox so its existing desktop interactions remain available behind macOS permissions. Strict verification initially exposed Finder metadata in the synced repository folder; signed app bundles now build outside it under `~/Library/Developer/Jerry`. The signed packaging script passes shell syntax, missing-identity preflight and a real signed-build check. Its optional notarytool Keychain-profile branch has not been exercised.

Submitted a valid application archive through `xcodebuild -exportArchive` using Xcode’s account session. Apple accepted notarisation, and `-exportNotarizedApp` exported the stapled universal app (arm64 and x86_64). Both the exported app and a freshly extracted copy of the exact release ZIP pass strict signature verification, `stapler validate`, and Gatekeeper assessment (`source=Notarized Developer ID`). The notarised app launches and displays Welcome. The signed executable’s terrain report succeeds. Intel execution, other macOS versions, and a full signed-build permissions/AI/physical-interaction walkthrough remain untested. Earlier unsigned-build test results do not establish those behaviours for the signed build.

### Jerry Keychain labels — 8 November 2026

Version 0.1.1 (build 2) adds explicit Jerry labels and descriptions to saved ChatGPT and API-key items. Existing entries are relabelled in place using a noninteractive metadata-only update. The internal service/account keys and saved secrets remain unchanged. New writes also set the display attributes. A failed background relabel does not block credential reads or show an authentication dialog; it retries on a later access.

Disposable Keychain integration checks cover both legacy labels and secret preservation, new entries, and updates without disturbing the other connection. All 55 agent checks and 82 native checks pass. No real tokens or API keys are used in the new checks. The signed, notarised 0.1.1 ZIP, extracted to a fresh temporary directory, passes strict signature verification, ticket validation and Gatekeeper assessment. Settings opens in that signed build. Native authorisation-dialog wording for a locked/inaccessible legacy item still requires a user check; a normal access authorisation may remain necessary after changing signing identity.

### Matching notebook toolbars — 8 November 2026

Settings now uses a standard native unified toolbar with a centred serif title rather than the Base Camp eyebrow. Its sidebar divider reaches through the titlebar, its default height is 540 points, and section headings use 21-point type. The journal also uses a standard-size unified toolbar and native symbol sizing; its compact content fonts, spacing, composer and default window dimensions are unchanged. Shared paper views now handle toolbar layout through the same notebook content class.

Debug build, 55 agent checks and 82 native checks pass. Interactive review covers the Settings General/Controls pages, journal toolbar, sidebar hide/show, and notebook divider/window-control placement. This iteration is a local UI preview; the GitHub 0.1.1 release remains unchanged.
