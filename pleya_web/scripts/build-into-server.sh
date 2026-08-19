#!/usr/bin/env bash
# Bouw Pleya Web en zet de bundel klaar voor //go:embed.
#
# De frontend wordt hier gebouwd en niet in de containerbuild. Twee redenen.
# De uitvoer is architectuurloos, dus de NAS hoeft er niets voor te doen; en
# `pleya_server/deploy-nas.sh` laat de NAS zelf bouwen omdat hij amd64 is,
# waardoor een Bun-stage daar een tweede toolchain op een Celeron zou zetten
# voor een resultaat dat overal identiek is.
#
# Wat hier neergezet wordt is de bundel die de releasebuild eist. Ontbreekt
# hij, dan faalt `go build -tags release` op de compiler; zie
# pleya_server/internal/web/release.go.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DEST="../pleya_server/internal/web/dist"

echo "→ types controleren tegen het contract"
./scripts/check-api-types.sh

echo "→ bundel bouwen"
bun run build

echo "→ $DEST vullen"
# De plaatshouder blijft staan: zonder minstens één bestand in Git compileert
# het //go:embed-patroon van een schone kloon niet.
find "$DEST" -mindepth 1 ! -name PLACEHOLDER -delete
cp -R build/. "$DEST/"

if [ ! -f "$DEST/index.html" ]; then
  echo "✗ $DEST/index.html ontbreekt na de bouw" >&2
  exit 1
fi

echo "✓ $(find "$DEST" -type f | wc -l | tr -d ' ') bestanden, $(du -sh "$DEST" | cut -f1)"
