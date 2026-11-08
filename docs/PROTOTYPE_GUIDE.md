# Prototype behavior reference

Detailed behavior and implementation notes for the current macOS prototype. For a public introduction, see the [README](../README.md); for development commands, see [AGENTS.md](../AGENTS.md). Historical implementation evidence is in [prototype validation](PROTOTYPE_VALIDATION.md).

## Desktop behavior

The macOS app draws one articulated, approximately 74-point explorer above normal windows. The Jerry menu groups **Ask Jerry…** and **Expedition Journal…** first, followed by **Take Control**, **Enable Idle Exploration**, and **Stop Task** while AI work is running. **Settings…** opens one window with General, AI, Privacy & Access, Controls and Advanced sections. Preferences save immediately. Welcome introduces Jerry as a personal desktop explorer: take control or give him a mission, with sock hunting as his idle pastime. Welcome and About Jerry link to the GitHub project. Welcome, Settings and the journal share a warm field-notebook style. Settings and the journal use standard-size native toolbars with notebook titles; Settings has no eyebrow caption, and the journal keeps its compact content typography and spacing. Enable Developer Tools under Advanced to expose activity tests; Debug builds also include the animation playground. Menus use at most two levels.

With **Enable Idle Exploration** checked, he wanders, explores windows and looks for the sock. Uncheck it and he stays where he is, watches a nearby pointer, and remains draggable. Gravity, window-edge landing and parachute recovery keep working. This does not freeze the simulation. Leaving manual control respects the idle preference. A legacy paused preference starts with idle exploration disabled.

The rendering overlay ignores mouse events and cannot become the key or main window. A separate 48 × 76 point, non-activating panel over the explorer accepts dragging. Grab anywhere inside that small character area, drag it aside, and release. The grab offset is preserved, and the explorer remains inside the primary display's usable area. All other overlay space passes mouse events through. Autonomous/dragging mode uses no keyboard monitor or permission prompts. Optional keyboard control captures play keys only in manual mode, using an invisible input target. Optional desktop clicks require Accessibility permission; neither feature captures screen images. Optional internal-window exploration uses a separate, explicit Screen Recording setting.

While held, idle movement stops. Release carries recent drag momentum, so quick sideways or upward motions produce an arc. Holding still before release gives a normal drop. The explorer initially falls faster; its chute emerges from behind the backpack, opens overhead, and slows the descent and drift. It lands on the first suitable exposed top below its trajectory. Gentle placement within 16 points of a top snaps it directly onto the edge. It needs its full body width on the platform and 76 points of clear space above it. It follows that window when moved or resized. Losing support starts another recovery. When idle exploration is enabled, it walks exposed tops, climbs reachable window sides, abseils from a window-relative rope, and steers parachutes towards safe landing areas. Window changes revalidate each transition; losing support or an invalid route starts recovery. A new grab cancels its route and mission immediately.

On landing, the explorer briefly crouches with planted feet and then rises. A settling interval prevents immediate autonomous movement. Occasional blinks have a tiny timing offset between the eyes. The developer-only simulation pause freezes visual clocks, recovery and polling; it is separate from the user-facing idle-exploration setting.

Bring the pointer near him and he notices it: his eyes follow first, with a small, slower head turn. Attention fades smoothly beyond about 220 points and returns to his normal expression. Blinking continues while he watches. This samples the current pointer position without capturing mouse events.

On first launch, a compact **Meet Jerry** welcome offers **Start Exploring**, **Try Controls**, and optional **Set up AI…**. It requests no permissions or account. The two global shortcuts are introduced there; the full reference is in **Controls & Tips…** (Settings → Controls). Reopen the welcome with **Settings → General → Meet Jerry…**.

## AI tasks

Set up ChatGPT sign-in or an API key in **Settings → AI**. Press **Control–Option–Return** from any app, or **Return** while controlling the explorer, for a small input bubble beside him; Return sends and Escape cancels. **Ask Jerry…** also opens it. The **Expedition journal** is a normal notebook window with warm paper, a stitched spine and ink typography. Each expedition has a sidebar entry; the native toolbar toggles the animated sidebar, starts a new expedition and exports the journal. Finish and Stop are contextual toolbar actions. The right page scrolls as a single chronology, with only its prompt fixed at the bottom. Following is automatic near the bottom and pauses while you read earlier entries. Details remain expandable. Close it with the native window button; Expedition Journal… brings it back.

The explorer is named **Jerry** and answers conversational questions directly. The agent can now inspect the active app and physically reach controls to click, scroll or drag. It opens apps through their UI and types by pressing an onscreen keyboard, which must also be opened physically. The explorer can grapple to the display rim, hang and traverse there, then lower on a rope into menus. He renders above the Dock and, during AI work, above menus. Survey flags and demo inspections are removed. There is one explorer in every mode. See [the computer-task guide](AGENT_PROTOTYPE.md) for permissions and current limits.

## Play with the keyboard

Press **Control–Option–Space** from any app while Jerry is open, or choose Jerry menu → **Take Control**. The same shortcut releases control. Manual mode captures the play keys without opening a controls window. The click marker beside the explorer indicates that you are in control. The explorer stops choosing adventures until you leave control mode.

| Key | Action |
| --- | --- |
| ← / → or A / D | Walk; steer while airborne; push a swing |
| ↑ / W | Grab/climb a nearby exposed side, or climb the attached rope |
| ↓ / S | Lower over a nearby window edge and abseil, or descend the attached rope |
| Shift | Run; climb walls/ropes and abseil faster |
| Space | Jump; jump off/release a rope |
| ↓ + Space | Drop through the current platform |
| Hold G, release G | Use the arrow keys to aim at a window’s top rim, then fire; works from a platform, in the air, or on a rope |
| E | Click the crosshair beside his hand |
| Return | Open a task input beside the explorer; Return sends, Escape cancels |
| Esc | End control and return focus to the previous app |

Hold **Option while crouching** to lower the pointer by a further 16 points without changing the crouch pose. A small extension shows the click point. AI uses this for very low controls such as the Dock.

Hold **Shift** for a distinct running gait at about twice manual walking speed, or for 1.8× wall/rope climbing and abseiling. Release it to return to normal pace. **Settings → General → Run while exploring** enables running on longer idle journeys, and **Faster Rope Work** makes the faster work rate the default. Both settings start off, persist across relaunch, and do not turn idle exploration on. Gravity, jump height, hook flight and swing timing remain unchanged.

Releasing Up/Down holds the current rope length, allowing a natural swing. Walking uses twice the normal cadence and matches its foot motion. Walking off a ledge or dropping through it deploys the parachute while keeping manual control and sideways steering. A ground jump has a short, planted crouch and leg push before take-off, then tucks and reaches for landing; a longer fall beyond its ordinary jump arc transitions to parachute recovery. Air steering accelerates smoothly and retains sideways momentum on release. Landings compress the knees before moving on. There are no mid-air double jumps. Changing apps, pausing, dragging, resetting, sleeping, or leaving the desktop stops keyboard capture and clears held directions. Movement needs no Accessibility or Input Monitoring permission.

**E** targets the visible crosshair, first using an accessible control's Press action and otherwise sending one ordinary left click there. Choose **Settings → Privacy & Access → Open Accessibility Settings…** in the Jerry menu (or press E once), then enable Jerry under **System Settings → Privacy & Security → Accessibility**. Return to keyboard control afterward. Without that permission E performs no click. Clicks keep the manual session and rope active. After an action takes focus, the explorer regains keyboard input without opening a window. E works while hanging, climbing or swinging; held movement is reconciled afterward to prevent stuck keys. Use Esc if you want to type in the target app normally. Buttons and toggles can be pressed; this first version does not route text typing, double-clicks, right-clicks, or drag gestures through the explorer.

## Connected rope activities

**Grappling hook** aims a small spool launcher, fires a hook over a reachable window lip, takes up the line, swings under gravity, then climbs and mantles onto the destination. Shots reach up to 2,300 points (with a 2,400-point spool). He can hook the middle of an exposed top rim and climb vertically up the window's front, including windows whose side edges are off-screen. An aligned shot uses his current horizontal position; angled shots still swing naturally. At the rim he pulls himself over to stand on top. It can reach exposed windows that have no climbable route from the floor. Automatic adventures occasionally consider these grapple routes as well.

While attached, **Swing on rope**, **Climb rope**, and **Abseil** change the motor/holding mode of that same rope; they preserve the anchor, deployed length, position and existing momentum. Swing pushes off if the explorer is resting against the wall. A completed abseil keeps its line attached, so Climb rope can take him back up without refiring. **Release rope** keeps his current velocity and uses parachute recovery. Grabbing always cancels the line immediately.

The physical rope has gravity, tension, slack, damping, a controlled reel/payout rate, corner contact and window/floor contact. Swinging is simulated rather than played as a looping animation. Rope contact uses each window’s corner radius and keeps it when tension or swing changes. Jerry’s notebook windows share their exact 12-point drawn radius; external windows use an estimate (16 points on macOS 26+, 10 on older macOS), because public window metadata does not expose their outline radius. Rendering keeps the rounded corner's tangent joins and shows slack in the free line. The body hangs from its harness and hands follow the line. Rope climbing lifts in time with the hand pulls.

The prototype models one load-bearing massless line, plus a pending second line during hook transfer. The load-bearing line has either a straight front-rim attachment or one rounded corner guide on its supporting window. It does not yet wrap rope around arbitrary intervening windows, collide ropes with each other, or simulate rope elasticity. A missing/covered anchor releases into recovery. The 2,400-point spool covers supported descent routes; reaching its end also releases safely.

## The sock hunt

The explorer spots a patterned sock through binoculars, approaches a launch point, crosses to a reachable discovery, investigates, finds a sock, marks its map, and rests before trying again. It prefers a valid parachute crossing; climbing and shorter walks provide alternatives. The prop follows its supporting window. Grabbing the explorer, losing support, or removing the destination cancels or replans the expedition. Discoveries rotate between red stripes, blue spots, teal argyle and purple zigzags. A sparse desktop permits short floor expeditions; no reachable route means a safe rest.

Movement uses a fixed 120 Hz simulation with at most 0.25 seconds of catch-up after a stall, presented at 30 fps. Walking follows the unchanged foot cycle (40 points/second on average at the default stride/cadence). Climbing follows alternating 12-point arm pulls (24 points/second on average), and abseiling descends at 48 points/second; Gentle Pace runs the expedition at 65% speed. Planned wall climb/abseil transitions are limited to 1,200 points and need exposed wall contacts. Planned flights have a 65 points/second steering cap and land farther inside tops than ordinary dropped-character recovery. Windows are platforms, rather than solid boxes: rear windows can form the visual background behind a foreground climb, and the screen floor remains rescue terrain.

## Climbing inside windows

Enable **Settings → Privacy & Access → Find ledges inside windows** to find terrain in window content. This optional feature needs macOS Screen Recording access. Pixels are analysed locally in memory; images are never saved or uploaded. Normal window-edge exploration keeps working without access.

Long, contrasting horizontal colour boundaries become standing/landing ledges. Thin horizontal lines become hanging traverses. Vertical boundaries and thin vertical lines become braced climbing routes. Short strokes and small controls are rejected. On-device text recognition excludes recognised text regions and their underlines before edges become terrain. Capture retains up to one pixel per desktop point (bounded to 800 × 600), preserving fine rules; lower contrast thresholds admit subtle panel boundaries and hairlines. Recognised strings are immediately discarded, with only exclusion rectangles kept. Up to two bounded captures keep the working/attached window and visible onscreen keyboard available together. The real keyboard has climbable edges; its invisible screen-sized helper windows are ignored. macOS Screenshot/recording overlays are also ignored, so opening the recording controls does not erase terrain. **Settings → Advanced → Show terrain guides** previews standing ledges in green, horizontal cracks in orange, internal vertical routes in purple, exterior sides in pink and screen rescue boundaries in teal.

In keyboard control, **Up** reaches for a nearby hold, including from a rope. Left/right traverses a horizontal crack; up/down climbs a vertical route. At intersections, use the perpendicular direction to transfer. **Down alone** steps off a standing ledge or lets go of a horizontal crack, then falls and parachutes; Down on a rope or vertical route still descends. Space remains jump, and Down + Space remains available. Transfers retain keyboard control, so E still clicks while climbing. The existing G + arrows grapple can be fired again from an internal hold.

Capture prioritises the explorer’s attached/rope-anchor window, otherwise the front climbable window. A second capture can track the visible onscreen keyboard. A background ScreenCaptureKit stream is capped at 20 fps with a three-buffer queue. Unchanged frames refresh existing holds without running detection again. Window geometry is read at 10 Hz. Confirmed feature coordinates feed the 30 fps presentation with at most 50 ms of bounded motion prediction; the physics loop remains 120 Hz. Appearance matching and coarse-to-fine image registration preserve identity through scrolling. New holds need two sightings. Unseen moving holds are removed immediately, stationary misses get up to 120 ms grace, and all samples expire after 250 ms. Holds disappearing, being covered, or scrolling beyond body clearance cause safe recovery. Resizing restarts detection rather than reusing stale image coordinates.

This is deliberately conservative visual terrain, not semantic UI understanding. A long rule may be climbable; a low-contrast boundary may be ignored. Large jumps, rapid reflows, continuous untextured dividers and changing/video content can lose tracking. Feature counts and capture sizes are bounded to limit cost.


## Crouch for toolbar clicks

While in keyboard control, hold **C** to crouch with his feet planted. The click marker lowers by 28 points; press **E** while holding C to click there. Release C to rise. C + left/right gives a slower, gait-matched crouched walk; Shift does not turn it into a run. Down keeps its step-off/descent behaviour. Crouching applies to standing surfaces, including internal toolbar ledges; rope and crack poses remain available as before. The animation playground also includes a Crouching clip.


## Repairing macOS access

Jerry checks macOS grants at startup without displaying system permission prompts. Missing access for configured desktop tasks, previously used clicks, enabled internal ledges or enabled AI images opens a compact notebook guide. New installations with no enabled desktop features keep the permission-free welcome.

Settings → Privacy & Access → Set up… opens the guide and the matching System Settings page. The draggable tile exports the currently running app’s file URL, including a development build’s actual location. Drag it into the permission list and enable Jerry, or use the + button and Show this app in Finder to select that exact copy. Dragging never moves the application. Older macOS versions call the control permission Accessibility; on macOS 27 the page is Device Control and Data Access.

The guide is a normal window and refreshes status without moving. When there is room, it is placed beside System Settings once; otherwise it keeps its position and lets Settings come in front. Moving it yourself or switching to the next permission preserves its position. When the first permission is granted, Next permission… opens the other missing permission needed by enabled features. If a renamed or moved copy is listed but still denied, remove its stale entry and add the running app again. Check again re-reads the macOS APIs; Restart Jerry handles grants that need a new process. Screen-capture permission failures also reopen the guide rather than trusting a saved feature preference. Local terrain capture and AI image sharing remain separate choices.

The user approves access in macOS; Jerry does not change permission switches or reset the system permission database. Apple documents the manual [Accessibility](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) and [Screen Recording](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac) permission lists. The drag tile uses AppKit’s native [file drag session](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)).


## Continuing an expedition

An expedition stays open after Jerry replies. Use the prompt beside Jerry or the journal composer to add directions with its existing conversation and tool context. Opening a prompt, focusing the journal or browsing older expeditions does not itself stop the conversation. Typing into the journal or opening the explorer prompt during an execution pauses the current work; submitting the direction cancels/drains that execution before resuming. Stop pauses execution and preserves the conversation. Finish closes it, and the next explorer prompt starts a new expedition. New expedition in the toolbar prepares a blank page and focuses the journal composer.

Selecting an older expedition only changes what you read. Its composer explicitly resumes that expedition; background progress remains attached to the active expedition. Export includes all histories and details. Histories live in memory until quitting.

The journal, Settings, welcome and other substantial titled Jerry windows now participate in terrain and hide covered window edges in stacking order. Transparent explorer, keyboard-input and prompt panels remain excluded. Bringing another app in front hides the journal normally; physical input restores it behind other apps rather than forcing it to the front.
