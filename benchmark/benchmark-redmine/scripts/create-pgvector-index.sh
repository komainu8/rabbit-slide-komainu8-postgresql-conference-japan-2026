#!/usr/bin/env bash

set -uex

podman compose exec -T redmine \
  env RAILS_ENV=production \
  bundle exec rake full_text_search:pgvector:index:create
