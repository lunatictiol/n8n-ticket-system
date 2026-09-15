# Progress

Running log of what shipped per milestone and any deviation from `CLAUDE.md`,
with the reason.

## M0 — Repository scaffold — ✅ complete (2026-09-14)

**Shipped:**
- Full `CLAUDE.md` §4 directory tree: `db/{migrations,seed}`, `ingestion/`,
  `knowledge-base/pdfs/`, `ai/`, `n8n/workflows/`, `dashboard/`, `scripts/`,
  `docs/adr/` — empty dirs tracked via `.gitkeep`.
- `.gitignore` — stack-aware (env/secrets, Node/Next.js, Python, Docker volumes,
  n8n, generated PDFs, agent tooling caches).
- `.env.example` — every variable the system will need across all milestones
  (Postgres, Supabase, Qdrant, Ollama, n8n, IMAP/SMTP, approval tokens, AI
  constants, dashboard). All values are placeholders or non-secret defaults.
- `Makefile` — self-documenting `help` plus `up`, `down`, `reset`, `logs`, `ps`,
  `bootstrap`, `health`, `ingest`, `seed`. Targets guard against files that
  arrive in later milestones so they invoke without error during M0.
- `README.md` — one-paragraph description, locked-stack table, quick start, and
  the full milestone list.

**Acceptance gate:** `make help` lists all targets; no target errors on
invocation; repo contains no secrets. — see verification below.

**Deviations from CLAUDE.md:**
- GNU Make was not installed on the Windows host. Installed `ezwinports.make`
  4.4.1 via winget (user-approved). No change to the locked stack — the Makefile
  remains the specified task runner.
- The repo is named `n8n-ticket-system` (existing directory), not `ai-ticketing`
  as in the §4 sample tree. Layout is otherwise identical.

**Notes:**
- `make help` and other targets are run from a POSIX shell (Git Bash / WSL), not
  cmd.exe. The `SHELL := /bin/sh` line in the Makefile assumes a POSIX `sh`.

## M1 — Infrastructure up — ✅ complete (2026-09-15)

**Shipped:**
- `docker-compose.yml` — full self-hosted Supabase (`db`, `kong`, `auth`, `rest`,
  `realtime`, `storage`, `imgproxy`, `meta`, `studio`) + `qdrant` + `ollama` +
  `n8n`. One user-defined bridge network (`ticketnet`); named volumes for
  Postgres data/config, Supabase storage, Qdrant storage, Ollama models and n8n
  data. Healthchecks on every service with `depends_on: condition: service_healthy`
  gating on the database.
- `supabase/kong.yml` and `supabase/db/{roles,jwt,webhooks,realtime}.sql` — the
  standard Supabase self-hosting config, plus `supabase/db/n8n.sql` which
  provisions the `n8n` role/database so n8n persists executions to Postgres
  (`DB_TYPE=postgresdb`), not SQLite.
- `scripts/bootstrap.sh` — brings the stack up, waits for health, then pulls
  `nomic-embed-text` and `qwen3:8b` into Ollama (idempotent).
- `scripts/healthcheck.sh` — the M1 acceptance gate as a script.
- `.env` (gitignored) with working local values; `.env.example` extended with the
  Supabase-internal vars the compose reads (`JWT_EXPIRY`, `PGRST_DB_SCHEMAS`,
  Studio org/project, auth enable flags, `REALTIME_SECRET_KEY_BASE`,
  `GENERIC_TIMEZONE`, SMTP sender/admin).
- README updated with the `make bootstrap` / `make health` flow and a
  service-endpoint table.

**Acceptance gate — actual results (2026-09-15):**
- `docker compose ps`: all 12 services healthy (`rest`/`meta` run without a
  container healthcheck — their images are distroless with no shell/wget — and
  report `running`; every other service reports `healthy`).
- Qdrant: `GET /collections` → `{"result":{"collections":[]},"status":"ok"}`.
- Supabase Studio: `GET /api/profile` → HTTP 200. REST-via-Kong with the anon key
  → HTTP 200 (proves gateway → PostgREST → Postgres chain).
- n8n: `GET /healthz` → `{"status":"ok"}`; ran its schema migrations against
  Postgres on first boot (executions persisted to Postgres, not SQLite).
- Ollama: `nomic-embed-text` + `qwen3:8b` pulled; `POST /api/generate` returns a
  completion. (See deviations re: Ollama image version.)
- Restart safety: stack survives `down` (without `-v`) / `up` with data intact
  (named volumes).

**Deviations from CLAUDE.md (with reasons):**
- **Supabase pinned to the v1.24.09 (Kong) self-hosting line.** Upstream master
  has since replaced Kong with Envoy and added supavisor/edge-functions/analytics.
  §2 locks "Kong", so the last Kong-based release is used. The optional
  `analytics` (logflare), `vector`, `supavisor` and `functions` services from that
  release are omitted — they are not in the §2 service set.
- **Host port exposure.** §6 M1 says "only n8n (5678) binds host ports," but the
  same milestone's gate requires loading Studio and curling Qdrant from the host,
  and the M0 `.env.example` already defines `KONG_HTTP_PORT`/`STUDIO_PORT`.
  Resolved by binding the minimum needed for the gate and the host-run M4/M5 jobs:
  n8n 5678, Kong 8000, Studio 3001, Qdrant 6333, Ollama 11434. Postgres, GoTrue,
  PostgREST, Realtime, Storage, imgproxy and meta remain internal-only.
- **Ollama image bumped `0.3.14` → `0.12.0`.** `qwen3:8b` requires a newer Ollama
  than the 2024 0.3.x line ("requires a newer version of Ollama"). Locked model
  unchanged; only the runtime version was advanced to support it.
- **Healthchecks on `rest`/`meta` removed** (distroless images, no shell/wget) and
  `studio` healthcheck targets the container hostname (Next.js binds to the
  container interface, not localhost). `storage`/`n8n` healthchecks use `127.0.0.1`
  (localhost resolved to IPv6 where the servers listen on IPv4).

**Notes (this host):**
- Ports 5678 and 8000 were already occupied by the developer's own running
  processes, so the live verification mapped n8n → host 15678 and Kong → host 8001
  via one-off `N8N_PORT`/`KONG_HTTP_PORT` overrides. The committed compose still
  binds 5678/8000; stop the conflicting processes (or override the ports) to run
  on the defaults.
