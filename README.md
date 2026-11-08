# Jerry

<img src="Jerry/Resources/AppIcon.png" alt="Jerry, your personal desktop explorer" width="128">

**Your own little explorer. Your desktop is his next adventure.**

Meet Jerry, a small adventurer who lives on your Mac. Take control and turn your windows into a platform game, or give him a mission and send him on an expedition. He keeps a journal along the way.

**[Download Jerry for Mac ↓](https://github.com/samwillis/jerry/releases/download/v0.1.1/Jerry-v0.1.1-macos-universal.zip)** · [Release notes](https://github.com/samwillis/jerry/releases/tag/v0.1.1)

macOS 14+ · Apple Silicon and Intel · v0.1.1 preview. Signed by Flutterbox Ltd. and notarised by Apple.

https://github.com/user-attachments/assets/b6b0a2ad-a652-4d23-af81-e2b7e0d47de9

## Your desktop, his landscape

Jerry walks along window tops, climbs their sides, abseils down ropes and parachutes between ledges. His grappling hook takes him to places his boots won’t. Move a window and he comes along for the ride.

You can carry on using your Mac while he explores. Bring your pointer nearby and he watches it; if he’s in the way, just drag him aside.

## Take control

Walk, run, jump, climb and swing your way around the desktop. Jerry can even press real buttons in other apps with the marker beside his hand.

Use his hat-and-face icon in the menu bar, or take the lead with the keyboard:

| Shortcut | Action |
| --- | --- |
| Control–Option–Space | Take or release control from any app |
| Control–Option–Return | Ask Jerry from any app |
| Arrows or WASD | Move, climb and swing while in control |
| Space | Jump or let go of a rope |
| Shift | Run or climb faster |
| Hold G + arrows; release G | Aim and fire the grappling hook |
| Hold C | Crouch |
| E | Click the marker beside Jerry’s hand |
| Return | Ask Jerry while in control |
| Escape | Leave control and return to your previous app |

The shortcuts above are the defaults. Change or clear either global shortcut in **Settings → Controls**, where you’ll also find the full movement reference.

## Send him on an expedition

Connect your ChatGPT account or configure an API key in **Settings → AI**, then give Jerry a mission using the input beside him.

Jerry can answer questions and attempt tasks on your computer. He reaches controls by travelling to them, then clicking. To type, he finds and presses keys on an onscreen keyboard. Even a simple job becomes a small expedition. It is deliberately, wonderfully inefficient—and still experimental.

You can add directions while he works, pause him, or take control yourself.

## Read his journal

Jerry records your requests, his notes and what happens along the way in the **Expedition Journal**. Each expedition has its own place in the sidebar, with technical details tucked into expandable sections. His handwritten field notes tell the story, with locally saved photographs of meaningful moments when Screen Recording access is available.

Continue an expedition from the journal’s prompt box or the input beside Jerry. It stays open for follow-up directions until you finish it or start a new one. Expeditions are saved automatically on your Mac, so you can revisit and resume them after restarting Jerry. An unfinished mission reopens paused. You can also export a readable copy of the journal.

## A little adventure between missions

When Jerry has nothing else to do, he can wander your windows in search of patterned socks. Someone has to find out where they all go.

Turn off **Explore when idle** if you’d rather he stayed put. You can still drag him, take control or give him a mission.

## Make yourself at home

No account is needed for idle exploration or keyboard movement. Extra abilities are optional:

- **Accessibility access** lets Jerry press controls in other apps. Newer macOS versions call this Device Control and Data Access.
- **Screen Recording access** lets him find ledges and cracks inside windows. This terrain analysis runs locally.
- **AI connections** send task context to your chosen service. Sharing active-window images with the AI is a separate setting.

Jerry guides you through missing permissions for features you’ve enabled. You can also manage them in **Settings → Privacy & Access**. Credentials are stored in macOS Keychain; AI connections are managed in **Settings → AI**.

## Current availability

Jerry is a macOS development preview targeting macOS 14 or later. Exploration currently stays on the primary display; multiple displays, full-screen traversal and Windows support are future work.

Download the [v0.1.1 preview for Mac](https://github.com/samwillis/jerry/releases/tag/v0.1.1). This experimental build is signed by Flutterbox Ltd. and notarised by Apple. It includes Apple Silicon and Intel binaries; testing so far has been on the development Apple Silicon Mac.

To build and run it locally, see the [developer guide](AGENTS.md). The [product plan](docs/PLAN.md) and [implementation plan](docs/IMPLEMENTATION_PLAN.md) describe where the expedition goes next.
