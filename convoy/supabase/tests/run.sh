#!/usr/bin/env bash
# Runs the migrations and rule tests against a throwaway Postgres database.
#   PGHOST=/var/tmp PGPORT=54329 PGUSER=postgres ./tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-convoy_test}
P="psql -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists $DB" >/dev/null
$P -c "create database $DB" >/dev/null
$P -d "$DB" -f tests/supabase_stub.sql 2>&1 | grep -v -e wal_level -e "Set wal_level" || true
for f in migrations/*.sql; do $P -d "$DB" -f "$f"; done
$P -d "$DB" -f seed.sql
$P -d "$DB" -f tests/rules_test.sql 2>&1 | grep -E "PASSED|ERROR"
