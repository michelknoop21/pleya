#!/usr/bin/env bash
# Valideer het Pleya-protocolcontract.
#
# De structuurcontrole vraagt openapi-spec-validator. Die staat niet op deze
# machine en hoeft dat ook niet: hij draait in een gepinde container, zodat de
# uitkomst hier dezelfde is als in CI.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PY_IMAGE="${PROTOCOL_PY_IMAGE:-python:3.12-slim}"

if command -v docker >/dev/null 2>&1; then
  docker run --rm \
    -v "$PWD:/repo:ro" \
    -w /repo \
    "$PY_IMAGE" \
    sh -c 'pip install --quiet --disable-pip-version-check openapi-spec-validator jsonschema pyyaml >/dev/null 2>&1 && python3 scripts/check_protocol.py'
  exit $?
fi

echo "docker ontbreekt; alleen de lokale controles draaien" >&2
exec python3 scripts/check_protocol.py
