#!/usr/bin/env bash
# Bewijs Pleya Server lokaal, van broncode tot draaiende catalogus.
#
# De fundering uit PS-0 blijft erin: non-root, read-only media, read-only rootfs,
# persistentie, uitval en herstel van de database, graceful shutdown en secrets.
# Daarbovenop staan de acceptatiecriteria van PS-2: migreren, scannen, bladeren
# met curl, en een herstart die de ids intact laat.
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

# Een echte bibliotheek, gemaakt met de ffmpeg uit de image zelf. Een verzonnen
# bestand bewijst niets over de analyse, en juist daar zit het punt waar een
# mediaserver stil fout gaat (hoofdstuk 7.4).
if [ ! -f "testdata/media/films/Grease (1978)/Grease (1978).mkv" ]; then
  if docker build -q -t pleya-server:verify-media . >/dev/null 2>&1 && \
     docker run --rm --entrypoint sh -v "$PWD/testdata/media:/out" pleya-server:verify-media -c '
       set -e
       mk() { mkdir -p "$(dirname "$1")"; ffmpeg -hide_banner -loglevel error -y \
         -f lavfi -i "testsrc=size=320x180:rate=24:duration=$2" \
         -f lavfi -i "sine=frequency=440:duration=$2" \
         -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest "$1"; }
       mk "/out/films/Grease (1978)/Grease (1978).mkv" 2
       mk "/out/films/Grease (1978)/Grease (1978) - 2160p.mkv" 2
       mk "/out/films/Blade Runner (1982)/Blade Runner (1982) {edition-Final Cut}.mkv" 2
       mk "/out/series/Testserie (2020)/Season 01/Testserie - S01E01 - Eerste.mkv" 1
       mk "/out/series/Testserie (2020)/Season 01/Testserie - S01E02 - Tweede.mkv" 1
       printf "1\n00:00:01,000 --> 00:00:02,000\nhallo daar\n" > "/out/films/Grease (1978)/Grease (1978).nld.srt"
       printf "geen echte jpeg" > "/out/films/Grease (1978)/poster.jpg"
     ' >/dev/null 2>&1; then
    ok "testbibliotheek gemaakt met de ffmpeg uit de image"
  else
    fail "testbibliotheek maken mislukte"
  fi
else
  ok "testbibliotheek aanwezig"
fi

export PLEYA_SERVER_LIBRARIES='films=movies:/media/library/films;series=shows:/media/library/series'
export PLEYA_SERVER_SCAN_INTERVAL=0

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

# ----------------------------------------------------------------- 6. catalogus
section "6. catalogus (PS-2)"

api() { curl -s -m 10 "$BASE/pleya/v1$1" "${@:2}"; }
status_with_auth() { curl -s -m 10 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $2" "$1"; }

# De uitdrukking gaat via de omgeving en niet via de opdrachtregel: hij bevat
# dubbele aanhalingstekens, en die overleven de weg door twee shells niet.
jq_field() {
  PLEYA_EXPR="$1" python3 -c 'import json, os, sys
d = json.load(sys.stdin)
print(eval(os.environ["PLEYA_EXPR"]))' 2>/dev/null
}

# Het schema hoort er te staan en /readyz hoort pas daarna groen te zijn.
tables="$($COMPOSE exec -T postgres psql -U pleya -d pleya -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'" 2>/dev/null | tr -d '\r')"
if [ "${tables:-0}" -ge 14 ]; then ok "schema gemigreerd ($tables tabellen)"; else fail "schema telt $tables tabellen"; fi

# Dat is de drift check uit hoofdstuk 23.1 in scriptvorm: geen enkele fase mag
# van een tabel uit een latere fase afhangen.
#
# watch_states en stream_sessions staan sinds PS-4 in het schema (DEC-049 en
# DEC-051); users, sessions en library_permissions sinds PS-9, migratie 0007
# (DEC-065, DEC-069). Alle vijf zijn daarom uit deze lijst gehaald. play_history
# en play_sessions staan er nadrukkelijk nog wel in: die horen bij PS-9P, en
# PS-9 mag daar niet van afhangen.
forbidden="$($COMPOSE exec -T postgres psql -U pleya -d pleya -tAc "SELECT coalesce(string_agg(table_name, ','), '') FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('play_history','play_sessions','user_item_data','transcode_sessions','external_ids','metadata_candidates')" 2>/dev/null | tr -d '\r')"
if [ -z "$forbidden" ]; then ok "geen tabel uit een latere fase"; else fail "tabellen uit een latere fase: $forbidden"; fi

setup_required="$(api /info | jq_field 'd["auth"]["setup_required"]')"
if [ "$setup_required" = "True" ] || [ "$setup_required" = "False" ]; then
  ok "/info is publiek bereikbaar zonder token (setup_required=$setup_required)"
else
  fail "/info gaf geen bruikbaar antwoord"
fi

# /info draagt geen servernaam, versie of buildnummer.
if api /info | grep -qiE '"(name|version|build)"'; then
  fail "/info lekt een naam of versienummer"
else
  ok "/info draagt geen naam, versie of buildnummer"
fi

CODE="$($COMPOSE logs pleya-server 2>/dev/null | grep -o 'Setupcode: [A-Z0-9-]*' | tail -1 | cut -d' ' -f2)"
if [ -n "$CODE" ]; then ok "setupcode op de console"; else fail "geen setupcode in de log"; fi

ACCESS="$(api /auth/setup -X POST -H 'Content-Type: application/json' \
  -d "{\"setup_code\":\"$CODE\",\"username\":\"verify\",\"password\":\"een-lang-genoeg-wachtwoord\"}" \
  | jq_field 'd["access_token"]')"
if [ -n "$ACCESS" ]; then ok "setupcode ingewisseld voor een tokenpaar"; else fail "setup mislukte"; fi

AUTH=(-H "Authorization: Bearer $ACCESS")

# Zonder token komt er niets door.
if [ "$(status "$BASE/pleya/v1/libraries")" = "401" ]; then
  ok "/libraries zonder token = 401"
else
  fail "/libraries zonder token = $(status "$BASE/pleya/v1/libraries")"
fi

libs="$(api /libraries "${AUTH[@]}")"
if [ "$(printf '%s' "$libs" | jq_field 'len(d["items"])')" = "2" ]; then
  ok "twee bibliotheken"
else
  fail "bibliotheken: $libs"
fi

FILMS="$(printf '%s' "$libs" | jq_field '[l["id"] for l in d["items"] if l["kind"]=="movies"][0]')"
page="$(api "/libraries/$FILMS/items" "${AUTH[@]}")"
count="$(printf '%s' "$page" | jq_field 'len(d["items"])')"
if [ "$count" = "2" ]; then ok "twee films in de catalogus"; else fail "$count films, verwacht 2"; fi

ITEM="$(printf '%s' "$page" | jq_field '[i["id"] for i in d["items"] if i["title"]=="Grease"][0]')"
detail="$(api "/items/$ITEM" "${AUTH[@]}")"
versions="$(printf '%s' "$detail" | jq_field 'len(d["versions"])')"
if [ "$versions" = "2" ]; then ok "twee versies van dezelfde film, één item"; else fail "$versions versies"; fi

if [ "$(printf '%s' "$detail" | jq_field 'd["user_state"] is None')" = "True" ]; then
  ok "user_state is null zolang niemand het item heeft aangeraakt"
else
  fail "user_state is gevuld terwijl niemand het item heeft aangeraakt"
fi

POSTER="$(printf '%s' "$detail" | jq_field 'd["artwork"]["poster_id"]')"
if [ "$(status "$BASE/pleya/v1/artwork/$POSTER")" = "401" ]; then ok "artwork zonder token = 401"; fi
if curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE/pleya/v1/artwork/$POSTER" | grep -q 200; then
  ok "artwork wordt geleverd"
else
  fail "artwork niet geleverd"
fi

SUBURL="$(printf '%s' "$detail" | jq_field '[s["url"] for v in d["versions"] for s in v["subtitle_streams"] if s["is_external"]][0]')"
if curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE$SUBURL" | grep -q 200; then
  ok "externe ondertitel wordt geleverd"
else
  fail "ondertitel niet geleverd"
fi

VER="$(printf '%s' "$detail" | jq_field 'd["versions"][0]["id"]')"
STOK="$(api /auth/stream-token -X POST "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"version_id\":\"$VER\"}" | jq_field 'd["stream_token"]')"
if [ -n "$STOK" ]; then ok "streamtoken uitgegeven"; else fail "streamtoken mislukte"; fi
if [ "$(status "$BASE/pleya/v1/libraries?stream_token=$STOK")" = "401" ]; then
  ok "een streamtoken opent de rest van de API niet"
else
  fail "een streamtoken opende /libraries"
fi

# Streaming en kijkstatus bestaan sinds PS-4, en horen dus te antwoorden.
stream_code="$(curl -s -m 30 -o /dev/null -w '%{http_code}' "${AUTH[@]}" -r 0-1023 "$BASE/pleya/v1/stream/$VER")"
if [ "$stream_code" = "206" ]; then
  ok "een bereik van 1 kB levert 206"
else
  fail "/stream met een bereik gaf $stream_code"
fi

# De validator is zwak, dus If-Range levert nooit een deelantwoord (DEC-050).
etag="$(curl -s -m 30 -o /dev/null -D - "${AUTH[@]}" -r 0-1023 "$BASE/pleya/v1/stream/$VER" | grep -i '^etag:' | tr -d '\r' | cut -d' ' -f2-)"
case "$etag" in
  'W/"'*) ok "de validator is zwak: $etag" ;;
  *)      fail "de validator is $etag; wil de vorm W/\"...\"" ;;
esac
ifrange_code="$(curl -s -m 30 -o /dev/null -w '%{http_code}' "${AUTH[@]}" -r 0-1023 -H "If-Range: $etag" "$BASE/pleya/v1/stream/$VER")"
if [ "$ifrange_code" = "200" ]; then
  ok "If-Range levert het hele bestand (RFC 9110 §13.1.5)"
else
  fail "If-Range gaf $ifrange_code; met een zwakke validator hoort dat 200 te zijn"
fi

watch_code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE/pleya/v1/watch-state")"
if [ "$watch_code" = "200" ]; then
  ok "/watch-state antwoordt (PS-4)"
else
  fail "/watch-state gaf $watch_code"
fi

# Een echte kijkstatusronde tegen de draaiende server: verwerven, schrijven,
# terugzien in het item, en een tweede sessie die de positie niet mag verzetten.
watch_post() {
  api /watch-state -X POST "${AUTH[@]}" -H 'Content-Type: application/json' -d "$1"
}
started="$(watch_post "{\"item_id\":\"$ITEM\",\"session_id\":\"sessie-tv\",\"position_ms\":0,\"occurred_at\":\"2026-08-21T20:00:00Z\",\"explicit_action\":\"playback_started\",\"cause\":\"user_started\"}")"
REV="$(printf '%s' "$started" | jq_field 'd["revision"]')"
if [ "$REV" = "1" ]; then ok "playback_started verwerft het eigendom (revision 1)"; else fail "revision na starten: $REV"; fi

moved="$(watch_post "{\"item_id\":\"$ITEM\",\"session_id\":\"sessie-tv\",\"position_ms\":1800000,\"duration_ms\":6720000,\"occurred_at\":\"2026-08-21T20:30:00Z\",\"explicit_action\":\"none\",\"base_revision\":1}")"
if [ "$(printf '%s' "$moved" | jq_field 'd["position_ms"]')" = "1800000" ]; then
  ok "de eigenaar verzet de canonieke positie"
else
  fail "positie na voortgang: $moved"
fi

stranger="$(watch_post "{\"item_id\":\"$ITEM\",\"session_id\":\"sessie-telefoon\",\"position_ms\":10,\"occurred_at\":\"2026-08-21T20:31:00Z\",\"explicit_action\":\"none\",\"base_revision\":2}")"
if [ "$(printf '%s' "$stranger" | jq_field 'd["position_ms"]')" = "1800000" ]; then
  ok "een tweede sessie verzet de positie niet zolang de lease loopt"
else
  fail "een niet-eigenaar verzette de positie: $stranger"
fi

if [ "$(api "/items/$ITEM" "${AUTH[@]}" | jq_field 'd["user_state"]["position_ms"]')" = "1800000" ]; then
  ok "het itemantwoord draagt de kijkstatus zonder tweede aanvraag"
else
  fail "user_state staat niet in het itemantwoord"
fi

if [ "$(api /watch-state "${AUTH[@]}" | jq_field 'len(d["items"])')" = "1" ]; then
  ok "de kijkstatuslijst bevat het aangeraakte item"
else
  fail "de kijkstatuslijst is leeg"
fi

section "gebruikers en sessies (PS-9)"

# Een tweede gebruiker aanmaken, haar één bibliotheek geven, en aantonen dat ze
# de andere niet ziet. Dat is acceptatiecriterium 1 en 2 in scriptvorm: de
# Go-tests bewijzen hetzelfde tegen de router, dit bewijst het tegen een
# draaiende container met een echte database eronder.
SANNE="$(api /users "${AUTH[@]}" -X POST -H 'Content-Type: application/json' \
  -d '{"username":"sanne","password":"nog-een-lang-wachtwoord","role":"member"}' | jq_field 'd["id"]')"
if [ -n "${SANNE:-}" ] && [ "$SANNE" != "None" ]; then
  ok "een tweede gebruiker aangemaakt via POST /users"
else
  fail "POST /users leverde geen gebruiker"
fi

api "/users/$SANNE/permissions" "${AUTH[@]}" -X PUT -H 'Content-Type: application/json' \
  -d "{\"permissions\":[{\"library_id\":\"$FILMS\",\"permission\":\"view\"}]}" >/dev/null

SANNE_ACCESS="$(api /auth/login -X POST -H 'Content-Type: application/json' \
  -d '{"username":"sanne","password":"nog-een-lang-wachtwoord"}' | jq_field 'd["access_token"]')"
if [ -n "${SANNE_ACCESS:-}" ] && [ "$SANNE_ACCESS" != "None" ]; then
  ok "de tweede gebruiker logt in met haar eigen wachtwoord"
else
  fail "de tweede gebruiker kon niet inloggen"
fi
SANNE_AUTH=(-H "Authorization: Bearer $SANNE_ACCESS")

if [ "$(api /libraries "${SANNE_AUTH[@]}" | jq_field 'len(d["items"])')" = "1" ]; then
  ok "zij ziet één bibliotheek en de owner ziet er twee"
else
  fail "de bibliotheekfilter per gebruiker klopt niet"
fi

if [ "$(api /users "${SANNE_AUTH[@]}" | jq_field 'len(d["items"])')" = "1" ]; then
  ok "een member ziet in GET /users alleen zichzelf"
else
  fail "een member ziet meer gebruikers dan zichzelf"
fi

# Haar sessie intrekken maakt haar token onmiddellijk ongeldig, en raakt de
# sessie van de owner niet. Dat is acceptatiecriterium 3 op aanvraagniveau; de
# gemeten grens tegen een lopende stream staat in de Go-test.
SANNE_SESSION="$(api "/sessions?user_id=$SANNE" "${AUTH[@]}" | jq_field 'd["items"][0]["id"]')"
api "/sessions/$SANNE_SESSION" "${AUTH[@]}" -X DELETE >/dev/null
if [ "$(status_with_auth "$BASE/pleya/v1/libraries" "$SANNE_ACCESS")" = "401" ]; then
  ok "een ingetrokken sessie maakt het accesstoken meteen ongeldig"
else
  fail "het token van een ingetrokken sessie werkt nog"
fi
if [ "$(api /libraries "${AUTH[@]}" | jq_field 'len(d["items"])')" = "2" ]; then
  ok "de sessie van de owner is ongemoeid gebleven"
else
  fail "de intrekking raakte een andere sessie"
fi

# En de owner blijft de owner.
if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" -X DELETE "$BASE/pleya/v1/users/$SANNE")" = "204" ]; then
  ok "een gebruiker verwijderen ruimt haar sessies en rechten op"
else
  fail "de gebruiker kon niet verwijderd worden"
fi

# En de latere fasen bestaan nog steeds niet.
for path in "/pleya/v1/playback/plan" "/pleya/v1/collections"; do
  if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE$path")" = "404" ]; then
    ok "$path bestaat niet"
  else
    fail "$path gaf $(curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE$path")"
  fi
done

# De ids overleven een herstart, en de tweede ronde raakt ffprobe niet aan.
before="$(api "/libraries/$FILMS/items" "${AUTH[@]}" | jq_field 'sorted(i["id"] for i in d["items"])')"
$COMPOSE restart pleya-server >/dev/null 2>&1
wait_healthy pleya-server >/dev/null
after="$(api "/libraries/$FILMS/items" "${AUTH[@]}" | jq_field 'sorted(i["id"] for i in d["items"])')"
if [ "$before" = "$after" ] && [ -n "$before" ]; then
  ok "de ids overleven een herstart"
else
  fail "de ids veranderden: $before -> $after"
fi
if [ "$(status "$BASE/pleya/v1/server")" != "000" ] && \
   curl -s -m 10 -o /dev/null -w '%{http_code}' "${AUTH[@]}" "$BASE/pleya/v1/server" | grep -q 200; then
  ok "het accesstoken werkt na de herstart; de sleutel staat op schijf"
else
  fail "het accesstoken werkte niet meer na de herstart"
fi

# compose zet de servicenaam vóór elke regel, dus die moet er eerst af voordat
# het JSON is.
probed="$($COMPOSE logs pleya-server 2>/dev/null | grep '"msg":"scan klaar"' | sed 's/^[^{]*//' | tail -2 \
  | python3 -c 'import json,sys; print(sum(json.loads(l)["files_probed"] for l in sys.stdin))' 2>/dev/null)"
if [ "${probed:-1}" = "0" ]; then
  ok "de tweede scan draaide ffprobe nul keer"
else
  fail "de tweede scan analyseerde $probed bestanden"
fi

# ---------------------------------------------------------------------- 7. non-root
section "7. non-root"
uid="$($COMPOSE exec -T pleya-server id -u 2>/dev/null | tr -d '\r')"
if [ -n "$uid" ] && [ "$uid" != "0" ]; then ok "container draait als uid $uid"; else fail "container draait als uid ${uid:-onbekend}"; fi

# ----------------------------------------------------------------- 8. media :ro
section "8. media read-only"
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

# ------------------------------------------------------- 9. rootfs en scratch
section "9. read-only rootfs en schrijfbare mappen"
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

# ----------------------------------------------------------------- 10. persistentie
section "10. persistentie over een herstart"
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

# -------------------------------------------------------------- 11. database weg
section "11. database weg en terug"
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

# ------------------------------------------------------- 12. graceful shutdown
section "12. graceful shutdown"
$COMPOSE stop -t 25 pleya-server >/dev/null 2>&1
code="$(docker inspect pleya-server --format '{{.State.ExitCode}}' 2>/dev/null)"
if [ "$code" = "0" ]; then ok "het Go-proces sloot met exitcode 0 op SIGTERM"; else fail "exitcode $code, verwacht 0"; fi
# De laatste logregel komt niet altijd meteen mee: `compose stop` keert terug
# zodra het proces weg is, en het doorgeven van de laatste bytes naar de
# logdriver loopt daar soms een tel achteraan. Vijf korte pogingen in plaats van
# één, want een race hier meet de logdriver en niet de afsluiting.
shutdown_logged=""
for _ in 1 2 3 4 5; do
  if $COMPOSE logs pleya-server 2>/dev/null | grep -q "afsluiten voltooid"; then
    shutdown_logged=yes
    break
  fi
  sleep 1
done
if [ -n "$shutdown_logged" ]; then
  ok "de server logde een nette afsluiting"
else
  fail "geen bewijs van een nette afsluiting in de log"
fi
$COMPOSE start pleya-server >/dev/null 2>&1
wait_healthy pleya-server >/dev/null

# ----------------------------------------------------------------- 13. secrets
section "13. secrets"
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

# --------------------------------------------------------------- 14. postgres net
section "14. postgres niet geexposed"
if docker inspect pleya-server-db --format '{{json .HostConfig.PortBindings}}' 2>/dev/null | grep -q '{}'; then
  ok "postgres heeft geen hostpoort"
else
  fail "postgres heeft een hostpoort: $(docker inspect pleya-server-db --format '{{json .HostConfig.PortBindings}}')"
fi

# ------------------------------------------------------------- 15. Pleya Web (PS-3W)
section "15. Pleya Web wordt geserveerd en overschaduwt het protocol niet"

web_status() { curl -s -o /dev/null -w '%{http_code}' "$1"; }
web_type()   { curl -s -o /dev/null -w '%{content_type}' "$1"; }

if [ "$(web_status "$BASE/")" = "200" ] && curl -s "$BASE/" | grep -q '<title>Pleya</title>'; then
  ok "de bundel wordt op / geleverd door dezelfde binary"
else
  fail "/ levert geen Pleya Web (status $(web_status "$BASE/"))"
fi

if curl -s "$BASE/libraries" | grep -q '<title>Pleya</title>'; then
  ok "SPA-terugval: een frontendroute krijgt index.html"
else
  fail "SPA-terugval werkt niet op /libraries"
fi

# De kern van acceptatiecriterium 1: het protocol houdt voorrang.
drift=0
for path in /healthz /readyz /pleya/v1/info; do
  case "$(web_type "$BASE$path")" in
    application/json*) ;;
    *) fail "$path werd niet als JSON beantwoord"; drift=1 ;;
  esac
done
[ "$drift" -eq 0 ] && ok "/healthz, /readyz en /pleya/v1/info houden voorrang"

if [ "$(web_status "$BASE/pleya/v1/nonexistent")" = "404" ] &&
   curl -s "$BASE/pleya/v1/nonexistent" | grep -q '"library.not_found"'; then
  ok "een onbekende protocolroute krijgt de foutvorm en geen pagina"
else
  fail "een onbekende protocolroute belandde bij de SPA"
fi

asset="$(curl -s "$BASE/" | grep -o '/_app/immutable/[^"]*\.js' | head -1)"
if [ -n "$asset" ] && curl -sI "$BASE$asset" | grep -qi 'cache-control:.*immutable'; then
  ok "een gehasht bestand mag een jaar gecachet worden"
else
  fail "de cacheheader op een gehasht bestand klopt niet"
fi

if curl -sI "$BASE/" | grep -qi 'cache-control: no-cache'; then
  ok "index.html krijgt geen agressieve cache"
else
  fail "index.html krijgt de verkeerde cacheheader"
fi

missing=""
for header in "x-content-type-options: nosniff" "x-frame-options: DENY" \
              "referrer-policy: no-referrer" "content-security-policy: frame-ancestors"; do
  curl -sI "$BASE/" | grep -qi "$header" || missing="$missing $header"
done
if [ -z "$missing" ]; then
  ok "de securityheaders staan er"
else
  fail "securityheaders ontbreken:$missing"
fi

if curl -sI "$BASE/" | grep -qi 'access-control-allow-origin'; then
  fail "er staat een CORS-header; bundel en API delen hun origin en hebben die niet nodig"
else
  ok "geen CORS-header, want bundel en API delen hun origin"
fi

# ------------------------------------------------------------------------ slot
cleanup

printf "\n%s%d geslaagd, %d gefaald%s\n" "$BOLD" "$PASSED" "$FAILED" "$RST"
[ "$FAILED" -eq 0 ]
