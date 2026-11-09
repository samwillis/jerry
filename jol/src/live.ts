import { createRealtime, rawSql } from "@neon/realtime/server";
import type { Config } from "./config.js";
export function liveQueries(config: Config) {
  if (!config.realtimeURL || !config.realtimeSecret) return undefined;
  return createRealtime({
    url: config.realtimeURL,
    secret: config.realtimeSecret,
    db: config.databaseName,
  });
}
export const devicesQuery = (owner: string) =>
  rawSql(
    `SELECT d.id,d.name,d.remote_enabled,d.last_seen FROM jol_devices d WHERE d.owner_id=$1 ORDER BY d.created_at`,
    [owner],
  );
export const expeditionsQuery = (owner: string) =>
  rawSql(
    `SELECT e.id,e.device_id,e.title,e.status,e.is_running,e.is_finished,e.created_at,e.cursor FROM jol_expeditions e JOIN jol_devices d ON d.id=e.device_id WHERE d.owner_id=$1 ORDER BY e.created_at DESC,e.device_id DESC,e.id DESC LIMIT 100`,
    [owner],
  );
export const expeditionQuery = (
  owner: string,
  device: string,
  expedition: string,
) =>
  rawSql(
    `SELECT e.id,e.device_id,e.title,e.status,e.is_running,e.is_finished,e.created_at,e.cursor
     FROM jol_expeditions e JOIN jol_devices d ON d.id=e.device_id
     WHERE d.owner_id=$1 AND e.device_id=$2::uuid AND e.id=$3::uuid`,
    [owner, device, expedition],
  );
export const entryColumns =
  "e.id,e.position,e.kind,e.text,e.details,e.photo,e.created_at,(a.filename IS NOT NULL) AS photo_ready";
export const entryAssetsJoin =
  "LEFT JOIN jol_assets a ON a.device_id=e.device_id AND a.expedition_id=e.expedition_id AND a.filename=lower(e.photo)";
export const entriesQuery = (
  owner: string,
  device: string,
  expedition: string,
  after: number,
) =>
  rawSql(
    `SELECT ${entryColumns} FROM jol_entries e JOIN jol_devices d ON d.id=e.device_id ${entryAssetsJoin} WHERE d.owner_id=$1 AND e.device_id=$2::uuid AND e.expedition_id=$3::uuid AND e.position>$4::integer ORDER BY e.position DESC LIMIT 200`,
    [owner, device, expedition, after],
  );
export const commandsQuery = (owner: string, device: string) =>
  rawSql(
    `SELECT c.id,c.status,c.result,c.expedition_id,c.kind,c.prompt,c.created_at,c.expires_at FROM jol_commands c JOIN jol_devices d ON d.id=c.device_id WHERE d.owner_id=$1 AND d.id=$2::uuid ORDER BY c.created_at DESC LIMIT 50`,
    [owner, device],
  );
export const commandInboxQuery = (owner: string, device: string) =>
  rawSql(
    `SELECT c.id,c.status,c.kind,c.lease_until
       FROM jol_commands c JOIN jol_devices d ON d.id=c.device_id
       WHERE d.owner_id=$1 AND d.id=$2::uuid AND NOT d.revoked
         AND c.status IN ('queued','received','started')
       ORDER BY c.created_at,c.id`,
    [owner, device],
  );
