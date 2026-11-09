CREATE TABLE IF NOT EXISTS jol_devices (
  id uuid PRIMARY KEY,
  owner_id text NOT NULL,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  credential_hash text NOT NULL,
  revoked boolean NOT NULL DEFAULT false,
  remote_enabled boolean NOT NULL DEFAULT false,
  last_seen timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id, owner_id)
);
CREATE TABLE IF NOT EXISTS jol_expeditions (
  id uuid NOT NULL,
  device_id uuid NOT NULL REFERENCES jol_devices(id),
  title text NOT NULL DEFAULT 'An untitled adventure',
  status text NOT NULL DEFAULT 'Catching up',
  is_running boolean NOT NULL DEFAULT false,
  is_finished boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL,
  cursor integer NOT NULL DEFAULT 0,
  PRIMARY KEY(device_id,id)
);
CREATE TABLE IF NOT EXISTS jol_events (
  device_id uuid NOT NULL,
  expedition_id uuid NOT NULL,
  sequence integer NOT NULL CHECK(sequence > 0),
  event_id uuid NOT NULL,
  digest text NOT NULL,
  payload jsonb NOT NULL,
  PRIMARY KEY(device_id,expedition_id,sequence),
  UNIQUE(device_id,expedition_id,event_id),
  FOREIGN KEY(device_id,expedition_id) REFERENCES jol_expeditions(device_id,id)
);
CREATE TABLE IF NOT EXISTS jol_entries (
  device_id uuid NOT NULL,
  expedition_id uuid NOT NULL,
  id uuid NOT NULL,
  position integer NOT NULL,
  kind text NOT NULL CHECK(kind IN ('request','response','activity')),
  text text NOT NULL,
  details text NOT NULL DEFAULT '',
  photo text,
  created_at timestamptz NOT NULL,
  PRIMARY KEY(device_id,expedition_id,id),
  FOREIGN KEY(device_id,expedition_id) REFERENCES jol_expeditions(device_id,id)
);
CREATE TABLE IF NOT EXISTS jol_commands (
  id uuid PRIMARY KEY,
  owner_id text NOT NULL,
  device_id uuid NOT NULL,
  expedition_id uuid,
  kind text NOT NULL CHECK(kind IN ('start','continue','stop','finish')),
  prompt text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','received','started','finished','failed','cancelled','expired','uncertain')),
  result text NOT NULL DEFAULT '',
  fence integer NOT NULL DEFAULT 0,
  lease_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  FOREIGN KEY(device_id,owner_id) REFERENCES jol_devices(id,owner_id)
);
CREATE INDEX IF NOT EXISTS jol_commands_queue ON jol_commands(device_id,status,created_at);
CREATE TABLE IF NOT EXISTS jol_assets (
  device_id uuid NOT NULL,
  expedition_id uuid NOT NULL,
  filename text NOT NULL,
  object_key text NOT NULL UNIQUE,
  PRIMARY KEY(device_id,expedition_id,filename),
  FOREIGN KEY(device_id,expedition_id) REFERENCES jol_expeditions(device_id,id)
);
