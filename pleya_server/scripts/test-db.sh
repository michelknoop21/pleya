#!/usr/bin/env bash
# Zet een wegwerp-Postgres klaar voor de integratietests en print de export-regels.
#
#   eval "$(scripts/test-db.sh up)"
#   scripts/go-tool.sh test ./...
#   scripts/test-db.sh down
#
# Dezelfde gepinde image als compose.yaml gebruikt, zodat een test die hier
# slaagt niet op een andere Postgres-versie leunt dan de productiestack.
set -euo pipefail

NETWORK="${PLEYA_TEST_DOCKER_NETWORK:-pleya-test-net}"
NAME="${PLEYA_TEST_DB_CONTAINER:-pleya-test-db}"
PG_IMAGE="${PLEYA_TEST_PG_IMAGE:-postgres:18.6-bookworm}"
PASS="testpass"
DSN="postgres://pleya:${PASS}@${NAME}:5432/pleya_test?sslmode=disable"

case "${1:-up}" in
  up)
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
    if ! docker inspect "$NAME" >/dev/null 2>&1; then
      docker run -d --name "$NAME" --network "$NETWORK" \
        -e POSTGRES_USER=pleya \
        -e POSTGRES_PASSWORD="$PASS" \
        -e POSTGRES_DB=pleya_test \
        --tmpfs /var/lib/postgresql \
        "$PG_IMAGE" >/dev/null
    fi
    docker start "$NAME" >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do
      if docker exec "$NAME" pg_isready -U pleya -d pleya_test >/dev/null 2>&1; then
        echo "export PLEYA_TEST_DOCKER_NETWORK=${NETWORK}"
        echo "export PLEYA_TEST_DATABASE_URL='${DSN}'"
        exit 0
      fi
      sleep 1
    done
    echo "postgres kwam niet op" >&2
    exit 1
    ;;
  down)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    ;;
  *)
    echo "gebruik: $0 up|down" >&2
    exit 64
    ;;
esac
