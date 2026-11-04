#!/usr/bin/env bash
# Bouw de testimage: dezelfde Go-toolchain als de builder, plus dezelfde gepinde
# ffmpeg en dezelfde PostgreSQL-client als de runtime.
#
# De scannertests draaien tegen een echte ffprobe en tegen bestanden die ffmpeg
# ter plekke maakt. Een test die de analyse namaakt bewijst niets over de
# analyse zelf, en juist daar zit het punt waar een mediaserver stil fout gaat.
# Voor de back-uptests (S25) geldt hetzelfde: pg_dump en psql komen uit dezelfde
# gepinde postgres-image als de runtime, dus een test die hier een back-up
# terugzet bewijst iets over de binaries die op de NAS draaien.
#
#   scripts/test-image.sh
#   GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test ./...
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GO_IMAGE="${GO_IMAGE_BASE:-golang:1.26.10-bookworm}"
FFMPEG_VERSION="${FFMPEG_VERSION:-7:5.1.9-0+deb12u1}"
PG_IMAGE="${PG_CLIENT_IMAGE:-postgres:18.6-bookworm@sha256:7d2695c3aa88e792e8b3b233e7e4adb296a20412c6c0ca361e3edaaacfada108}"
TAG="${PLEYA_TEST_IMAGE:-pleya-server-test:go-ffmpeg}"

docker build -t "$TAG" -f - . <<EOF
FROM ${PG_IMAGE} AS pgclient
FROM ${GO_IMAGE}
RUN apt-get update \
 && apt-get install --no-install-recommends -y "ffmpeg=${FFMPEG_VERSION}" \
      libldap-2.5-0 libgssapi-krb5-2 libzstd1 liblz4-1 libreadline8 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=pgclient /usr/lib/postgresql/18/bin/pg_dump /usr/lib/postgresql/18/bin/psql /usr/local/bin/
COPY --from=pgclient /usr/lib/*-linux-gnu/libpq.so.5* /usr/local/lib/
RUN ldconfig && pg_dump --version && psql --version
EOF

echo "$TAG gereed. Draai de tests met:"
echo "  GO_IMAGE=$TAG scripts/go-tool.sh test ./..."
