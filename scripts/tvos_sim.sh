#!/usr/bin/env bash
# Snelle tvOS-simulator-loop: bouwen, installeren, starten, screenshotten, loggen
# en — als de Mac ontgrendeld is — knoppen indrukken.
#
# Waarom dit bestaat: dictatie is niet simuleerbaar (DEC-009), maar de rest van
# de tvOS-invoer wél — juist de dingen die op device pas opvallen, zoals of Menu
# een scherm sluit. Zonder dit harnas kost elke verificatie een TestFlight-ronde.
#
#   scripts/tvos_sim.sh doctor            # kan ik knoppen sturen?
#   scripts/tvos_sim.sh build             # xcodebuild voor de simulator
#   scripts/tvos_sim.sh run               # boot + install + launch
#   scripts/tvos_sim.sh shot out.png      # screenshot (werkt óók vergrendeld)
#   scripts/tvos_sim.sh log               # applog volgen (Ctrl-C stopt)
#   scripts/tvos_sim.sh key down|select|menu|up|left|right   # afstandsbediening
#   scripts/tvos_sim.sh keys down down select                # meerdere na elkaar
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE_ID="nl.michelknoop.pleya"
APP="tvos/build/dd/Build/Products/Debug-appletvsimulator/Runner.app"
# Overrulen met TVOS_SIM_UDID als je een ander toestel wilt.
DEVICE="${TVOS_SIM_UDID:-$(xcrun simctl list devices available \
  | awk '/-- tvOS/{tv=1} tv && /Apple TV 4K \(3rd generation\) \(/{gsub(/[()]/,"",$NF); print $(NF-1); exit}' \
  | tr -d '()')}"

die() { echo "FOUT: $*" >&2; exit 1; }

resolve_device() {
  [[ -n "$DEVICE" ]] || die "geen tvOS-simulator gevonden (xcrun simctl list devices)"
}

boot() {
  resolve_device
  if ! xcrun simctl list devices | grep -q "$DEVICE.*Booted"; then
    xcrun simctl boot "$DEVICE"
  fi
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
}

# Het Simulator-venster bestaat alleen op een ontgrendeld, wakker scherm. Zonder
# dat venster gaan toetsaanslagen nergens heen — screenshots en logs werken wél.
input_available() {
  caffeinate -u -t 1 >/dev/null 2>&1 || true
  local n
  n="$(osascript -e 'tell application "System Events" to get count of windows of process "Simulator"' 2>/dev/null || echo 0)"
  [[ "${n:-0}" != "0" ]]
}

key_code_for() {
  case "$1" in
    up) echo 126 ;;
    down) echo 125 ;;
    left) echo 123 ;;
    right) echo 124 ;;
    select|enter) echo 36 ;;
    menu|back|escape) echo 53 ;;
    *) die "onbekende toets: $1 (up|down|left|right|select|menu)" ;;
  esac
}

send_key() {
  local code; code="$(key_code_for "$1")"
  osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to key code $code" >/dev/null 2>&1
}

case "${1:-}" in
  doctor)
    resolve_device
    echo "toestel:    $DEVICE"
    echo "app-build:  $([[ -d $APP ]] && echo aanwezig || echo 'ontbreekt — draai: scripts/tvos_sim.sh build')"
    open -a Simulator >/dev/null 2>&1 || true
    sleep 2
    if input_available; then
      echo "invoer:     OK — knoppen sturen kan"
    else
      echo "invoer:     NIET beschikbaar."
      echo "            De Mac is vergrendeld of het scherm slaapt; Simulator toont dan geen"
      echo "            venster en toetsaanslagen komen nergens aan. Ontgrendel het scherm en"
      echo "            draai dit opnieuw. Screenshots en logs werken ondertussen gewoon."
    fi
    ;;
  build)
    xcodebuild -workspace tvos/Runner.xcworkspace -scheme Runner -configuration Debug \
      -destination 'generic/platform=tvOS Simulator' -derivedDataPath tvos/build/dd \
      build CODE_SIGNING_ALLOWED=NO
    ;;
  run)
    resolve_device; boot
    [[ -d "$APP" ]] || die "geen build op $APP — draai eerst: scripts/tvos_sim.sh build"
    open -a Simulator >/dev/null 2>&1 || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$DEVICE" "$APP"
    xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
    ;;
  shot)
    resolve_device
    xcrun simctl io "$DEVICE" screenshot "${2:-shot.png}"
    ;;
  log)
    resolve_device
    # flutter/Dart schrijft naar stderr van het proces; os_log vangt beide.
    xcrun simctl spawn "$DEVICE" log stream --style compact \
      --predicate "processImagePath CONTAINS \"Runner\""
    ;;
  key)
    [[ $# -ge 2 ]] || die "gebruik: $0 key <up|down|left|right|select|menu>"
    input_available || die "geen invoer mogelijk — zie: $0 doctor"
    send_key "$2"
    ;;
  keys)
    shift
    input_available || die "geen invoer mogelijk — zie: $0 doctor"
    for k in "$@"; do send_key "$k"; sleep 0.6; done
    ;;
  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
