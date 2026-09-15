#!/usr/bin/env sh
# AI Ticketing System — health / acceptance gate (CLAUDE.md M1)
#
# Verifies the M1 acceptance gate:
#   - every compose service reports healthy
#   - Qdrant returns its collections list
#   - Ollama returns a generate completion
#   - Supabase Studio loads
#   - n8n UI loads
# Exits non-zero if any check fails. Run host-side (needs the published ports).
set -u

COMPOSE="docker compose -f docker-compose.yml"
QDRANT_HOST_URL="${QDRANT_HOST_URL:-http://localhost:6333}"
OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://localhost:11434}"
STUDIO_URL="${STUDIO_HOST_URL:-http://localhost:3001}"
N8N_URL="${N8N_HOST_URL:-http://localhost:5678}"
KONG_URL="${KONG_HOST_URL:-http://localhost:8000}"
LLM_MODEL="${OLLAMA_LLM_MODEL:-qwen3:8b}"

FAILED=0
pass() { printf '  [PASS] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILED=1; }

echo ">> Service health (docker):"
for svc in db kong auth rest realtime storage imgproxy meta studio qdrant ollama n8n; do
  cid="$($COMPOSE ps -q "$svc" 2>/dev/null || true)"
  if [ -z "$cid" ]; then fail "$svc not running"; continue; fi
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
  case "$status" in
    healthy|running) pass "$svc ($status)" ;;
    *) fail "$svc ($status)" ;;
  esac
done

echo ">> Qdrant collections:"
if curl -fsS "$QDRANT_HOST_URL/collections" >/dev/null 2>&1; then
  pass "GET $QDRANT_HOST_URL/collections"
else
  fail "GET $QDRANT_HOST_URL/collections"
fi

echo ">> Ollama generate:"
if curl -fsS "$OLLAMA_HOST_URL/api/generate" \
    -d "{\"model\":\"$LLM_MODEL\",\"prompt\":\"Reply with the single word OK.\",\"stream\":false}" \
    2>/dev/null | grep -q '"response"'; then
  pass "POST $OLLAMA_HOST_URL/api/generate ($LLM_MODEL)"
else
  fail "POST $OLLAMA_HOST_URL/api/generate ($LLM_MODEL) — is the model pulled? (run make bootstrap)"
fi

echo ">> Supabase Studio:"
if curl -fsS -o /dev/null "$STUDIO_URL/api/profile" 2>/dev/null; then
  pass "GET $STUDIO_URL"
else
  fail "GET $STUDIO_URL"
fi

echo ">> n8n UI:"
if curl -fsS -o /dev/null "$N8N_URL/healthz" 2>/dev/null; then
  pass "GET $N8N_URL/healthz"
else
  fail "GET $N8N_URL/healthz"
fi

echo ">> Kong gateway:"
if curl -fsS -o /dev/null "$KONG_URL/" 2>/dev/null || [ "$?" -ne 7 ]; then
  pass "Kong reachable at $KONG_URL"
else
  fail "Kong not reachable at $KONG_URL"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo ">> M1 acceptance gate: PASS"
  exit 0
else
  echo ">> M1 acceptance gate: FAIL"
  exit 1
fi
