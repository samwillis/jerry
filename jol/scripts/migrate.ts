import pg from "pg";
import { readFile } from "node:fs/promises";
const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 1,
});
const client = await pool.connect();
try {
  await client.query("BEGIN");
  await client.query("SELECT pg_advisory_xact_lock(71940318)");
  await client.query(await readFile("migrations/001_jol.sql", "utf8"));
  await client.query("COMMIT");
  console.log("JOL schema is ready");
} catch (e) {
  await client.query("ROLLBACK");
  throw e;
} finally {
  client.release();
  await pool.end();
}
