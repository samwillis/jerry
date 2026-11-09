import type { Pool, PoolClient } from "pg";
import {
  APIError,
  digest,
  type DetailChange,
  type JournalRecord,
} from "./protocol.js";

export interface SQL {
  query(
    sql: string,
    values?: any[],
  ): Promise<{ rows: any[]; rowCount?: number | null }>;
}
export interface Database extends SQL {
  transaction<T>(fn: (q: SQL) => Promise<T>): Promise<T>;
}
export function postgres(pool: Pool): Database {
  return {
    query: (s, v) => pool.query(s, v),
    async transaction(fn) {
      const q: PoolClient = await pool.connect();
      try {
        await q.query("BEGIN");
        const value = await fn(q);
        await q.query("COMMIT");
        return value;
      } catch (e) {
        await q.query("ROLLBACK");
        throw e;
      } finally {
        q.release();
      }
    },
  };
}
export async function ingest(
  db: Database,
  deviceID: string,
  expeditionID: string,
  start: number,
  records: JournalRecord[],
) {
  return db.transaction(async (q) => {
    // Lock the existing device first, including for a brand new expedition.
    await q.query("SELECT id FROM jol_devices WHERE id=$1 FOR UPDATE", [
      deviceID,
    ]);
    let exp = (
      await q.query(
        "SELECT cursor FROM jol_expeditions WHERE device_id=$1 AND id=$2",
        [deviceID, expeditionID],
      )
    ).rows[0];
    if (!exp) {
      const first = records[0];
      if (
        start !== 1 ||
        first.event !== "created" ||
        first.expedition?.id !== expeditionID
      )
        throw new APIError(
          409,
          "A new stream must begin with its creation record",
        );
      await q.query(
        "INSERT INTO jol_expeditions(device_id,id,title,created_at) VALUES($1,$2,$3,$4)",
        [
          deviceID,
          expeditionID,
          first.expedition.title,
          new Date(first.expedition.date),
        ],
      );
      exp = { cursor: 0 };
    }
    let cursor = exp.cursor as number;
    for (let i = 0; i < records.length; i++) {
      const sequence = start + i,
        record = records[i],
        hash = digest(record);
      const prior = (
        await q.query(
          "SELECT event_id,digest FROM jol_events WHERE device_id=$1 AND expedition_id=$2 AND sequence=$3",
          [deviceID, expeditionID, sequence],
        )
      ).rows[0];
      if (prior) {
        if (prior.event_id !== record.id || prior.digest !== hash)
          throw new APIError(409, "Conflicting event at an accepted sequence");
        continue;
      }
      if (sequence !== cursor + 1)
        throw new APIError(409, `Expected sequence ${cursor + 1}`);
      const duplicate = (
        await q.query(
          "SELECT sequence FROM jol_events WHERE device_id=$1 AND expedition_id=$2 AND event_id=$3",
          [deviceID, expeditionID, record.id],
        )
      ).rows[0];
      if (duplicate)
        throw new APIError(409, "Event already belongs to another sequence");
      await q.query(
        "INSERT INTO jol_events(device_id,expedition_id,sequence,event_id,digest,payload) VALUES($1,$2,$3,$4,$5,$6)",
        [
          deviceID,
          expeditionID,
          sequence,
          record.id,
          hash,
          JSON.stringify(record),
        ],
      );
      await apply(q, deviceID, expeditionID, sequence, record);
      cursor = sequence;
    }
    await q.query(
      "UPDATE jol_expeditions SET cursor=$3 WHERE device_id=$1 AND id=$2",
      [deviceID, expeditionID, cursor],
    );
    return cursor;
  });
}

/** Add explicitly shared details to previously acknowledged records. The
 * original digests still validate retries of the notes-only upload. */
export async function shareDetails(
  db: Database,
  device: string,
  expedition: string,
  changes: DetailChange[],
) {
  await db.transaction(async (q) => {
    await q.query("SELECT id FROM jol_devices WHERE id=$1 FOR UPDATE", [
      device,
    ]);
    const entries = new Set<string>();
    for (const { sequence, id, date, event, entryID, text } of changes) {
      const prior = (
        await q.query(
          "SELECT payload FROM jol_events WHERE device_id=$1 AND expedition_id=$2 AND sequence=$3",
          [device, expedition, sequence],
        )
      ).rows[0]?.payload as JournalRecord | undefined;
      if (!prior || prior.id !== id || prior.date !== date)
        throw new APIError(
          409,
          "Details do not match an accepted journal record",
        );
      if (event === "entry" && prior.event === "entry" && prior.entry) {
        if (
          prior.entry.id !== entryID ||
          (prior.entry.details && prior.entry.details !== text)
        )
          throw new APIError(409, "Details do not match the journal entry");
        prior.entry.details = text;
      } else if (
        event === "detailsAppended" &&
        (prior.event === "redacted" ||
          (prior.event === "detailsAppended" &&
            prior.entryID === entryID &&
            prior.text === text))
      ) {
        Object.assign(prior, { event, entryID, text });
      } else {
        throw new APIError(
          409,
          "Details do not match an accepted journal record",
        );
      }
      entries.add(entryID);
      await q.query(
        "UPDATE jol_events SET payload=$4 WHERE device_id=$1 AND expedition_id=$2 AND sequence=$3",
        [device, expedition, sequence, JSON.stringify(prior)],
      );
    }
    for (const id of entries) {
      const result = await q.query(
        `UPDATE jol_entries SET details=(
          SELECT COALESCE(string_agg(CASE WHEN payload->>'event'='entry'
            THEN payload->'entry'->>'details' ELSE payload->>'text' END, '' ORDER BY sequence),'')
          FROM jol_events WHERE device_id=$1 AND expedition_id=$2 AND (
            (payload->>'event'='entry' AND payload->'entry'->>'id'=$3::text) OR
            (payload->>'event'='detailsAppended' AND payload->>'entryID'=$3::text)
          )
        ) WHERE device_id=$1 AND expedition_id=$2 AND id=$3::uuid RETURNING id`,
        [device, expedition, id],
      );
      if (!result.rows.length)
        throw new APIError(409, "Journal entry not found");
    }
  });
}

async function apply(
  q: SQL,
  device: string,
  exp: string,
  sequence: number,
  r: JournalRecord,
) {
  const keys = [device, exp];
  if (r.event === "created" && r.expedition?.id !== exp)
    throw new APIError(409, "Expedition does not match stream");
  if (r.event === "entry" && r.entry) {
    const e = r.entry;
    await q.query(
      "INSERT INTO jol_entries(device_id,expedition_id,id,position,kind,text,details,photo,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
      [
        ...keys,
        e.id,
        sequence,
        e.kind,
        e.text,
        e.details,
        e.photo ?? null,
        new Date(e.date),
      ],
    );
  } else if (
    ["textAppended", "textReplaced", "detailsAppended"].includes(r.event)
  ) {
    const expression =
      r.event === "textReplaced"
        ? "text=$4"
        : r.event === "textAppended"
          ? "text=text || $4"
          : "details=details || $4";
    const result = await q.query(
      `UPDATE jol_entries SET ${expression} WHERE device_id=$1 AND expedition_id=$2 AND id=$3 RETURNING id`,
      [...keys, r.entryID, r.text],
    );
    if (!result.rows.length)
      throw new APIError(409, "Text change precedes its journal entry");
  } else if (r.event === "titleChanged")
    await q.query(
      "UPDATE jol_expeditions SET title=$3 WHERE device_id=$1 AND id=$2",
      [...keys, r.text],
    );
  else if (r.event === "state")
    await q.query(
      "UPDATE jol_expeditions SET status=coalesce($3,status),is_running=coalesce($4,is_running),is_finished=coalesce($5,is_finished) WHERE device_id=$1 AND id=$2",
      [...keys, r.status ?? null, r.isRunning ?? null, r.isFinished ?? null],
    );
}

export async function claim(
  db: Database,
  device: string,
  owner: string,
  busy: boolean,
) {
  return db.transaction(async (q) => {
    const d = (
      await q.query(
        "SELECT remote_enabled FROM jol_devices WHERE id=$1 AND owner_id=$2 AND NOT revoked FOR UPDATE",
        [device, owner],
      )
    ).rows[0];
    if (!d?.remote_enabled) return null;
    await q.query(
      "UPDATE jol_commands SET status='uncertain',result='Connection interrupted after execution began; give Jerry a fresh direction' WHERE device_id=$1 AND status='started' AND lease_until < now()",
      [device],
    );
    await q.query(
      "UPDATE jol_commands SET status='queued',lease_until=NULL WHERE device_id=$1 AND status='received' AND lease_until < now()",
      [device],
    );
    await q.query(
      "UPDATE jol_commands SET status='expired' WHERE device_id=$1 AND status='queued' AND expires_at < now()",
      [device],
    );
    const command = (
      await q.query(
        `SELECT * FROM jol_commands WHERE device_id=$1 AND status='queued' AND expires_at > now() ${busy ? "AND kind='stop'" : ""} ORDER BY CASE WHEN kind='stop' THEN 0 ELSE 1 END,created_at,id LIMIT 1 FOR UPDATE`,
        [device],
      )
    ).rows[0];
    if (!command) return null;
    if (
      command.kind !== "stop" &&
      (
        await q.query(
          "SELECT id FROM jol_commands WHERE device_id=$1 AND status IN ('received','started') LIMIT 1",
          [device],
        )
      ).rows.length
    )
      return null;
    return (
      await q.query(
        "UPDATE jol_commands SET status='received',fence=fence+1,lease_until=now()+interval '90 seconds' WHERE id=$1 RETURNING *",
        [command.id],
      )
    ).rows[0];
  });
}
