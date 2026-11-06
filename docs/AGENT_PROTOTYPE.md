# Native computer tasks

Press **Control–Option–Return** from any app, open **Ask Jerry…** from the hiking menu, or press **Return** in manual control. Type in the small bubble beside him; Return sends and Escape cancels. Idle wandering waits while you type. AI text and physical progress appear in the **Expedition journal** at the right of the screen. Stop or take manual control to interrupt; hiding the journal leaves the task running.

## Connection and observation

Use **Settings → AI** for ChatGPT browser sign-in or an OpenAI API key, and select a vision/tool-capable model from the loaded catalog. Credentials are stored in this app’s macOS Keychain items. **Disconnect** removes only the selected connection’s local credentials; it does not revoke the remote grant or remove the other saved connection. Models load automatically after connecting; selections are remembered per connection. Incomplete setup keeps the request intact and offers Return to Request. Unsigned Debug and Release builds may have different Keychain access identities; production signing remains necessary.

The AI reads the active app’s accessible controls and text, plus the Dock and system menu controls. Secure text fields are excluded. **Also share active-window images with the AI** adds optional vision observations and requires Screen Recording permission. Images are bounded, sent only with an explicit inspection, and are not saved by the app. The checkbox is off by default. Accessibility permission is required for computer interaction.

**Offline connection test** checks the native model/tool loop without reading desktop data or sending computer input. It does not plan or run a computer task.

## Physical actions

The `computer_action` tool can inspect, hover, click, double-click, scroll, drag and type. Every press waits for the explorer to arrive with a reachable hand or the explicit lower-pointer extension. There is one input lease; concurrent input requests are refused. Targets use IDs from the latest observation, are clipped to the display, are checked again after travel, and must still belong to the front app for normal app controls. Pointer movement during travel also defers input. The drag hit area does not steal the pointer parked over an auto-hidden Dock. A changed window or app requires another observation.

Traversal uses the existing walking, grappling, swinging and rope motors. It walks across a usable floor before an ascent and coils a grounded line to allow walking and crouching. A replacement hook keeps the old line supporting the explorer until the new pin is secure; a failed new shot leaves the old line attached. It prefers a suitable window roof. The physical display rim supplies a fallback for global menus and otherwise empty desktop. At the top he can hang and traverse with alternating grips. To reach an open menu, he lowers from that grip onto the shared rope system, then climbs or descends along it. The character is above the Dock; during AI operation he is also above popup menus. Explicit AI work can remain visible in full-screen apps, while idle exploration keeps its existing full-screen policy.

Typing presses keys on an already-visible system onscreen keyboard. The agent must first open it physically, through the Input menu or System Settings → Accessibility → Keyboard. There is no programmatic app launch, shell, clipboard insertion, AXSetValue, or direct text/shortcut injection. Uppercase and special layout changes currently require explicit physical Shift/key clicks. Long text is split into bounded calls. Inspecting the destination establishes whether typing succeeded.

## One explorer, one journal

There is one explorer in all modes. Recruitment, roles, survey flags and automatic demo jobs have been removed. Stop simply stops the active task.

The journal reads as a sequence of instructions, short accounts of actions and model responses. Tool arguments, returned control lists and model setup are retained under expandable **Details**, closed by default. Opening details pauses automatic following; **Follow latest** resumes it. History remains across tasks in the running session. **Save log…** exports both the readable entries and their full technical details.

The accepted crouch animation is unchanged. **Option while crouching** lowers the pointer another 16 points, shown by a short extension. AI uses the same pointer adjustment for low controls. Keyboard presses include a brief hold, then verify the focused text value. A press is retried only when the value provably did not change; focus changes, user edits and autocorrection stop blind retries.

## Architecture and limits

- Foundation Models custom providers and native tool sessions require macOS 27. The Responses adapter supports text, image tool outputs, namespaces and opaque reasoning replay, with bounded streams and a 160-turn ceiling.
- The model never directly injects input. `ExplorerComputer` observes and validates; `OverlayController` and `ExplorerInteraction` provide physical reach; the rig supplies contact poses.
- Stop, replacement, manual takeover and dragging the explorer cancel pending work. No late tool callback is allowed to start a new action for an old run.
- This is a first implementation on the primary display, with an English system keyboard/UI as the initial acceptance target. Unlabelled canvas controls, custom keyboard layouts, moving controls, repeated reflow and complicated multi-window tasks still need further acceptance testing.
- It must explain a blocker rather than invent a completed task. Consequential actions, credentials and unrelated app content are outside an ordinary benign task’s authority.

## References

- [OpenAI ChatGPT sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Function tools and image outputs](https://developers.openai.com/api/docs/guides/function-calling)
