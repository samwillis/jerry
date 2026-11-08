# Expedition journal storage

Jerry automatically saves journals locally. Each expedition has a stable UUID directory:

```text
~/Library/Application Support/Jerry/Expeditions/
  <expedition-uuid>/
    journal.jsonl
```

Only `journal.jsonl` is created today. Screenshots and other assets can be added alongside it in future; the loader ignores unrelated files. Folder names do not depend on the mission title.

## JSONL format, version 1

Each UTF-8 line is one JSON object. Every record has `version` (currently `1`), a unique event `id`, a `date` in milliseconds since the Unix epoch, and an `event` name. Record payloads are:

| Event | Payload |
| --- | --- |
| `created` | `expedition`: its `id`, creation `date` and `title` |
| `entry` | `entry`: its stable `id`, `date`, `kind` (`request`, `response` or `activity`), `text` and expandable `details` |
| `textAppended` | `entryID`, `text`: the next streamed text chunk |
| `textReplaced` | `entryID`, `text`: replacement text when a response revises an earlier prefix |
| `detailsAppended` | `entryID`, `text`: additional details, including any paragraph separator |
| `state` | `status`, `isRunning`, `isFinished` |

Records append in order. Event IDs make retries idempotent. Streaming deltas avoid storing a complete response for every token update. Unknown JSON fields are ignored; an unsupported format version leaves that expedition untouched rather than rewriting it.

## Saving and recovery

A serial utility queue batches changes over approximately 200 ms. Task boundaries, finishing an expedition and graceful shutdown drain pending writes. Files use mode 0600 and expedition directories use 0700. A save error keeps pending records in memory and shows a Retry saving action at the end of the scrolling journal.

The loader replays complete records, preserves original files and warns about malformed records. An interrupted last line is skipped; subsequent writes start on a fresh line so later notes remain readable. Duplicate events are ignored. A newer unsupported expedition format does not prevent other expeditions from loading.

On reopening the journal, finished expeditions remain finished and an unfinished expedition remains available for follow-up prompts. A previously running task restores paused. Jerry never automatically resumes computer actions. Selection initially opens the unfinished expedition, or the newest saved expedition if all are finished.

Visible messages and expandable tool/metadata details are persisted. API keys, OAuth credentials, provider-specific transcripts and opaque model reasoning are not part of this store. Credentials stay in Keychain. Continuing after restarting reconstructs conversation context from saved user/Jerry messages, then obtains fresh screen context through the normal task flow.

**Export journal** still produces a separate readable text export of all expeditions and details. It is not needed for automatic saving. No in-app deletion control is implemented yet; quit Jerry before removing an expedition folder manually.

## Development

`ExpeditionJournalStore.swift` owns the JSONL writer and replay. `ExpeditionJournal` owns UI state and emits records as it changes. Passing `storageDirectory: nil` disables persistence; native/agent fixtures use this or a disposable directory and must never write test expeditions into the real Application Support history.

Agent checks cover round trips, Unicode and revisions, state restoration, paused restart, multiple expeditions, resuming an older expedition, automatic batching, interrupted tails, duplicate events, future formats/assets, and recovery after write failure. Store errors are visible in the scrolling journal rather than in a separate blocking window.
