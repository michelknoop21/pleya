#!/usr/bin/env bash
# Bouw de testimage: dezelfde Go-toolchain als de builder, plus dezelfde gepinde
# ffmpeg als de runtime.
#
# De scannertests draaien tegen een echte ffprobe en tegen bestanden die ffmpeg
# ter plekke maakt. Een test die de analyse namaakt bewijst niets over de
# analyse zelf, en juist daar zit het punt waar een mediaserver stil fout gaat.
#
#   scripts/test-image.sh
#   GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test ./...
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GO_IMAGE="${GO_IMAGE_BASE:-golang:1.26.6-bookworm}"
FFMPEG_VERSION="${FFMPEG_VERSION:-7:5.1.9-0+deb12u1}"
TAG="${PLEYA_TEST_IMAGE:-pleya-server-test:go-ffmpeg}"

docker build -t "$TAG" -f - . <<EOF
FROM ${GO_IMAGE}
RUN apt-get update \
 && apt-get install --no-install-recommends -y "ffmpeg=${FFMPEG_VERSION}" \
 && rm -rf /var/lib/apt/lists/*
EOF

echo "$TAG gereed. Draai de tests met:"
echo "  GO_IMAGE=$TAG scripts/go-tool.sh test ./..."
