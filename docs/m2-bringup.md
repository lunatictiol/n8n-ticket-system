# M2 — Bring-up runbook

Everything deterministic is already done and verified (see `progress.md`). What
remains are the interactive steps that require the n8n UI and a real mailbox:
creating credentials, importing the workflows, and sending a test email.

## 0. Prerequisites (already true in this repo)

- Stack is up and healthy: `make ps` (or `docker compose ps`) shows every
  service healthy.
- Ollama has both models: `curl -s localhost:11434/api/tags` lists `qwen3:8b`
  and `nomic-embed-text`.
- Postgres schema applied: migrations `001` and `002` (run `make bootstrap` on a
  fresh volume, or `docker exec -i supabase-db psql -U postgres -d postgres < db/migrations/001_m2_minimal_schema.sql` then `002`).
- Qdrant `company_docs` populated: `python -m ingestion.seed_qdrant`
  (or `make ingest`). Verify: `curl -s localhost:6333/collections/company_docs`.

n8n UI: <http://localhost:15678> (basic-auth user/pass from `.env`).

## 1. Create four n8n credentials

In n8n → **Credentials → New**. The workflows reference these by placeholder id;
after import you re-select each real credential on the marked nodes.

| Credential type | Values |
|---|---|
| **Postgres** | Host `db`, Port `5432`, Database `postgres`, User `postgres`, Password = `POSTGRES_PASSWORD` from `.env`. SSL off. |
| **Ollama** | Base URL `http://ollama:11434` |
| **Qdrant** | URL `http://qdrant:6333` (no API key) |
| **Gmail OAuth2** | Google Cloud OAuth client (see step 2) |

> Use the container **service names** (`db`, `ollama`, `qdrant`), not
> `localhost` — n8n talks to them over the compose network.

## 2. Gmail OAuth2 (the only external setup)

1. Google Cloud Console → create an OAuth 2.0 Client ID (Web application).
2. Authorized redirect URI: `http://localhost:15678/rest/oauth2-credential/callback`.
3. Enable the Gmail API for the project.
4. In n8n, create the **Gmail OAuth2** credential with the client id/secret and
   connect it. The mailbox you authorize is both the support inbox (Gmail
   Trigger polls it) and the approver/operator address — the workflows are
   pre-set to send approval and failure mail to `bhatsabiq9@gmail.com`. Change
   that in the *Human Approval*, *Record Sent + Audit*, *Record Rejection* nodes
   and the error handler's *Notify Operator* node if you use a different address.

## 3. Import and wire (order matters)

1. Import **`n8n/workflows/wf-error-handler.json`** first. Re-select the Postgres
   and Gmail credentials on its two nodes. Save. Note its workflow id (in the URL).
2. Import **`n8n/workflows/wf-support-ticketing.json`**. Re-select Postgres,
   Gmail, Ollama and Qdrant credentials on every node showing a credential
   warning.
3. Open the main workflow → **Settings → Error Workflow** → select
   *Support Ticketing — Error Handler*. (Replaces the `REPLACE_WITH_ERROR_WORKFLOW_ID`
   placeholder — set it before the first run, not after the first failure.)
4. Import **`n8n/workflows/wf-ingest-knowledge-base.json`** and re-select the
   Qdrant + Ollama credentials. (Optional for M2 — Qdrant is already seeded by
   the Python path — but this is the locked-decision ingestion workflow.)
5. **Activate** the main workflow so the Gmail Trigger polls.

## 4. One-time verification of the retrieval score (breakage #4)

The grounding gate reads `top_score` from `Build Context`. `Build Context` reads
the score the Qdrant node surfaces. Before trusting the gate on real mail, run
the workflow once (send yourself a refund question) and open the execution:
inspect the **Qdrant — Retrieve Context** node output and confirm each item
carries a `score`. `Build Context` already looks for the score under
`item.json.score`, `document.score`, `metadata.score` and `metadata._score`, so
it tolerates the common locations; if your n8n build surfaces it elsewhere, add
that path to the `rawScore` line in that node.

Reference numbers from the seeded corpus (Qdrant REST, same embedding path):

| Query | Top score | Top doc |
|---|---|---|
| "How long do I have to request a refund?" | 0.78 | Refund Policy (customer_safe) |
| internal discount/escalation question | 0.52 | Product Documentation — handbook **filtered out** |
| out-of-scope ("London office holiday hours") | 0.45 | borderline; draft layer must refuse |

## 5. Acceptance gate (M2.5) — manual checks

Send real mail from an outside address to the authorized inbox and confirm:

- [ ] A `tickets` row with a `TKT-2026-NNNNN` number, a `ticket_messages` row,
      and a `replies` row with `draft_reply`, `confidence`, `retrieved_chunk_ids`;
      ticket status `PENDING_APPROVAL`.
- [ ] Approval mail arrives with the retrieved context visible.
- [ ] Approve → reply threads under the original in the customer's client;
      ticket `AWAITING_CUSTOMER`; `audit_log` has an `approve_and_send` row.
- [ ] Reject with a reason → status `MANUAL`, reason persisted, audit row written.
- [ ] Send the identical message twice → one ticket (provider_message_id UNIQUE).
- [ ] Ask something the three PDFs cannot answer → the exact refusal string, no
      invented policy.
- [ ] Stop Ollama (`docker compose stop ollama`) and send mail → the run fails,
      `dead_letter` has the payload, the operator mail arrives. Restart with
      `docker compose start ollama`.

Handy DB peek:
```
docker exec -i supabase-db psql -U postgres -d postgres -c \
  "SELECT ticket_number, status FROM tickets ORDER BY created_at DESC LIMIT 5;"
```

## Known M2 characteristics (by design; addressed later)

- **Out-of-scope scores hug the 0.45 floor** on this 3-document corpus because
  `nomic-embed-text` has a high similarity baseline. The draft prompt's hard
  refusal rule is the backstop. M3's ten-document corpus with heading-prepended
  chunks widens the separation.
- **`sendAndWait` parks a live execution** waiting on the approval form — that is
  exactly what M7 removes by decoupling approval into a webhook workflow.
- **Ingestion access-level metadata**: the Python seeder sets it per document and
  is verified; the n8n ingestion workflow sets it via the data-loader metadata
  mapping and is hardened (heading-aware chunking, file_hash skip,
  `knowledge_documents` rows) in M3.
