#!/usr/bin/env bash

set -uex

podman compose exec -T postgres \
  psql -U redmine -d redmine \
  -c "ALTER SYSTEM SET pgroonga.query_log_path = 'pgroonga.query.log';"

podman compose exec -T postgres \
  psql -U redmine -d redmine \
  -c "SELECT pg_reload_conf();"

podman compose exec postgres \
  sh -lc 'tail -F "$PGDATA/pgroonga.query.log"'
