#!/usr/bin/env bash

set -uex

podman compose exec -T redmine \
  env RAILS_ENV=production \
  bin/rails full_text_search:synchronize
