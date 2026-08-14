#!/usr/bin/env sh
# Redeploy de Pleya-relay (ice.pleya.app) naar de Synology NAS.
# Ship de bronnen + dockerbestanden en herbouw de containers.
#
# Eenmalig vooraf, zie README.md: server/.env met TUNNEL_TOKEN op de NAS,
# en de tunnel-hostname ice.pleya.app -> http://relay:8080 in Cloudflare.
set -e
cd "$(dirname "$0")"

REMOTE_DIR=/volume1/docker/pleya-relay

# De compose heeft hier bewust geen harde guard op (die zou ook lokaal testen
# breken), dus controleer hier: zonder token komt cloudflared niet omhoog en
# blijft ice.pleya.app onbereikbaar.
if ! ssh synology "grep -q '^TUNNEL_TOKEN=.\\+' $REMOTE_DIR/.env 2>/dev/null"; then
  echo "✗ $REMOTE_DIR/.env op de NAS heeft geen TUNNEL_TOKEN — zie README.md" >&2
  exit 1
fi

echo "→ shipping to NAS ($REMOTE_DIR)"
COPYFILE_DISABLE=1 tar czf - Dockerfile docker-compose.yml Caddyfile go.mod go.sum *.go \
  | ssh synology "mkdir -p $REMOTE_DIR && tar xzf - -C $REMOTE_DIR"

echo "→ rebuilding containers"
# --remove-orphans: `bugs` is uit de compose gehaald en `caddy` zit achter het
# vps-profile. Zonder deze vlag waarschuwt compose er alleen over en blijft een
# eerder gestarte container gewoon draaien.
ssh synology "export PATH=\$PATH:/usr/local/bin; cd $REMOTE_DIR && docker compose up -d --build --remove-orphans"

echo "→ health check via LAN"
ssh synology "curl -fsS -m 10 http://127.0.0.1:8831/health" && echo

echo "→ done. Publiek: https://ice.pleya.app/health"
