#!/usr/bin/env bash
# Bewijs de PS-0-fundering lokaal, van broncode tot draaiende stack.
#
# Elke stap print PASS of FAIL. Aan het eind staat er een telling, en de
# exitcode is niet nul zodra er iets faalt.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -t 1 ]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GRN=$'\e[32m'; DIM=$'\e[2m'; RST=$'\e[0m'
else
  BOLD=""; RED=""; GRN=""; DIM=""; RST=""
fi
section() { printf "\n%s==> %s%s\n" "$BOLD" "$1" "$RST"; }
ok()   { printf "  %sPASS%s  %s\n" "$GRN" "$RST" "$1"; PASSED=$((PASSED+1)); }
fail() { printf "  %sFAIL%s  %s\n" "$RED" "$RST" "$1"; FAILED=$((FAILED+1)); }
note() { printf "  %s%s%s\n" "$DIM" "$1" "$RST"; }

PASSED=0
FAILED=0

COMPOSE="docker compose"
PORT="$(grep -E '^PLEYA_SERVER_HOST_PORT=' .env 2>/dev/null | cut -d= -f2)"
PORT="${PORT:-8832}"
BASE="http://127.0.0.1:${PORT}"

cleanup() {
  section "opruimen"
  $COMPOSE down -v --remove-orphans >/dev/null 2>&1 && ok "stack verwijderd" || note "opruimen gaf een fout"
}

# ---------------------------------------------------------------- voorbereiding
section "voorbereiding"

if [ ! -f .env ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    fail "openssl ontbreekt en er is geen .env"
    exit 1
  fi
  sed "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 32)|" .env.example > .env
  chmod 600 .env
  ok ".env aangemaakt met een gegenereerd wachtwoord"
else
  ok ".env aanwezig"
fi

mkdir -p testdata/media data/config data/cache data/transcode
echo "dit bestand staat er zodat de read-only test iets te lezen heeft" > testdata/media/leesbaar.txt
ok "testmappen gereed"

# --------------------------------------------------------------------- 1. compose
section "1. compose config"
if $COMPOSE config -q 2>/dev/null; then ok "compose.yaml valideert"; else fail "compose.yaml valideert niet"; fi

# -------------------------------------------------------------------------- 2. go
section "2. go vet en go test"
if scripts/go-tool.sh vet ./... >/dev/null 2>&1; then ok "go vet"; else fail "go vet"; fi

out="$(mktemp)"
if scripts/go-tool.sh test ./... >"$out" 2>&1; then
  ok "go test ($(grep -c '^ok' "$out") pakketten)"
else
  fail "go test"
  sed 's/^/    /' "$out"
fi
rm -f "$out"

# ------------------------------------------------------------------ 3. amd64 build
section "3. image bouwen voor linux/amd64"
if docker buildx build --platform linux/amd64 -t pleya-server:verify-amd64 --load . >/dev/null 2>&1; then
  arch="$(docker image inspect pleya-server:verify-amd64 --format '{{.Os}}/{{.Architecture}}')"
  if [ "$arch" = "linux/amd64" ]; then ok "image is $arch"; else fail "image is $arch, verwacht linux/amd64"; fi
else
  fail "buildx build voor linux/amd64"
fi

# ------------------------------------------------------------------- 4. stack start
section "4. stack starten"
$COMPOSE down -v --remove-orphans >/dev/null 2>&1
if $COMPOSE up -d --build >/dev/null 2>&1; then ok "compose up"; else fail "compose up"; cleanup; exit 1; fi

wait_healthy() {
  local svc="$1" deadline=$((SECONDS + 120)) state
  while [ $SECONDS -lt $deadline ]; do
    state="$($COMPOSE ps --format json "$svc" 2>/dev/null | sed -n 's/.*"Health":"\([^"]*\)".*/\1/p' | head -1)"
    [ "$state" = "healthy" ] && return 0
    sleep 2
  done
  return 1
}

if wait_healthy postgres; then ok "postgres healthy"; else fail "postgres werd niet healthy"; fi
if wait_healthy pleya-server; then ok "pleya-server healthy"; else fail "pleya-server werd niet healthy"; fi

status() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$1" 2>/dev/null || echo 000; }

# ------------------------------------------------------------------ 5. health/ready
section "5. healthz en readyz"
[ "$(status "$BASE/healthz")" = "200" ] && ok "/healthz = 200" || fail "/healthz = $(status "$BASE/healthz")"
[ "$(status "$BASE/readyz")"  = "200" ] && ok "/readyz = 200"  || fail "/readyz = $(status "$BASE/readyz")"

# ---------------------------------------------------------------------- 6. non-root
section "6. non-root"
uid="$($COMPOSE exec -T pleya-server id -u 2>/dev/null | tr -d '\r')"
if [ -n "$uid" ] && [ "$uid" != "0" ]; then ok "container draait als uid $uid"; else fail "container draait als uid ${uid:-onbekend}"; fi

# ----------------------------------------------------------------- 7. media :ro
section "7. media read-only"
if $COMPOSE exec -T pleya-server cat /media/library/leesbaar.txt >/dev/null 2>&1; then
  ok "lezen uit /media/library lukt"
else
  fail "lezen uit /media/library lukt niet"
fi
if $COMPOSE exec -T pleya-server sh -c 'touch /media/library/schrijfpoging' >/dev/null 2>&1; then
  fail "schrijven naar /media/library LUKTE, de mount is niet read-only"
  rm -f testdata/media/schrijfpoging
else
  ok "schrijven naar /media/library faalt"
fi
if $COMPOSE logs pleya-server 2>/dev/null | grep -q '"mounted_read_only":true'; then
  ok "de server meet zelf dat de mount read-only is"
else
  note "de server meldde geen mounted_read_only=true; zie de startlog"
fi

# ------------------------------------------------------- 8. rootfs en scratch
section "8. read-only rootfs en schrijfbare mappen"
if $COMPOSE exec -T pleya-server sh -c 'touch /rootfs-poging' >/dev/null 2>&1; then
  fail "de rootfs is beschrijfbaar"
else
  ok "de rootfs is read-only"
fi
for d in /config /cache /transcode /tmp; do
  if $COMPOSE exec -T pleya-server sh -c "touch $d/.probe && rm -f $d/.probe" >/dev/null 2>&1; then
    ok "$d is beschrijfbaar"
  else
    fail "$d is niet beschrijfbaar"
  fi
done

# ------------------------------------------------------------------ 9. persistentie
section "9. persistentie over een herstart"
psql() { $COMPOSE exec -T postgres psql -U pleya -d pleya -tAc "$1" 2>/dev/null | tr -d '\r'; }

psql "CREATE SCHEMA IF NOT EXISTS pleya_verify;" >/dev/null
psql "CREATE TABLE IF NOT EXISTS pleya_verify.proef (id int primary key, tekst text);" >/dev/null
psql "INSERT INTO pleya_verify.proef VALUES (1,'overleeft-een-herstart') ON CONFLICT DO NOTHING;" >/dev/null

if [ "$(psql "SELECT tekst FROM pleya_verify.proef WHERE id=1;")" = "overleeft-een-herstart" ]; then
  ok "testdata geschreven"
else
  fail "testdata schrijven mislukt"
fi

$COMPOSE restart >/dev/null 2>&1
wait_healthy postgres >/dev/null

if [ "$(psql "SELECT tekst FROM pleya_verify.proef WHERE id=1;")" = "overleeft-een-herstart" ]; then
  ok "testdata overleefde de herstart"
else
  fail "testdata was na de herstart weg"
fi

psql "DROP SCHEMA pleya_verify CASCADE;" >/dev/null
if [ -z "$(psql "SELECT 1 FROM information_schema.schemata WHERE schema_name='pleya_verify';")" ]; then
  ok "testschema opgeruimd, geen producttabel achtergelaten"
else
  fail "testschema staat er nog"
fi

# -------------------------------------------------------------- 10. database weg
section "10. database weg en terug"
wait_healthy pleya-server >/dev/null
$COMPOSE stop postgres >/dev/null 2>&1
sleep 3

[ "$(status "$BASE/healthz")" = "200" ] && ok "/healthz blijft 200 zonder database" || fail "/healthz = $(status "$BASE/healthz") zonder database"

ready_after() {
  local deadline=$((SECONDS + 60))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(status "$BASE/readyz")" = "$1" ] && return 0
    sleep 2
  done
  return 1
}

if ready_after 503; then ok "/readyz wordt 503 zonder database"; else fail "/readyz werd geen 503 (nu $(status "$BASE/readyz"))"; fi

$COMPOSE start postgres >/dev/null 2>&1
if ready_after 200; then ok "/readyz wordt weer 200 zonder rebuild"; else fail "/readyz kwam niet terug op 200"; fi

# ------------------------------------------------------- 11. graceful shutdown
section "11. graceful shutdown"
$COMPOSE stop -t 25 pleya-server >/dev/null 2>&1
code="$(docker inspect pleya-server --format '{{.State.ExitCode}}' 2>/dev/null)"
if [ "$code" = "0" ]; then ok "het Go-proces sloot met exitcode 0 op SIGTERM"; else fail "exitcode $code, verwacht 0"; fi
if $COMPOSE logs pleya-server 2>/dev/null | grep -q "afsluiten voltooid"; then
  ok "de server logde een nette afsluiting"
else
  fail "geen bewijs van een nette afsluiting in de log"
fi
$COMPOSE start pleya-server >/dev/null 2>&1
wait_healthy pleya-server >/dev/null

# ----------------------------------------------------------------- 12. secrets
section "12. secrets"
pw="$(grep -E '^POSTGRES_PASSWORD=' .env | cut -d= -f2)"
if git -C .. grep -qI --cached "$pw" 2>/dev/null; then
  fail "het wachtwoord staat in de git-index"
else
  ok "het wachtwoord staat niet in de git-index"
fi
if git -C .. check-ignore -q pleya_server/.env 2>/dev/null; then
  ok ".env wordt door .gitignore uitgesloten"
else
  fail ".env wordt NIET uitgesloten door .gitignore"
fi
if $COMPOSE logs 2>/dev/null | grep -q "$pw"; then
  fail "het wachtwoord staat in de containerlogs"
else
  ok "het wachtwoord staat niet in de containerlogs"
fi
if $COMPOSE logs pleya-server 2>/dev/null | grep -q '"database":"postgresql://postgres:5432/pleya"'; then
  ok "de startlog toont de database geredigeerd"
else
  note "de geredigeerde verbindingsreeks is niet teruggevonden in de log"
fi
# Eerlijk vastleggen wat .env wel en niet verbergt.
if docker inspect pleya-server --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -q "$pw"; then
  note "docker inspect toont het wachtwoord: bekend en aanvaard, zie README"
fi

# --------------------------------------------------------------- 13. postgres net
section "13. postgres niet geexposed"
if docker inspect pleya-server-db --format '{{json .HostConfig.PortBindings}}' 2>/dev/null | grep -q '{}'; then
  ok "postgres heeft geen hostpoort"
else
  fail "postgres heeft een hostpoort: $(docker inspect pleya-server-db --format '{{json .HostConfig.PortBindings}}')"
fi

# ------------------------------------------------------------------------ slot
cleanup

printf "\n%s%d geslaagd, %d gefaald%s\n" "$BOLD" "$PASSED" "$FAILED" "$RST"
[ "$FAILED" -eq 0 ]
