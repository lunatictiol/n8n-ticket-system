# Build milestones — v2 (n8n-first)

**Change from v1:** the working n8n workflow is now M2, not the endpoint. Everything from M3
onward is an enhancement layered onto the same two workflows. Nothing is dropped; it is
re-ordered so a running system exists at the end of M2 rather than at the end of M9.

**Reference workflows (already written):**
- `wf-support-ticketing.json` — *Support Ticketing — Intake to Send*. One linear workflow:
  Gmail trigger → normalize → dedupe → complaint classifier → create ticket → store message →
  Qdrant retrieve → build context → grounding gate → structured draft → save draft →
  Gmail `sendAndWait` approval → approve/reject → threaded reply → audit.
- `wf-error-handler.json` — error trigger → shape → `dead_letter` → notify operator.

M1 (stack up) is done.

---

## M2 — Get the attached workflows running green

**Goal:** a real email to the support inbox becomes a ticket, a grounded draft, an approval
mail, and a threaded reply back to the customer. One pass, no branches, no dashboard.

The workflows cannot be imported and run as-is — they read and write a schema and a Qdrant
collection that do not exist yet. M2 is the smallest amount of everything else needed to make
them execute.

### M2.1 — Minimal schema

Only the tables and columns the two JSONs actually touch. No RLS, no state-machine CHECK, no
views — those are M4.

- `tickets` — id, ticket_number (default from a per-year sequence), customer_name,
  customer_email, subject, category, priority, status, thread_id, source_message_id,
  created_at, updated_at
- `ticket_messages` — id, ticket_id, direction, from_email, body_text,
  provider_message_id **UNIQUE**, in_reply_to, received_at
- `replies` — id, ticket_id, version, draft_reply, final_reply, status, confidence,
  model_name, prompt_version, retrieved_chunk_ids (JSONB), rejection_reason, approved_by,
  approved_at, sent_at
- `ticket_events` — id, ticket_id, event_type, event_description, actor, timestamp
- `audit_log` — id, actor, actor_role, action, entity_type, entity_id, before, after, timestamp
- `dead_letter` — id, workflow, payload (JSONB), error, attempt_count, created_at, resolved_at

Status values in use this milestone: `CLASSIFIED`, `NEEDS_MANUAL`, `PENDING_APPROVAL`,
`AWAITING_CUSTOMER`, `MANUAL`. Leave them unconstrained for now.

Two notes that bite immediately: `ticket_number` must have a working default, because
*Create Ticket* does `RETURNING id, ticket_number` and everything downstream reads it. And
`dead_letter` has `ON CONFLICT DO NOTHING` with no unique constraint behind it — either add one
or drop the clause, because right now it is decorative.

### M2.2 — Minimal knowledge base

Three PDFs, not ten: Refund Policy, Support Handbook, Product Documentation. Enough to make the
grounding gate fire on one query and refuse on another.

Ingest in n8n (manual-trigger workflow, matching the locked decision): read PDF → split →
embed with `nomic-embed-text` → upsert to Qdrant collection `company_docs`, 768 dims, cosine.

The retrieve node filters on `metadata.access_level = customer_safe`, so **every point must
carry that key in its payload** or retrieval returns nothing and every ticket falls to
`NEEDS_MANUAL`. Mark one of the three `internal_only` on purpose — it is the negative test.

### M2.3 — Import and wire

- Import the error handler first, then set it as the Error Workflow in the main workflow's
  settings. Do this before the first run, not after the first failure.
- Replace `REPLACE_POSTGRES_CRED_ID`, `REPLACE_GMAIL_CRED_ID`, and all three occurrences of
  `REPLACE_WITH_AGENT_EMAIL@example.com` (approval recipient, `Record Sent + Audit`,
  `Record Rejection`).
- Confirm `qwen3:8b` and `nomic-embed-text` are pulled and that n8n reaches Ollama on the
  container network name, not `localhost`.

### M2.4 — Known breakages to fix during bring-up

These are the things that will fail on first run. Work them in this order:

1. **`queryReplacement` is comma-split.** Every Postgres node passes parameters as one
   comma-joined string. A customer subject or body containing a comma shifts every parameter
   after it. `Create Ticket` and `Store Inbound Message` will corrupt rows on the first
   realistic email. Switch to an array expression (`={{ [a, b, c] }}`) or a JSON-array
   parameter, whichever your node version accepts.
2. **Empty result kills the branch.** `Check Duplicate` returns zero rows for every *new*
   message, so the node emits no items and `Already Seen?` never evaluates — the run ends
   silently instead of taking the false branch. Turn on **Always Output Data** on that node.
3. **qwen3 emits `<think>` blocks.** The Structured Output Parser will fail to parse them.
   Disable thinking on the model or strip before parsing. Expect this first.
4. **Verify the retrieval score is actually populated.** The gate reads `item.json.score` and
   compares against `0.45`. If the Qdrant node version does not surface a score,
   `Build Context` computes `top_score = 0` and every ticket routes to `NEEDS_MANUAL`. Log the
   raw retrieve output once and confirm before trusting the gate.
5. **Multi-statement Postgres queries.** `Mark Needs Manual`, `Record Sent + Audit` and
   `Record Rejection` each run several statements reusing `$1`/`$4`. Confirm your node version
   executes them as one parameterised batch; if not, split into separate nodes.
6. **Classifier fallback is `discard`.** Non-complaints vanish rather than erroring. That is
   intended, but verify it, because a misclassified real complaint disappears the same way.

### M2.5 — Acceptance gate

- Send a real email from an outside address. A ticket row appears with a formatted number, a
  `ticket_messages` row is written, and a `replies` row lands with `draft_reply`, `confidence`
  and `retrieved_chunk_ids` populated. Ticket status is `PENDING_APPROVAL`.
- The approval mail arrives with the retrieved context visible in it.
- Approve → the reply arrives in the customer's client **threaded under the original**;
  ticket becomes `AWAITING_CUSTOMER`; `audit_log` has an `approve_and_send` row.
- Reject with a reason → status `MANUAL`, reason persisted, audit row written.
- Send the identical message twice → one ticket.
- Ask something the three PDFs cannot answer → the refusal string, no invented policy.
- Stop Ollama and send an email → the run fails, `dead_letter` has the payload, the operator
  mail arrives.

**Deferred out of M2 on purpose:** reply/threading detection, attachments, the separate
classification call, composite confidence, citation validation, the dashboard, RLS, retries and
circuit breaking. Each has its own milestone below.

---

## M3 — Knowledge base and ingestion, properly

**Enhances:** M2.2. Same Qdrant collection, same retrieve node, better content and better chunks.

Ten documents instead of three, generated reproducibly rather than hand-authored, with one
consistent fictional company identity across all of them — contradictions between documents
poison retrieval. 4–10 pages each, numbered sections, version and effective date in the footer,
specific checkable facts (exact refund windows, named SLA times, numbered escalation tiers).

Upgrade the ingestion workflow: chunk on headings first, then pack to ~600 tokens with ~80
overlap, and **prepend document name and section heading to each chunk before embedding** —
`Refund Policy › Eligibility › Customers may request…` retrieves materially better than the bare
paragraph. Payload carries `doc_id`, `doc_name`, `doc_type`, `section`, `page`, `chunk_index`,
`access_level`, `version`. Skip re-embedding unchanged files by `file_hash`. Deleting and
re-ingesting a document must not orphan vectors. Write a `knowledge_documents` row per document
with the real chunk count.

**Gate:** a written list of ≥15 assertions (fact → document → section) in `docs/`, run as
retrieval queries, **≥80% with the correct source document in the top 3**. Re-running ingestion
on an unchanged corpus is a no-op. A `customer_safe` filtered query returns zero internal-only
chunks. Re-run the M2 acceptance emails — draft quality should visibly improve.

---

## M4 — Schema hardening

**Enhances:** M2.1, without changing any workflow.

Add the columns M2 skipped (language, assigned_to, sla_due_at, closed_at, the `attachments` and
`knowledge_documents` tables). Then add the invariants:

- Ticket number trigger on a per-year sequence; concurrency test of 100 parallel inserts yields
  100 distinct numbers.
- `audit_log` append-only — revoke UPDATE and DELETE at the role level, not by application
  discipline.
- Status transitions enforced by CHECK or trigger against the state machine in §5.
- RLS per role: agents see tickets, only supervisors and admins approve, viewers are read-only,
  only the service role writes `audit_log`.
- `updated_at` by trigger.
- SQL views for every dashboard metric: open/closed counts, pending approvals, average
  resolution time, category and priority breakdowns, confidence distribution,
  approval-without-edit rate.

**Gate:** migrations apply cleanly to a fresh volume; illegal transition rejected; non-service
UPDATE on `audit_log` rejected; every view returns rows against seed data; **the M2 workflow
still runs green afterwards**.

---

## M5 — Intake and threading

**Enhances:** the front half of the workflow. Split intake into WF1 so the main workflow stops
being one 28-node line.

Reply detection, in precedence order:
1. `In-Reply-To` / `References` matched against stored message IDs — the reliable path.
2. `TKT-\d{4}-\d{5}` on the subject.
3. Sender email matched to their most recent non-closed ticket.

On match: reopen if resolved, append the message, preserve the thread. On no match: new ticket.
Add attachment storage with rows in `attachments`.

**Gate:** reply to a sent thread → appends, no new ticket. Reply with the subject rewritten →
header matching still resolves it. New address with a ticket number in the subject → fallback 2.
Attachments land with rows.

---

## M6 — AI layer quality

**Enhances:** the drafting half. Still inside n8n.

- Split classification into its own strict-JSON call producing category, priority, sentiment and
  language — the current binary complaint classifier stays as the pre-filter.
- Add a **validation step** after drafting: assert every cited source number was actually in the
  retrieved set, and assert no `internal_only` text leaked. A fabricated citation must be caught.
- Replace the model's self-rating with **composite confidence**: top retrieval score, how many
  distinct documents the citations span, self-rating as tiebreaker. Formula documented in `docs/`.
- Bump `prompt_version` on every change so any stored draft traces to the prompt that made it.

**Gate:** 8 fixture emails sent as real mail, all behaving correctly — answerable policy
question, out-of-scope question (exact refusal string), prompt-injection attempt, angry customer,
multi-issue email, a question answerable only from internal-only docs (must refuse on the
customer path), a reply to an existing thread, a near-empty email. Validation catches a
deliberately fabricated citation.

---

## M7 — Decouple approval

**Enhances:** the approval step. This is the milestone that removes `sendAndWait`.

Split the tail into WF3 (draft), WF4 (approval webhook) and WF5 (send). WF4 **validates a
signed, single-use, expiring token** — an open approval endpoint is a way to send arbitrary mail
from the company domain. WF4 writes the audit entry and triggers WF5. WF5 sets `In-Reply-To` and
`References` explicitly, records `sent_at`, sets `AWAITING_CUSTOMER`.

n8n is the API layer here, so WF4 also exposes the read endpoints the dashboard will need.

**Gate:** approval works end to end without any waiting execution parked in n8n. Forged, expired
and reused tokens are all rejected and all logged. Full round trip: customer email → draft →
approve → send → customer reply → new draft → approve → send.

---

## M8 — Agent dashboard

**Enhances:** the human side. The approval mail becomes a fallback, not the interface.

Login, role-aware queue sorted by priority/age/confidence, and the ticket detail screen — four
panes: conversation, **retrieved chunks with document name and section visible**, editable draft,
confidence. Approving without seeing what was retrieved is rubber-stamping; the citations pane is
what makes the system trustworthy. Approve / edit-and-approve / reject-with-reason, each writing
`audit_log`. Metrics read the M4 views, including approval-without-edit trended over time.

**Gate:** all four roles behave per §5, enforced at the API layer not hidden in the UI. Edit and
approve retains both `draft_reply` and `final_reply`. Two tabs approving the same reply — the
second is rejected cleanly.

---

## M9 — Resilience and audit hardening

**Enhances:** the error handler already wired in M2.3.

Exponential backoff on Ollama and SMTP. Circuit breaker after N consecutive Ollama failures —
park tickets in `NEEDS_MANUAL` rather than looping. Poison-message quarantine after 3 failures on
the same item. A replay command for dead letters. Audit review across every workflow and the
dashboard, with `system` as actor for AI-originated actions.

**Gate:** stop Ollama, send mail → `NEEDS_MANUAL` + dead letters, nothing lost. Restart and
replay → drafts generate. Kill the stack mid-draft and restart → no duplicate tickets, no
duplicate sends, no `PENDING_APPROVAL` without a draft. Corrupt attachment quarantined after 3
attempts. Walk one ticket's full lifecycle in the audit log — every transition attributable.

---

## M10 — Documentation and demo

`README.md` (prerequisites, RAM/GPU expectations, numbered setup, first-run walkthrough),
`docs/architecture.md`, `docs/runbook.md` (Ollama OOM, Qdrant dimension mismatch, Gmail auth,
n8n credential loss on re-import, migration drift), `docs/adr/` for the four decisions with real
trade-offs — plain Postgres over self-hosted Supabase, decoupled approval over Wait nodes,
ingestion in n8n, retrieval gate over prompt-only grounding.

Seed script producing ~20 tickets across statuses with varied confidence and a few closed with
resolution times. A 10-step demo script.

**Gate:** clean machine, fresh clone, `cp .env.example .env`, fill three values, `make up`,
`make ingest`, `make seed` → working system, populated dashboard, one email round trip. Time it
and record it in the README.
