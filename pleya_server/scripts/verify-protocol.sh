#!/usr/bin/env bash
# Toets de antwoorden van de draaiende server tegen het bevroren wire-contract.
#
# Twee stappen. De Go-test bouwt een echte bibliotheek, scant hem en legt elk
# antwoord vast; de Python-validator houdt die antwoorden tegen hetzelfde
# openapi.yaml waar ook de fixtures tegen valideren.
#
# Dat is acceptatiecriterium 4 van PS-2, en de scheiding is opzet: een validator
# in Go zou de server tegen zijn eigen lezing van het contract houden.
#
#   eval "$(scripts/test-db.sh up)"
#   scripts/test-image.sh
#   scripts/verify-protocol.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REPO_ROOT="$(cd .. && pwd)"
OUT="$PWD/.responses"
PY_IMAGE="${PROTOCOL_PY_IMAGE:-python:3.12-slim}"
TEST_IMAGE="${PLEYA_TEST_IMAGE:-pleya-server-test:go-ffmpeg}"

if [ -z "${PLEYA_TEST_DATABASE_URL:-}" ]; then
  echo "PLEYA_TEST_DATABASE_URL ontbreekt; draai eval \"\$(scripts/test-db.sh up)\"" >&2
  exit 64
fi

echo "==> antwoorden vastleggen"
rm -rf "$OUT"
mkdir -p "$OUT"

PLEYA_RESPONSE_DIR=/src/.responses GO_IMAGE="$TEST_IMAGE" \
  scripts/go-tool.sh test -count=1 ./internal/api/

echo
echo "==> valideren tegen docs/pleya-protocol/v1/openapi.yaml"
docker run --rm \
  -v "$REPO_ROOT:/repo:ro" \
  -w /repo \
  "$PY_IMAGE" \
  sh -c 'pip install --quiet --disable-pip-version-check jsonschema pyyaml referencing >/dev/null 2>&1 && python3 scripts/check_server_responses.py /repo/pleya_server/.responses'
