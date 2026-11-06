# Swift task and team prototype

Open **Ask Explorer…** from the hiking menu, or press **Return** in manual control. A small input bubble appears beside the explorer and stays within the screen. Return sends; Escape dismisses it and restores manual control when that is how it was opened. Idle wandering waits while you type. This increment surveys three illustrated flags; it does not yet operate other applications. Only the illustrated card and the task instruction go to a live model.

## Try it

Open **Settings → AI Connection…**. Choose **ChatGPT**, use **Continue with ChatGPT** to complete browser consent, then **Load models** and choose a model supporting images and tools. Settings is separate from the task prompt. Type a task beside the explorer and press Return to ask the model to assign inspections. An OpenAI API key can alternatively be saved through the secure field. Credentials belong to this app and are stored in macOS Keychain; other apps' sessions are never imported. **Forget Connection** removes local credentials; it does not revoke the remote grant.

The **Offline demo** provider in Settings exercises the same native session and tool loop without networking. Its presets demonstrate a solo job, three independent jobs and a dependent sequence.

The permanent explorer does the first ready job. At most two friends join for additional independent ready jobs. They enter from the screen edges, walk to their flags, inspect with binoculars and leave when their work finishes. Dependent work waits for its prerequisites; three sequential jobs do not recruit three explorers. Helpers are draggable. Stop, grabbing the leader or taking manual control cancels the survey and sends helpers home. Closing Settings or hiding the journal leaves the task running. The leader remains.

Unsigned Debug and Release builds can have different Keychain access identities. Automatic credential reads never prompt or block startup; a production build needs a stable signing identity. The currently running Debug build retains the tested connection.

## Expedition journal

AI text streams into a non-activating panel at the right edge of the primary display. It shows the instruction, live physical progress and model output. **Stop task** cancels both the model request and queued work. **New task…** opens the input beside the explorer; submitting replaces the current task. **Hide** and the close button only hide the panel. **Show Expedition Journal** restores it from the menu. The model output remains readable after completion or failure. Returning to manual control cancels the active task.

## Implementation

- Foundation Models custom `LanguageModel` and `LanguageModelExecutor` provide the Swift session/tool abstraction. This prototype requires macOS 27 for those custom-provider APIs.
- A Responses adapter translates native text, image attachments, schemas, tool calls and tool results. It preserves opaque provider reasoning for subsequent turns and bounds stream sizes and model turns.
- ChatGPT sign-in uses a system browser, app-owned loopback callback, PKCE S256, independent state and nonce, signed ID-token validation, Keychain storage and refresh rotation. The listener installs its connection handler before starting.
- `assign_survey_jobs` can only submit validated blue/amber/purple jobs. It reports queued work. Physical arrival and inspection, not the model's prose, mark completion.
- `TeamMission` schedules ready jobs and rejects invalid graphs and stale completion callbacks. `MissionTeamNode` renders temporary companions using the existing character rig and traversal simulation.

## Next increments

1. Introduce a shared physical-action queue and exclusive input lease. The model requests a destination/action; traversal must reach it before an input event is possible.
2. Add a binocular observation action with explicit screen-sharing controls and bounded, timestamped screenshots. Screen contents remain untrusted task data.
3. Add physical control pressing, scrolling, focus changes and window dragging. Coordinate validation, interruption, cancellation and user takeover must precede broader tasks.
4. Locate and launch the system onscreen keyboard through physical interactions, then type through its keys. Only then keep a helper stationed there while another handles controls.
5. Let the planner use dependencies, travel cost and scarce input ownership to request helpers. Helpers should never multiply merely because the task is long.
6. Add other Swift providers behind the same native session abstraction, and evaluate the Apple on-device model separately. The current offline provider is scripted, not Apple Intelligence inference.

## References

- [OpenAI ChatGPT sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
