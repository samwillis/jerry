# Jerry

<img src="Jerry/Resources/AppIcon.png" alt="Jerry, the desktop explorer" width="128">

**One small adventurer. One missing sock.**

Meet Jerry, a tiny desktop explorer with more determination than sense. He climbs your windows, abseils down ropes and parachutes between ledges in search of patterned socks.

Let him wander while you work, take control for a little desktop platforming, or give him a task and watch him attempt it the long way round.

## Meet Jerry

Jerry treats your open windows as a landscape. He walks along their tops, climbs their sides and uses his grappling hook to reach new places. Move a window and he comes along for the ride. Bring your pointer nearby and he watches it; get in his way and you can simply drag him aside.

His hunt takes him from binocular surveys to precarious crossings, with striped, spotted, argyle and zigzag socks waiting to be discovered. Your desktop stays usable while he explores.

## Take the lead

Use Jerry’s hat-and-face icon in the menu bar to ask him something, open his expedition journal or change his settings.

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

The full reference is in **Settings → Controls**. Turn off **Explore when idle** if you’d like Jerry to stay put. You can still drag him, take control or give him a task.

## Give him a mission

Connect your ChatGPT account or configure an API key in **Settings → AI**, then type a request in the input beside Jerry.

Jerry can answer questions and attempt tasks on your computer. To operate an app, he travels to its controls before clicking them. Typing means finding and pressing keys on an onscreen keyboard. It is deliberately, wonderfully inefficient—and still experimental.

The **Expedition Journal** keeps your requests, Jerry’s replies and his progress in a field notebook. Tool details are expandable, and you can save the log. Stop a task from the menu or take manual control to interrupt it.

## Make yourself at home

No account is needed for wandering or keyboard movement. Extra abilities are optional:

- **Accessibility access** lets Jerry press controls in other apps.
- **Screen Recording access** lets him find ledges and cracks inside windows. This terrain analysis runs locally.
- **AI connections** send task context to your chosen service. Sharing active-window images with the AI is a separate setting.

Credentials are stored in macOS Keychain. Manage these options in **Settings → Privacy & Access** and **Settings → AI**.

## Current availability

Jerry is a macOS development preview targeting macOS 14 or later. Exploration currently stays on the primary display; multiple displays, full-screen traversal and Windows support are future work.

There is no signed public release yet. To build and run it locally, see the [developer guide](AGENTS.md). The [product plan](docs/PLAN.md) and [implementation plan](docs/IMPLEMENTATION_PLAN.md) describe where the expedition goes next.
