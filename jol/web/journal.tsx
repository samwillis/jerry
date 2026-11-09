import { Button } from "@base-ui/react/button";
import { Collapsible } from "@base-ui/react/collapsible";
import { Select } from "@base-ui/react/select";
import { createRealtimeClient } from "@neon/realtime/client";
import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { useRemoteRows } from "./live.js";
import type { JournalAPI } from "./session.js";

type Stamp = string | Date;
type Expedition = {
  id: string;
  device_id: string;
  title: string;
  status: string;
  is_running: boolean;
  is_finished: boolean;
  created_at: Stamp;
};
type Device = {
  id: string;
  name: string;
  last_seen: Stamp | null;
  remote_enabled: boolean;
};
type Entry = {
  id: string;
  position: number;
  kind: "request" | "response" | "activity";
  text: string;
  details: string;
  photo: string | null;
  photo_ready: boolean;
  created_at: Stamp;
};
type Command = {
  id: string;
  kind: string;
  prompt: string;
  status: string;
  result: string;
  expedition_id: string | null;
  created_at: Stamp;
};
const id = (row: { id: string }) => row.id;
const expeditionKey = (row: { device_id: string; id: string }) =>
  row.device_id + "/" + row.id;
const time = (stamp: Stamp) =>
  new Date(stamp).toLocaleTimeString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  });
const pageDate = (stamp: Stamp) =>
  new Date(stamp).toLocaleDateString(undefined, {
    weekday: "long",
    day: "numeric",
    month: "long",
  });
const trailDate = (stamp: Stamp) =>
  new Date(stamp).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
  }) +
  " at " +
  time(stamp);
const newest = (a: { created_at: Stamp }, b: { created_at: Stamp }) =>
  +new Date(b.created_at) - +new Date(a.created_at);
const problem = (e: unknown) =>
  e instanceof Error ? e.message : "Could not reach JOL.";

export function Brand() {
  return (
    <>
      <img className="jol-logo" src="/jol-logo.svg" alt="JOL" />
      <span className="brand-name">Jerry On Line</span>
    </>
  );
}
function Icon({
  name,
}: {
  name: "sidebar" | "new" | "finish" | "stop" | "send" | "chevron";
}) {
  const drawing: Record<typeof name, ReactNode> = {
    sidebar: (
      <>
        <rect x="3" y="4" width="18" height="16" rx="3" />
        <path d="M9 4v16M5.8 8h.6m-.6 4h.6" />
      </>
    ),
    new: (
      <>
        <path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6" />
        <path d="m10 14 1-4 7-7 3 3-7 7-4 1Z" />
      </>
    ),
    finish: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="m8 12 3 3 5-6" />
      </>
    ),
    stop: (
      <>
        <circle cx="12" cy="12" r="9" />
        <rect x="9" y="9" width="6" height="6" rx="1" />
      </>
    ),
    send: (
      <>
        <circle cx="12" cy="12" r="11" fill="currentColor" stroke="none" />
        <path d="M12 17V7m-4 4 4-4 4 4" stroke="var(--paper)" />
      </>
    ),
    chevron: <path d="m9 6 6 6-6 6" />,
  };
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {drawing[name]}
    </svg>
  );
}

export function Journal({
  api,
  realtimeURL,
}: {
  api: JournalAPI;
  realtimeURL: string | null;
}) {
  const [client, setClient] =
    useState<ReturnType<typeof createRealtimeClient>>();
  useEffect(() => {
    if (!realtimeURL) return;
    const next = createRealtimeClient({ url: realtimeURL });
    setClient(next);
    return () => next.close();
  }, [realtimeURL]);
  if (realtimeURL && !client)
    return <p className="connecting">Opening your journal…</p>;
  return <JournalContents api={api} client={client} />;
}

function JournalContents({
  api,
  client,
}: {
  api: JournalAPI;
  client?: ReturnType<typeof createRealtimeClient>;
}) {
  const [sidebarOpen, setSidebarOpen] = useState(() => window.innerWidth > 680);
  const [selection, setSelection] = useState<Expedition | null>();
  const [chosenDevice, setChosenDevice] = useState("");
  const [older, setOlder] = useState<Expedition[]>([]);
  const [pageEnd, setPageEnd] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [issue, setIssue] = useState("");
  const [clock, setClock] = useState(Date.now);

  useEffect(() => {
    const timer = setInterval(() => setClock(Date.now()), 5000);
    return () => clearInterval(timer);
  }, []);

  const macs = useRemoteRows<Device>(
    api,
    client,
    { kind: "devices" },
    "/devices",
    id,
  );
  const recents = useRemoteRows<Expedition>(
    api,
    client,
    { kind: "expeditions" },
    "/expeditions",
    expeditionKey,
  );
  const all = new Map<string, Expedition>();
  for (const expedition of [...older, ...(recents.rows ?? [])])
    all.set(expeditionKey(expedition), expedition);
  const expeditions = [...all.values()].sort(
    (a, b) => newest(a, b) || expeditionKey(b).localeCompare(expeditionKey(a)),
  );
  const base = selection === undefined ? expeditions[0] : selection;
  const selected = base ? (all.get(expeditionKey(base)) ?? base) : undefined;
  const devices = macs.rows ?? [];
  const activeDevice =
    devices.find(
      (device) => device.id === (selected?.device_id || chosenDevice),
    ) ?? devices[0];
  const online =
    activeDevice?.last_seen != null &&
    clock - +new Date(activeDevice.last_seen) < 60_000;
  const liveDelayed = !!client && (macs.fallback || recents.fallback);

  function choose(expedition: Expedition | null) {
    setSelection(expedition);
    if (expedition) setChosenDevice(expedition.device_id);
    if (window.innerWidth <= 680) setSidebarOpen(false);
  }
  async function loadOlder() {
    const last = expeditions.at(-1);
    if (!last || loadingOlder) return;
    setLoadingOlder(true);
    const query = new URLSearchParams({
      before: new Date(last.created_at).toISOString(),
      device: last.device_id,
      expedition: last.id,
    });
    try {
      const rows = await api.read<Expedition[]>("/expeditions?" + query);
      setOlder((previous) => [...previous, ...rows]);
      setPageEnd(rows.length < 100);
    } catch (e) {
      setIssue(problem(e));
    } finally {
      setLoadingOlder(false);
    }
  }

  return (
    <main className="shell">
      <header className="masthead">
        <Brand />
        <span className="connection">
          <span className={online ? "lamp" : "lamp offline"} />
          {liveDelayed
            ? "Reconnecting live updates"
            : online
              ? "Jerry is on line"
              : activeDevice?.last_seen
                ? "Last seen " + time(activeDevice.last_seen)
                : "Waiting for Jerry"}
        </span>
        <Button
          onClick={() => void api.signOut().catch((e) => setIssue(problem(e)))}
        >
          Sign out
        </Button>
      </header>
      <section
        className={`notebook workspace ${sidebarOpen ? "sidebar-open" : ""}`}
      >
        <aside className="sidebar" id="expeditions" inert={!sidebarOpen}>
          <h2>Expeditions</h2>
          <div className="expedition-list">
            {!expeditions.length && (
              <p className="sidebar-note">
                {recents.ready ? "No expeditions yet" : "Opening your journal…"}
              </p>
            )}
            {expeditions.map((expedition) => {
              const key = expeditionKey(expedition);
              const active = !!selected && expeditionKey(selected) === key;
              return (
                <Button
                  className={`expedition ${active ? "active" : ""}`}
                  key={key}
                  aria-current={active ? "page" : undefined}
                  title={expedition.title}
                  onClick={() => choose(expedition)}
                >
                  <span className="expedition-name">{expedition.title}</span>
                  <small>
                    {expedition.is_running && (
                      <span
                        className="writing-dot"
                        aria-label="Jerry is writing"
                      />
                    )}
                    {trailDate(expedition.created_at)}
                  </small>
                </Button>
              );
            })}
            {!pageEnd && (recents.rows?.length ?? 0) >= 100 && (
              <Button
                className="quiet more-expeditions"
                disabled={loadingOlder}
                onClick={() => void loadOlder()}
              >
                Earlier expeditions
              </Button>
            )}
          </div>
          {devices.length > 0 && (
            <Select.Root
              value={activeDevice?.id ?? null}
              onValueChange={(value) => {
                if (value) {
                  setChosenDevice(value);
                  choose(null);
                }
              }}
            >
              <Select.Trigger className="device-picker" aria-label="Choose Mac">
                <span>{activeDevice?.name}</span>
                <Select.Icon>
                  <Icon name="chevron" />
                </Select.Icon>
              </Select.Trigger>
              <Select.Portal>
                <Select.Positioner side="top" sideOffset={5}>
                  <Select.Popup className="device-popup">
                    {devices.map((device) => (
                      <Select.Item value={device.id} key={device.id}>
                        <Select.ItemText>{device.name}</Select.ItemText>
                        <Select.ItemIndicator>✓</Select.ItemIndicator>
                      </Select.Item>
                    ))}
                  </Select.Popup>
                </Select.Positioner>
              </Select.Portal>
            </Select.Root>
          )}
        </aside>
        <section className="journal">
          <ExpeditionPage
            key={
              selected ? expeditionKey(selected) : (activeDevice?.id ?? "new")
            }
            api={api}
            client={client}
            selected={selected}
            device={activeDevice}
            online={online}
            issue={issue}
            onNew={() => choose(null)}
            sidebarOpen={sidebarOpen}
            onToggleSidebar={() => setSidebarOpen(!sidebarOpen)}
          />
        </section>
      </section>
    </main>
  );
}

type PageProps = {
  api: JournalAPI;
  client: ReturnType<typeof createRealtimeClient> | undefined;
  selected: Expedition | undefined;
  device: Device | undefined;
  online: boolean;
  issue: string;
  onNew(): void;
  sidebarOpen: boolean;
  onToggleSidebar(): void;
};
function ExpeditionPage({
  api,
  client,
  selected,
  device,
  online,
  issue,
  onNew,
  sidebarOpen,
  onToggleSidebar,
}: PageProps) {
  const path = selected
    ? `/devices/${selected.device_id}/expeditions/${selected.id}`
    : undefined;
  const spec = selected && {
    deviceID: selected.device_id,
    expeditionID: selected.id,
  };
  const metadata = useRemoteRows<Expedition>(
    api,
    client,
    spec && { ...spec, kind: "expedition" },
    path,
    expeditionKey,
  );
  const recent = useRemoteRows<Entry>(
    api,
    client,
    spec && { ...spec, kind: "entries" },
    path && path + "/entries",
    id,
  );
  const deliveries = useRemoteRows<Command>(
    api,
    client,
    device && { kind: "commands", deviceID: device.id },
    device && `/devices/${device.id}/commands`,
    id,
  );
  const [earlier, setEarlier] = useState<Entry[]>([]);
  const [hasEarlier, setHasEarlier] = useState(true);
  const [reading, setReading] = useState(false);
  const [direction, setDirection] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const pages = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLTextAreaElement>(null);
  const following = useRef(true);
  const prepend = useRef<number | null>(null);
  const submission = useRef<{ key: string; id: string } | null>(null);

  const expedition = metadata.rows?.[0] ?? selected;
  // Retain entries that scrolled out of the live window while reading.
  const [seen, setSeen] = useState<Entry[]>([]);
  useEffect(() => {
    if (!recent.rows?.length) return;
    const incoming = recent.rows;
    setSeen((previous) => [
      ...new Map(
        [...previous, ...incoming].map((entry) => [entry.id, entry]),
      ).values(),
    ]);
  }, [recent.rows]);
  const entries = [
    ...new Map(
      [...earlier, ...seen, ...(recent.rows ?? [])].map((entry) => [
        entry.id,
        entry,
      ]),
    ).values(),
  ].sort((a, b) => a.position - b.position);
  const commands = [...(deliveries.rows ?? [])]
    .sort(newest)
    .filter(
      (command) =>
        (!selected ||
          command.expedition_id === selected.id ||
          command.expedition_id == null) &&
        [
          "queued",
          "received",
          "started",
          "failed",
          "expired",
          "uncertain",
        ].includes(command.status),
    )
    .slice(0, 8);
  const delayed =
    !!client && (metadata.fallback || recent.fallback || deliveries.fallback);
  const canSend = !!device?.remote_enabled && !expedition?.is_finished;
  const showOlder = hasEarlier && (recent.rows?.length ?? 0) >= 200;

  useLayoutEffect(() => {
    const box = pages.current;
    if (!box) return;
    if (prepend.current !== null) {
      box.scrollTop += box.scrollHeight - prepend.current;
      prepend.current = null;
    } else if (following.current) {
      box.scrollTop = box.scrollHeight;
    }
  }, [recent.rows, earlier, metadata.rows, deliveries.rows]);

  async function moreEntries() {
    if (!path || !entries.length || reading) return;
    setReading(true);
    try {
      const rows = await api.read<Entry[]>(
        path + "/entries?before=" + entries[0].position,
      );
      if (pages.current) prepend.current = pages.current.scrollHeight;
      following.current = false;
      setEarlier((old) => [...rows, ...old]);
      setHasEarlier(rows.length === 200);
    } catch (e) {
      setError(problem(e));
    } finally {
      setReading(false);
    }
  }

  async function send(
    kind: "start" | "continue" | "finish" | "stop",
    event?: FormEvent,
  ) {
    event?.preventDefault();
    if (sending || !device) return;
    const prompt =
      kind === "start" || kind === "continue" ? direction.trim() : "";
    if ((kind === "start" || kind === "continue") && (!canSend || !prompt))
      return;
    const key = JSON.stringify([device.id, selected?.id, kind, prompt]);
    if (submission.current?.key !== key)
      submission.current = { key, id: crypto.randomUUID() };
    setSending(true);
    setError("");
    try {
      await api.read("/commands", {
        id: submission.current.id,
        deviceID: device.id,
        expeditionID: selected?.id,
        kind,
        prompt,
      });
      submission.current = null;
      if (prompt) setDirection("");
    } catch (e) {
      setError(problem(e));
    } finally {
      setSending(false);
    }
  }
  return (
    <>
      <header className="toolbar">
        <Button
          className="tool-button sidebar-toggle"
          aria-label="Toggle expeditions"
          aria-controls="expeditions"
          aria-expanded={sidebarOpen}
          title="Toggle expeditions"
          onClick={onToggleSidebar}
        >
          <Icon name="sidebar" />
        </Button>
        <h1>Expedition journal</h1>
        <div className="tools">
          <Button
            className="tool-button"
            aria-label="New expedition"
            title="New expedition"
            onClick={() => {
              onNew();
              input.current?.focus();
            }}
          >
            <Icon name="new" />
          </Button>
          {expedition?.is_running && (
            <Button
              className="tool-button"
              disabled={!device?.remote_enabled || sending}
              aria-label="Stop expedition"
              title="Stop expedition"
              onClick={() => void send("stop")}
            >
              <Icon name="stop" />
            </Button>
          )}
          <Button
            className="tool-button"
            disabled={
              !device?.remote_enabled ||
              !selected ||
              !!expedition?.is_finished ||
              sending
            }
            aria-label="Finish expedition"
            title="Finish expedition"
            onClick={() => void send("finish")}
          >
            <Icon name="finish" />
          </Button>
        </div>
      </header>
      <div
        className="pages"
        ref={pages}
        tabIndex={0}
        aria-label="Expedition journal"
        onScroll={(event) => {
          const box = event.currentTarget;
          following.current =
            box.scrollHeight - box.scrollTop - box.clientHeight < 80;
        }}
      >
        <div className="page">
          {expedition ? (
            <>
              <header className="page-heading">
                <time dateTime={new Date(expedition.created_at).toISOString()}>
                  {pageDate(expedition.created_at)}
                </time>
                <h2>{expedition.title}</h2>
              </header>
              {showOlder && (
                <Button
                  className="quiet load-older"
                  disabled={reading}
                  onClick={() => void moreEntries()}
                >
                  Earlier entries
                </Button>
              )}
              {!recent.ready && !entries.length && (
                <p className="journal-status">Opening this expedition…</p>
              )}
              {entries.map((entry) => (
                <JournalEntry
                  key={entry.id}
                  entry={entry}
                  path={path!}
                  api={api}
                />
              ))}
              {expedition.is_running ? (
                <p className="journal-status">Jerry is working…</p>
              ) : (
                expedition.status !== "Ready for your next direction" && (
                  <p className="journal-status">{expedition.status}</p>
                )
              )}
            </>
          ) : (
            <header className="page-heading new-page">
              <h2>A new expedition</h2>
              <p>Where shall we go?</p>
            </header>
          )}
          {!!commands.length && (
            <div className="deliveries" aria-live="polite">
              {commands.map((command) => (
                <div className="delivery" key={command.id}>
                  <span>
                    {command.status === "queued"
                      ? "Waiting for Jerry"
                      : command.status === "received"
                        ? "Received by the Mac"
                        : command.status === "started"
                          ? "Jerry is working"
                          : command.status}
                  </span>
                  {command.result
                    ? ` · ${command.result}`
                    : command.prompt
                      ? ` · ${command.prompt}`
                      : ""}
                  {command.status === "queued" && (
                    <Button
                      className="quiet"
                      onClick={() => {
                        void api
                          .read(`/commands/${command.id}/cancel`, {})
                          .catch((e) => setError(problem(e)));
                      }}
                    >
                      Cancel
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
      <form
        className="composer"
        onSubmit={(event) => void send(selected ? "continue" : "start", event)}
      >
        <div className="compose-field">
          <textarea
            ref={input}
            value={direction}
            maxLength={20000}
            rows={1}
            aria-label="Expedition direction"
            placeholder={
              selected ? "Add a direction…" : "Give Jerry a mission…"
            }
            onChange={(event) => setDirection(event.target.value)}
            onKeyDown={(event) => {
              if (
                event.key === "Enter" &&
                !event.shiftKey &&
                !event.nativeEvent.isComposing
              ) {
                event.preventDefault();
                event.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <Button
            className="send-button"
            type="submit"
            aria-label="Send to Jerry"
            title="Send to Jerry"
            disabled={!canSend || !direction.trim() || sending}
          >
            <Icon name="send" />
          </Button>
        </div>
        <p
          className={error || issue ? "compose-status error" : "compose-status"}
          role={error || issue ? "alert" : undefined}
        >
          {error ||
            issue ||
            (delayed
              ? "Live updates are reconnecting"
              : !device
                ? "Connect Jerry on your Mac"
                : expedition?.is_finished
                  ? "Expedition finished"
                  : !device.remote_enabled
                    ? "Enable remote missions on this Mac"
                    : !online
                      ? "Mac offline · directions wait up to one hour"
                      : "")}
        </p>
      </form>
    </>
  );
}

function JournalEntry({
  entry,
  path,
  api,
}: {
  entry: Entry;
  path: string;
  api: JournalAPI;
}) {
  const label = entry.photo
    ? "A memento"
    : entry.kind === "request"
      ? "Your direction"
      : entry.kind === "response"
        ? "Jerry’s notes"
        : "On the trail";
  return (
    <article className={`entry entry-${entry.kind}`}>
      <div
        className={
          entry.kind === "request" ? "entry-paper scrap" : "entry-paper"
        }
      >
        <header className="entry-label">
          <span>{label}</span>
          <time dateTime={new Date(entry.created_at).toISOString()}>
            {time(entry.created_at)}
          </time>
        </header>
        {entry.photo ? (
          <Photograph
            path={path + "/photos/" + encodeURIComponent(entry.photo)}
            entry={entry}
            api={api}
          />
        ) : (
          <div
            className={entry.kind === "request" ? "typewritten" : "handwriting"}
          >
            {entry.text}
          </div>
        )}
        {entry.kind === "response" && !entry.photo && (
          <span className="signature">— Jerry</span>
        )}
      </div>
      {entry.details && (
        <Collapsible.Root className="details">
          <Collapsible.Trigger className="details-trigger">
            <Icon name="chevron" />
            Details
          </Collapsible.Trigger>
          <Collapsible.Panel>
            <div className="receipt">{entry.details}</div>
          </Collapsible.Panel>
        </Collapsible.Root>
      )}
    </article>
  );
}

function Photograph({
  path,
  entry,
  api,
}: {
  path: string;
  entry: Entry;
  api: JournalAPI;
}) {
  const [src, setSrc] = useState("");
  useEffect(() => {
    if (!entry.photo_ready) return;
    const abort = new AbortController();
    let objectURL: string | undefined;
    void api
      .photo(path, abort.signal)
      .then((image) => {
        if (abort.signal.aborted) return;
        objectURL = URL.createObjectURL(image);
        setSrc(objectURL);
      })
      .catch(() => {});
    return () => {
      abort.abort();
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [api, path, entry.photo_ready]);
  return (
    <figure className="polaroid">
      {src ? (
        <img src={src} alt="Jerry’s expedition photograph" />
      ) : (
        <div className="photo-placeholder">Photograph arriving…</div>
      )}
      <figcaption>{entry.text}</figcaption>
    </figure>
  );
}
