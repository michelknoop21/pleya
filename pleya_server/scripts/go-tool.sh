#!/usr/bin/env bash
# Draai de Go-toolchain in de gepinde builder-image.
#
# Er staat geen Go op de ontwikkelmachine, en dat hoeft ook niet: de versie die
# de tests draait hoort dezelfde te zijn als die de container bouwt.
#
#   scripts/go-tool.sh vet ./...
#   scripts/go-tool.sh test ./...
#   scripts/go-tool.sh mod tidy
#
# Integratietests tegen een echte Postgres hebben een netwerk en een DSN nodig.
# scripts/test-db.sh zet die klaar en exporteert PLEYA_TEST_DATABASE_URL en
# PLEYA_TEST_DOCKER_NETWORK; staan ze niet in de omgeving, dan slaan die tests
# zichzelf over.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GO_IMAGE="${GO_IMAGE:-golang:1.26.6-bookworm}"
MODCACHE="${PWD}/.gocache"
mkdir -p "$MODCACHE/mod" "$MODCACHE/build"

extra=()
if [ -n "${PLEYA_TEST_DOCKER_NETWORK:-}" ]; then
  extra+=(--network "$PLEYA_TEST_DOCKER_NETWORK")
fi
if [ -n "${PLEYA_TEST_FFPROBE_MOUNT:-}" ]; then
  extra+=(-v "${PLEYA_TEST_FFPROBE_MOUNT}:/usr/local/bin/ffprobe:ro")
fi

# De repository-wortel gaat alleen-lezen mee. Eén test heeft hem nodig:
# internal/logging toetst de redactie tegen pleya_verify/redact/cases.json,
# hetzelfde bestand dat de app en de Verify-runner lezen (K rij 11). Zonder deze
# koppeling zou die test een kopie meten, en dan zegt hij niets meer over de
# vraag of de drie implementaties nog gelijk redigeren.
REPO_ROOT="$(cd .. && pwd)"

exec docker run --rm \
  -v "$PWD:/src" \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$MODCACHE/mod:/go/pkg/mod" \
  -v "$MODCACHE/build:/root/.cache/go-build" \
  -w /src \
  -e GOFLAGS \
  -e CGO_ENABLED=0 \
  -e PLEYA_REPO_ROOT=/repo \
  -e PLEYA_TEST_DATABASE_URL \
  -e PLEYA_RESPONSE_DIR \
  ${extra[@]+"${extra[@]}"} \
  "$GO_IMAGE" \
  go "$@"
