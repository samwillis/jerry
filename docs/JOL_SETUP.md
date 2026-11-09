# Jerry On Line setup

Jerry On Line is optional. Without a connection Jerry keeps working and saving journals on the Mac. JOL adds a private web journal and remote directions; it never receives your AI credentials or executes computer actions on the server.

## Current implementation

The first version includes:

- A **Jerry On Line** page in native Settings, server discovery and browser-based Neon Auth sign-in with PKCE. JOL credentials and Mac enrollment credentials stay in Keychain.
- Ordered, retryable journal uploads from the local writer’s committed records. Notes are shared for expeditions created after connecting; existing history, technical details and photographs are separate opt-ins.
- A responsive notebook web journal based on the desktop layout, with Caveat, taped directions and Details, signed notes, and Polaroids. TanStack Start builds the browser shell and Base UI supplies the controls. The Function serves the shell and hashed assets from the same origin as the API.
- Neon Realtime feeds TanStack DB collections over one browser WebSocket. On the Mac, an authenticated SSE stream relays changes from a Neon Realtime command inbox. Both clients can recover through ordinary API reads when live updates are unavailable.
- Durable remote **new expedition**, **continue**, **finish**, **stop** and **cancel queued direction** commands. Normal directions queue while busy. Live interruption/steering is not implemented; Stop followed by a fresh direction is the current path.
- Device possession checks, owner isolation, command leases/fences, durable accepted-command IDs and completion receipts. An ambiguous interrupted command does not automatically repeat physical actions.

Remote missions start disabled after every app launch. Enable **Allow remote missions** on the Mac when ready. Taking manual control or opening the local task prompt pauses remote operation; re-enable it explicitly afterwards. Losing an execution lease stops the remote task. A disconnected server never blocks local journal writing.

This is an owner-only prototype, not a production service. Reader/controller invitations, account/cloud deletion and retention controls, quotas for a public service and cross-device expedition handoff remain future work. Disconnecting disables that Mac’s server connection but preserves its cloud journals for its owner. Native local files remain unchanged.

## Local development and checks

Run backend commands inside `jol/` with Node.js 22.12 or later:

```sh
npm ci
npm run check
npm test
npm run build
```

Tests run actual Postgres semantics in a disposable in-memory PGlite instance; no Neon project, credentials or real journal data are used. Auth tests verify signed JWTs against a temporary JWKS server, including wrong-branch tokens signed with the same key. They do not substitute for testing the real hosted login and Realtime services.

For an isolated visual sample:

```sh
npm run preview
```

Open `http://127.0.0.1:8788`. The preview binds only to loopback and contains synthetic notes and Jerry’s app artwork, with a fixture-only auth adapter. It is not imported into the production entry point, performs no computer actions and reads no real journals or credentials. Its commands remain inside the disposable database.

For the native page, build the Debug app and run its executable with `--jol-preview`. This opens Settings with persistence and JOL startup disabled. Native/agent checks use temporary sync directories; never point fixtures at the real Application Support directory.

## Deploy your own Neon instance

Use a dedicated development project first. Functions, Storage and Realtime must all be available in its region. The researched overlap was Ohio, N. Virginia, Frankfurt and Singapore; check current [product availability](https://neon.com/docs/introduction/regions#product-availability).

1. Sign in to the Neon CLI yourself if needed, choose/create the project, and create an isolated development branch in the Console. A Neon platform account is for the operator; JOL’s ordinary users sign in through Neon Auth instead.

2. From `jol/`, link that existing branch without overwriting environment variables:

   ```sh
   npx neon link --project-id YOUR_PROJECT_ID --branch YOUR_BRANCH --no-env-pull -y
   cp .env.example .env.local
   ```

   Set `JOL_ORIGIN` to your intended HTTPS origin and `JOL_INSTANCE_ID` to a fresh UUID. Keep that UUID stable for the deployment. Do not copy it into an independently operated instance or enable remote execution in a preview cloned from production.

3. Provision the initial services before creating the OAuth client:

   ```sh
   npx neon deploy --config neon.bootstrap.ts --env .env.local
   ```

   Enabling Realtime enables logical replication project-wide and can restart existing computes. Use the dedicated project rather than surprising another application sharing a project. The deploy pulls Neon-managed connection variables into the gitignored environment file.

4. In that branch’s **Neon Auth** configuration:

   - Enable email/password sign-in and configure verification/email delivery as appropriate. Each account sees only its own Macs and journals; signing up does not make a user an instance administrator.
   - Add the exact JOL origin as a trusted domain.
   - Enable the **OAuth Provider** plugin, with login URL `https://YOUR_JOL_HOST/login`, consent URL `https://YOUR_JOL_HOST/consent` and protected resource `https://YOUR_JOL_HOST/api`.
   - Enable localhost access: the current registered native client uses a loopback callback, including on a deployed server. This is intentional for native authorization and is separate from adding arbitrary web origins.
   - Create a **public** managed OAuth client named **Jerry**, with redirect URI `http://127.0.0.1:49381/jol/callback`, linked to the API resource above. Keep consent enabled. Do not enable dynamic client registration or configure an MCP resource for this application.
   - Put that public client ID in `JOL_OAUTH_CLIENT_ID` in `.env.local`. No client secret belongs in the Mac app.

   Follow the current [Neon OAuth Provider guide](https://neon.com/docs/auth/guides/plugins/oauth-provider). Registered clients currently reject custom callback schemes; changing Jerry’s callback requires changing both server discovery and the native implementation. Production email may need an operator SMTP configuration: see [Auth production setup](https://neon.com/docs/auth/production-checklist).

5. Confirm the `.env.local` Neon variables refer to this branch: `DATABASE_URL`, `NEON_AUTH_BASE_URL`, `NEON_AUTH_JWKS_URL`, `NEON_REALTIME_URL`, `NEON_REALTIME_SECRET`. Never print or commit their values. Then:

   ```sh
   npm run migrate
   npm run build
   npx neon deploy --env .env.local
   ```

   `neon.ts` deploys the prebuilt `dist/index.mjs` as the `jol` Function. The bundle includes its dependencies and web assets. Neon injects Postgres/Auth/Storage credentials; the policy explicitly passes the current branch’s Realtime URL and sealing secret from `.env.local`. Refresh that file when changing branches. The photo bucket is private. Browser assets contain only public configuration, never database or sealing secrets.

6. In Functions, register your chosen custom domain for the `jol` Function and configure its DNS-only CNAME. Neon manages TLS; verify the hostname actually serves HTTPS before connecting a Mac. Keep `JOL_ORIGIN` equal to the user-facing canonical origin, rather than deriving it from the Function’s internal request hostname. See [custom domains](https://neon.com/docs/compute/functions/custom-domains).

7. Verify `/health` and `/.well-known/jerry-online`, then open the website and sign in. In native **Settings → Jerry On Line**, enter that same origin, find the server, review sharing choices and connect in the browser. Use a disposable expedition first. No real history is uploaded unless explicitly selected.

8. Check note/photo delivery, hosted sign-out, token refresh, Mac sleep/reconnect, server restart, local takeover, offline command expiry and a real remote mission against a disposable app. The local test suite does not establish these hosted-service behaviors. Keep remote missions off until the connection has been verified.

For a local API using a real development branch, set `JOL_ORIGIN=http://127.0.0.1:8787` and run `npm run dev`. The native release connection intentionally requires HTTPS, so this local endpoint is for browser/API development. Do not run the local fixture or development HTTP server as a public deployment.

## Storage and recovery

Local journals keep their existing layout. Sync acknowledgements and command receipts are separate:

```text
~/Library/Application Support/Jerry/
  Expeditions/<expedition UUID>/journal.jsonl
  Expeditions/<expedition UUID>/<photo UUID>.jpg
  JOL/<server instance UUID>/<device UUID>/sync.json
```

The sync state contains cursors, uploaded photo names and command receipts. Auth tokens stay in Keychain. After the first upload for an expedition, the Mac sends only journal records after its last acknowledged cursor. A lost acknowledgement can cause a batch retry, which the server deduplicates. Each photograph uploads once after its acknowledgement is saved.

In **Settings → Jerry On Line → Journal sharing**, choose **Share Older Expeditions…** to add locally saved expeditions from before the connection. Choose **Share Technical Details…** to include the Details from shared expeditions, including records already uploaded. Technical details can include screen content. Both options preserve the current Mac enrollment and its note cursors. Details added to a notes-only connection use a separate cursor and send only the omitted detail fields. Previously uploaded notes and photos stay in place.

The server stores ordered events and materialized entries in Postgres. Batches are deduplicated by stable event IDs and acknowledged only after their transaction commits. Gaps and conflicting retries are rejected. Details backfill enriches existing records and preserves their original retry digests. A remote photograph is a separate private Storage object with its own sharing choice.

The browser subscribes to Macs, recent expeditions, the selected expedition and its newest entries, and the selected Mac’s command status. The photo readiness flag updates when the private object is registered. Earlier pages are fetched on demand. When a live collection fails, its view reads from the API while reconnecting. Healthy collections do not use periodic API reads.

While remote missions are enabled, the Mac receives a wake-up as soon as the Function’s live command inbox changes. It claims work through the authenticated API so leases, permissions and retries stay authoritative. The Mac also reconciles the queue on connection, after local work finishes, and periodically for recovery. When the live stream is unavailable, it checks the queue about every ten seconds. Presence heartbeats and local journal uploads run separately from command receipt.

Remote commands expire after one hour by default. A received-but-not-started command can be leased again; a started command whose connection disappears becomes uncertain rather than queued. The Mac also records accepted command IDs before execution and retries known completion receipts after a lost acknowledgement. Restarting Jerry leaves remote missions disabled and restores interrupted expeditions paused.

## Operating limits and trust

Choose a JOL operator you trust. The server can read uploaded text/photos, and allowing remote missions makes it part of the Mac’s control trust boundary. This implementation uses HTTPS and private ownership checks, not encryption against the operator.

The native API rejects redirects, partitions sync state by instance/device and validates the discovered origin/protocol before sign-in. The server verifies OAuth resource token issuer and audience; web session JWT verification uses Neon’s separately documented session issuer. Preview branches cannot pass as production just by sharing signing keys. Browser writes carry the expected signed-in account to prevent a stale page from submitting under a switched session.

Native browser sign-in enters through JOL’s `/authorize` route, which turns Managed Auth’s JSON authorization redirect into normal browser navigation. Signed login/consent queries are passed back through the official Auth SDK; the Mac receives only its loopback callback and exchanges the code with PKCE. A declined authorization closes cleanly without changing local functionality.

Do not enable production remote control on cloned test branches. Do not remove cloud rows manually while a Mac still has pending uploads: deletion tombstones and a supported cloud-deletion UI are not implemented yet. Configure Neon retention/backups and private operator access before storing important journals. Long-lived streams and database queries consume resources; measure costs before offering a public service.

The dedicated development deployment passed synthetic checks for browser and native authentication, journal deltas and detail backfill through Neon Realtime and TanStack DB, private photo delivery, a live command wake-up through SSE, and command claims and acknowledgements. The signed Mac build passed 88 agent checks. Its existing connection and the redesigned Safari journal were checked interactively. Each self-hosted deployment needs its own checks.

The design and future phases are in [JOL plan](JOL_PLAN.md).
