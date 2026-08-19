#!/usr/bin/env bash
# Zet een echte Pleya-stack klaar voor de end-to-end-tests.
#
# Geen mocks: de bundel wordt door dezelfde binary geserveerd als in productie,
# en de API is de echte API met een echte Postgres en een echte ffprobe. Een
# nagebootste server bewijst niets over het contract, en juist daar zit wat deze
# tests horen te meten.
#
#   scripts/e2e-stack.sh up      # bouwen, starten, setupcode afdrukken
#   scripts/e2e-stack.sh down    # stack en volume weg
#   scripts/e2e-stack.sh code    # de huidige setupcode
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../pleya_server"

COMPOSE="docker compose"
PORT="$(grep -E '^PLEYA_SERVER_HOST_PORT=' .env 2>/dev/null | cut -d= -f2 || true)"
PORT="${PORT:-8832}"
BASE="http://127.0.0.1:${PORT}"

media() {
  [ -f "testdata/media/films/Grease (1978)/Grease (1978).mkv" ] && return 0
  docker build -q -t pleya-server:e2e-media . >/dev/null
  docker run --rm --entrypoint sh -v "$PWD/testdata/media:/out" pleya-server:e2e-media -c '
    set -e
    mk() { mkdir -p "$(dirname "$1")"; ffmpeg -hide_banner -loglevel error -y \
      -f lavfi -i "testsrc=size=320x180:rate=24:duration=$2" \
      -f lavfi -i "sine=frequency=440:duration=$2" \
      -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest "$1"; }
    mk "/out/films/Grease (1978)/Grease (1978).mkv" 2
    mk "/out/films/Blade Runner (1982)/Blade Runner (1982).mkv" 2
    mk "/out/series/Testserie (2020)/Season 01/Testserie - S01E01 - Eerste.mkv" 1
    mk "/out/series/Testserie (2020)/Season 01/Testserie - S01E02 - Tweede.mkv" 1
  ' >/dev/null
}

case "${1:-up}" in
  up)
    if [ ! -f .env ]; then
      sed "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 32)|" .env.example > .env
      chmod 600 .env
    fi
    mkdir -p testdata/media data/config data/cache data/transcode
    media

    echo "→ Pleya Web bouwen en in de binary zetten" >&2
    ../pleya_web/scripts/build-into-server.sh >&2

    echo "→ stack starten" >&2
    PLEYA_SERVER_LIBRARIES="${PLEYA_E2E_LIBRARIES:-films=movies:/media/library/films;series=shows:/media/library/series}" \
    PLEYA_SERVER_SCAN_INTERVAL=0 \
      $COMPOSE up -d --build --remove-orphans >&2

    for _ in $(seq 1 90); do
      if curl -fsS -m 5 "$BASE/readyz" >/dev/null 2>&1; then break; fi
      sleep 2
    done
    curl -fsS -m 5 "$BASE/readyz" >/dev/null || { echo "✗ readyz werd niet groen" >&2; exit 1; }

    # Wachten tot de eerste scanronde iets heeft opgeleverd; anders test een
    # raster tegen een lege catalogus en meet het niets.
    for _ in $(seq 1 60); do
      if $COMPOSE logs pleya-server 2>/dev/null | grep -q 'scan klaar'; then break; fi
      sleep 2
    done

    echo "export PLEYA_E2E_BASE_URL='${BASE}'"
    echo "export PLEYA_E2E_SETUP_CODE='$($COMPOSE logs pleya-server 2>/dev/null | grep -o 'Setupcode: [A-Z0-9-]*' | tail -1 | cut -d' ' -f2)'"
    ;;
  seed-large)
    # Vijfhonderd items met een echte poster ernaast, voor de artworkmeting uit
    # acceptatiecriterium 6. Eén bestand met ffmpeg en daarna kopieën: de
    # scanner ziet vijfhonderd verschillende paden en maakt er vijfhonderd
    # items van, en dat is wat een raster van die omvang nodig heeft. De poster
    # is 1000x1500 ruis, want een JPEG van een paar honderd kilobyte meet iets
    # anders dan een van tweehonderd byte.
    media
    docker build -q -t pleya-server:e2e-media . >/dev/null
    docker run --rm --entrypoint sh -v "$PWD/testdata/media:/out" pleya-server:e2e-media -c '
      set -e
      base="/out/films/Grease (1978)/Grease (1978).mkv"
      ffmpeg -hide_banner -loglevel error -y -f lavfi         -i "nullsrc=size=1000x1500,geq=random(1)*255:128:128" -frames:v 1 -q:v 4 /tmp/poster.jpg
      i=1
      while [ $i -le 500 ]; do
        dir="/out/bulk/Meting $i (2026)"
        mkdir -p "$dir"
        [ -f "$dir/Meting $i (2026).mkv" ] || cp "$base" "$dir/Meting $i (2026).mkv"
        [ -f "$dir/poster.jpg" ] || cp /tmp/poster.jpg "$dir/poster.jpg"
        i=$((i+1))
      done
    ' >/dev/null
    echo "→ 500 items klaargezet in testdata/media/bulk" >&2
    echo "  start de stack met PLEYA_SERVER_LIBRARIES=...;meting=movies:/media/library/bulk" >&2
    ;;
  code)
    $COMPOSE logs pleya-server 2>/dev/null | grep -o 'Setupcode: [A-Z0-9-]*' | tail -1 | cut -d' ' -f2
    ;;
  down)
    $COMPOSE down -v --remove-orphans >/dev/null 2>&1 || true
    ;;
  *)
    echo "gebruik: $0 up|down|code|seed-large" >&2
    exit 64
    ;;
esac
