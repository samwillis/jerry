import pg from "pg";
import { attachDatabasePool } from "@neon/functions";
import { config } from "./config.js";
import { authentication } from "./auth.js";
import { postgres } from "./database.js";
import { createApp } from "./app.js";
declare const __JOL_ASSETS__: Record<string, { base64: string; type: string }>;
const settings = config();
const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 3,
});
attachDatabasePool(pool);
const assets = Object.fromEntries(
  Object.entries(__JOL_ASSETS__).map(([key, value]) => [
    key,
    { body: Buffer.from(value.base64, "base64"), type: value.type },
  ]),
);
export default createApp({
  db: postgres(pool),
  config: settings,
  authenticate: authentication(settings),
  assets,
});
