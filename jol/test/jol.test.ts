import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import { createApp } from "../src/app.js";
import type { Database } from "../src/database.js";
import { APIError } from "../src/protocol.js";
import type { Config } from "../src/config.js";

const store = new PGlite();
const db: Database = {
  query: async (s, v) => store.query(s, v),
  transaction: (fn) =>
    store.transaction((q) => fn({ query: async (s, v) => q.query(s, v) })),
};
const cfg: Config = {
  origin: "https://jol.example.test",
  instanceID: randomUUID(),
  name: "JOL",
  authURL: "https://auth.example.test/neondb/auth",
  jwksURL: "https://auth.example.test/jwks",
  clientID: "native",
  databaseName: "postgres",
};
const app = createApp({
  db,
  config: cfg,
  authenticate: async (r) => {
    const user = r.headers.get("x-test-user");
    if (!user) throw new APIError(401, "Sign in");
    return { id: user, expires: Date.now() + 60_000 };
  },
});
const device = randomUUID(),
  expedition = randomUUID(),
  entry = randomUUID(),
  credential = "x".repeat(43);
const created = {
  version: 1,
  id: randomUUID(),
  date: 1000,
  event: "created",
  expedition: { id: expedition, date: 1000, title: "The Great Paper Trail" },
};
const note = {
  version: 1,
  id: randomUUID(),
  date: 1001,
  event: "entry",
  entry: {
    id: entry,
    date: 1001,
    kind: "response",
    text: "I found ",
    details: "",
  },
};
const delta = {
  version: 1,
  id: randomUUID(),
  date: 1002,
  event: "textAppended",
  entryID: entry,
  text: "a way.",
};
async function call(
  path: string,
  body?: unknown,
  user = "alice",
  native = false,
  method?: string,
) {
  return app.request("https://jol.example.test" + path, {
    method: method ?? (body === undefined ? "GET" : "POST"),
    headers: {
      "x-test-user": user,
      ...(native ? { "X-JOL-Device": credential } : {}),
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
before(async () => {
  await store.exec(await readFile("migrations/001_jol.sql", "utf8"));
});
after(async () => {
  await store.close();
});
test("discovery is public and contains no secret", async () => {
  const r = await app.request(
    "https://jol.example.test/.well-known/jerry-online",
  );
  assert.equal(r.status, 200);
  const body = await r.json();
  assert.equal(body.auth.resource, cfg.origin + "/api");
  assert.equal(body.version, 1);
  assert.ok(!JSON.stringify(body).includes(credential));
});
test("protected routes require sign-in and reject a foreign browser origin", async () => {
  assert.equal(
    (await app.request("https://jol.example.test/api/devices")).status,
    401,
  );
  assert.equal(
    (
      await app.request("https://jol.example.test/api/devices", {
        headers: { "x-test-user": "alice", Origin: "https://evil.test" },
      })
    ).status,
    403,
  );
});
test("enrollment is idempotent but another account cannot replace it", async () => {
  assert.equal(
    (await call("/api/devices", { id: device, name: "Test Mac", credential }))
      .status,
    200,
  );
  assert.equal(
    (await call("/api/devices", { id: device, name: "Test Mac", credential }))
      .status,
    200,
  );
  assert.equal(
    (
      await call(
        "/api/devices",
        { id: device, name: "Other Mac", credential },
        "bob",
      )
    ).status,
    404,
  );
  assert.equal(
    (
      await call("/api/devices", {
        id: device,
        name: "Test Mac",
        credential: "y".repeat(43),
      })
    ).status,
    409,
  );
});
const batches = `/api/devices/${device}/expeditions/${expedition}/batches`;
test("browser sessions cannot upload journals without Mac possession", async () => {
  assert.equal(
    (await call(batches, { start: 1, records: [created] })).status,
    403,
  );
  assert.equal(
    (await call(batches, { start: 1, records: [created] }, "bob", true)).status,
    404,
  );
});
test("gaps and incomplete creation are rejected without partial writes", async () => {
  assert.equal(
    (await call(batches, { start: 2, records: [created] }, "alice", true))
      .status,
    409,
  );
  assert.equal(
    (await call(batches, { start: 1, records: [note] }, "alice", true)).status,
    409,
  );
  assert.equal(
    (await db.query("SELECT * FROM jol_expeditions")).rows.length,
    0,
  );
});
test("ordered batches and retry after lost acknowledgement append text only once", async () => {
  const batch = { start: 1, records: [created, note, delta] };
  const first = await call(batches, batch, "alice", true);
  assert.equal(first.status, 200);
  assert.equal((await first.json()).cursor, 3);
  assert.equal((await call(batches, batch, "alice", true)).status, 200);
  const rows = (await db.query("SELECT text FROM jol_entries")).rows;
  assert.equal(rows[0].text, "I found a way.");
  assert.equal((await db.query("SELECT * FROM jol_events")).rows.length, 3);
});
test("conflicting accepted sequence or reused event ID cannot corrupt a journal", async () => {
  assert.equal(
    (
      await call(
        batches,
        { start: 3, records: [{ ...delta, text: "different" }] },
        "alice",
        true,
      )
    ).status,
    409,
  );
  assert.equal(
    (await call(batches, { start: 4, records: [delta] }, "alice", true)).status,
    409,
  );
  assert.equal(
    (await db.query("SELECT text FROM jol_entries")).rows[0].text,
    "I found a way.",
  );
});
test("a later gap rolls back the entire batch and keeps its cursor", async () => {
  assert.equal(
    (
      await call(
        batches,
        { start: 5, records: [{ ...delta, id: randomUUID() }] },
        "alice",
        true,
      )
    ).status,
    409,
  );
  assert.equal(
    (await db.query("SELECT cursor FROM jol_expeditions")).rows[0].cursor,
    3,
  );
});
test("text revisions, redacted details and title changes project correctly", async () => {
  const records = [
    {
      ...delta,
      id: randomUUID(),
      event: "textReplaced",
      text: "I crossed the paper cliffs.",
    },
    { version: 1, id: randomUUID(), date: 1003, event: "redacted" },
    {
      version: 1,
      id: randomUUID(),
      date: 1004,
      event: "titleChanged",
      text: "Paper Cliffs and Small Victories",
    },
  ];
  assert.equal(
    (await call(batches, { start: 4, records }, "alice", true)).status,
    200,
  );
  assert.equal(
    (await db.query("SELECT text,details FROM jol_entries")).rows[0].text,
    "I crossed the paper cliffs.",
  );
  assert.equal(
    (await db.query("SELECT details FROM jol_entries")).rows[0].details,
    "",
  );
  assert.equal(
    (await db.query("SELECT title FROM jol_expeditions")).rows[0].title,
    "Paper Cliffs and Small Victories",
  );
});
test("sharing redacted details is device-scoped, retry-safe and leaves the journal cursor alone", async () => {
  const path = batches.replace(/batches$/, "details");
  const redaction = (
    await db.query("SELECT payload FROM jol_events WHERE sequence=5")
  ).rows[0].payload;
  const changes = [
    {
      sequence: 2,
      id: note.id,
      date: note.date,
      event: "entry",
      entryID: entry,
      text: "First detail.",
    },
    {
      sequence: 5,
      id: redaction.id,
      date: redaction.date,
      event: "detailsAppended",
      entryID: entry,
      text: " Another detail.",
    },
  ];
  assert.equal(
    (await call(path, changes, "alice", false, "PATCH")).status,
    403,
  );
  assert.equal((await call(path, changes, "bob", true, "PATCH")).status, 404);
  for (let retry = 0; retry < 2; retry++) {
    assert.equal(
      (await call(path, changes, "alice", true, "PATCH")).status,
      200,
    );
  }
  assert.equal(
    (await call(batches, { start: 2, records: [note] }, "alice", true)).status,
    200,
  );
  assert.equal(
    (await call(batches, { start: 5, records: [redaction] }, "alice", true))
      .status,
    200,
  );
  assert.equal(
    (await db.query("SELECT details FROM jol_entries")).rows[0].details,
    "First detail. Another detail.",
  );
  assert.equal(
    (await db.query("SELECT cursor FROM jol_expeditions")).rows[0].cursor,
    6,
  );
});
test("private journal, assets and named queries cannot be read across accounts", async () => {
  assert.equal(
    (await (await call("/api/expeditions", undefined, "bob")).json()).length,
    0,
  );
  assert.equal(
    (
      await call(
        `/api/devices/${device}/expeditions/${expedition}/entries`,
        undefined,
        "bob",
      )
    ).status,
    404,
  );
  assert.equal(
    (await call(`/api/devices/${device}/commands`, undefined, "bob")).status,
    404,
  );
  assert.equal(
    (
      await call("/api/live", {
        kind: "anything",
        sql: "SELECT * FROM jol_entries",
      })
    ).status,
    503,
  );
});
const commandID = randomUUID();
test("remote commands start disabled and only the Mac can arm them", async () => {
  const command = {
    id: commandID,
    deviceID: device,
    kind: "continue",
    expeditionID: expedition,
    prompt: "Explore further",
  };
  assert.equal((await call("/api/commands", command)).status, 409);
  assert.equal(
    (await call(`/api/devices/${device}/heartbeat`, { remoteEnabled: true }))
      .status,
    403,
  );
  assert.equal(
    (
      await call(
        `/api/devices/${device}/heartbeat`,
        { remoteEnabled: true },
        "alice",
        true,
      )
    ).status,
    200,
  );
  assert.equal((await call("/api/commands", command)).status, 201);
  assert.equal((await call("/api/commands", command)).status, 200);
  assert.equal(
    (await call("/api/commands", { ...command, prompt: "replace" })).status,
    409,
  );
});
test("busy Macs leave routine prompts queued", async () => {
  const r = await call(
    `/api/devices/${device}/commands/claim`,
    { busy: true },
    "alice",
    true,
  );
  assert.equal((await r.json()).command, null);
});
let fence = 0;
test("claiming work increments a fence; stale acknowledgements are rejected", async () => {
  const r = await call(
    `/api/devices/${device}/commands/claim`,
    { busy: false },
    "alice",
    true,
  );
  const c = (await r.json()).command;
  assert.equal(c.id, commandID);
  fence = c.fence;
  assert.equal(c.status, "received");
  const ack = `/api/devices/${device}/commands/${commandID}/ack`;
  assert.equal(
    (await call(ack, { fence: fence + 1, status: "started" }, "alice", true))
      .status,
    409,
  );
  assert.equal(
    (await call(ack, { fence, status: "started" }, "alice", true)).status,
    200,
  );
});
test("a crash after starting never automatically requeues physical actions", async () => {
  await db.query(
    "UPDATE jol_commands SET lease_until=now()-interval '1 second' WHERE id=$1",
    [commandID],
  );
  assert.equal(
    (
      await (
        await call(
          `/api/devices/${device}/commands/claim`,
          { busy: false },
          "alice",
          true,
        )
      ).json()
    ).command,
    null,
  );
  assert.equal(
    (await db.query("SELECT status FROM jol_commands WHERE id=$1", [commandID]))
      .rows[0].status,
    "uncertain",
  );
});
test("stop targets a specific expedition and can pass the routine queue", async () => {
  assert.equal(
    (
      await call("/api/commands", {
        id: randomUUID(),
        deviceID: device,
        kind: "stop",
      })
    ).status,
    400,
  );
  const id = randomUUID();
  assert.equal(
    (
      await call("/api/commands", {
        id,
        deviceID: device,
        expeditionID: expedition,
        kind: "stop",
      })
    ).status,
    201,
  );
  const command = (
    await (
      await call(
        `/api/devices/${device}/commands/claim`,
        { busy: true },
        "alice",
        true,
      )
    ).json()
  ).command;
  assert.equal(command.id, id);
  await call(
    `/api/devices/${device}/commands/${id}/ack`,
    { fence: command.fence, status: "finished" },
    "alice",
    true,
  );
});
test("queued requests can be cancelled and expired work cannot be claimed", async () => {
  const id = randomUUID(),
    expired = randomUUID();
  for (const key of [id, expired])
    await call("/api/commands", {
      id: key,
      deviceID: device,
      kind: "start",
      prompt: "A small adventure",
    });
  assert.equal((await call(`/api/commands/${id}/cancel`, {})).status, 200);
  await db.query(
    "UPDATE jol_commands SET expires_at=now()-interval '1 second' WHERE id=$1",
    [expired],
  );
  assert.equal(
    (
      await (
        await call(
          `/api/devices/${device}/commands/claim`,
          { busy: false },
          "alice",
          true,
        )
      ).json()
    ).command,
    null,
  );
  assert.equal(
    (await db.query("SELECT status FROM jol_commands WHERE id=$1", [expired]))
      .rows[0].status,
    "expired",
  );
});
test("device revocation blocks its old connection and remote execution", async () => {
  assert.equal((await call(`/api/devices/${device}/revoke`, {})).status, 200);
  assert.equal(
    (
      await call(
        batches,
        { start: 7, records: [{ ...delta, id: randomUUID() }] },
        "alice",
        true,
      )
    ).status,
    404,
  );
  assert.equal(
    (
      await call(
        `/api/devices/${device}/commands/claim`,
        { busy: false },
        "alice",
        true,
      )
    ).status,
    404,
  );
});
