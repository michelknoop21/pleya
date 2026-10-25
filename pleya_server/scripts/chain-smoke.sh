#!/usr/bin/env bash
# Rooktest van de hele keten tegen de testinstance op de NAS:
# bibliotheken, metadata en artwork, zoeken, direct play met range, hervatten
# op een tweede toestel, transcode (HLS) en download met digest.
#
# De testinstance luistert alleen op 127.0.0.1 van de NAS en `ssh -L` werkt niet
# door DSM, dus de aanvragen lopen op de NAS zelf. De inloggegevens worden daar
# uit test-credentials.txt gelezen en verlaten de NAS niet. Alleen de testinstance
# is een doel; productie wordt hier nooit aangeraakt.
#
#   pleya_server/scripts/chain-smoke.sh
#
# Omgevingsvariabelen: SMOKE_DOWNLOAD_QUERY (zoekterm voor een klein bestand,
# standaard "Jokie"), SMOKE_SSH_HOST (standaard synology).
set -euo pipefail

HOST="${SMOKE_SSH_HOST:-synology}"
QUERY="${SMOKE_DOWNLOAD_QUERY:-Jokie}"

ssh -o BatchMode=yes "$HOST" "SMOKE_DOWNLOAD_QUERY='$QUERY' sh -s" <<'REMOTE'
B=http://127.0.0.1:8833/pleya/v1
CRED=/volume1/docker/pleya-server-test/test-credentials.txt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILS=0
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
info() { echo "INFO  $1"; }
check() { if [ "$2" = "1" ]; then ok "$1"; else bad "$1"; fi; }

U=$(sed -n 's/^user[:=] *//p' "$CRED" | head -1)
P=$(sed -n 's/^pass[:=] *//p' "$CRED" | head -1)

login() { # $1 = device id
  jq -n --arg u "$U" --arg p "$P" --arg d "$1" '{username:$u,password:$p,device_id:$d,device_name:$d}' \
    | curl -s -m 120 -H 'Content-Type: application/json' -d @- "$B/auth/login" | jq -r '.access_token // empty'
}
get()  { curl -s -m 120 -H "Authorization: Bearer $2" "$B$1"; }                  # path token
post() { curl -s -m 120 -H "Authorization: Bearer $3" -H 'Content-Type: application/json' -d "$2" "$B$1"; } # path body token

echo "== 1. server en inloggen"
INFO=$(curl -s -m 30 "$B/info")
for c in browse search artwork watch_state playback_plan transcode downloads watch_state_ownership filters; do
  check "capability $c" "$(echo "$INFO" | jq -r --arg c "$c" '.capabilities[$c] == true' | sed 's/true/1/;s/false/0/')"
done
TA=$(login smoke-device-a); TB=$(login smoke-device-b)
check "twee toestellen loggen in" "$([ -n "$TA" ] && [ -n "$TB" ] && echo 1 || echo 0)"
[ -n "$TA" ] || { echo "geen token, afbreken"; exit 1; }

echo "== 2. scan en bibliotheken"
LIBS=$(get /libraries "$TA")
echo "$LIBS" | jq -r '.items[] | "INFO  bibliotheek \(.title) (\(.kind)): \(.item_count) items"'
check "elke bibliotheek heeft items" "$(echo "$LIBS" | jq '[.items[] | .item_count > 0] | all | if . then 1 else 0 end')"
MOVIES=$(echo "$LIBS" | jq -r '[.items[] | select(.kind=="movies")][0].id')

echo "== 3. metadata en artwork"
PAGE=$(get "/libraries/$MOVIES/items?limit=100" "$TA")
N=$(echo "$PAGE" | jq '.items | length')
POSTER=$(echo "$PAGE" | jq '[.items[] | select(.artwork.poster_id != null)] | length')
SUMMARY=$(echo "$PAGE" | jq '[.items[] | select((.summary // "") != "")] | length')
GENRES=$(echo "$PAGE" | jq '[.items[] | select((.genres // []) | length > 0)] | length')
info "eerste $N films: poster $POSTER, samenvatting $SUMMARY, genres $GENRES"
check "minstens 80% heeft een poster" "$([ "$POSTER" -ge $((N * 8 / 10)) ] && echo 1 || echo 0)"
check "minstens 50% heeft een samenvatting" "$([ "$SUMMARY" -ge $((N / 2)) ] && echo 1 || echo 0)"
PID=$(echo "$PAGE" | jq -r '[.items[] | select(.artwork.poster_id != null)][0].artwork.poster_id')
CODE=$(curl -s -m 60 -o "$TMP/art" -w '%{http_code} %{content_type} %{size_download}' -H "Authorization: Bearer $TA" "$B/artwork/$PID?width=300")
info "artwork $CODE"
check "artwork komt als afbeelding" "$(echo "$CODE" | awk '$1==200 && $2 ~ /^image\// && $3>0 {print 1; exit} {print 0}' | head -1)"

echo "== 4. zoeken"
ITEM=$(echo "$PAGE" | jq -c '[.items[] | select(.versions | length > 0)][0]')
IID=$(echo "$ITEM" | jq -r .id); TITLE=$(echo "$ITEM" | jq -r .title)
WORD=$(echo "$TITLE" | awk '{print $1}')
FOUND=$(curl -s -m 60 -G -H "Authorization: Bearer $TA" --data-urlencode "q=$WORD" "$B/search" | jq --arg id "$IID" '[.items[].id] | index($id) != null')
check "zoeken op \"$WORD\" vindt \"$TITLE\"" "$([ "$FOUND" = true ] && echo 1 || echo 0)"

echo "== 5. direct play"
CAPS='{"decoder":{"video_codecs":{"value":["h264","hevc","av1","vp9","mpeg4"],"confidence":"confirmed"},"audio_codecs":{"value":["aac","ac3","eac3","dts","mp3","flac","opus","truehd"],"confidence":"confirmed"},"containers":{"value":["mkv","mp4","matroska","mov"],"confidence":"confirmed"}}}'
PLAN=$(post /playback/plan "$(jq -n --arg i "$IID" --argjson c "$CAPS" '{item_id:$i,capabilities:$c}')" "$TA")
MODE=$(echo "$PLAN" | jq -r '.delivery_mode // .error.code // "?"')
info "plan voor \"$TITLE\": $MODE"
check "plan is direct_play" "$([ "$MODE" = direct_play ] && echo 1 || echo 0)"
VID=$(echo "$PLAN" | jq -r '.version_id // empty')
H1=$(curl -s -m 60 -D - -o /dev/null -r 0-1023 -H "Authorization: Bearer $TA" "$B/stream/$VID")
echo "$H1" | head -1 | grep -q ' 206' && ok "range 0-1023 geeft 206" || bad "range 0-1023 geeft 206"
TOTAL=$(echo "$H1" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Rr]ange: bytes [0-9]*-[0-9]*\/\([0-9]*\).*/\1/p')
echo "$H1" | tr -d '\r' | grep -qi '^etag: W/' && ok "ETag is zwak (W/)" || bad "ETag is zwak (W/)"
MID=$((TOTAL / 2))
H2=$(curl -s -m 60 -D - -o /dev/null -r "$MID-$((MID + 1023))" -H "Authorization: Bearer $TA" "$B/stream/$VID")
echo "$H2" | head -1 | grep -q ' 206' && ok "seek naar het midden geeft 206" || bad "seek naar het midden geeft 206"

echo "== 6. hervatten en kijkstatus op een tweede toestel"
SID=$(cat /proc/sys/kernel/random/uuid)
NOW() { date -u +%Y-%m-%dT%H:%M:%SZ; }
EV() { jq -n --arg i "$IID" --arg s "$SID" --arg t "$(NOW)" --argjson p "$1" --arg a "$2" --argjson r "${3:-null}" \
  '{item_id:$i,session_id:$s,position_ms:$p,duration_ms:7200000,occurred_at:$t,explicit_action:$a} + (if $a=="playback_started" then {cause:"user_started"} else {} end) + (if $r != null then {base_revision:$r} else {} end)'; }
S0=$(post /watch-state "$(EV 0 playback_started)" "$TA")
REV=$(echo "$S0" | jq '.revision // 0')
S1=$(post /watch-state "$(EV 600000 none "$REV")" "$TA")
info "toestel A schreef positie $(echo "$S1" | jq -r .position_ms) ms, revision $(echo "$S1" | jq -r .revision)"
SEEN=$(get "/items/$IID" "$TB" | jq -r '.user_state.position_ms // "geen"')
check "toestel B ziet positie 600000" "$([ "$SEEN" = 600000 ] && echo 1 || echo 0)"
HIST=$(get "/history?limit=5" "$TB" | jq --arg id "$IID" '[.items[]? | (.item.id // .item_id // .id)] | index($id) != null')
info "item staat in de geschiedenis van toestel B: $HIST"
post /watch-state "$(EV 0 mark_unwatched)" "$TA" >/dev/null

echo "== 7. transcode"
NOH264='{"decoder":{"video_codecs":{"value":["h264"],"confidence":"confirmed"},"audio_codecs":{"value":["aac"],"confidence":"confirmed"},"containers":{"value":["mp4"],"confidence":"confirmed"}}}'
TID=""
for cand in $(echo "$PAGE" | jq -r '[.items[] | select(.versions | length > 0)][0:25][].id'); do
  TP=$(curl -s -m 120 -w '\n%{time_total}' -H "Authorization: Bearer $TA" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg i "$cand" --argjson c "$NOH264" '{item_id:$i,capabilities:$c}')" "$B/playback/plan")
  PLAN_T=$(echo "$TP" | tail -1); TP=$(echo "$TP" | sed '$d')
  M=$(echo "$TP" | jq -r '.delivery_mode // "?"')
  if [ "$M" != direct_play ] && [ "$M" != "?" ]; then TID=$cand; break; fi
done
if [ -z "$TID" ]; then bad "geen film in de eerste 25 die een omzetting vraagt"; else
  URL=$(echo "$TP" | jq -r .stream_url); SES=$(echo "$TP" | jq -r .session_id)
  info "omzetten ($M) gestart, sessie $SES, plan-aanvraag (tot de eerste segmenten klaarstaan) $PLAN_T s"
  T0=$(curl -s -m 120 -o "$TMP/pl" -w '%{http_code} %{time_total}' -H "Authorization: Bearer $TA" "$B${URL#/pleya/v1}")
  info "afspeellijst $T0 s"
  SEG=$(grep -v '^#' "$TMP/pl" | head -1)
  if [ -n "$SEG" ]; then
    SEGT=$(curl -s -m 120 -o "$TMP/seg" -w '%{http_code} %{time_total} %{size_download}' -H "Authorization: Bearer $TA" "$(dirname "$B${URL#/pleya/v1}")/$SEG")
    info "eerste segment (code, seconden, bytes): $SEGT"
    check "eerste segment is geleverd" "$(echo "$SEGT" | awk '$1==200 && $3>0 {print 1; exit} {print 0}' | head -1)"
  else bad "afspeellijst bevat geen segment"; fi
  curl -s -m 30 -X DELETE -H "Authorization: Bearer $TA" "$B/playback/sessions/$SES" -o /dev/null -w 'INFO  sessie opgeruimd: %{http_code}\n'
fi

echo "== 8. download met digest"
SR=$(curl -s -m 60 -G -H "Authorization: Bearer $TA" --data-urlencode "q=$SMOKE_DOWNLOAD_QUERY" "$B/search" | jq -c '[.items[] | select(.versions | length > 0)][0]')
DI=$(echo "$SR" | jq -r '.id // empty'); DV=$(echo "$SR" | jq -r '.versions[0].id // empty')
if [ -z "$DI" ]; then bad "geen item voor \"$SMOKE_DOWNLOAD_QUERY\""; else
  DL=$(post /downloads "$(jq -n --arg i "$DI" --arg v "$DV" '{item_id:$i,version_id:$v}')" "$TA")
  DID=$(echo "$DL" | jq -r .id); n=0
  while [ "$(echo "$DL" | jq -r .status)" = preparing ] && [ $n -lt 60 ]; do sleep 2; n=$((n + 1)); DL=$(get "/downloads/$DID" "$TA"); done
  info "download $(echo "$DL" | jq -r .status), $(echo "$DL" | jq -r .size_bytes) bytes"
  EXP=$(echo "$DL" | jq -r '.sha256 // empty')
  check "server noemt een SHA-256" "$([ -n "$EXP" ] && echo 1 || echo 0)"
  FURL=$(echo "$DL" | jq -r .file_url)
  GOT=$(curl -s -m 600 -H "Authorization: Bearer $TA" "http://127.0.0.1:8833$FURL" | sha256sum | cut -d' ' -f1)
  check "gedownload bestand heeft de genoemde SHA-256" "$([ "$GOT" = "$EXP" ] && echo 1 || echo 0)"
  RH=$(curl -s -m 60 -D - -o /dev/null -r 0-1023 -H "Authorization: Bearer $TA" "http://127.0.0.1:8833$FURL")
  echo "$RH" | head -1 | grep -q ' 206' && ok "download-range geeft 206" || bad "download-range geeft 206"
  curl -s -m 30 -X DELETE -H "Authorization: Bearer $TA" "$B/downloads/$DID" -o /dev/null -w 'INFO  download opgeruimd: %{http_code}\n'
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "KETEN: alles groen"; else echo "KETEN: $FAILS stap(pen) rood"; exit 1; fi
REMOTE
