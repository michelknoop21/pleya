#!/usr/bin/env bash
# TestFlight release: build & upload, commit het (auto-bepaalde) buildnummer.
# Gebruik: scripts/testflight_release.sh [--clean] [beta|ios_beta|tvos_beta|macos_beta]
# Het buildnummer wordt in de Fastfile bepaald (hoogste TestFlight-build +1),
# dus dit script bumpt niet zelf. Draait ook headless via launchd (zie docs/TESTFLIGHT.md).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# De gepinde SDK moet vóór homebrew staan, anders wint een nieuwere
# /opt/homebrew/bin/flutter van de pin uit .fvmrc en blokkeert de preflight
# hieronder zijn eigen release. Dit geldt ook headless: launchd start met een
# minimale PATH, dus zonder deze regel resolvet flutter daar naar homebrew.
# Geen match op deze machine betekent geen wijziging, dus elders blijft het
# gedrag zoals het was.
PINNED_FLUTTER="$(scripts/check_flutter_version.sh --print 2>/dev/null || true)"
PINNED_FLUTTER_BIN="${FLUTTER_SDKS_DIR:-/Volumes/SSD/flutter-sdks}/${PINNED_FLUTTER}/flutter/bin"
if [[ -n "$PINNED_FLUTTER" && -x "$PINNED_FLUTTER_BIN/flutter" ]]; then
  export PATH="$PINNED_FLUTTER_BIN:$PATH"
fi

DO_CLEAN=0
LANE=""
for arg in "$@"; do
  case "$arg" in
    --clean) DO_CLEAN=1 ;;
    -*) echo "onbekende optie: $arg" >&2; exit 2 ;;
    *) LANE="$arg" ;;
  esac
done
LANE="${LANE:-beta}"
LOG_PREFIX="[testflight $(date '+%Y-%m-%d %H:%M')]"

# Blokkerend: een release die met een andere SDK is gebouwd dan CI verifieert,
# is niet dezelfde build.
scripts/check_flutter_version.sh

# Pleya Verify's automatiseringsserver hoort in geen enkele release te zitten.
# tvos/scripts/xcode_appletv.sh leest PLEYA_VERIFY uit de omliggende omgeving —
# terecht voor een simulatorbuild van de verify-driver, fataal voor een archive.
# Een lane die op de aanroeper vertrouwt is er één die een keer een verkeerde
# build uploadt, dus zet hij zijn eigen omgeving dicht. De build-script-guard in
# xcode_appletv.sh blijft daarnaast staan: die vangt de aanroep die dit script
# overslaat.
export PLEYA_VERIFY=false
unset PLEYA_VERIFY_TOKEN PLEYA_VERIFY_PORT

if [[ ! -f .env ]]; then
  echo "$LOG_PREFIX FOUT: .env ontbreekt (zie .env.example)" >&2
  exit 1
fi

# Adviserend, nooit blokkerend: vlak voor een release wil je zien wat er
# openstaat, maar offline of GitHub plat mag de build niet tegenhouden. Dit
# vervangt de losse MPVKit-aanroep — check_updates.sh roept die zelf aan en zet
# hem naast de engine, de Android-binaries, de git-forks en de Actions.
scripts/check_updates.sh || true

# De iOS-lane besteedde tot vandaag ruim een uur aan twee recursieve
# xattr-passes over de hele repo voordat xcodebuild ook maar begon. Zie
# DEC-029; scripts/xattr-fast/xattr doet hetzelfde werk parallel. Uitzetten met
# PLEYA_XATTR_FAST=0, dan geldt weer het kale gedrag van Flutter.
XATTR_MARKER=""
if [[ "${PLEYA_XATTR_FAST:-1}" != "0" ]]; then
  export PATH="$ROOT/scripts/xattr-fast:$PATH"
  if [[ "$(command -v xattr)" != "$ROOT/scripts/xattr-fast/xattr" ]]; then
    echo "$LOG_PREFIX FOUT: xattr-versnelling niet actief, command -v xattr wijst naar $(command -v xattr)" >&2
    exit 1
  fi
  XATTR_MARKER="$(mktemp "${TMPDIR:-/tmp}/pleya-xattr-marker.XXXXXX")"
  export PLEYA_XATTR_MARKER="$XATTR_MARKER"
  echo "$LOG_PREFIX xattr-versnelling actief (${PLEYA_XATTR_JOBS:-12} workers)"
else
  echo "$LOG_PREFIX xattr-versnelling uitgeschakeld via PLEYA_XATTR_FAST=0"
fi

# Alleen op verzoek. Opruimen is hier een herstelmiddel voor een build die zich
# raar gedraagt, geen snelheidstruc: de xattr-recursie is met DEC-029 al
# opgelost, en clean kost juist een volledige hercompilatie. De tvOS-lane kan
# er tegenwoordig tegen, want fetch_engine.sh herstelt de artefacten waar een
# clean hem vroeger op brak (zie de toelichting in fastlane/Fastfile).
if [[ "$DO_CLEAN" == "1" ]]; then
  echo "$LOG_PREFIX --clean: flutter clean vooraf"
  flutter clean
fi

# Exitcode zelf opvangen in plaats van set -e het script laten afkappen: bij een
# gefaalde lane wil je de markerrapportage hieronder juist wél zien. Verderop
# gaat het script alsnog stuk op deze code, dus het gedrag naar buiten blijft
# gelijk: een mislukte lane commit geen buildnummer.
set +e
fastlane "$LANE"
fastlane_status=$?
set -e

# Bewijs achteraf dat Flutter de shim écht met het verwachte patroon heeft
# aangeroepen. Zonder deze controle is "de shim deed zijn werk" niet te
# onderscheiden van "Flutter roept iets anders aan sinds de laatste SDK-bump en
# het trage pad liep gewoon door". Adviserend: een geslaagde upload afkeuren op
# een meetpunt zou erger zijn dan de traagheid zelf.
if [[ -n "$XATTR_MARKER" ]]; then
  hits=$(wc -l < "$XATTR_MARKER" | tr -d ' ')
  if [[ "$LANE" == "beta" || "$LANE" == "ios_beta" ]] && [[ "$hits" -eq 0 ]]; then
    echo "$LOG_PREFIX WAARSCHUWING: de shim is geen enkele keer aangeroepen." >&2
    echo "$LOG_PREFIX Controleer of flutter_tools nog 'xattr -r -d <attr> <map>' gebruikt (DEC-029)." >&2
  else
    echo "$LOG_PREFIX xattr-shim ${hits}x aangeroepen:"
    sort "$XATTR_MARKER" | uniq -c | sed "s|^|$LOG_PREFIX   |"
  fi
  rm -f "$XATTR_MARKER"
fi

if [[ "$fastlane_status" -ne 0 ]]; then
  exit "$fastlane_status"
fi

# fastlane heeft pubspec.yaml op het nieuwe buildnummer gezet — leg dat vast.
new_number=$(grep -m1 '^version:' pubspec.yaml | sed 's/.*+//')
if ! git diff --quiet pubspec.yaml; then
  git add pubspec.yaml
  git commit -m "chore: bump build number to ${new_number} for TestFlight"
  git push origin HEAD || echo "$LOG_PREFIX WAARSCHUWING: push faalde, commit staat lokaal" >&2
fi
echo "$LOG_PREFIX klaar: lane ${LANE}, build ${new_number}"
