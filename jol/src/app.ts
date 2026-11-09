import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { secureHeaders } from "hono/secure-headers";
import { streamSSE } from "hono/streaming";
import { z } from "zod";
import { createHash, timingSafeEqual } from "node:crypto";
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import {
  APIError,
  batchSchema,
  detailChangeSchema,
  commandSchema,
  uuid,
  digest,
} from "./protocol.js";
import { ingest, claim, shareDetails, type Database } from "./database.js";
import type { Config } from "./config.js";
import type { Authenticate, Identity } from "./auth.js";
import {
  liveQueries,
  devicesQuery,
  entriesQuery,
  expeditionsQuery,
  expeditionQuery,
  entryColumns,
  entryAssetsJoin,
  commandsQuery,
  commandInboxQuery,
} from "./live.js";

type Dependencies = {
  db: Database;
  config: Config;
  authenticate: Authenticate;
  assets?: Record<string, { body: Uint8Array; type: string }>;
};
export function createApp({
  db,
  config,
  authenticate,
  assets = {},
}: Dependencies) {
  const app = new Hono<{ Variables: { identity: Identity } }>();
  const live = liveQueries(config);
  // Start's prerendered shell carries static hydration scripts.
  const shell = assets["/"]?.body;
  const scripts = shell
    ? [
        ...new TextDecoder()
          .decode(shell)
          .matchAll(/<script\b[^>]*>([^]*?)<\/script>/g),
      ]
        .map((match) => match[1])
        .filter(Boolean)
        .map(
          (script) =>
            "'sha256-" +
            createHash("sha256").update(script).digest("base64") +
            "'",
        )
    : [];
  const s3 = config.photoBucket
    ? new S3Client({
        forcePathStyle: true,
        endpoint: process.env.AWS_ENDPOINT_URL_S3,
      })
    : undefined;
  app.use(
    "*",
    secureHeaders({
      contentSecurityPolicy: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", ...scripts],
        styleSrc: ["'self'"],
        fontSrc: ["'self'"],
        imgSrc: ["'self'", "blob:"],
        connectSrc: [
          "'self'",
          new URL(config.authURL).origin,
          ...(config.realtimeURL
            ? [
                new URL(config.realtimeURL).origin,
                new URL(config.realtimeURL).origin.replace(/^https:/, "wss:"),
              ]
            : []),
        ],
        frameSrc: [new URL(config.authURL).origin],
        objectSrc: ["'none'"],
        baseUri: ["'none'"],
        frameAncestors: ["'none'"],
      },
      crossOriginResourcePolicy: "same-origin",
      crossOriginOpenerPolicy: "same-origin-allow-popups",
    }),
  );
  app.onError((e, c) => {
    if (e instanceof APIError)
      return c.json({ error: e.message }, e.status as 400);
    if (e instanceof z.ZodError)
      return c.json(
        {
          error: "Invalid request",
          issues: e.issues.map((i) => ({ path: i.path, message: i.message })),
        },
        400,
      );
    console.error(
      "JOL request failed",
      e instanceof Error ? e.name : "unknown",
    );
    return c.json({ error: "JOL could not complete this request" }, 500);
  });
  app.get("/.well-known/jerry-online", (c) =>
    c.json({
      version: 1,
      instanceID: config.instanceID,
      name: config.name,
      origin: config.origin,
      auth: {
        issuer: config.authURL,
        clientID: config.clientID,
        resource: `${config.origin}/api`,
        redirectURI: "http://127.0.0.1:49381/jol/callback",
      },
      capabilities: {
        journal: true,
        commands: true,
        photos: !!s3,
        realtime: !!live,
        detailsBackfill: true,
      },
      realtimeURL: config.realtimeURL ?? null,
    }),
  );
  app.get("/health", (c) => c.json({ ok: true, protocol: 1 }));
  // Managed Auth currently returns a JSON redirect even for a browser authorize
  // request. Turn that response into navigation without proxying session cookies.
  app.get("/authorize", async (c) => {
    const query = z
      .object({
        response_type: z.literal("code"),
        client_id: z.literal(config.clientID),
        redirect_uri: z.literal("http://127.0.0.1:49381/jol/callback"),
        resource: z.literal(config.origin + "/api"),
        scope: z.literal("openid offline_access"),
        state: z.string().min(32).max(128),
        code_challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        code_challenge_method: z.literal("S256"),
      })
      .parse(c.req.query());
    const upstream = await fetch(
      config.authURL + "/oauth2/authorize?" + new URLSearchParams(query),
      { redirect: "manual", headers: { Accept: "application/json" } },
    );
    let target = upstream.headers.get("location");
    if (!target) {
      const result = (await upstream.json()) as { url?: string };
      target = result.url ?? null;
    }
    if (!target)
      throw new APIError(
        502,
        "The sign-in service did not return a destination",
      );
    const url = new URL(target);
    if (
      url.origin !== config.origin ||
      !["/login", "/consent"].includes(url.pathname)
    )
      throw new APIError(
        502,
        "The sign-in service returned an unexpected destination",
      );
    c.header("Cache-Control", "no-store");
    return c.redirect(url.href, 302);
  });
  app.use("/api/*", async (c, next) => {
    c.header("Cache-Control", "no-store");
    const origin = c.req.header("Origin");
    if (origin && origin !== config.origin)
      throw new APIError(403, "This origin is not allowed");
    const identity = await authenticate(c.req.raw);
    if (
      c.req.header("X-JOL-Expected-User") &&
      c.req.header("X-JOL-Expected-User") !== identity.id
    )
      throw new APIError(409, "Account changed; reload JOL");
    c.set("identity", identity);
    await next();
  });
  app.use(
    "/api/*",
    bodyLimit({
      maxSize: 4 * 1024 * 1024,
      onError: (c) => c.json({ error: "Request too large" }, 413),
    }),
  );
  const owner = async (id: string, user: string) => {
    const d = (
      await db.query("SELECT * FROM jol_devices WHERE id=$1 AND owner_id=$2", [
        id,
        user,
      ])
    ).rows[0];
    if (!d) throw new APIError(404, "Mac not found");
    return d;
  };
  const device = async (id: string, user: string, request: Request) => {
    const d = await owner(id, user);
    if (d.revoked) throw new APIError(404, "Mac disconnected");
    const supplied = digest(request.headers.get("X-JOL-Device") ?? "");
    if (!timingSafeEqual(Buffer.from(supplied), Buffer.from(d.credential_hash)))
      throw new APIError(403, "This connection is not the enrolled Mac");
    return d;
  };
  app.get("/api/me", (c) =>
    c.json({ id: c.get("identity").id, instanceID: config.instanceID }),
  );
  app.post("/api/devices", async (c) => {
    const { id, name, credential } = z
      .object({
        id: uuid,
        name: z.string().trim().min(1).max(80),
        credential: z.string().min(40).max(100),
      })
      .parse(await c.req.json());
    const who = c.get("identity").id,
      hash = digest(credential);
    // Retry enrollment with the same device credential; never rotate on an arbitrary browser request.
    const d = (
      await db.query(
        "INSERT INTO jol_devices(id,owner_id,name,credential_hash) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO NOTHING RETURNING id",
        [id, who, name, hash],
      )
    ).rows[0];
    if (!d) {
      const prior = await owner(id, who);
      if (prior.credential_hash !== hash)
        throw new APIError(409, "Mac is already enrolled");
    }
    return c.json({ id });
  });
  app.get("/api/devices", async (c) =>
    c.json(
      (
        await db.query(
          "SELECT id,name,remote_enabled,last_seen FROM jol_devices WHERE owner_id=$1 ORDER BY created_at",
          [c.get("identity").id],
        )
      ).rows,
    ),
  );
  app.post("/api/devices/:device/heartbeat", async (c) => {
    const id = uuid.parse(c.req.param("device"));
    await device(id, c.get("identity").id, c.req.raw);
    const { remoteEnabled } = z
      .object({ remoteEnabled: z.boolean() })
      .parse(await c.req.json());
    await db.query(
      "UPDATE jol_devices SET last_seen=now(),remote_enabled=$2 WHERE id=$1",
      [id, remoteEnabled],
    );
    return c.json({ ok: true });
  });
  app.post("/api/devices/:device/revoke", async (c) => {
    const id = uuid.parse(c.req.param("device"));
    await owner(id, c.get("identity").id);
    await db.transaction(async (q) => {
      await q.query(
        "UPDATE jol_devices SET revoked=true,remote_enabled=false WHERE id=$1",
        [id],
      );
      await q.query(
        "UPDATE jol_commands SET status='cancelled',result='Mac disconnected' WHERE device_id=$1 AND status IN ('queued','received')",
        [id],
      );
    });
    return c.json({ ok: true });
  });
  app.patch(
    "/api/devices/:device/expeditions/:expedition/details",
    async (c) => {
      const d = uuid.parse(c.req.param("device")),
        e = uuid.parse(c.req.param("expedition"));
      await device(d, c.get("identity").id, c.req.raw);
      const changes = z
        .array(detailChangeSchema)
        .min(1)
        .max(100)
        .parse(await c.req.json());
      await shareDetails(db, d, e, changes);
      return c.json({ ok: true });
    },
  );
  app.post(
    "/api/devices/:device/expeditions/:expedition/batches",
    async (c) => {
      const d = uuid.parse(c.req.param("device")),
        e = uuid.parse(c.req.param("expedition"));
      await device(d, c.get("identity").id, c.req.raw);
      const batch = batchSchema.parse(await c.req.json());
      const cursor = await ingest(db, d, e, batch.start, batch.records);
      return c.json({ cursor });
    },
  );
  app.get("/api/expeditions", async (c) => {
    const before = c.req.query("before");
    const params: unknown[] = [c.get("identity").id];
    if (before) {
      params.push(
        z.iso.datetime({ offset: true }).parse(before),
        uuid.parse(c.req.query("device")),
        uuid.parse(c.req.query("expedition")),
      );
    }
    return c.json(
      (
        await db.query(
          `SELECT e.* FROM jol_expeditions e JOIN jol_devices d ON d.id=e.device_id
            WHERE d.owner_id=$1 ${before ? "AND (e.created_at,e.device_id,e.id)<($2::timestamptz,$3::uuid,$4::uuid)" : ""}
            ORDER BY e.created_at DESC,e.device_id DESC,e.id DESC LIMIT 100`,
          params,
        )
      ).rows,
    );
  });
  app.get("/api/devices/:device/expeditions/:expedition", async (c) => {
    const d = uuid.parse(c.req.param("device")),
      e = uuid.parse(c.req.param("expedition"));
    await owner(d, c.get("identity").id);
    return c.json(
      (
        await db.query(
          "SELECT * FROM jol_expeditions WHERE device_id=$1 AND id=$2",
          [d, e],
        )
      ).rows,
    );
  });
  app.get("/api/devices/:device/expeditions/:expedition/entries", async (c) => {
    const d = uuid.parse(c.req.param("device")),
      e = uuid.parse(c.req.param("expedition"));
    await owner(d, c.get("identity").id);
    const before = z.coerce
      .number()
      .int()
      .min(1)
      .parse(c.req.query("before") ?? 2147483647);
    return c.json(
      (
        await db.query(
          `SELECT ${entryColumns} FROM jol_entries e ${entryAssetsJoin} WHERE e.device_id=$1 AND e.expedition_id=$2 AND e.position<$3 ORDER BY e.position DESC LIMIT 200`,
          [d, e, before],
        )
      ).rows.reverse(),
    );
  });
  app.post("/api/live", async (c) => {
    if (!live) throw new APIError(503, "Live updates are not configured");
    const x = z
      .object({
        kind: z.enum([
          "devices",
          "expeditions",
          "expedition",
          "entries",
          "commands",
        ]),
        deviceID: uuid.optional(),
        expeditionID: uuid.optional(),
        after: z.number().int().min(0).default(0),
      })
      .parse(await c.req.json());
    const user = c.get("identity").id;
    if (x.deviceID) await owner(x.deviceID, user);
    const query =
      x.kind === "devices"
        ? devicesQuery(user)
        : x.kind === "expeditions"
          ? expeditionsQuery(user)
          : x.kind === "commands" && x.deviceID
            ? commandsQuery(user, x.deviceID)
            : x.kind === "entries" && x.deviceID && x.expeditionID
              ? entriesQuery(user, x.deviceID, x.expeditionID, x.after)
              : x.kind === "expedition" && x.deviceID && x.expeditionID
                ? expeditionQuery(user, x.deviceID, x.expeditionID)
                : undefined;
    if (!query) throw new APIError(400, "Choose a Mac and expedition");
    return c.json(await live.seal({ query }));
  });
  app.post("/api/commands", async (c) => {
    const x = commandSchema.parse(await c.req.json()),
      who = c.get("identity").id;
    await owner(x.deviceID, who);
    const accepted = await db.transaction(async (q) => {
      const current = (
        await q.query(
          "SELECT remote_enabled,revoked FROM jol_devices WHERE id=$1 AND owner_id=$2 FOR UPDATE",
          [x.deviceID, who],
        )
      ).rows[0];
      const prior = (
        await q.query("SELECT * FROM jol_commands WHERE id=$1", [x.id])
      ).rows[0];
      if (prior) {
        if (
          prior.owner_id !== who ||
          prior.device_id !== x.deviceID ||
          prior.kind !== x.kind ||
          prior.prompt !== x.prompt ||
          prior.expedition_id !== (x.expeditionID ?? null)
        )
          throw new APIError(409, "Conflicting command ID");
        return { command: prior, created: false };
      }
      if (!current?.remote_enabled || current.revoked)
        throw new APIError(409, "Enable remote missions on this Mac first");
      if (x.expeditionID) {
        const e = (
          await q.query(
            "SELECT is_finished FROM jol_expeditions WHERE device_id=$1 AND id=$2",
            [x.deviceID, x.expeditionID],
          )
        ).rows[0];
        if (!e || (e.is_finished && x.kind === "continue"))
          throw new APIError(409, "Choose an unfinished expedition");
      }
      if (x.kind === "stop")
        await q.query(
          "UPDATE jol_commands SET status='cancelled',result='Superseded by your stop request' WHERE device_id=$1 AND expedition_id=$2 AND kind='continue' AND status='queued'",
          [x.deviceID, x.expeditionID],
        );
      const outstanding = (
        await q.query(
          "SELECT count(*)::int AS count FROM jol_commands WHERE device_id=$1 AND status IN ('queued','received','started')",
          [x.deviceID],
        )
      ).rows[0].count;
      if (outstanding >= 50)
        throw new APIError(
          429,
          "This Mac already has too many waiting directions",
        );
      const command = (
        await q.query(
          "INSERT INTO jol_commands(id,owner_id,device_id,expedition_id,kind,prompt,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *",
          [
            x.id,
            who,
            x.deviceID,
            x.expeditionID ?? null,
            x.kind,
            x.prompt,
            new Date(Date.now() + x.ttlMinutes * 60_000),
          ],
        )
      ).rows[0];
      return { command, created: true };
    });
    return c.json(accepted.command, accepted.created ? 201 : 200);
  });
  app.get("/api/devices/:device/commands", async (c) => {
    const d = uuid.parse(c.req.param("device"));
    await owner(d, c.get("identity").id);
    return c.json(
      (
        await db.query(
          "SELECT id,kind,prompt,status,result,expedition_id,created_at,expires_at FROM jol_commands WHERE device_id=$1 ORDER BY created_at DESC LIMIT 50",
          [d],
        )
      ).rows,
    );
  });
  app.post("/api/commands/:id/cancel", async (c) => {
    const id = uuid.parse(c.req.param("id"));
    const result = await db.query(
      "UPDATE jol_commands SET status='cancelled' WHERE id=$1 AND owner_id=$2 AND status='queued' RETURNING id",
      [id, c.get("identity").id],
    );
    if (!result.rows.length)
      throw new APIError(409, "This direction is no longer queued");
    return c.json({ ok: true });
  });
  app.post("/api/devices/:device/commands/claim", async (c) => {
    const d = uuid.parse(c.req.param("device"));
    await device(d, c.get("identity").id, c.req.raw);
    const { busy } = z.object({ busy: z.boolean() }).parse(await c.req.json());
    return c.json({ command: await claim(db, d, c.get("identity").id, busy) });
  });
  app.post("/api/devices/:device/commands/:id/ack", async (c) => {
    const d = uuid.parse(c.req.param("device")),
      id = uuid.parse(c.req.param("id"));
    await device(d, c.get("identity").id, c.req.raw);
    const x = z
      .object({
        fence: z.number().int().min(1),
        status: z.enum(["started", "finished", "failed", "uncertain"]),
        result: z.string().max(1000).default(""),
      })
      .parse(await c.req.json());
    const result = await db.query(
      `UPDATE jol_commands SET status=$4,result=$5,lease_until=now()+interval '90 seconds' WHERE device_id=$1 AND id=$2 AND fence=$3 AND (($4='started' AND lease_until>now() AND status IN ('received','started')) OR ($4<>'started' AND status IN ('received','started','uncertain',$4))) RETURNING id`,
      [d, id, x.fence, x.status, x.result],
    );
    if (!result.rows.length)
      throw new APIError(
        409,
        "Command lease changed; do not repeat the action",
      );
    return c.json({ ok: true });
  });
  app.get("/api/devices/:device/events", async (c) => {
    const d = uuid.parse(c.req.param("device")),
      user = c.get("identity");
    await device(d, user.id, c.req.raw);
    if (!live) throw new APIError(503, "Live directions are unavailable");
    const subscribe = () => live.subscribe(commandInboxQuery(user.id, d));
    return streamSSE(c, async (stream) => {
      let closed = false;
      let subscription: Awaited<ReturnType<typeof subscribe>> | undefined;
      stream.onAbort(() => {
        closed = true;
        subscription?.unsubscribe();
      });
      try {
        subscription = await subscribe();
        if (closed) return;
        await subscription.awaitRows(() => true, 10_000);
        if (closed) return;
        subscription.onChange(() => {
          void stream
            .writeSSE({ event: "commands_changed", data: "{}" })
            .catch(() => {
              closed = true;
            });
        });
        subscription.onStateChange((s) => {
          if (s.status === "error" || s.status === "stale") closed = true;
        });
        await stream.writeSSE({ event: "connected", data: "{}" });
        await stream.writeSSE({ event: "live", data: "{}" });
        const deadline = Math.min(user.expires - 5000, Date.now() + 40_000);
        while (!closed && Date.now() < deadline) {
          await stream.sleep(10_000);
          if (closed || Date.now() >= deadline) break;
          const current = (
            await db.query("SELECT revoked FROM jol_devices WHERE id=$1", [d])
          ).rows[0];
          if (!current || current.revoked) break;
          await stream.writeSSE({ event: "heartbeat", data: "{}" });
        }
      } catch {
        // The Mac reconciles the durable queue while the stream reconnects.
      } finally {
        subscription?.unsubscribe();
      }
    });
  });
  app.put(
    "/api/devices/:device/expeditions/:expedition/photos/:filename",
    async (c) => {
      if (!s3) throw new APIError(503, "Photo sharing is unavailable");
      const d = uuid.parse(c.req.param("device")),
        e = uuid.parse(c.req.param("expedition")),
        filename = z
          .string()
          .regex(/^[a-f0-9-]{36}\.jpg$/i)
          .parse(c.req.param("filename"))
          .toLowerCase();
      await device(d, c.get("identity").id, c.req.raw);
      if (
        !(
          await db.query(
            "SELECT id FROM jol_expeditions WHERE device_id=$1 AND id=$2",
            [d, e],
          )
        ).rows.length
      )
        throw new APIError(404, "Expedition not found");
      const body = new Uint8Array(await c.req.arrayBuffer());
      if (
        body.length > 4_000_000 ||
        body.length < 3 ||
        body[0] !== 255 ||
        body[1] !== 216 ||
        body[2] !== 255
      )
        throw new APIError(400, "Expected a JPEG photograph up to 4 MB");
      const key = `${config.instanceID}/${d}/${e}/${filename}`;
      await s3.send(
        new PutObjectCommand({
          Bucket: config.photoBucket,
          Key: key,
          Body: body,
          ContentType: "image/jpeg",
          CacheControl: "private, no-store",
        }),
      );
      await db.query(
        "INSERT INTO jol_assets(device_id,expedition_id,filename,object_key) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING",
        [d, e, filename, key],
      );
      return c.json({ ok: true });
    },
  );
  app.get(
    "/api/devices/:device/expeditions/:expedition/photos/:filename",
    async (c) => {
      if (!s3) throw new APIError(503, "Photos unavailable");
      const d = uuid.parse(c.req.param("device")),
        e = uuid.parse(c.req.param("expedition"));
      await owner(d, c.get("identity").id);
      const a = (
        await db.query(
          "SELECT object_key FROM jol_assets WHERE device_id=$1 AND expedition_id=$2 AND filename=$3",
          [d, e, c.req.param("filename").toLowerCase()],
        )
      ).rows[0];
      if (!a) throw new APIError(404, "This photo has not arrived yet");
      const image = await s3.send(
        new GetObjectCommand({ Bucket: config.photoBucket, Key: a.object_key }),
      );
      const bytes = await image.Body!.transformToByteArray();
      const exact = new Uint8Array(bytes.byteLength);
      exact.set(bytes);
      return c.body(exact.buffer, 200, {
        "Content-Type": "image/jpeg",
        "Cache-Control": "private, no-store",
      });
    },
  );
  for (const [path, asset] of Object.entries(assets))
    app.get(path, (c) =>
      c.body(asset.body as any, 200, {
        "Content-Type": asset.type,
        "Cache-Control": path.startsWith("/assets/")
          ? "public, max-age=31536000, immutable"
          : "no-cache",
      }),
    );
  app.get("/public-config", (c) =>
    c.json({
      authURL: config.authURL,
      origin: config.origin,
      realtimeURL: config.realtimeURL ?? null,
      name: config.name,
    }),
  );
  app.notFound((c) => c.json({ error: "Not found" }, 404));
  return app;
}
