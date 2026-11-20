#!/usr/bin/env bash

set -uex

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DATA_FILE="${PROJECT_DIR}/../benchmark/redmine_dataset/documents.csv"
cd "${PROJECT_DIR}"

if [[ ! -f "${DATA_FILE}" ]]; then
  echo "CSVが見つかりません: ${DATA_FILE}" >&2
  exit 1
fi

echo "[1/2] Redmineの日本語初期データをロードします（登録済みならスキップされます）。"
podman compose exec -T redmine \
  env RAILS_ENV=production REDMINE_LANG=ja \
  bundle exec rake redmine:load_default_data

echo "[2/2] 検証用チケットを登録します。"
podman compose exec -T redmine \
  env RAILS_ENV=production TEST_DATA_CSV=/opt/redmine-import/data/documents.csv \
  bundle exec rails runner /opt/redmine-import/scripts/import_test_data.rb

echo "登録完了: http://127.0.0.1:3000/projects/semantic-search-benchmark/issues"
