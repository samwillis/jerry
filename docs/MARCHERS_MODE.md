# Marchers Rescue

Marchers Rescue is an optional mode with a classic falling-walker puzzle. A hatch at the top centre of the primary display releases a line of small marchers. Each marcher walks along your windows, turns at walls and falls off edges. An exit door sits on one of the window tops. Jerry watches the line and hands out skills to guide the marchers to the exit. Your windows form the level, and moving a window changes it while he works.

Turn it on or off with **Jerry menu → Marchers Rescue**. The mode stops when Jerry quits and does not persist. Idle exploration pauses while it runs and resumes when you turn the mode off.

The mode uses generic names and its own artwork. It reproduces no names, characters, art, sound or levels from an existing game.

## Rules

| Item | Behaviour |
| --- | --- |
| Release | 20 marchers per level, one every 1.6 s, after a 2 s pause. The first one appears once an exit exists. |
| Walking | 24 pt/s. A marcher steps up to 6 pt and down up to 4 pt. Anything taller is a wall, and the marcher turns around. The screen's sides and top are walls. |
| Falling | 150 pt/s. A fall longer than 140 pt kills a marcher unless it has an umbrella. Falling below the bottom of the visible screen also loses it. |
| Exit | An exposed window top, away from the hatch and preferably lower and farther across the screen. It moves with its window. It relocates if that window closes or is covered. |
| End | A level ends when every marcher is home or lost. A level held up only by blockers, or with no progress for 75 s, ends with every remaining fuse lit. The time limit is 300 s. The next level starts 6 s later. |

### Window material

Each window is a hollow room. Its 28 pt title band is solid, and so are 6 pt side walls and a 6 pt bottom rim. Windows shorter than 68 pt or narrower than 40 pt are solid throughout.

The frontmost window at a point decides what is there, so covered frames are hidden exactly as they are on screen. Transparent panels, non-climbable windows and Jerry's own overlay are ignored.

### Moving windows

Tunnels, blast holes and bricks are stored relative to their window's top-left corner. Marchers record the window they stand on or climb. When the 10 Hz terrain refresh moves that window, its marchers, holes, bridges and exit move with it.

If a moved window buries a marcher, the marcher pops out on top, or drops into the room below when it is buried deeply. Closing a window removes its holes and bricks, and anyone standing on it falls.

## Skills

| Skill | Effect | Stock |
| --- | --- | --- |
| Climber | Permanent. Scales walls; lets go at an overhang. | 20 |
| Floater | Permanent. Opens an umbrella after 18 pt of fall and survives any fall. | 20 |
| Bomber | 5 s fuse, then blasts a 16 pt hole. The marcher is lost. | 10 |
| Blocker | Stands still and turns others back within 4 pt. | 6 |
| Builder | Lays 12 steps (8 × 2 pt, 4 pt forward each, one every 0.5 s). Stops and turns at a wall or a low ceiling. | 15 |
| Basher | Cuts horizontally (12 pt high) while there is material within 8 pt ahead. | 10 |
| Miner | Cuts diagonally down until it breaks through or runs out of material. | 10 |
| Digger | Digs straight down (9 pt wide) until it breaks through. | 10 |

Jerry is the only one who hands out skills. AI tasks do not use the mode. Like computer actions, skills reach marchers through Jerry himself. He walks, climbs, abseils, parachutes or grapples towards the next planned skill. He can signal only a marcher within 420 pt of his raised hand. A token flies from his hand, he points, and the marcher's hat gains a badge for permanent skills. You can take control and move Jerry yourself; he keeps signalling whatever is in reach.

## How Jerry decides

`MarcherPlanner` runs a receding-horizon search over the same deterministic physics the level uses.

1. It simulates the chosen marcher doing nothing for 20 s. Marchers that are already digging, bashing, mining or building keep working alongside, so unfinished tunnels and bridges count.
2. If that run reaches the exit, nothing is planned.
3. Otherwise it tries Floater and Climber now. It also tries Builder, Basher, Digger, Miner and Blocker at moments along the baseline path, sampled every second and just before each edge, wall or turn, up to 7.5 s ahead. A task that would end in a fatal fall is retried with an umbrella first; if that wins, Floater is assigned now and the task is planned on the next pass.
4. Each outcome is scored for the marcher itself:
   - a rescue scores 1000, less 3 points per second until rescue;
   - a death scores −1000;
   - a marcher still wandering scores by the closest it came to the exit.
5. The four best terrain changes, and up to four blocker positions spread along the path, also receive a probe. A follower with an umbrella is dropped from the hatch into the resulting terrain, and 60% of its outcome is added. This values bridges, tunnels and blockers that help the rest of the line.
6. Skill costs (Floater 8 up to Blocker 70) and a small delay penalty break ties. A plan must beat doing nothing by more than 5 points.

A walker that turns again at a spot where it already turned is pacing, so that simulation stops early. The coach plans one marcher up to four times a second and each marcher at most once a second. Plans are recomputed continuously, so when you move a window, the next search simply uses the new terrain.

`MarcherCoach` owns the level, plans, signals and level progression. It also decides where Jerry should be: at the next planned skill, at the centre of the active line, or below the hatch. In the app, each search runs on a background task from a value snapshot of the level. The result returns to the main actor. Results from an earlier session of the mode are discarded.

## Code

- `Packages/ExpeditionCore/Sources/ExpeditionCore/MarcherWorld.swift`: window material, carves, bricks and window-following.
- `Marcher.swift`: marcher state, skills and the shared step function (`MarcherPhysics`).
- `MarcherLevel.swift`: hatch, release, exit placement, terrain updates and level end.
- `MarcherPlanner.swift`: look-ahead search.
- `MarcherCoach.swift`: planning cadence, Jerry's reach, steering, signals and level progression.
- `Jerry/Rendering/MarcherLayer.swift`: SpriteKit artwork. `ExplorerScene` hosts the coach, `OverlayController` forwards the mode, and `AppDelegate` adds the menu item.

## Validation

`swift test --package-path Packages/ExpeditionCore --filter MarcherTests` covers:

- window material and occlusion;
- carves and bricks travelling with windows;
- landing, splatting and umbrellas;
- riding a moving window;
- blockers, walls and climbers;
- builders, diggers, bashers and bombers;
- exit placement;
- scripted rescues, background planning and Jerry's reach limit.

The scripted rescues are: an umbrella drop (at least 9 of 10 saved), a bridged gap (at least 8 of 10), a blocker turnaround (at least 8 of 10), digging through a full-width window (at least 4 of 6), and a mid-level window move (at least 5 of 8).

On a Linux container with Swift 6.0.3, a crowded 12-window desktop measured these planning times:

| Build | Mean | Worst |
| --- | --- | --- |
| Debug | about 50–60 ms | about 160–250 ms |
| Release | 1.3 ms | 4.6 ms |

Debug planning would stall the main thread, so the app plans in the background.

The native app code was not compiled or run in that environment. Overlay rendering, Jerry's travel towards the line, menu behaviour and frame timing on macOS need the manual checks in [manual tests](MANUAL_TESTS.md#marchers-rescue).

### Known limits

- The planner considers one marcher and one skill at a time, plus an umbrella, and assumes the terrain stays still during each search. It can waste skills, and it can fail on levels that need several coordinated moves.
- Blockers are released only by the end-of-level detonation.
- Window rooms are a model. Real window shapes, toolbars, transparency and rounded corners are not represented.
- Only the primary display is used, with the same full-screen and Space guards as exploration.
