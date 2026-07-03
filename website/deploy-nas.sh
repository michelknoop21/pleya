#!/usr/bin/env sh
# Redeploy the Pleya landing site to the Synology NAS.
# Builds the static site locally, ships build/ + docker files, rebuilds the container.
set -e
cd "$(dirname "$0")"

echo "→ building static site"
bun run build

echo "→ shipping to NAS (/volume1/docker/pleya)"
tar czf - Dockerfile nginx.conf docker-compose.yml .dockerignore build \
  | ssh synology 'mkdir -p /volume1/docker/pleya && rm -rf /volume1/docker/pleya/build \
      && tar xzf - -C /volume1/docker/pleya'

echo "→ rebuilding container"
ssh synology 'export PATH=$PATH:/usr/local/bin; cd /volume1/docker/pleya && docker compose up -d --build'

echo "→ live at http://192.168.3.135:8830/"
