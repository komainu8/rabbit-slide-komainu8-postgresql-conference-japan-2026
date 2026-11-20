#!/usr/bin/env bash

set -uex

podman compose exec -T postgres \
  psql -U redmine -d redmine <<'SQL'
ALTER ROLE redmine IN DATABASE redmine
  SET session_preload_libraries = 'auto_explain';

ALTER ROLE redmine IN DATABASE redmine
  SET auto_explain.log_min_duration = 0;

ALTER ROLE redmine IN DATABASE redmine
  SET auto_explain.log_analyze = on;

ALTER ROLE redmine IN DATABASE redmine
  SET auto_explain.log_buffers = on;

ALTER ROLE redmine IN DATABASE redmine
  SET auto_explain.log_timing = off;

ALTER ROLE redmine IN DATABASE redmine
  SET auto_explain.log_parameter_max_length = 0;
SQL

podman compose restart redmine

podman compose logs -f postgres 2>&1 |
  grep --line-buffered -E \
  'fts_target_pgvector_embeddings|binary_hnsw_idx'
