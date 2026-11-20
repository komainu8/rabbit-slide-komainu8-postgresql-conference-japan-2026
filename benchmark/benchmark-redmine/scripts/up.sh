#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

MAX_WAIT_SECONDS=360
WAIT_INTERVAL=2

echo "[1/4] Stop Redmine if it is already running."
podman compose stop redmine >/dev/null 2>&1 || true

echo "[2/4] Build and start PostgreSQL."
podman compose up -d --build postgres

POSTGRES_CID=""

while IFS= read -r container_id; do
  service="$(
    podman inspect \
      --format '{{ index .Config.Labels "com.docker.compose.service" }}' \
      "$container_id"
  )"

  if [[ "$service" == "postgres" ]]; then
    POSTGRES_CID="$container_id"
    break
  fi
done < <(podman compose ps -q)

if [[ -z "${POSTGRES_CID}" ]]; then
  echo "PostgreSQL container not found." >&2
  podman compose ps -a >&2
  exit 1
fi

echo "[3/4] Wait for the PostgreSQL health check, then enable extensions."
health_status=""
elapsed=0

while (( elapsed < MAX_WAIT_SECONDS )); do
  health_status="$(
    podman inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
      "${POSTGRES_CID}" 2>/dev/null || true
  )"

  case "${health_status}" in
    healthy)
      break
      ;;
    unhealthy)
      echo "PostgreSQL health check reported unhealthy." >&2
      podman compose logs --tail=100 postgres >&2 || true
      exit 1
      ;;
    no-healthcheck)
      echo "The PostgreSQL container has no configured health check." >&2
      exit 1
      ;;
    *)
      sleep "${WAIT_INTERVAL}"
      elapsed=$((elapsed + WAIT_INTERVAL))
      ;;
  esac
done

if [[ "${health_status}" != "healthy" ]]; then
  echo "Timed out waiting for PostgreSQL to become healthy." >&2
  podman inspect \
    --format '{{json .State.Health}}' \
    "${POSTGRES_CID}" >&2 || true
  podman compose logs --tail=100 postgres >&2 || true
  exit 1
fi

# Read credentials from the PostgreSQL container environment.
# PGPASSWORD is not printed in the command line or logs.
podman compose exec -T postgres sh -ec '
  : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is empty or unset}"
  export PGPASSWORD="${POSTGRES_PASSWORD}"
  exec psql \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --host=127.0.0.1 \
    --port=5432 \
    --username="${POSTGRES_USER}" \
    --dbname="${POSTGRES_DB}"
' <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgroonga;
CREATE EXTENSION IF NOT EXISTS vector;
SQL

echo "[4/4] Build and start Redmine."
podman compose up -d --build redmine

echo "Done. Redmine: http://127.0.0.1:3000"

