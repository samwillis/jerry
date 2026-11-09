// Disposable local visual fixture. Never imported by the deployed entry point.
import { PGlite } from "@electric-sql/pglite";
import { serve } from "@hono/node-server";
import { loadWebAssets } from "./web-assets.js";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { createApp } from "../src/app.js";
import { ingest, type Database } from "../src/database.js";
import { recordSchema } from "../src/protocol.js";
const pg = new PGlite();
await pg.exec(await readFile("migrations/001_jol.sql", "utf8"));
const db: Database = {
  query: (s, v) => pg.query(s, v),
  transaction: (f) =>
    pg.transaction((q) => f({ query: (s, v) => q.query(s, v) })),
};
const device = randomUUID(),
  exp = randomUUID(),
  photo = randomUUID() + ".jpg",
  authURL = "https://fixture.example/neondb/auth";
await db.query(
  "INSERT INTO jol_devices(id,owner_id,name,credential_hash,remote_enabled,last_seen) VALUES($1,$2,'My Mac','fixture',true,now())",
  [device, authURL + "|preview-user"],
);
const make = (event: string, rest: object) =>
  recordSchema.parse({
    version: 1,
    id: randomUUID(),
    date: Date.now(),
    event,
    ...rest,
  });
await ingest(db, device, exp, 1, [
  make("created", {
    expedition: {
      id: exp,
      date: Date.now(),
      title: "The Paper Cliffs of Possibility",
    },
  }),
  make("entry", {
    entry: {
      id: randomUUID(),
      date: Date.now(),
      kind: "request",
      text: "Open a new document and write a small poem about your adventure.",
      details: "",
    },
  }),
  make("entry", {
    entry: {
      id: randomUUID(),
      date: Date.now(),
      kind: "response",
      text: "I found the document window tucked beneath a rather impressive toolbar. A short climb, a careful landing, and I’m ready to put pen to paper.",
      details:
        "Observed the active document window. The next physical action is to reach its text area.",
    },
  }),
  make("entry", {
    entry: {
      id: randomUUID(),
      date: Date.now(),
      kind: "activity",
      text: "One explorer. A whole desktop of possibility.",
      details: "Synthetic visual fixture; no screen was captured.",
      photo,
    },
  }),
  make("entry", {
    entry: {
      id: randomUUID(),
      date: Date.now(),
      kind: "response",
      text: "The poem is safely on the page. I shall keep this photograph as proof that even a small explorer can get a little writing done.",
      details: "",
    },
  }),
  make("state", {
    status: "Ready for your next direction",
    isRunning: false,
    isFinished: false,
  }),
]);
await db.query(
  "INSERT INTO jol_assets(device_id,expedition_id,filename,object_key) VALUES($1,$2,$3,'fixture-photo')",
  [device, exp, photo],
);
const assets = await loadWebAssets("dist/web-fixture/client");
const image = await readFile("../Jerry/Resources/AppIcon.png");
const app = createApp({
  db,
  config: {
    origin: "http://127.0.0.1:8788",
    instanceID: randomUUID(),
    name: "JOL preview",
    authURL,
    jwksURL: authURL + "/jwks",
    clientID: "fixture",
    databaseName: "postgres",
  },
  authenticate: async () => ({
    id: authURL + "|preview-user",
    expires: Date.now() + 60_000,
  }),
  assets,
});
serve(
  {
    hostname: "127.0.0.1",
    port: 8788,
    fetch: (request) =>
      new URL(request.url).pathname.includes("/photos/")
        ? new Response(image, { headers: { "Content-Type": "image/png" } })
        : app.fetch(request),
  },
  () => console.log("Disposable JOL preview: http://127.0.0.1:8788"),
);
