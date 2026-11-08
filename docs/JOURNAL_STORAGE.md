# Expedition journal storage

Jerry automatically saves journals locally. Each expedition has a stable UUID directory:

```text
~/Library/Application Support/Jerry/Expeditions/
  <expedition-uuid>/
    journal.jsonl
    <photo-uuid>.jpg
```

Photographs are saved as JPEG assets alongside `journal.jsonl`; the loader ignores unrelated files. Folder names do not depend on the mission title.

## JSONL format, version 1

Each UTF-8 line is one JSON object. Every record has `version` (currently `1`), a unique event `id`, a `date` in milliseconds since the Unix epoch, and an `event` name. Record payloads are:

| Event | Payload |
| --- | --- |
| `created` | `expedition`: its `id`, creation `date` and `title` |
| `entry` | `entry`: its stable `id`, `date`, `kind` (`request`, `response` or `activity`), `text`, expandable `details`, and optional `photo` (a UUID `.jpg` filename) |
| `textAppended` | `entryID`, `text`: the next streamed text chunk |
| `textReplaced` | `entryID`, `text`: replacement text when a response revises an earlier prefix |
| `detailsAppended` | `entryID`, `text`: additional details, including any paragraph separator |
| `titleChanged` | `text`: the AI-generated expedition name |
| `state` | `status`, `isRunning`, `isFinished` |

Records append in order. Event IDs make retries idempotent. Streaming deltas avoid storing a complete response for every token update. Unknown JSON fields are ignored; an unsupported format version leaves that expedition untouched rather than rewriting it.

## Saving and recovery

A serial utility queue batches changes over approximately 200 ms. Task boundaries, finishing an expedition and graceful shutdown drain pending writes. Files use mode 0600 and expedition directories use 0700. A save error keeps pending records in memory and shows a Retry saving action at the end of the scrolling journal.

The loader replays complete records, preserves original files and warns about malformed records. An interrupted last line is skipped; subsequent writes start on a fresh line so later notes remain readable. Duplicate events are ignored. A newer unsupported expedition format does not prevent other expeditions from loading.

On reopening the journal, finished expeditions remain finished and an unfinished expedition remains available for follow-up prompts. A previously running task restores paused. Jerry never automatically resumes computer actions. Selection initially opens the unfinished expedition, or the newest saved expedition if all are finished.

Visible messages and expandable tool/metadata details are persisted. API keys, OAuth credentials, provider-specific transcripts and opaque model reasoning are not part of this store. Credentials stay in Keychain. Continuing after restarting reconstructs conversation context from saved user/Jerry messages, then obtains fresh screen context through the normal task flow.

**Export journal** still produces a separate readable text export of all expeditions and details. It is not needed for automatic saving. No in-app deletion control is implemented yet; quit Jerry before removing an expedition folder manually.

## Field notes and photographs

Jerry’s model instructions ask for first-person observations, verified achievements and the next meaningful step, with a little explorer character. Jerry’s sidebar, title, dates, notes and captions use bundled Caveat handwriting. Expandable details use Courier on separate taped white receipts. Your directions use Courier on cut-out white paper with translucent tape, and the composer uses the same typewriter style. Low-level receipts remain expandable.

The `computer_action` tool accepts `take_photo`, with a factual caption in `text`. It stages a brief “One for the journal!” moment, with a raised-arm pose on safe standing surfaces while preserving climbing and rope grips elsewhere. ScreenCaptureKit captures a crop around Jerry containing only his transparent rendering layer and the frontmost task window, up to 1200 pixels wide, with a warm paper background. Other apps, the journal and prompt are excluded. Existing Screen Recording access is required. It neither prompts for permission nor enables AI image sharing. The JPEG is saved before its journal entry is appended, then appears as a slightly tilted, taped Polaroid: a square centre crop, narrow top/side borders and a deep white strip for the handwritten caption. Only the outer print casts a shadow; the photo and lettering have no separate shadow. The original JPEG remains uncropped on disk. Captions are model-written and photographs document a moment; neither replaces verification of task success. Missing assets retain their captions. Photo bytes load off the main thread.

Photos stay local and are not attached to tool results or restored model context. The separate active-window image sharing option still controls AI inspection attachments. Jerry is instructed to photograph meaningful intermediate achievements as well as the final goal, using relevant non-sensitive results and continuing without photos if unavailable. A completed route with at least 240 points of accumulated climbing can also trigger a local photograph, with a 45-second cooldown and a maximum of three automatic climb photographs per direction. Local journals and photos may contain screen content; keep that in mind when sharing their folders. Text exports include relative asset references, not embedded images.

New expeditions begin as “An untitled adventure”. The task’s existing AI generates a short whimsical title through `name_expedition`, saved as a `titleChanged` record. Direct copies of the prompt are rejected. Follow-up prompts retain the name; older prompt-derived titles become eligible for an AI name when resumed, without bulk-sending historical journals to a model.

## Development

`ExpeditionJournalStore.swift` owns the JSONL writer and replay. `ExpeditionJournal` owns UI state and emits records as it changes. Passing `storageDirectory: nil` disables persistence; native/agent fixtures use this or a disposable directory and must never write test expeditions into the real Application Support history.

Agent checks cover round trips, Unicode and revisions, state restoration, paused restart, multiple expeditions, resuming an older expedition, automatic batching, interrupted tails, duplicate events, future formats/assets, and recovery after write failure. Store errors are visible in the scrolling journal rather than in a separate blocking window.

Run the Debug executable with `--journal-preview` for an isolated visual fixture with a drawn TextEdit photograph. It uses a temporary directory, performs no computer input and reads no real screen or saved history. Quit that preview before launching the normal app.

Caveat is distributed under the SIL Open Font License 1.1. The unmodified variable font comes from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/caveat); its licence is bundled in `Jerry/Resources/Caveat-OFL.txt`. Registration is process-local: the app does not install a system font or fetch fonts at runtime.

The preview also accepts `--compact` or `--wide` for layout checks. `--live-photo-preview --fixture-terrain --start-on-window` uses the normal capture action against an already open disposable Terrain Fixture, with temporary journal storage. It requires existing Screen Recording permission, does not request access and performs no clicks, typing or model requests. Quit all Jerry instances before running it.
