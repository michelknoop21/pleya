#!/usr/bin/env bash
# tvOS-simulator harnas: bouwen, draaien, bedienen en verifiëren zonder
# TestFlight-ronde.
#
# Waarom dit bestaat: alleen dictatie is niet simuleerbaar (DEC-009). Al het
# andere aan tvOS-invoer wél — juist de dingen die anders pas op een echt
# toestel opvallen, zoals of Menu een scherm sluit. Zie DEC-011: een bug die
# twee TestFlight-builds overleefde was hier in één run zichtbaar.
#
#   scripts/tvos_sim.sh doctor           # kan ik knoppen sturen?
#   scripts/tvos_sim.sh build            # xcodebuild voor de simulator
#   scripts/tvos_sim.sh run              # boot + install + launch
#   scripts/tvos_sim.sh login            # demoserver koppelen (incl. Quick Connect)
#   scripts/tvos_sim.sh goto search      # deterministisch navigeren
#   scripts/tvos_sim.sh type "sintel"    # tekst typen (leestekens kloppen)
#   scripts/tvos_sim.sh key menu         # één toets
#   scripts/tvos_sim.sh keys down down select
#   scripts/tvos_sim.sh shot out.png     # screenshot (werkt ook vergrendeld)
#   scripts/tvos_sim.sh logs NativeText  # gefilterde log, laatste 30s
#   scripts/tvos_sim.sh wait "cancel"    # wacht tot een logregel verschijnt
#   scripts/tvos_sim.sh check-keyboard   # regressietest: Menu sluit het toetsenbord
#
# Eén randvoorwaarde: knoppen sturen vereist een ONTGRENDELD, WAKKER scherm.
# Staat het scherm uit, dan heeft Simulator geen venster en verdwijnen
# toetsaanslagen geruisloos — geen foutmelding, ze doen gewoon niets. `doctor`
# zegt het expliciet. Screenshots en logs werken altijd.
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE_ID="nl.michelknoop.pleya"
APP="tvos/build/dd/Build/Products/Debug-appletvsimulator/Runner.app"
# Screenshots buiten de repo: het simulator-proces mag daar niet schrijven
# (TCC weigert het met een misleidende "You don't have permission"), en ze
# horen er ook niet thuis. Overrule met TVOS_SIM_SHOT_DIR.
SHOT_DIR="${TVOS_SIM_SHOT_DIR:-${TMPDIR:-/tmp}}"

die() { echo "FOUT: $*" >&2; exit 1; }
note() { echo "· $*"; }

# Een al draaiend toestel wint (dat is wat je op je scherm ziet), anders de
# nieuwste Apple TV 4K. Overrule met TVOS_SIM_UDID.
resolve_device() {
  if [[ -n "${TVOS_SIM_UDID:-}" ]]; then DEVICE="$TVOS_SIM_UDID"; return; fi
  DEVICE="$(xcrun simctl list devices | awk '/^-- tvOS/{tv=1; next} /^--/{tv=0} tv && /Booted/ {print}' \
    | head -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)"
  [[ -n "$DEVICE" ]] && return
  # BSD-awk kent geen 3-argument match(), dus filteren en dan grep'en.
  DEVICE="$(xcrun simctl list devices available \
    | awk '/^-- tvOS/{tv=1; next} /^--/{tv=0} tv && /Apple TV 4K \(3rd generation\) \(/ && !/1080p/ {print}' \
    | tail -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)"
  [[ -n "$DEVICE" ]] || die "geen tvOS-simulator gevonden (xcrun simctl list devices)"
}

boot() {
  xcrun simctl list devices | grep -q "$DEVICE.*Booted" || xcrun simctl boot "$DEVICE"
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
}

# idb injecteert HID-events rechtstreeks in de simulator: geen venster, geen
# focus-diefstal, werkt met een vergrendeld scherm. Zonder idb valt alles terug
# op AppleScript, en dat stuurt naar de vóórste app — dus het Simulator-venster
# moet dan zichtbaar zijn en je verliest je focus bij elke druk.
IDB_READY=""
idb_available() {
  [[ -n "$IDB_READY" ]] && return "$IDB_READY"
  if command -v idb >/dev/null 2>&1 && idb connect "$DEVICE" >/dev/null 2>&1; then
    IDB_READY=0
  else
    IDB_READY=1
  fi
  return "$IDB_READY"
}

# HID usage codes; de tvOS-simulator vertaalt die naar de afstandsbediening.
hid_code_for() {
  case "$1" in
    up) echo 82 ;; down) echo 81 ;; left) echo 80 ;; right) echo 79 ;;
    select|enter|return) echo 40 ;;
    menu|back|escape) echo 41 ;;
    delete|backspace) echo 42 ;;
    *) die "onbekende toets: $1" ;;
  esac
}

# Simulator kan alleen een venster tonen op een wakker, ontgrendeld scherm, en
# zonder venster landen toetsaanslagen nergens.
window_input_available() {
  caffeinate -u -t 1 >/dev/null 2>&1 || true
  open -a Simulator >/dev/null 2>&1 || true
  local n deadline=$((SECONDS + 8))
  while ((SECONDS < deadline)); do
    n="$(osascript -e 'tell application "System Events" to get count of windows of process "Simulator"' 2>/dev/null || echo 0)"
    [[ "${n:-0}" != "0" ]] && return 0
    sleep 1
  done
  return 1
}

input_available() { idb_available || window_input_available; }

require_input() {
  input_available || die "geen invoer mogelijk — installeer idb of ontgrendel het Mac-scherm. Zie: $0 doctor"
}

key_code_for() {
  case "$1" in
    up) echo 126 ;; down) echo 125 ;; left) echo 123 ;; right) echo 124 ;;
    select|enter|return) echo 36 ;;
    menu|back|escape) echo 53 ;;
    delete|backspace) echo 51 ;;
    *) die "onbekende toets: $1" ;;
  esac
}

send_code() {
  local using=""
  [[ "${2:-}" == "shift" ]] && using=" using shift down"
  osascript -e 'tell application "Simulator" to activate' \
            -e "tell application \"System Events\" to key code $1$using" >/dev/null 2>&1
}

send_key() {
  if idb_available; then
    IDB_UDID="$DEVICE" idb ui key "$(hid_code_for "$1")" >/dev/null 2>&1 && return 0
  fi
  send_code "$(key_code_for "$1")"
}

# De simulator vertaalt sommige leestekens verkeerd (een getypte '.' komt aan
# als ','), dus die gaan per key code. Letters en cijfers mogen gewoon.
special_code_for() {
  case "$1" in
    .) echo 47 ;; ,) echo 43 ;; /) echo 44 ;; -) echo 27 ;; \;) echo 41 ;;
    :) echo "41 shift" ;; !) echo "18 shift" ;; _) echo "27 shift" ;; \?) echo "44 shift" ;;
    *) echo "" ;;
  esac
}

type_text() {
  local text="$1" i ch run=""
  if idb_available; then
    IDB_UDID="$DEVICE" idb ui text "$text" >/dev/null 2>&1 && return 0
  fi
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    local code; code="$(special_code_for "$ch")"
    if [[ -n "$code" ]]; then
      [[ -n "$run" ]] && { osascript -e 'tell application "Simulator" to activate' \
        -e "tell application \"System Events\" to keystroke \"$run\"" >/dev/null 2>&1; run=""; }
      send_code $code
    else
      run+="$ch"
    fi
  done
  [[ -n "$run" ]] && osascript -e 'tell application "Simulator" to activate' \
    -e "tell application \"System Events\" to keystroke \"$run\"" >/dev/null 2>&1
  return 0
}

# Dart-logs komen binnen als "(Flutter) flutter:", native NSLog als "(Foundation)".
read_logs() {
  local pattern="${1:-}" window="${2:-30}"
  xcrun simctl spawn "$DEVICE" log show --last "${window}s" --style compact \
    --predicate "processImagePath CONTAINS \"Runner\"" 2>/dev/null \
    | { [[ -n "$pattern" ]] && grep -E "$pattern" || cat; } \
    | sed 's/.*Runner\[[0-9:a-z]*\] //'
}

wait_for_log() {
  local pattern="$1"
  local timeout="${2:-15}"
  local deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    read_logs "$pattern" 12 | grep -q . && return 0
    sleep 1
  done
  return 1
}

# Aantal keer dat een patroon in het recente logvenster voorkomt. De log is een
# terugblik, geen stream, dus "is het er al?" is onbetrouwbaar — vergelijken met
# een nulmeting wél.
count_log() { read_logs "$1" "${2:-60}" | wc -l | tr -d ' '; }

wait_for_more() {
  local pattern="$1" baseline="$2"
  local timeout="${3:-20}"
  local deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    (( $(count_log "$pattern") > baseline )) && return 0
    sleep 1
  done
  return 1
}

# Deterministisch naar een tab, ongeacht waar de app stond: eerst met Menu
# terug naar de root, dan naar de sidebar en vanaf de bovenste tab omlaag.
goto_tab() {
  local target="$1" index
  case "$target" in
    home) index=0 ;; movies) index=1 ;; search|zoeken) index=2 ;; settings|opties) index=3 ;;
    *) die "onbekend tabblad: $target (home|movies|search|settings)" ;;
  esac
  require_input
  # Hooguit twee keer Menu: dat verlaat een detailscherm of overlay, maar méér
  # drukken zet de app op de tvOS-thuisscherm en dan wordt de eerstvolgende
  # select opgesnoept door het heropenen van de app.
  local i
  for i in 1 2; do send_key menu; sleep 0.9; done
  send_key left; sleep 1.2
  for i in 1 2 3; do send_key up; sleep 0.4; done
  for ((i = 0; i < index; i++)); do send_key down; sleep 0.5; done
  send_key select; sleep 4
}

load_env() {
  [[ -f .env ]] && set -a && . ./.env && set +a || true
}

do_login() {
  local url="${1:-${PLEYA_DEMO_URL:-demo.pleya.app}}"
  load_env
  [[ -n "${PLEYA_DEMO_USER:-}" && -n "${PLEYA_DEMO_PASS:-}" ]] \
    || die "zet PLEYA_DEMO_URL/USER/PASS in .env (gitignored)"
  require_input

  # Verwacht het scherm "Jellyfin-server toevoegen" met het URL-veld gefocust.
  # Focusvolgorde daaronder: serverkaart, gebruikersnaam, wachtwoord, inloggen.
  note "server-URL invoeren"
  type_text "$url"
  sleep 1
  note "server zoeken"
  send_key down; sleep 0.7; send_key select
  sleep 9

  # Terug naar de bovenkant en dan omlaag tellen: na het vinden van de server
  # staat de focus niet op een vaste plek, maar de volgorde eronder wel
  # (URL, serverkaart, gebruikersnaam, wachtwoord, inloggen).
  note "gebruikersnaam"
  local i; for i in 1 2 3 4 5; do send_key up; sleep 0.35; done
  send_key down; sleep 0.7; send_key down; sleep 0.9
  send_key select; sleep 3
  type_text "$PLEYA_DEMO_USER"; sleep 1
  send_key return; sleep 2.5

  note "wachtwoord"
  send_key down; sleep 0.9
  send_key select; sleep 3
  type_text "$PLEYA_DEMO_PASS"; sleep 1
  send_key return; sleep 2.5

  note "inloggen"
  send_key down; sleep 0.9; send_key select
  sleep 10
  echo "klaar — controleer met: $0 shot"
}

# Regressietest voor DEC-011: het toetsenbord moet met Menu te sluiten zijn.
check_keyboard() {
  require_input
  note "naar het zoekscherm"
  goto_tab search

  # Navigeren door een TV-UI is niet volledig deterministisch (de focus kan op
  # de sidebar of op een rij landen), dus één herkansing voordat we het een
  # echte fout noemen.
  local attach_before finish_before attempt opened=0
  for attempt in 1 2; do
    attach_before="$(count_log 'attach becameFirstResponder')"
    note "zoekbalk selecteren → systeemtoetsenbord (poging $attempt)"
    send_key select
    if wait_for_more 'attach becameFirstResponder' "$attach_before" 15; then opened=1; break; fi
    note "geen toetsenbord; opnieuw navigeren"
    goto_tab search
  done
  if ((opened == 0)); then
    echo "MISLUKT: het toetsenbord ging niet open"
    read_logs "NativeTextEntry" 40 | tail -5
    return 1
  fi

  finish_before="$(count_log 'finish submitted')"
  note "Menu indrukken"
  send_key menu
  if ! wait_for_more 'finish submitted' "$finish_before" 20; then
    echo "MISLUKT: Menu sloot het toetsenbord niet — sessie loopt nog"
    read_logs "NativeTextEntry" 40 | tail -8
    return 1
  fi
  echo "GESLAAGD: Menu sluit het systeemtoetsenbord en beëindigt de sessie"
  read_logs "NativeTextEntry" 40 | tail -4
}

resolve_device
case "${1:-}" in
  doctor)
    echo "toestel:   $DEVICE"
    echo "app-build: $([[ -d $APP ]] && echo aanwezig || echo 'ontbreekt — draai: scripts/tvos_sim.sh build')"
    boot
    if idb_available; then
      echo "invoer:    OK via idb — geen venster nodig, pikt je focus niet af"
    elif window_input_available; then
      echo "invoer:    OK via AppleScript — LET OP: elke druk activeert Simulator en"
      echo "           pakt je focus. Installeer idb om dat te voorkomen:"
      echo "           brew trust facebook/fb && brew install idb-companion && pip install fb-idb"
    else
      echo "invoer:    NIET beschikbaar. Geen idb, en het Mac-scherm is vergrendeld of"
      echo "           slaapt — dan toont Simulator geen venster en verdwijnen toetsen"
      echo "           geruisloos. Installeer idb, of ontgrendel het scherm."
      echo "           Screenshots en logs werken ondertussen wel."
    fi
    load_env
    echo "demo-login: $([[ -n "${PLEYA_DEMO_USER:-}" ]] && echo 'PLEYA_DEMO_* gezet' || echo 'ontbreekt in .env')"
    ;;
  build)
    xcodebuild -workspace tvos/Runner.xcworkspace -scheme Runner -configuration Debug \
      -destination 'generic/platform=tvOS Simulator' -derivedDataPath tvos/build/dd \
      build CODE_SIGNING_ALLOWED=NO
    ;;
  run)
    boot
    [[ -d "$APP" ]] || die "geen build op $APP — draai eerst: $0 build"
    open -a Simulator >/dev/null 2>&1 || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$DEVICE" "$APP"
    xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
    ;;
  reset)
    boot
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "app verwijderd — volgende 'run' start met schone staat"
    ;;
  shot)  out="${2:-${SHOT_DIR%/}/tvos-sim.png}"
         xcrun simctl io "$DEVICE" screenshot "$out" >/dev/null 2>&1 \
           || die "screenshot mislukt — schrijf naar een pad buiten de repo (bv. \$TMPDIR)"
         echo "$out" ;;
  log|logs) read_logs "${2:-}" "${3:-30}" ;;
  wait)  [[ $# -ge 2 ]] || die "gebruik: $0 wait <patroon> [timeout]"
         wait_for_log "$2" "${3:-15}" && echo "gevonden: $2" || die "niet gezien binnen ${3:-15}s: $2" ;;
  key)   [[ $# -ge 2 ]] || die "gebruik: $0 key <up|down|left|right|select|menu|delete>"
         require_input; send_key "$2" ;;
  keys)  shift; require_input; for k in "$@"; do send_key "$k"; sleep 0.6; done ;;
  type)  [[ $# -ge 2 ]] || die "gebruik: $0 type <tekst>"; require_input; type_text "$2" ;;
  goto)  [[ $# -ge 2 ]] || die "gebruik: $0 goto <home|movies|search|settings>"; goto_tab "$2" ;;
  login) shift; do_login "${1:-}" ;;
  check-keyboard) check_keyboard ;;
  *) sed -n '2,30p' "$0"; exit 1 ;;
esac
