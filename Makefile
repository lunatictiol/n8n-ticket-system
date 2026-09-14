# AI Ticketing System — task runner
# Run `make help` to list targets. Recipes use docker compose and scripts that
# land in later milestones; each target guards against missing files in a SINGLE
# shell line so the guard actually prevents the action (Make runs every recipe
# line in its own shell, so a bare `exit` cannot stop later lines).
#
# COMPOSE pins `-f docker-compose.yml` on purpose: without it, `docker compose`
# searches parent directories and can match an unrelated compose file above the
# repo. Pinning the file keeps every target scoped to this project only.

.DEFAULT_GOAL := help
SHELL := /bin/sh
COMPOSE := docker compose -f docker-compose.yml
NO_COMPOSE_MSG := >> docker-compose.yml not present yet (arrives in M1)

.PHONY: help up down reset logs ps bootstrap health ingest seed

help: ## List available targets
	@echo "AI Ticketing System — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Start the full stack (detached)
	@if [ -f docker-compose.yml ]; then $(COMPOSE) up -d; else echo "$(NO_COMPOSE_MSG)"; fi

down: ## Stop the stack (keep volumes/data)
	@if [ -f docker-compose.yml ]; then $(COMPOSE) down; else echo "$(NO_COMPOSE_MSG)"; fi

reset: ## Stop the stack AND destroy all volumes (DANGER: wipes data)
	@if [ -f docker-compose.yml ]; then \
		echo ">> This destroys all Postgres, Qdrant, Ollama and n8n data."; \
		$(COMPOSE) down -v; \
	else echo "$(NO_COMPOSE_MSG)"; fi

logs: ## Tail logs for all services
	@if [ -f docker-compose.yml ]; then $(COMPOSE) logs -f; else echo "$(NO_COMPOSE_MSG)"; fi

ps: ## Show status of all services
	@if [ -f docker-compose.yml ]; then $(COMPOSE) ps; else echo "$(NO_COMPOSE_MSG)"; fi

bootstrap: ## Wait for health, pull Ollama models, apply migrations (M1)
	@if [ -f scripts/bootstrap.sh ]; then sh scripts/bootstrap.sh; \
	else echo ">> scripts/bootstrap.sh not implemented yet (M1)"; fi

health: ## Run health checks against all services (M1)
	@if [ -f scripts/healthcheck.sh ]; then sh scripts/healthcheck.sh; \
	else echo ">> scripts/healthcheck.sh not implemented yet (M1)"; fi

ingest: ## Ingest knowledge-base PDFs into Qdrant (M4)
	@if [ -f ingestion/ingest.py ]; then python -m ingestion.ingest; \
	else echo ">> ingestion/ingest.py not implemented yet (M4)"; fi

seed: ## Load seed data (roles, demo agents, demo tickets) (M2/M11)
	@if [ -d db/seed ] && [ -n "$$(ls -A db/seed 2>/dev/null | grep -v .gitkeep)" ]; then \
		echo ">> seed target scaffolded; wiring lands in M2/M11"; \
	else echo ">> db/seed has no seed files yet (M2/M11)"; fi
