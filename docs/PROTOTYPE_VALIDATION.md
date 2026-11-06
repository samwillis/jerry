# Phases 5–7: local prototype validation

## Delivered scope

One explorer on the primary macOS display can walk real window tops, climb exposed sides, descend an anchored rope, parachute with limited steering, recover and land, and run a repeating sock/banana adventure. The body remains draggable throughout, including while paused. This is a local prototype, version 0.1.0 (build 1), with an unsigned host-architecture Release app and archive.

The implementation uses window metadata, never titles or window images. No new permissions, global input hooks, network service, or background agent are required. The existing shape rig and painted finish are retained.

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
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock --native-checks
./scripts/package.sh
```

For real-window test terrain:

```sh
./scripts/terrain-fixture.sh
build/TerrainFixture.app/Contents/MacOS/TerrainFixture --exercise
# In another terminal, with the normal explorer copy quit:
build/Build/Products/Debug/OtherSock.app/Contents/MacOS/OtherSock \
  --fixture-terrain --start-on-window --trace-movement --performance-report
```

Omit `--exercise` for a stable layout. Add `--start-low --rope-demo` to begin a reproducible rope descent from the lower window; `--freeze-rope` pauses it partway for visual review. Add `--movement-only` to the explorer to isolate traversal from mission selection. Quit the fixture after testing. These switches are development tools, not requirements for normal use.


## Movement and activity refinement — 6 November 2026

- 78 core tests pass. New coverage checks walking stance-foot cancellation in both directions, climbing pull distance/inverse phase, fixed contacts during stance, lower climbing boots and consistent knee branches, corner path endpoints/continuity, planted-boot weight transfer, all four manual travel activities, safe queuing, manual completion/rest, grabs/support loss during transitions, rounded-rope mirroring/clearance, and tangent directions at both curve joins over a range of hand positions.
- 19 native checks pass, including submenu construction, reachable-route enablement, dispatching Walk into the desktop actor, and returning to automatic adventures. The native menu test restores the saved pause preference after checking dispatch.
- Native playground review covered a lip pull, mirrored weight transfer, jump clearance and the tangent rounded-corner rope preview, all with zero clamped contacts. macOS status-item automation timed out, so menu dispatch was verified through the real NSMenu action mechanism in the native check harness.
- Debug and Release packages were rebuilt for these changes. Earlier performance measurements remain historical; this refinement did not rerun the hardware benchmark.
