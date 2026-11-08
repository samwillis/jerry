# Native computer tasks

Press **Control–Option–Return** from any app, open **Ask Jerry…** from the hiking menu, or press **Return** in manual control. Type in the small bubble beside him; Return sends and Escape cancels. Idle wandering waits while you type. AI text and physical progress appear in the **Expedition journal** at the right of the screen. Stop or take manual control to interrupt; hiding the journal leaves the task running.

## Connection and observation

Use **Settings → AI** for ChatGPT browser sign-in or an OpenAI API key, and select a vision/tool-capable model from the loaded catalog. Credentials are stored in this app’s macOS Keychain items, labelled **Jerry — ChatGPT** and **Jerry — API key**. Legacy items are relabelled in place without replacing saved tokens or keys. Their internal service identifier remains stable for compatibility; background relabelling does not show authentication dialogs. **Disconnect** removes only the selected connection’s local credentials; it does not revoke the remote grant or remove the other saved connection. Models load automatically after connecting; selections are remembered per connection. Incomplete setup keeps the request intact and offers Return to Request. Unsigned Debug and Release builds may have different Keychain access identities; production signing remains necessary.

The AI reads the active app’s accessible controls and text, plus the Dock and system menu controls. Secure text fields are excluded. **Also share active-window images with the AI** adds optional vision observations and requires Screen Recording permission. Images are bounded, sent only with an explicit inspection, and are not saved by the app. The checkbox is off by default. Accessibility permission is required for computer interaction.

**Offline connection test** checks the native model/tool loop without reading desktop data or sending computer input. It does not plan or run a computer task.

## Physical actions

The `computer_action` tool can inspect, hover, click, double-click, scroll, drag and type. Every press waits for the explorer to arrive with a reachable hand or the explicit lower-pointer extension. There is one input lease; concurrent input requests are refused. Targets use IDs from the latest observation, are clipped to the display, are checked again after travel, and must still belong to the front app for normal app controls. Pointer movement during travel also defers input. The drag hit area does not steal the pointer parked over an auto-hidden Dock. A changed window or app requires another observation.

Traversal uses the existing walking, grappling, swinging and rope motors. It walks across a usable floor before an ascent and coils a grounded line to allow walking and crouching. A replacement hook keeps the old line supporting the explorer until the new pin is secure; a failed new shot leaves the old line attached. It prefers a suitable window roof. The physical display rim supplies a fallback for global menus and otherwise empty desktop. At the top he can hang and traverse with alternating grips. To reach an open menu, he lowers from that grip onto the shared rope system, then climbs or descends along it. The character is above the Dock; during AI operation he is also above popup menus. Explicit AI work can remain visible in full-screen apps, while idle exploration keeps its existing full-screen policy.

Typing presses keys on an already-visible system onscreen keyboard. The agent must first open it physically, through the Input menu or System Settings → Accessibility → Keyboard. There is no programmatic app launch, shell, clipboard insertion, AXSetValue, or direct text/shortcut injection. Uppercase and special layout changes currently require explicit physical Shift/key clicks. Long text is split into bounded calls. Inspecting the destination establishes whether typing succeeded.

## One explorer, separate expeditions

There is one explorer in all modes. Recruitment, roles, survey flags and automatic demo jobs have been removed. Stop simply stops the active task.

Each expedition has its own sidebar entry, history and model context. The prompt beside Jerry continues the open expedition; with none open it creates one. The journal’s composer addresses the selected expedition, allowing an archived expedition to resume without merging its history with another. A reply does not finish an expedition: Finish closes it, New expedition starts a fresh conversation, and Stop only pauses execution. Typing a new direction cancels the previous execution and waits for it to drain before starting another.

The journal is a normal Mac window. Its native toolbar toggles the animated sidebar, starts an expedition and exports the complete journal; Finish and Stop appear only when applicable. The date, entries and progress share one scrolling page, with only the composer fixed below it. Near the bottom (within 80 points), new content follows automatically. Scrolling up pauses following; returning to the bottom resumes it. Tool arguments, control lists and metadata stay under expandable Details. Journal history is saved automatically as versioned JSONL under `~/Library/Application Support/Jerry/Expeditions/<UUID>/journal.jsonl`. Earlier expeditions restore when the journal is opened; unfinished work restores paused and never resumes computer actions automatically. Export journal writes a separate readable copy of all expeditions and details. Provider-specific transcripts and opaque reasoning remain in memory; after restart, saved user/Jerry messages supply the continuation context. See [journal storage](JOURNAL_STORAGE.md).

Follow-ups rebuild a native Foundation Models session from its completed transcript, retaining provider reasoning with the expedition and refreshing credentials. Incomplete tool exchanges are removed after cancellation, target IDs are cleared, and the next instruction must inspect again. Switching provider/model retains readable conversational context without transferring opaque provider reasoning. Turning image sharing off removes old screen attachments from continuation context. Progress callbacks are scoped to their execution so cancelled work cannot create an expedition or write into another history.

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

### Journal field notes and local photographs

Jerry writes first-person field notes about verified progress and his next step. The `take_photo` computer action saves an active-window JPEG and caption in the current expedition folder when Screen Recording is already permitted. It does not share the photo with AI or change image-sharing settings. Notes and captions use handwriting; photographs have paper mounts. See [journal storage](JOURNAL_STORAGE.md) for the asset format and local privacy behavior.

Milestone photos now stage Jerry in a local ScreenCaptureKit crop with the task window, preserving supports on ropes and window sides. Large completed climbs can trigger a photo with a cooldown; the model can photograph substantial task achievements with captions. `name_expedition` is journal metadata, generated by the same task model before a new mission proceeds; follow-ups keep the title. Details are typewritten on their own taped receipts.
