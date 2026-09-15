# AI Ticketing System

A locally-deployed, AI-powered customer support platform. Customers send email;
tickets are created automatically; a local LLM drafts a reply grounded strictly
in company documentation retrieved from a vector store; and a human agent reviews
and approves every outbound message before it is sent. Built to run as if a real
company depends on it — correctness, auditability and restart-safety come before
feature count. The stack is fully local via Docker Compose: self-hosted Supabase
(Postgres + auth + storage + Studio), Qdrant for vectors, Ollama for the LLM and
embeddings, n8n for orchestration, and a custom Next.js approval dashboard.

## Stack (locked decisions)

| Concern | Choice |
|---|---|
| Database | Self-hosted Supabase (Postgres + GoTrue + PostgREST + Realtime + Storage + Kong + Studio) |
| Vector store | Qdrant — single collection, payload filtering, 768-dim cosine |
| LLM | Ollama, `qwen3:8b` |
| Embeddings | Ollama, `nomic-embed-text` (768 dims) |
| Orchestration | n8n, executions persisted to Postgres |
| Ingestion | Standalone Python job (not n8n) |
| Approval UI | Custom Next.js dashboard; decoupled webhook-triggered approval |
| Deployment | Docker Compose, fully local |

See [`CLAUDE.md`](./CLAUDE.md) for the full specification and the reasoning behind
each locked decision.

## Quick start

```sh
cp .env.example .env    # then fill in the CHANGE_ME_* values
make bootstrap          # start the stack, wait for health, pull Ollama models (M1)
make health             # verify the M1 acceptance gate
make ingest             # index the knowledge base (M4+)
make seed               # load demo data           (M2/M11+)
```

`make up` starts the stack without pulling models; use `make bootstrap` on first
run so `qwen3:8b` and `nomic-embed-text` are present before anything needs them.
Run `make help` to list all available targets.

### Service endpoints (local)

| Service | URL | Notes |
|---|---|---|
| n8n | http://localhost:5678 | basic auth (`N8N_BASIC_AUTH_USER` / `_PASSWORD`) |
| Supabase Studio | http://localhost:3001 | direct; or via Kong at `:8000` (dashboard basic auth) |
| Supabase API (Kong) | http://localhost:8000 | REST/Auth/Realtime/Storage gateway |
| Qdrant | http://localhost:6333 | REST + dashboard at `/dashboard` |
| Ollama | http://localhost:11434 | `qwen3:8b`, `nomic-embed-text` |

Postgres, GoTrue, PostgREST, Realtime, Storage, imgproxy and postgres-meta are
internal-only (reachable by other containers via their compose service name).

## Milestones

Milestones are sequential — milestone N+1 does not begin until N's acceptance
gate passes. Progress is tracked in [`docs/progress.md`](./docs/progress.md).

- **M0 — Repository scaffold**: complete skeleton, conventions, `.env.example`, `Makefile`, `README`.
- **M1 — Infrastructure up**: full stack healthy on one `docker compose up`; bootstrap pulls Ollama models.
- **M2 — Database schema**: relational model with constraints, RLS, append-only audit log, metric views.
- **M3 — Knowledge base documents**: ten reproducible, realistic company PDFs with checkable facts.
- **M4 — Ingestion pipeline**: PDFs chunked, embedded and upserted into Qdrant; ≥80% retrieval hit rate.
- **M5 — AI layer (standalone)**: classify → retrieve → draft → validate, working from the CLI.
- **M6 — Email intake (n8n WF1 + WF2)**: email in, deduped ticket out, reliable reply/thread detection.
- **M7 — AI draft workflow (n8n WF3)**: every inbound message produces a reviewable, cited draft.
- **M8 — Agent dashboard**: the approval queue and the four-pane ticket detail — the actual product.
- **M9 — Approval & send (n8n WF4 + WF5)**: signed-token approval; threaded outbound email; full round trip.
- **M10 — Resilience & audit hardening**: dead-letter, backoff, circuit breaker, replay, complete audit trail.
- **M11 — Documentation & demo**: run from a clean checkout; seeded demo state; timed first-run walkthrough.

## Requirements

- Docker + Docker Compose
- GNU Make
- ~16 GB RAM recommended (Ollama `qwen3:8b`). GPU optional; on CPU expect 30–90s per draft.
