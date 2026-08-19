#!/usr/bin/env sh
# Deploy de Pleya Server-fundering (PS-0) naar de Synology NAS.
#
# Eenmalig vooraf, zie README.md: /volume1/docker/pleya-server/.env met een
# POSTGRES_PASSWORD uit `openssl rand -hex 32`, en de drie schrijfbare mappen.
#
# De NAS bouwt de image zelf. Dat is geen omweg maar de kortste route: hij is
# amd64 en de ontwikkelmachine niet, en emuleren duurt langer dan bouwen.
set -e
cd "$(dirname "$0")"

REMOTE_DIR=/volume1/docker/pleya-server
SSH_HOST=synology

if ! ssh "$SSH_HOST" "grep -q '^POSTGRES_PASSWORD=.\{16,\}' $REMOTE_DIR/.env" 2>/dev/null; then
  echo "✗ $REMOTE_DIR/.env mist een POSTGRES_PASSWORD — zie README.md" >&2
  exit 1
fi

echo "→ Pleya Web bouwen"
# De frontend wordt hier gebouwd en gaat als bundel mee in de tar. De NAS bouwt
# wel de Go-binary zelf, want hij is amd64 en de ontwikkelmachine meestal niet;
# de webbundel is architectuurloos, dus daar zou een Bun-toolchain op een
# Celeron niets aan toevoegen behalve tijd. Zonder deze stap faalt de
# containerbuild luid op de ontbrekende bundel, en dat is opzet.
../pleya_web/scripts/build-into-server.sh

echo "→ bronnen versturen naar $SSH_HOST:$REMOTE_DIR"
COPYFILE_DISABLE=1 tar czf - Dockerfile compose.yaml .dockerignore go.mod go.sum cmd internal \
  | ssh "$SSH_HOST" "mkdir -p $REMOTE_DIR && tar xzf - -C $REMOTE_DIR"

echo "→ containers bouwen en starten"
ssh "$SSH_HOST" "export PATH=\$PATH:/usr/local/bin; cd $REMOTE_DIR && docker compose up -d --build --remove-orphans"

echo "→ wachten tot de server gereed is"
ssh "$SSH_HOST" "export PATH=\$PATH:/usr/local/bin; \
  port=\$(grep -E '^PLEYA_SERVER_HOST_PORT=' $REMOTE_DIR/.env | cut -d= -f2); \
  port=\${port:-8832}; \
  for i in \$(seq 1 30); do \
    if curl -fsS -m 5 http://127.0.0.1:\$port/readyz >/dev/null 2>&1; then \
      echo \"  readyz groen op poort \$port\"; exit 0; \
    fi; \
    sleep 2; \
  done; \
  echo '  readyz werd niet groen' >&2; \
  docker compose -f $REMOTE_DIR/compose.yaml logs --tail 40 >&2; \
  exit 1"

echo "→ klaar. Alleen bereikbaar op 127.0.0.1 van de NAS zelf, en dat is opzet."
