# The Other Sock

A tiny desktop expedition: one hopelessly committed explorer climbs your windows, abseils down their sides, and parachutes across your screen in search of a missing sock.

Build for macOS first, then bring it to Windows once the movement and comedy work.

## 1. Prove the desktop interaction

Build a minimal Mac app with a transparent overlay, a menu bar control, and one placeholder explorer.

- Detect the position and stacking order of open windows.
- Turn visible window tops and sides into platforms and climbing routes.
- Let the explorer walk, climb, fall, and land.
- Keep normal desktop clicks, typing, scrolling, and window dragging working. Pass mouse events through everywhere except directly on an explorer, and do not take keyboard focus.
- Let the user grab and drag the explorer out of the way. Suspend its autonomous movement while held; on release, let it settle on a platform or parachute safely down, then resume exploring. Give it a short settling period so it does not immediately walk back into the way.
- Add pause and quit controls in the menu bar.

Done when: the explorer can climb a real window, be dragged aside, and respond sensibly when you move, resize, or close a window, while you continue using the computer normally. Verify that dragging works without activating the app and that clicks outside the character reach the underlying windows. This is the main technical risk, so tackle it first.

## 2. Build one complete adventure

Give the explorer a destination and a short sequence:

1. Spot a possible sock on another window.
2. Climb to a launch point.
3. Jump and deploy a parachute.
4. Land and investigate.
5. Discover a banana.
6. Mark the map with unjustified confidence.

Add abseiling as another way down, plus recovery behaviours for missed landings and disappearing platforms.

Done when: this sequence is entertaining to watch and survives ordinary desktop use.

## 3. Refine the explorer’s personality

Keep one character: fearless, confidently wrong, and prone to misreading maps. Vary his moods, hesitations, equipment mishaps and moments of competence. Refine his shared rig and animation until the personality reads clearly at desktop size.

Done when: his movement and reactions feel expressive without needing dialogue or extra characters.

## 4. Give him an ongoing mission

Build a small collection of expedition scenes:

- Investigating fluff and other false leads.
- Hauling oversized equipment up a window.
- Establishing a camp in an inconvenient place.
- Recovering his kettle from an inconvenient ledge.
- Spotting the sock just before it escapes.

A simple expedition director picks scenes according to the available terrain, avoids frequent repetition, and leaves quiet stretches between events. Save progress between launches so his journey feels continuous.

Done when: he can entertain you over several sessions without constantly demanding attention.

## 5. Make it comfortable to live with

- Support multiple displays and changing display arrangements.
- Handle sleep, wake, full-screen apps, and desktop switching.
- Keep CPU and battery use low.
- Offer a few controls: activity level, sound, pause, and launch at login.
- Package a signed Mac app for testing and distribution.

Done when: you can leave it running during a normal working day without it getting in your way.

## 6. Bring it to Windows

Keep terrain, movement, mission rules, and animation definitions separate from Mac-specific window handling. Build the Windows overlay and window detection around those same behaviours and assets.

Prioritise getting the Mac version right; the first prototype should help decide how much code is worth sharing.

## Technical direction

- macOS: Swift, AppKit, and SpriteKit.
- Transparent, non-activating desktop overlay with mouse events passed through to underlying apps except within tightly fitted explorer hit areas. Use a separate input layer or small non-activating character panels for dragging; verify the AppKit approach in the first prototype rather than making the entire overlay intercept input.
- Window geometry and stacking order provide terrain; window contents are not needed for the expedition.
- Behaviour rules and a lightweight scene director provide personality without an AI service.
- Keep platform-specific window discovery and overlay handling separate from expedition behaviour and asset definitions.

## First milestone

One draggable explorer, one display, real window climbing, one parachute jump, and one disappointing banana. This should establish whether the central idea feels alive before building the whole expedition.

## Later ideas

Optional ideas to explore after the core expedition works, outside the first milestone:

- **The user is his mysterious benefactor.** Dragging an explorer across a gap earns an awestruck salute. He records it as excellent leadership.
- **Equipment has consequences.** A parachute occasionally opens into a picnic blanket. They land safely, then reluctantly have lunch.
- **Monitors become continents.** They establish a departure camp at the boundary between displays. The first crossing gets an unnecessarily elaborate ceremony.
- **The sock is nesting.** It steals flags, ropes, and unattended sandwiches to furnish its hiding place.
- **Their map remembers the desktop.** Landmarks acquire names based on actual expedition events: "The Great Browser Cliffs" and "The Valley Where Brian Fell." Generate these from geometry and expedition history without reading window contents.
- **Rare moments of competence.** After dozens of mishaps, he executes a perfect crossing, gives himself a tiny salute, and immediately walks the wrong way.
- **An expedition journal.** Open a little journal from the menu bar, with entries inspired by events: "Day 12. The giant moved the mountain again. Morale adequate. Biscuits low."
