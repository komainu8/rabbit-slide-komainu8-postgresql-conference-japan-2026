#!/usr/bin/env bash

set -uex

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DATA_FILE="${PROJECT_DIR}/../benchmark/redmine_dataset/synonyms.csv"
cd "${PROJECT_DIR}"

if [[ ! -f "${DATA_FILE}" ]]; then
  echo "CSVが見つかりません: ${DATA_FILE}" >&2
  exit 1
fi

podman compose exec -T redmine \
       sh -c 'cat > /tmp/synonyms.csv' < "${DATA_FILE}"

podman compose exec redmine \
       wc -l /tmp/synonyms.csv

echo "Redmineの同義語辞書をロードします。"
podman compose exec -T redmine \
  env RAILS_ENV=production \
  bin/rails full_text_search:query_expansion:synchronize \
  INPUT=/tmp/synonyms.csv
