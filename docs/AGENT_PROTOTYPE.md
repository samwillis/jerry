# Swift task and team prototype

Open **Tasks…** from the hiking menu. This increment surveys three illustrated flags; it does not yet operate other applications. Only the illustrated card and the task instruction go to a live model.

## Try it

Choose **ChatGPT plan**, use **Continue with ChatGPT** to complete browser consent, then **Load Models** and choose a model supporting images and tools. **Plan Survey** asks the model to assign the flag inspections. An OpenAI API key can alternatively be saved through the secure field. Credentials belong to this app and are stored in macOS Keychain; other apps' sessions are never imported. **Forget Connection** removes local credentials; it does not revoke the remote grant.

The **Scripted Foundation Models test (offline)** option exercises the same native session and tool loop without networking. Its presets demonstrate a solo job, three independent jobs and a dependent sequence.

The permanent explorer does the first ready job. At most two friends join for additional independent ready jobs. They enter from the screen edges, walk to their flags, inspect with binoculars and leave when their work finishes. Dependent work waits for its prerequisites; three sequential jobs do not recruit three explorers. Helpers are draggable. Stop, closing Tasks, grabbing the leader or taking manual control cancels the survey and sends helpers home. The leader remains.

Unsigned Debug and Release builds can have different Keychain access identities. Automatic credential reads never prompt or block startup; a production build needs a stable signing identity. The currently running Debug build retains the tested connection.

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
