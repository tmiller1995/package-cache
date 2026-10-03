#!/usr/bin/env bash
# Nightly pg_dump of the Nexus database, keeping the last 7 days.
# Blobs are not dumped: they are a pull-through cache that refills from
# upstream, and OVH's included daily backup covers the system disk anyway.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${DATA_DIR:-/srv/package-cache-data}"
OUT_DIR="${DATA_DIR}/backups"
STAMP="$(date +%Y-%m-%d)"

mkdir -p "${OUT_DIR}"
docker compose --project-directory "${APP_DIR}" exec -T postgres \
  pg_dump -U nexus -d nexus -Fc > "${OUT_DIR}/nexus-${STAMP}.dump.tmp"
mv "${OUT_DIR}/nexus-${STAMP}.dump.tmp" "${OUT_DIR}/nexus-${STAMP}.dump"

find "${OUT_DIR}" -name 'nexus-*.dump' -mtime +7 -delete
echo "$(date -Is) backup ok: nexus-${STAMP}.dump"
