#!/usr/bin/env sh
# AI Ticketing System — bootstrap (CLAUDE.md M1)
#
# Brings the stack up, waits for every service to report healthy, then pulls the
# required Ollama models. The model pull is mandatory: Ollama ships with no models
# on first boot, and nothing downstream (M4 embeddings, M5 drafting) works without
# them. Idempotent — re-running skips models that are already present.
set -eu

COMPOSE="docker compose -f docker-compose.yml"
LLM_MODEL="${OLLAMA_LLM_MODEL:-qwen3:8b}"
EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"

# Number of health poll attempts (5s apart). Supabase + n8n first boot can be slow.
MAX_TRIES="${BOOTSTRAP_MAX_TRIES:-120}"

log() { printf '>> %s\n' "$*"; }

require_env() {
  if [ ! -f .env ]; then
    log "ERROR: .env not found. Run: cp .env.example .env  (then fill values)"
    exit 1
  fi
}

start_stack() {
  log "Starting stack (docker compose up -d)..."
  $COMPOSE up -d
}

# Wait until a named service reports Docker health = healthy.
wait_healthy() {
  svc="$1"
  i=0
  while [ "$i" -lt "$MAX_TRIES" ]; do
    cid="$($COMPOSE ps -q "$svc" 2>/dev/null || true)"
    if [ -n "$cid" ]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo unknown)"
      if [ "$status" = "healthy" ] || [ "$status" = "running" ]; then
        log "  $svc: $status"
        return 0
      fi
    fi
    i=$((i + 1))
    sleep 5
  done
  log "ERROR: $svc did not become healthy within $((MAX_TRIES * 5))s"
  $COMPOSE ps
  return 1
}

pull_model() {
  model="$1"
  if $COMPOSE exec -T ollama ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$model"; then
    log "  model already present: $model"
  else
    log "  pulling model: $model (this can take several minutes)"
    $COMPOSE exec -T ollama ollama pull "$model"
  fi
}

main() {
  require_env
  start_stack

  log "Waiting for core services to become healthy..."
  for svc in db kong auth rest realtime storage imgproxy meta studio qdrant ollama n8n; do
    wait_healthy "$svc"
  done

  log "Pulling Ollama models..."
  pull_model "$LLM_MODEL"
  pull_model "$EMBED_MODEL"

  log "Bootstrap complete. Stack is up and models are present."
  log "Run 'make health' to verify the acceptance gate."
}

main "$@"
