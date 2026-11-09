import { serve } from "@hono/node-server";
import app from "./index.js";
serve(
  {
    fetch: app.fetch,
    hostname: "127.0.0.1",
    port: Number(process.env.PORT || 8787),
  },
  (address) => console.log(`JOL listening on http://127.0.0.1:${address.port}`),
);
