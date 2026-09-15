-- 001_m2_minimal_schema.sql
-- Milestone M2.1 — minimal schema: only the tables and columns the two n8n
-- workflows actually read and write. No RLS, no state-machine CHECK, no metric
-- views — those land in M4. Forward-only; never edit after it has been applied.
--
-- Applied against the main `postgres` database (the same Postgres the Supabase
-- `db` service runs). n8n's own execution data lives in the separate `n8n`
-- database and is untouched here.

BEGIN;

-- ---------------------------------------------------------------------------
-- Ticket number: TKT-YYYY-NNNNN, backed by a per-year sequence.
-- The sequence is the single source of uniqueness (CLAUDE.md §3.6). The
-- function creates the year's sequence on first use; CREATE SEQUENCE IF NOT
-- EXISTS is atomic, so concurrent first-inserts of a new year cannot both win.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION next_ticket_number() RETURNS text AS $$
DECLARE
  yr      text := to_char(now(), 'YYYY');
  seqname text := 'ticket_seq_' || yr;
  n       bigint;
BEGIN
  EXECUTE format('CREATE SEQUENCE IF NOT EXISTS %I', seqname);
  EXECUTE format('SELECT nextval(%L)', seqname) INTO n;
  RETURN 'TKT-' || yr || '-' || lpad(n::text, 5, '0');
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- tickets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tickets (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number     text NOT NULL UNIQUE DEFAULT next_ticket_number(),
  customer_name     text,
  customer_email    text,
  subject           text,
  category          text,
  priority          text,
  status            text NOT NULL DEFAULT 'CLASSIFIED',
  thread_id         text,
  source_message_id text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- ticket_messages
-- provider_message_id UNIQUE is the DB-enforced dedupe (CLAUDE.md §3.6).
-- Outbound rows carry no provider id, so the column is nullable and the unique
-- index skips NULLs (Postgres treats NULLs as distinct).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_messages (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id           uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  direction           text NOT NULL,                     -- inbound | outbound
  from_email          text,
  body_text           text,
  provider_message_id text UNIQUE,
  in_reply_to         text,
  received_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- replies
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS replies (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id           uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  version             int  NOT NULL DEFAULT 1,
  draft_reply         text,
  final_reply         text,
  status              text NOT NULL DEFAULT 'draft',      -- draft|approved|rejected|sent
  confidence          numeric,
  model_name          text,
  prompt_version      text,
  retrieved_chunk_ids jsonb,
  rejection_reason    text,
  approved_by         text,
  approved_at         timestamptz,
  sent_at             timestamptz
);

-- ---------------------------------------------------------------------------
-- ticket_events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id         uuid NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  event_type        text NOT NULL,
  event_description text,
  actor             text,
  "timestamp"       timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- audit_log  (append-only hardening deferred to M4)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor       text,
  actor_role  text,
  action      text NOT NULL,
  entity_type text,
  entity_id   uuid,
  before      jsonb,
  after       jsonb,
  "timestamp" timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- dead_letter
-- The error handler used `ON CONFLICT DO NOTHING` with no unique key behind it,
-- which is a no-op. There is no natural dedupe key for an arbitrary failure, so
-- the workflow drops that clause instead. Every failure gets its own row.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dead_letter (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow      text,
  payload       jsonb,
  error         text,
  attempt_count int NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  resolved_at   timestamptz
);

COMMIT;
