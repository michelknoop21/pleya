#!/usr/bin/env bash
# Hersteltest vanaf een kopie buiten de back-upmap (S25.7), op de testinstance.
#
# Wat het bewijst: een back-up die uit een externe kopie terugkomt is na een
# herstart weer bruikbaar, en de hersteltest slaagt erop. De kopie hier is een
# rsync naar een tweede map op de NAS, hetzelfde commando dat een geplande taak
# naar een andere schijf of machine zou draaien; de echte bestemming is een
# keuze van de beheerder.
#
# Alleen de testinstance wordt aangeraakt (/volume1/docker/pleya-server-test).
# De inloggegevens worden op de NAS gelezen en verlaten die niet.
#
#   pleya_server/scripts/offsite-restore-test.sh
set -euo pipefail

HOST="${SMOKE_SSH_HOST:-synology}"

ssh -o BatchMode=yes "$HOST" 'sh -s' <<'REMOTE'
D=/usr/local/bin/docker
T=/volume1/docker/pleya-server-test
OFF=/volume1/docker/pleya-server-test-offsite-sim
B=http://127.0.0.1:8833/pleya/v1
CRED=$T/test-credentials.txt
U=$(sed -n 's/^user[:=] *//p' "$CRED" | head -1); P=$(sed -n 's/^pass[:=] *//p' "$CRED" | head -1)
FAILS=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS + 1)); }
tok() { jq -n --arg u "$U" --arg p "$P" '{username:$u,password:$p}' | curl -s -m 60 -H 'Content-Type: application/json' -d @- "$B/auth/login" | jq -r .access_token; }
api() { curl -s -m 60 -H "Authorization: Bearer $A" "$@"; }
ready() { for i in $(seq 1 90); do curl -fsS -m 5 http://127.0.0.1:8833/readyz >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }
list() { api $B/backups | jq -r '.items[] | "\(.id) \(.status)"'; }

A=$(tok)
echo "== 1. verse back-up"
ID=$(api -X POST $B/backups | jq -r '.id')
for i in $(seq 1 60); do S=$(api $B/backups/$ID | jq -r .status); [ "$S" = ok ] && break; [ "$S" = failed ] && break; sleep 3; done
[ "$S" = ok ] && ok "back-up $ID is ok" || bad "back-up eindigde op $S"

echo "== 2. kopie buiten de back-upmap"
mkdir -p "$OFF" && rsync -a --chmod=F600 "$T/data/backups/" "$OFF/"
[ "$(cat "$T"/data/backups/*.tar | sha256sum)" = "$(cat "$OFF"/*.tar | sha256sum)" ] && ok "kopie is byte-gelijk" || bad "kopie wijkt af"

echo "== 3. de bron verliezen"
rm -f "$T"/data/backups/*.tar
(cd "$T" && $D restart pleya-server-test >/dev/null) && ready && A=$(tok)
[ "$(list | awk -v id=$ID '$1==id{print $2}')" = missing ] && ok "na verlies staat de back-up op missing" || bad "status na verlies is niet missing"

echo "== 4. terugzetten vanaf de kopie en herstarten"
cp -p "$OFF"/*.tar "$T/data/backups/" && chmod 600 "$T"/data/backups/*.tar
(cd "$T" && $D restart pleya-server-test >/dev/null) && ready && A=$(tok)
[ "$(list | awk -v id=$ID '$1==id{print $2}')" = ok ] && ok "teruggezette back-up staat weer op ok" || bad "teruggezette back-up staat niet op ok"

echo "== 5. hersteltest op de teruggezette kopie"
CODE=$(api -X POST $B/backups/$ID/verify -o /dev/null -w '%{http_code}')
[ "$CODE" = 202 ] && ok "verify aangenomen (202)" || bad "verify gaf $CODE"
for i in $(seq 1 60); do R=$(api $B/backups/$ID | jq -r '.last_restore_test.status // empty'); case "$R" in ok|failed) break;; esac; sleep 3; done
api $B/backups/$ID | jq -c '.last_restore_test | {status, titles_expected, titles_found, failure_code}' 2>/dev/null || true
[ "$R" = ok ] && ok "hersteltest slaagt op de kopie" || bad "hersteltest eindigde op '$R'"

echo
if [ "$FAILS" -eq 0 ]; then echo "OFF-SITE: alles groen"; else echo "OFF-SITE: $FAILS stap(pen) rood"; exit 1; fi
REMOTE
