import { defineConfig } from "@neon/config/v1";
// Provision identity/storage/live SQL before registering the native OAuth client.
export default defineConfig({
  auth: true,
  preview: { realtime: { allowedOrigins: [process.env.JOL_ORIGIN!] } },
  buckets: { "jol-photos": { access: "private" } },
});
