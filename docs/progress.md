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
