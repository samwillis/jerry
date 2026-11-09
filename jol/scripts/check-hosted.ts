// Explicit, opt-in integration checks against the dedicated development server.
// Uses only a synthetic account/notes/assets, never the Mac's journal or keys.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { randomUUID, randomBytes, createHash } from "node:crypto";
import { createAuthClient } from "@neon/auth";
import { createRealtimeClient } from "@neon/realtime/client";
import { realtimeCollectionOptions } from "@neon/realtime-tanstack";
import { createCollection } from "@tanstack/react-db";
import assert from "node:assert/strict";
const origin = process.env.JOL_ORIGIN!,
  issuer = process.env.NEON_AUTH_BASE_URL!,
  clientID = process.env.JOL_OAUTH_CLIENT_ID!;
assert.ok(origin?.startsWith("https://"));
assert.ok(issuer?.startsWith("https://"));
const fixtureFile = ".data/hosted-fixture.json";
await mkdir(".data", { recursive: true, mode: 0o700 });
let fixture: Record<string, any>;
try {
  fixture = JSON.parse(await readFile(fixtureFile, "utf8"));
  assert.equal(fixture.origin, origin);
} catch {
  const account = {
    email: `jol-fixture-${randomUUID()}@example.invalid`,
    password: randomBytes(32).toString("base64url"),
    name: "JOL integration fixture",
  };
  const r = await fetch(issuer + "/sign-up/email", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: origin },
    body: JSON.stringify(account),
  });
  assert.equal(r.status, 200, "fixture sign-up");
  fixture = {
    ...account,
    origin,
    cookies: r.headers
      .getSetCookie()
      .map((x) => x.split(";")[0])
      .join("; "),
  };
}
const signIn = await fetch(issuer + "/sign-in/email", {
  method: "POST",
  headers: { "Content-Type": "application/json", Origin: origin },
  body: JSON.stringify({ email: fixture.email, password: fixture.password }),
});
assert.equal(signIn.status, 200, "fixture sign-in");
fixture.cookies = signIn.headers
  .getSetCookie()
  .map((x) => x.split(";")[0])
  .join("; ");
const browserAuth = createAuthClient(issuer);
const sessionOptions = {
  fetchOptions: { headers: { Cookie: fixture.cookies, Origin: origin } },
};
for (const phase of ["restored", "cached"]) {
  const { data, error } = await browserAuth.getSession(sessionOptions);
  assert.ok(!error && data?.session?.token, `${phase} browser session JWT`);
  const me = await fetch(origin + "/api/me", {
    headers: { Authorization: "Bearer " + data.session.token },
  });
  assert.equal(me.status, 200, `${phase} browser session opens the journal`);
}
console.log("PASS hosted restored and cached browser session");
const verifier = randomBytes(32).toString("base64url"),
  state = randomBytes(32).toString("base64url"),
  redirect = "http://127.0.0.1:49381/jol/callback";
const params = new URLSearchParams({
  response_type: "code",
  client_id: clientID,
  redirect_uri: redirect,
  scope: "openid offline_access",
  state,
  code_challenge: createHash("sha256").update(verifier).digest("base64url"),
  code_challenge_method: "S256",
  resource: origin + "/api",
});
const browserEntry = await fetch(origin + "/authorize?" + params, {
  redirect: "manual",
});
assert.equal(
  browserEntry.status,
  302,
  "native browser entry must navigate, not display JSON",
);
const loginURL = new URL(browserEntry.headers.get("location")!);
assert.equal(loginURL.pathname, "/login");
console.log("PASS hosted browser authorization entry");
const authorization = await fetch(issuer + "/oauth2/continue", {
  method: "POST",
  headers: {
    Cookie: fixture.cookies,
    Origin: origin,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    selected: true,
    oauth_query: loginURL.search.slice(1),
  }),
  redirect: "manual",
});
assert.equal(authorization.status, 200, "hosted signed login continuation");
const consentURL =
  authorization.headers.get("location") ??
  ((await authorization.json()) as { url: string }).url;
let callback = new URL(consentURL);
if (callback.pathname !== "/jol/callback") {
  assert.equal(
    callback.pathname,
    "/consent",
    "signed-in fixture goes to consent",
  );
  const consent = await fetch(issuer + "/oauth2/consent", {
    method: "POST",
    headers: {
      Cookie: fixture.cookies,
      Origin: origin,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      accept: true,
      oauth_query: callback.search.slice(1),
    }),
  });
  assert.equal(consent.status, 200, "hosted consent");
  callback = new URL(((await consent.json()) as { url: string }).url);
}
assert.equal(callback.searchParams.get("state"), state);
const tokenRequest = await fetch(issuer + "/oauth2/token", {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientID,
    redirect_uri: redirect,
    code: callback.searchParams.get("code")!,
    code_verifier: verifier,
    resource: origin + "/api",
  }),
});
assert.equal(tokenRequest.status, 200, "PKCE exchange");
const tokens = (await tokenRequest.json()) as Record<string, any>;
assert.ok(tokens.refresh_token);
fixture.oauth = tokens;
await writeFile(fixtureFile, JSON.stringify(fixture), { mode: 0o600 });
console.log("PASS hosted PKCE and native resource token");
const device = randomUUID(),
  credential = randomBytes(32).toString("base64url"),
  exp = randomUUID(),
  entry = randomUUID(),
  photo = randomUUID() + ".jpg";
async function api(
  path: string,
  body?: unknown,
  native = false,
  method = body === undefined ? "GET" : "POST",
) {
  const r = await fetch(origin + "/api" + path, {
    method,
    headers: {
      Authorization: "Bearer " + tokens.access_token,
      ...(native ? { "X-JOL-Device": credential } : {}),
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.ok(r.ok, `${method} ${path}: ${r.status}`);
  return r.json();
}
const me = await api("/me");
assert.ok(
  me.id.endsWith(
    "|" +
      JSON.parse(
        Buffer.from(tokens.access_token.split(".")[1], "base64url").toString(),
      ).sub,
  ),
);
await api("/devices", {
  id: device,
  name: "Hosted integration fixture",
  credential,
});
await api(`/devices/${device}/heartbeat`, { remoteEnabled: true }, true);
const created = {
  version: 1,
  id: randomUUID(),
  date: Date.now(),
  event: "created",
  expedition: { id: exp, date: Date.now(), title: "The Hosted Paper Trail" },
};
const note = {
  version: 1,
  id: randomUUID(),
  date: Date.now(),
  event: "entry",
  entry: {
    id: entry,
    date: Date.now(),
    kind: "response",
    text: "A live field note",
    details: "",
    photo: photo.toUpperCase().replace(".JPG", ".jpg"),
  },
};
await api(
  `/devices/${device}/expeditions/${exp}/batches`,
  { start: 1, records: [created, note] },
  true,
);
console.log("PASS hosted Mac enrollment and journal upload");
const realtime = createRealtimeClient({ url: process.env.NEON_REALTIME_URL! });
const photoPath = `/devices/${device}/expeditions/${exp}/photos/${photo}`;
const image = await readFile(".data/fixture.jpg");
try {
  const sealed = await api("/live", {
    kind: "entries",
    deviceID: device,
    expeditionID: exp,
    after: 0,
  });
  type Note = {
    id: string;
    text: string;
    details: string;
    photo_ready: boolean;
  };
  const subscription = realtime.subscribe<Note>(sealed);
  const collection = createCollection(
    realtimeCollectionOptions<Note>({
      client: realtime,
      query: sealed,
      getKey: (row) => row.id,
    }),
  );
  await subscription.awaitRows(
    (rows) =>
      rows.some((r) => r.id === entry && r.text === "A live field note"),
    20_000,
  );
  await collection.preload();
  assert.equal(collection.get(entry)?.text, "A live field note");
  await api(
    `/devices/${device}/expeditions/${exp}/batches`,
    {
      start: 3,
      records: [
        {
          version: 1,
          id: randomUUID(),
          date: Date.now(),
          event: "textAppended",
          entryID: entry,
          text: " from the summit.",
        },
      ],
    },
    true,
  );
  await subscription.awaitRows(
    (rows) =>
      rows.some((r) => r.id === entry && r.text.endsWith("from the summit.")),
    20_000,
  );
  const detail = [
    {
      sequence: 2,
      id: note.id,
      date: note.date,
      event: "entry",
      entryID: entry,
      text: "Synthetic technical detail.",
    },
  ];
  await api(
    `/devices/${device}/expeditions/${exp}/details`,
    detail,
    true,
    "PATCH",
  );
  await subscription.awaitRows(
    (rows) => rows.some((r) => r.id === entry && r.details === detail[0].text),
    20_000,
  );
  const upload = await fetch(origin + "/api" + photoPath, {
    method: "PUT",
    headers: {
      Authorization: "Bearer " + tokens.access_token,
      "X-JOL-Device": credential,
      "Content-Type": "image/jpeg",
    },
    body: image,
  });
  assert.equal(upload.status, 200, "private photo upload");
  await subscription.awaitRows(
    (rows) => rows.some((r) => r.id === entry && r.photo_ready),
    20_000,
  );
  const published = await new Promise<Note>((resolve, reject) => {
    let listener: ReturnType<typeof collection.subscribeChanges>;
    const timer = setTimeout(() => {
      listener.unsubscribe();
      reject(new Error("TanStack DB did not receive the live photo update"));
    }, 10_000);
    const check = () => {
      const row = collection.get(entry);
      if (row?.photo_ready) {
        clearTimeout(timer);
        listener.unsubscribe();
        resolve(row);
      }
    };
    listener = collection.subscribeChanges(check);
    check();
  });
  assert.equal(published.details, detail[0].text);
  await collection.cleanup();
  subscription.unsubscribe();
  console.log(
    "PASS hosted Neon Realtime and TanStack DB journal, detail and photo changes",
  );
} finally {
  realtime.close();
}
const commandID = randomUUID();
const stream = await fetch(origin + `/api/devices/${device}/events`, {
  signal: AbortSignal.timeout(30_000),
  headers: {
    Authorization: "Bearer " + tokens.access_token,
    "X-JOL-Device": credential,
  },
});
assert.equal(stream.status, 200);
const reader = stream.body!.getReader();
const decoder = new TextDecoder();
let events = "";
async function waitForEvent(name: string) {
  const marker = `event: ${name}\n`;
  while (!events.includes(marker)) {
    const chunk = await reader.read();
    assert.ok(!chunk.done, `stream closed before ${name}`);
    events += decoder.decode(chunk.value, { stream: true });
  }
  events = events.slice(events.indexOf(marker) + marker.length);
}
await waitForEvent("live");
await api("/commands", {
  id: commandID,
  deviceID: device,
  expeditionID: exp,
  kind: "continue",
  prompt: "Write another synthetic field note",
});
await waitForEvent("commands_changed");
await reader.cancel();
console.log("PASS hosted Neon Realtime wakes the native command stream");
assert.equal(
  (await api(`/devices/${device}/commands/claim`, { busy: true }, true))
    .command,
  null,
);
const command = (
  await api(`/devices/${device}/commands/claim`, { busy: false }, true)
).command;
assert.equal(command.id, commandID);
await api(
  `/devices/${device}/commands/${commandID}/ack`,
  { fence: command.fence, status: "started" },
  true,
);
await api(
  `/devices/${device}/commands/${commandID}/ack`,
  {
    fence: command.fence,
    status: "finished",
    result: "Synthetic command acknowledged; no computer input was performed",
  },
  true,
);
assert.equal((await api(`/devices/${device}/commands`))[0].status, "finished");
console.log("PASS hosted durable command delivery and acknowledgement");
const download = await fetch(origin + "/api" + photoPath, {
  headers: { Authorization: "Bearer " + tokens.access_token },
});
assert.equal(download.status, 200);
assert.deepEqual(Buffer.from(await download.arrayBuffer()), image);
console.log("PASS hosted private photograph round trip");
const refresh = await fetch(issuer + "/oauth2/token", {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "refresh_token",
    client_id: clientID,
    refresh_token: tokens.refresh_token,
    resource: origin + "/api",
  }),
});
assert.equal(refresh.status, 200);
fixture.oauth = await refresh.json();
await writeFile(fixtureFile, JSON.stringify(fixture), { mode: 0o600 });
console.log("PASS hosted rotating refresh token");
await api(`/devices/${device}/revoke`, {});
// This is a one-shot probe. The managed SDK/HTTP pool can retain background
// handles after close; all writes and device revocation are acknowledged above.
process.stdout.write(
  "Hosted checks complete. Only synthetic fixture records were written.\n",
  () => process.exit(0),
);
