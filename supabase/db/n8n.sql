-- Provision a dedicated database and login role for n8n execution data.
-- n8n is configured (DB_TYPE=postgresdb) to persist executions here instead of
-- its default SQLite. Runs once, on first initialisation of an empty PGDATA.
-- Idempotent so a manual re-run against an existing cluster does not error.
\set n8n_pass `echo "$N8N_DB_PASSWORD"`

SELECT 'CREATE ROLE n8n LOGIN PASSWORD ' || quote_literal(:'n8n_pass')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'n8n')
\gexec

SELECT 'CREATE DATABASE n8n OWNER n8n'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')
\gexec

GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
