import { defineConfig } from "@neon/config/v1";
const origin = process.env.JOL_ORIGIN!;
export default defineConfig({
  auth: true,
  preview: { realtime: { allowedOrigins: [origin] } },
  buckets: { "jol-photos": { access: "private" } },
  functions: {
    jol: {
      name: "Jerry On Line",
      source: "dist/index.mjs",
      bundler: "none",
      env: {
        JOL_ORIGIN: origin,
        JOL_INSTANCE_ID: process.env.JOL_INSTANCE_ID!,
        JOL_OAUTH_CLIENT_ID: process.env.JOL_OAUTH_CLIENT_ID!,
        JOL_PHOTO_BUCKET: "jol-photos",
        NEON_REALTIME_URL: process.env.NEON_REALTIME_URL!,
        NEON_REALTIME_SECRET: process.env.NEON_REALTIME_SECRET!,
        NODE_ENV: "production",
      },
    },
  },
});
