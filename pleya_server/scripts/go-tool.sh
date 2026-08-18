#!/usr/bin/env bash
# Draai de Go-toolchain in de gepinde builder-image.
#
# Er staat geen Go op de ontwikkelmachine, en dat hoeft ook niet: de versie die
# de tests draait hoort dezelfde te zijn als die de container bouwt.
#
#   scripts/go-tool.sh vet ./...
#   scripts/go-tool.sh test ./...
#   scripts/go-tool.sh mod tidy
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GO_IMAGE="${GO_IMAGE:-golang:1.26.6-bookworm}"
MODCACHE="${PWD}/.gocache"
mkdir -p "$MODCACHE/mod" "$MODCACHE/build"

exec docker run --rm \
  -v "$PWD:/src" \
  -v "$MODCACHE/mod:/go/pkg/mod" \
  -v "$MODCACHE/build:/root/.cache/go-build" \
  -w /src \
  -e GOFLAGS \
  -e CGO_ENABLED=0 \
  "$GO_IMAGE" \
  go "$@"
