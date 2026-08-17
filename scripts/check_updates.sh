#!/usr/bin/env bash
set -uo pipefail

# Eén rapport voor alles wat in dit project gepind staat: de Flutter-SDK, de
# tvOS-engine, MPVKit, de Android-binaries, de git-forks, de Dart-pakketten en
# de GitHub Actions.
#
#   scripts/check_updates.sh                        # rapporteer, faal alleen op UNKNOWN
#   scripts/check_updates.sh --strict-through-ring 1
#   scripts/check_updates.sh --json
#   scripts/check_updates.sh --bump                 # alleen patch/minor, nooit een major
#   scripts/check_updates.sh --only engine,flutter
#
# Vier statussen, geen twee. Een netwerkchecker die alleen "actueel" en
# "achter" kent liegt zodra GitHub rate-limit geeft of een JSON-formaat
# verandert:
#
#   CURRENT   gecontroleerd, staat op de nieuwste bruikbare versie
#   BLOCKED   nieuwere versie bestaat, maar een bekende relatie verhindert hem
#   OUTDATED  gecontroleerd, er is een nieuwere versie
#   UNKNOWN   de controle is niet betrouwbaar uitgevoerd
#
# Exit: 0 niets blokkerends, 1 minimaal één OUTDATED binnen de gekozen
# strict-ring, 2 rapport incompleet doordat minimaal één check UNKNOWN is.
# 2 wint van 1 — een incompleet rapport zegt niets over wat er nog meer misging.
#
# Het bewijsniveau per component staat als ring in het rapport; zie DEC-023.
# --strict-through-ring N laat alleen componenten met ring <= N de run laten
# falen, zodat een ring-3-set die bewust op een cyclus wacht de wekelijkse
# signalering niet rood zet.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STRICT_RING=0        # 0 = niets is blokkerend behalve UNKNOWN
JSON=0
BUMP=0
ONLY=""

die() { echo "check_updates: $*" >&2; exit 64; }

while [ $# -gt 0 ]; do
  case "$1" in
    --strict-through-ring) STRICT_RING="${2:-}"; shift 2 || die "--strict-through-ring zonder getal" ;;
    --json)   JSON=1; shift ;;
    --bump)   BUMP=1; shift ;;
    --only)   ONLY="${2:-}"; shift 2 || die "--only zonder namen" ;;
    --root)   ROOT="$(cd "${2:-}" && pwd)" || die "--root bestaat niet"; shift 2 ;;
    -h|--help) sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "onbekend argument: $1" ;;
  esac
done
case "$STRICT_RING" in 0|1|2|3) ;; *) die "--strict-through-ring wil 0, 1, 2 of 3" ;; esac

wanted() {
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; esac
  return 1
}

# --- netwerklaag --------------------------------------------------------------
# Onder PLEYA_UPDATE_FIXTURES komt alles uit bestanden in plaats van van het
# net. Dat is hoe de statustests een rate-limit, een onbereikbare host en een
# gewijzigd upstream-formaat kunnen naspelen; zonder die injectie zou "geeft
# een onverwacht antwoord ook echt UNKNOWN?" niet te testen zijn.
FIXTURES="${PLEYA_UPDATE_FIXTURES:-}"

slug() { printf '%s' "$1" | sed -e 's#^https\{0,1\}://##' -e 's#[^A-Za-z0-9._-]#_#g'; }

fetch_url() {
  if [ -n "$FIXTURES" ]; then
    local f="$FIXTURES/get_$(slug "$1")"
    [ -f "$f" ] || return 1
    cat "$f"
    return 0
  fi
  curl -fsSL --max-time 30 "$1" 2>/dev/null
}

# Tags van een repo, versie-gesorteerd, zonder de v-prefix. Alleen tags die met
# een cijfer beginnen: een repo mag ook `latest` of `nightly` als tag hebben, en
# die zouden bij `sort -V` achter elk versienummer landen.
list_tags() {
  local raw
  if [ -n "$FIXTURES" ]; then
    local f="$FIXTURES/tags_$(slug "$1")"
    [ -f "$f" ] || return 1
    raw="$(cat "$f")"
  else
    raw="$(git ls-remote --tags --refs "$1" 2>/dev/null | sed -n 's#.*refs/tags/v\{0,1\}##p')"
  fi
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | grep '^[0-9]' | sort -V
}

remote_ref() { # repo ref -> commit
  if [ -n "$FIXTURES" ]; then
    local f="$FIXTURES/ref_$(slug "$1")_$(slug "$2")"
    [ -f "$f" ] || return 1
    cat "$f"
    return 0
  fi
  git ls-remote "$1" "$2" 2>/dev/null | head -1 | cut -f1
}

# --- rapportregels ------------------------------------------------------------
NAMES=(); RINGS=(); STATUSES=(); CURRENTS=(); AVAILABLES=(); REASONS=()

record() { # naam ring status huidig beschikbaar reden
  NAMES+=("$1"); RINGS+=("$2"); STATUSES+=("$3")
  CURRENTS+=("$4"); AVAILABLES+=("$5"); REASONS+=("$6")
}

GENERATOR_PACKAGES=(build_runner json_serializable drift_dev freezed slang_build_runner)
is_generator_pkg() {
  local g
  for g in "${GENERATOR_PACKAGES[@]}"; do [ "$1" = "$g" ] && return 0; done
  return 1
}

# --- checks -------------------------------------------------------------------

pinned_flutter() {
  "$SCRIPT_DIR/check_flutter_version.sh" --root "$ROOT" --print 2>/dev/null
}

check_flutter_sdk() {
  local pin; pin="$(pinned_flutter)"
  if [ -z "$pin" ]; then
    record flutter-sdk 3 UNKNOWN "?" "?" "kon .fvmrc niet lezen"
    return
  fi

  local json; json="$(fetch_url https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)"
  local latest=""
  if [ -n "$json" ]; then
    latest="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    stable = d["current_release"]["stable"]
    for r in d["releases"]:
        if r["hash"] == stable:
            print(r["version"]); break
except Exception:
    pass
' 2>/dev/null)"
  fi
  if [ -z "$latest" ]; then
    record flutter-sdk 3 UNKNOWN "$pin" "?" "releases_macos.json onbereikbaar of van vorm veranderd"
    return
  fi

  if [ "$pin" = "$latest" ]; then
    record flutter-sdk 3 CURRENT "$pin" "$latest" ""
    return
  fi

  # De SDK-bump zit vast aan de tvOS-engine: tvos/scripts/fetch_engine.sh haalt
  # een prebuilt engine bij edde746/flutter-tvos, en daar bestaat alleen een
  # lijn per Flutter-versie. Een host-SDK tegen een engine van een andere
  # minor is precies het soort mismatch dat op tvOS stil kapot gaat.
  local engine_line="${latest%%+*}"
  local tags; tags="$(list_tags https://github.com/edde746/flutter-tvos)"
  if [ -z "$tags" ]; then
    record flutter-sdk 3 UNKNOWN "$pin" "$latest" "kon de enginelijnen van edde746/flutter-tvos niet ophalen"
    return
  fi
  if printf '%s\n' "$tags" | grep -q "^${engine_line}+"; then
    record flutter-sdk 3 OUTDATED "$pin" "$latest" ""
  else
    record flutter-sdk 3 BLOCKED "$pin" "$latest" \
      "geen bekende compatibele Pleya tvOS-enginelijn; edde746/flutter-tvos publiceert alleen $(printf '%s\n' "$tags" | sed 's/+.*//' | sort -Vu | sed 's/$/+N/' | paste -sd' ' -)"
  fi
}

# .fvmrc, de workflows en de lokale SDK moeten hetzelfde zeggen. Loopt dat
# uiteen, dan is elke andere meting in dit rapport op een andere SDK gedaan dan
# CI draait. Een workflow mag de versie op twee manieren opgeven: letterlijk
# (`flutter-version:`, moet gelijk zijn aan de pin) of via het bestand
# (`flutter-version-file: .fvmrc`, de bedoelde vorm). Een flutter-action-stap
# zonder allebei valt terug op de kop van het kanaal en is dus geen pin.
check_flutter_drift() {
  local pin; pin="$(pinned_flutter)"
  if [ -z "$pin" ]; then
    record flutter-pin-drift 1 UNKNOWN "?" "?" "kon .fvmrc niet lezen"
    return
  fi
  local mismatched=()
  local f v steps pinned_steps
  for f in "$ROOT"/.github/workflows/*.yml; do
    [ -f "$f" ] || continue
    while IFS= read -r v; do
      [ "$v" = "$pin" ] || mismatched+=("$(basename "$f") flutter-version:$v")
    done < <(sed -n 's/.*flutter-version: *"\{0,1\}\([0-9][^"]*\)"\{0,1\}.*/\1/p' "$f")
    while IFS= read -r v; do
      [ "$v" = ".fvmrc" ] || mismatched+=("$(basename "$f") flutter-version-file:$v")
    done < <(sed -n 's/.*flutter-version-file: *"\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p' "$f")
    # grep -c geeft 0 én exitcode 1 als er niets staat; die 1 mag hier niets
    # betekenen, anders telt het script de nul dubbel.
    steps="$(grep -c "uses: subosito/flutter-action@" "$f" 2>/dev/null)" || steps=0
    pinned_steps="$(grep -c "flutter-version" "$f" 2>/dev/null)" || pinned_steps=0
    if [ "$steps" -gt "$pinned_steps" ]; then
      mismatched+=("$(basename "$f") $((steps - pinned_steps)) flutter-action-stap(pen) zonder versie")
    fi
  done
  local local_v=""
  if command -v flutter >/dev/null 2>&1; then
    local_v="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9][^ ]*\).*/\1/p' | head -1)"
  fi
  if [ -n "$local_v" ] && [ "$local_v" != "$pin" ]; then
    mismatched+=("PATH:$local_v")
  fi
  if [ ${#mismatched[@]} -eq 0 ]; then
    record flutter-pin-drift 1 CURRENT "$pin overal gelijk" "" ""
  else
    record flutter-pin-drift 1 OUTDATED "$pin" "${#mismatched[@]} afwijking(en)" \
      "deze plekken wijken af van .fvmrc: ${mismatched[*]}"
  fi
}

check_tvos_engine() {
  local vf="$ROOT/tvos/engine.version"
  if [ ! -f "$vf" ]; then
    record tvos-engine 3 UNKNOWN "?" "?" "tvos/engine.version ontbreekt"
    return
  fi
  local cur; cur="$(tr -d '[:space:]' <"$vf")"
  local tags; tags="$(list_tags https://github.com/edde746/flutter-tvos)"
  if [ -z "$tags" ]; then
    record tvos-engine 3 UNKNOWN "$cur" "?" "kon de tags van edde746/flutter-tvos niet ophalen"
    return
  fi
  # Alleen binnen dezelfde Flutter-lijn: +N van een andere minor is geen update.
  local line="${cur%%+*}"
  local latest
  latest="$(printf '%s\n' "$tags" | grep "^${line}+" | sort -V | tail -1)"
  if [ -z "$latest" ]; then
    record tvos-engine 3 UNKNOWN "$cur" "?" "geen enkele tag op lijn $line"
    return
  fi
  if [ "$cur" = "$latest" ]; then
    record tvos-engine 3 CURRENT "$cur" "$latest" ""
  else
    local behind
    behind="$(printf '%s\n' "$tags" | grep "^${line}+" | sort -V |
      awk -v c="$cur" 'seen{n++} $0==c{seen=1} END{print n+0}')"
    record tvos-engine 3 OUTDATED "$cur" "$latest" \
      "$behind openstaande build(s); na een bump opnieuw valideren dat AppDelegate bij het opstarten 'engine press hook available=true' logt (DEC-019)"
  fi
}

check_mpvkit() {
  local out
  out="$("$SCRIPT_DIR/check_mpvkit_update.sh" 2>/dev/null)"
  local rc=$?
  local cur lat
  cur="$(printf '%s\n' "$out" | sed -n 's/^MPVKit pinned: *//p')"
  lat="$(printf '%s\n' "$out" | sed -n 's/^MPVKit latest: *//p')"
  if [ -z "$cur" ] || [ -z "$lat" ]; then
    record mpvkit 3 UNKNOWN "${cur:-?}" "${lat:-?}" "check_mpvkit_update.sh gaf geen bruikbaar antwoord"
    return
  fi
  if [ "$rc" -eq 0 ] && [ "$cur" = "$lat" ]; then
    record mpvkit 3 CURRENT "$cur" "$lat" ""
  else
    record mpvkit 3 OUTDATED "$cur" "$lat" "bump met scripts/check_mpvkit_update.sh --bump; daarna afspelen echt verifiëren"
  fi
}

# Android-binaries: de versie staat in het buildbestand dat hem downloadt, dus
# dat bestand is de bron van waarheid, niet een losse lijst hier.
check_pinned_release() { # naam ring bestand sed-expressie repo reden-bij-outdated
  local name="$1" ring="$2" file="$3" expr="$4" repo="$5" note="$6"
  if [ ! -f "$ROOT/$file" ]; then
    record "$name" "$ring" UNKNOWN "?" "?" "$file ontbreekt"
    return
  fi
  local cur; cur="$(sed -n "$expr" "$ROOT/$file" | head -1)"
  if [ -z "$cur" ]; then
    record "$name" "$ring" UNKNOWN "?" "?" "kon de pin niet uit $file lezen"
    return
  fi
  local tags; tags="$(list_tags "$repo")"
  if [ -z "$tags" ]; then
    record "$name" "$ring" UNKNOWN "$cur" "?" "kon de tags van $repo niet ophalen"
    return
  fi
  local latest; latest="$(printf '%s\n' "$tags" | sort -V | tail -1)"
  if [ "$cur" = "$latest" ]; then
    record "$name" "$ring" CURRENT "$cur" "$latest" ""
  else
    record "$name" "$ring" OUTDATED "$cur" "$latest" "$note"
  fi
}

# De git-forks dragen de patches waar de app op leunt. Een blinde
# `git ls-remote HEAD` zou permanent OUTDATED melden zodra een default branch
# beweegt die wij niet volgen, dus de gevolgde ref staat hier expliciet.
# Formaat: pakket|repo|gevolgde ref|ring|waarom die ref
FORKS=(
  "connectivity_plus|https://github.com/edde746/plus_plugins|refs/heads/main|3|netwerkdetectie met platformcode op elk doel"
  "os_media_controls|https://github.com/edde746/media_controls|refs/heads/main|3|native mediasessie-integratie"
  "wakelock_plus|https://github.com/edde746/wakelock_plus|refs/heads/main|3|platformcode voor schermwaak"
  "background_downloader|https://github.com/edde746/background_downloader|refs/heads/main|3|achtergronddownloads, iOS 14-eis"
  "sentry_flutter|https://github.com/edde746/sentry-dart|refs/heads/build/fetch-native-zip|3|fork-branch die de native zip ophaalt in plaats van meebouwt; sentry (pure Dart) beweegt hier atomair mee"
  "auto_updater|https://github.com/edde746/auto_updater|refs/heads/main|3|Sparkle/WinSparkle-integratie op desktop"
  "material_symbols_icons|https://github.com/edde746/material_symbols_icons|refs/heads/master|2|alleen fontassets en Dart"
)

check_forks() {
  local lock="$ROOT/pubspec.lock"
  if [ ! -f "$lock" ]; then
    record git-forks 3 UNKNOWN "?" "?" "pubspec.lock ontbreekt"
    return
  fi
  local entry pkg repo ref ring why pinned head
  local behind_list=() unknown=0
  for entry in "${FORKS[@]}"; do
    IFS='|' read -r pkg repo ref ring why <<<"$entry"
    pinned="$(awk -v n="  $pkg:" '$0==n{f=1} f&&/resolved-ref:/{gsub(/[",]/,"");print $2; exit}' "$lock")"
    if [ -z "$pinned" ]; then
      unknown=1
      behind_list+=("$pkg: geen resolved-ref in pubspec.lock")
      continue
    fi
    head="$(remote_ref "$repo" "$ref")"
    if [ -z "$head" ]; then
      unknown=1
      behind_list+=("$pkg: $ref onbereikbaar")
      continue
    fi
    if [ "$pinned" != "$head" ]; then
      behind_list+=("$pkg (ring $ring): ${pinned:0:12} != ${head:0:12} op $ref — $why")
    fi
  done
  if [ "$unknown" -eq 1 ]; then
    record git-forks 3 UNKNOWN "${#FORKS[@]} forks" "?" "$(printf '%s; ' "${behind_list[@]}")"
  elif [ ${#behind_list[@]} -eq 0 ]; then
    record git-forks 3 CURRENT "${#FORKS[@]} forks" "gelijk aan hun gevolgde ref" ""
  else
    record git-forks 3 OUTDATED "${#FORKS[@]} forks" "${#behind_list[@]} wijken af" \
      "rapporteren, niet automatisch bumpen: $(printf '%s; ' "${behind_list[@]}")"
  fi
}

# De analyzer-stack is bewust bevroren. Een nieuwere analyzer laat drift_dev
# zonder compilefout relaties uit app_database.g.dart weglaten: de foreign key,
# de ON DELETE CASCADE, de writepropagatie en de reference managers. Gemeten,
# niet vermoed — zie DEC-024. Deze regel is BLOCKED en geen OUTDATED, want
# "loop achter" is hier de bedoeling en niet een achterstand.
ANALYZER_STACK=(analyzer dart_code_linter)

check_analyzer_stack() {
  local lock="$ROOT/pubspec.lock"
  if [ ! -f "$lock" ]; then
    record analyzer-stack 2 UNKNOWN "?" "?" "pubspec.lock ontbreekt"
    return
  fi
  local pkg cur latest behind=()
  for pkg in "${ANALYZER_STACK[@]}"; do
    cur="$(awk -v n="  $pkg:" '$0==n{f=1} f&&/^    version:/{gsub(/"/,"");print $2; exit}' "$lock")"
    if [ -z "$cur" ]; then
      record analyzer-stack 2 UNKNOWN "?" "?" "$pkg staat niet in pubspec.lock"
      return
    fi
    latest="$(fetch_url "https://pub.dev/api/packages/$pkg" |
      python3 -c 'import json,sys
try: print(json.load(sys.stdin)["latest"]["version"])
except Exception: pass' 2>/dev/null)"
    if [ -z "$latest" ]; then
      record analyzer-stack 2 UNKNOWN "$pkg $cur" "?" "pub.dev gaf geen bruikbaar antwoord voor $pkg"
      return
    fi
    [ "$cur" = "$latest" ] || behind+=("$pkg $cur -> $latest")
  done
  if [ ${#behind[@]} -eq 0 ]; then
    record analyzer-stack 2 CURRENT "$(printf '%s ' "${ANALYZER_STACK[@]}")" "" ""
  else
    record analyzer-stack 2 BLOCKED "${behind[*]}" ""       "een nieuwere analyzer laat drift_dev de foreign key, de ON DELETE CASCADE, de writepropagatie en de reference managers uit app_database.g.dart weg, zonder compilefout (DEC-024); pas los te laten als drift_dev compatibiliteit ondersteunt of als test/database/drift_relations_test.dart bij de nieuwe versie groen blijft"
  fi
}

# Pakketten die bewust achterlopen, met de reden erbij. Zonder deze lijst zou de
# ring-1-gate permanent rood staan op een achterstand die een besluit is.
BLOCKED_PACKAGES=(
  "analyzer|DEC-024: een nieuwere analyzer laat drift_dev relaties weg"
  "_fe_analyzer_shared|DEC-024: beweegt met analyzer mee"
  "analyzer_plugin|DEC-024: beweegt met analyzer mee"
  "dart_code_linter|DEC-024: trekt een nieuwere analyzer mee"
  "rate_limiter|1.1.0 leest de tijd via package:clock; onder de fake clock van flutter_test vuurt de zoekdebounce anders en vallen twee TV-focustests om — eerst die tests aanpassen"
)

blocked_reason() {
  local e
  for e in "${BLOCKED_PACKAGES[@]}"; do
    if [ "${e%%|*}" = "$1" ]; then printf '%s' "${e#*|}"; return 0; fi
  done
  return 1
}

# Declareert de geïnstalleerde versie flutter.plugin.platforms? Zo ja, dan kan
# een update platformcode meebrengen en is de wijziging niet ring 1. Dezelfde
# regel als in classify_lock_diff.sh, hier op de versie die nú in de cache
# staat — dit rapport lost geen nieuwe versies op.
# 0 = plugin, 1 = geen plugin, 2 = niet in de cache (onbekend).
installed_is_plugin() {
  local dir host
  for host in pub.dev pub.dartlang.org; do
    dir="${PUB_CACHE:-$HOME/.pub-cache}/hosted/$host/$1-$2"
    [ -f "$dir/pubspec.yaml" ] || continue
    python3 - "$dir/pubspec.yaml" <<'PYPLUGIN'
import sys

want = ("flutter", "plugin", "platforms")
stack = []
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if ":" not in stripped or stripped.startswith("-"):
            continue
        key = stripped.split(":", 1)[0].strip().strip("\"'")
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, key))
        if tuple(k for _, k in stack) == want:
            sys.exit(0)
sys.exit(1)
PYPLUGIN
    return $?
  done
  return 2
}

COUPLED=()
check_dart_packages() {
  local json rows
  json="$(cd "$ROOT" && flutter pub outdated --json 2>/dev/null)"
  rows="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    pkgs = json.load(sys.stdin)["packages"]
except Exception:
    sys.exit(1)

def v(p, key):
    x = p.get(key)
    return x.get("version") if isinstance(x, dict) else None

for p in pkgs:
    cur, up, res, lat = (v(p, k) for k in ("current", "upgradable", "resolvable", "latest"))
    print("\t".join([p.get("package", "?"), cur or "", up or "", res or "", lat or ""]))
' 2>/dev/null)"
  if [ -z "$rows" ]; then
    record dart-lockfile 1 UNKNOWN "?" "?" "flutter pub outdated --json gaf niets bruikbaars"
    record dart-constraints 2 UNKNOWN "?" "?" "flutter pub outdated --json gaf niets bruikbaars"
    record dart-majors 3 UNKNOWN "?" "?" "flutter pub outdated --json gaf niets bruikbaars"
    return
  fi

  local pkg cur up res lat reason rc s
  local r1=() r2=() r3=() unknown=() blocked=()
  local con=0 maj=0
  while IFS=$'\t' read -r pkg cur up res lat; do
    [ -n "$pkg" ] || continue
    if [ -n "$up" ] && [ -n "$res" ] && [ "$up" != "$res" ]; then con=$((con + 1)); fi
    if [ -n "$res" ] && [ -n "$lat" ] && [ "$res" != "$lat" ]; then maj=$((maj + 1)); fi
    [ -n "$cur" ] && [ -n "$up" ] && [ "$cur" != "$up" ] || continue

    if reason="$(blocked_reason "$pkg")"; then
      blocked+=("$pkg $cur -> $up ($reason)")
      continue
    fi
    installed_is_plugin "$pkg" "$cur"; rc=$?
    case "$rc" in
      0) r3+=("$pkg $cur -> $up") ;;
      1) if is_generator_pkg "$pkg"; then r2+=("$pkg $cur -> $up"); else r1+=("$pkg $cur -> $up"); fi ;;
      *) unknown+=("$pkg $cur (niet in de pub-cache)") ;;
    esac
  done <<<"$rows"

  # Bereikbaarheid, niet alleen beschikbaarheid. `pub outdated` zegt dat een
  # pakket binnen zijn constraint hoger kan, maar niet of het dat op eigen
  # kracht kan. Kan drift alleen mee als drift_dev meegaat, dan is de
  # change-set ring 2 en niet ring 1 — dezelfde promotieregel als overal.
  # Eén dry-run over de hele kandidatenset, en die schrijft niets.
  if [ ${#r1[@]} -gt 0 ]; then
    local names=() moved="" probe rc_probe
    for pkg in "${r1[@]}"; do names+=("${pkg%% *}"); done
    probe="$(cd "$ROOT" && flutter pub upgrade --dry-run "${names[@]}" 2>/dev/null)"
    rc_probe=$?
    if [ "$rc_probe" -ne 0 ] || [ -z "$probe" ]; then
      record dart-lockfile 1 UNKNOWN "${#r1[@]} kandidaten" "?" \
        "kon niet meten of ze op eigen kracht bewegen (pub upgrade --dry-run faalde)"
      r1=()
    else
      moved="$(printf '%s\n' "$probe" | sed -n 's/^> \([^ ]*\) .*/\1/p')"
      local still=() coupled=()
      for pkg in "${r1[@]}"; do
        if printf '%s\n' "$moved" | grep -qx "${pkg%% *}"; then still+=("$pkg"); else coupled+=("$pkg"); fi
      done
      r1=("${still[@]:-}")
      [ -z "${r1[0]:-}" ] && r1=()
      COUPLED=("${coupled[@]:-}")
      [ -z "${COUPLED[0]:-}" ] && COUPLED=()
    fi
  fi

  # Een lockfile-update is niet per definitie ring 1: dezelfde beweging kan een
  # plugin met platformcode zijn. De achterstand wordt daarom gesplitst met
  # dezelfde regel die classify_lock_diff.sh gebruikt. Eén plat getal zou de
  # ring-1-gate op ring-3-werk laten afgaan, en dan leert iedereen die kleur
  # negeren.
  s=CURRENT; [ ${#r1[@]} -gt 0 ] && s=OUTDATED
  record dart-lockfile 1 "$s" "${#r1[@]} pakket(ten)" "pure Dart, binnen de huidige constraints" "${r1[*]:-}"
  if [ ${#COUPLED[@]} -gt 0 ]; then
    record dart-lockfile-gekoppeld 2 OUTDATED "${#COUPLED[@]} pakket(ten)" \
      "alleen bereikbaar samen met een codegen- of pluginpakket" "${COUPLED[*]}"
  fi
  s=CURRENT; [ ${#r2[@]} -gt 0 ] && s=OUTDATED
  record dart-lockfile-codegen 2 "$s" "${#r2[@]} pakket(ten)" "lopen door codegen heen" "${r2[*]:-}"
  s=CURRENT; [ ${#r3[@]} -gt 0 ] && s=OUTDATED
  record dart-lockfile-plugins 3 "$s" "${#r3[@]} pakket(ten)" "plugins met platformcode" "${r3[*]:-}"
  if [ ${#blocked[@]} -gt 0 ]; then
    record dart-blocked 2 BLOCKED "${#blocked[@]} pakket(ten)" "" "${blocked[*]}"
  fi
  if [ ${#unknown[@]} -gt 0 ]; then
    record dart-lockfile-unclassified 1 UNKNOWN "${#unknown[@]} pakket(ten)" "?" \
      "geen bron in de pub-cache, dus niet aan te tonen dat ze ring 1 zijn: ${unknown[*]}"
  fi

  s=CURRENT; [ "$con" -gt 0 ] && s=OUTDATED
  record dart-constraints 2 "$s" "$con pakket(ten)" "vragen een ruimere constraint" ""
  s=CURRENT; [ "$maj" -gt 0 ] && s=OUTDATED
  record dart-majors 3 "$s" "$maj pakket(ten)" "zitten achter een major" ""
}

check_actions() {
  local dir="$ROOT/.github/workflows"
  if [ ! -d "$dir" ]; then
    record github-actions 1 UNKNOWN "?" "?" ".github/workflows ontbreekt"
    return
  fi
  local uses; uses="$(grep -rh "uses: " "$dir" | sed 's/.*uses: //' | sed 's/ *$//' | sort -u)"
  local movable=() unpinned=() behind=() unknown=()
  local line spec comment owner repo ref latest
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    spec="${line%%#*}"; spec="$(printf '%s' "$spec" | sed 's/ *$//')"
    comment="$(printf '%s' "$line" | sed -n 's/.*# *//p')"
    ref="${spec##*@}"
    repo="${spec%@*}"
    owner="${repo%%/*}"
    case "$ref" in
      latest|master|main)
        movable+=("$repo@$ref")
        continue
        ;;
    esac
    latest="$(list_tags "https://github.com/$repo" | sort -V | tail -1)"
    if [ -z "$latest" ]; then
      unknown+=("$repo")
      continue
    fi
    if [ "$owner" != "actions" ]; then
      # Third-party hoort op een volledige commit-SHA te staan.
      case "$ref" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
          [ ${#ref} -eq 40 ] || unpinned+=("$repo@$ref") ;;
        *) unpinned+=("$repo@$ref") ;;
      esac
      [ -n "$comment" ] && [ "${comment#v}" != "$latest" ] &&
        behind+=("$repo $comment -> v$latest")
      continue
    fi
    # Eerste partij staat op een major-tag; vergelijk alleen het major-deel.
    [ "${ref#v}" = "${latest%%.*}" ] || behind+=("$repo $ref -> v${latest%%.*}")
  done <<<"$uses"

  if [ ${#unknown[@]} -gt 0 ]; then
    record github-actions 1 UNKNOWN "?" "?" "geen tags op te halen voor: ${unknown[*]}"
  elif [ ${#movable[@]} -gt 0 ]; then
    record github-actions 1 OUTDATED "verplaatsbaar tag" "${movable[*]}" \
      "een tag die de eigenaar kan verplaatsen is geen pin"
  elif [ ${#behind[@]} -gt 0 ]; then
    record github-actions 1 OUTDATED "${#behind[@]} achter" "${behind[*]}" \
      "een major wordt nooit automatisch herschreven; leg hem eerst tegen de release notes"
  else
    record github-actions 1 CURRENT "$(printf '%s\n' "$uses" | wc -l | tr -d ' ') actions" "op de nieuwste major" ""
  fi

  if [ ${#unpinned[@]} -gt 0 ]; then
    record github-actions-pinning 1 OUTDATED "${#unpinned[@]} zonder SHA" "${unpinned[*]}" \
      "third-party actions horen op een volledige commit-SHA met de versie als comment"
  else
    record github-actions-pinning 1 CURRENT "third-party op SHA" "" ""
  fi
}

# --- uitvoeren ----------------------------------------------------------------
wanted flutter  && check_flutter_sdk
wanted drift    && check_flutter_drift
wanted engine   && check_tvos_engine
wanted mpvkit   && check_mpvkit
wanted libmpv   && check_pinned_release libmpv-android 3 android/app/build.gradle.kts \
  's/^val mpvVersion = "v\{0,1\}\([^"]*\)".*/\1/p' https://github.com/edde746/libmpv-android \
  "Android-speler; na een bump afspelen op een toestel verifiëren"
wanted libdovi  && check_pinned_release libdovi-builds 3 android/app/build.gradle.kts \
  's/^val doviVersion = "v\{0,1\}\([^"]*\)".*/\1/p' https://github.com/edde746/libdovi-builds \
  "Dolby Vision op Android; na een bump HDR-afspelen verifiëren"
wanted libass   && check_pinned_release libass 3 android/libass/src/main/cpp/CMakeLists.txt \
  's/^set(LIBASS_VERSION "\([^"]*\)").*/\1/p' https://github.com/edde746/libass \
  "ASS/SSA-styling, timing en shaping; flutter analyze ziet hier niets van"
wanted forks    && check_forks
wanted analyzer && check_analyzer_stack
wanted dart     && check_dart_packages
wanted actions  && check_actions

# --- bump ---------------------------------------------------------------------
if [ "$BUMP" -eq 1 ]; then
  # Bewust smal: alleen wat een eigen bumper heeft. Een major herschrijven zou
  # betekenen dat dit script inputs en runtimes beoordeelt die het niet leest.
  echo "--bump: MPVKit overlaten aan zijn eigen bumper"
  "$SCRIPT_DIR/check_mpvkit_update.sh" --bump || true
  echo
fi

# --- rapport ------------------------------------------------------------------
if [ "${#NAMES[@]}" -eq 0 ]; then
  echo "check_updates: geen enkele check uitgevoerd (--only $ONLY?)" >&2
  exit 2
fi

RECORDS="$(mktemp)"
trap 'rm -f "$RECORDS"' EXIT
for i in "${!NAMES[@]}"; do
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${NAMES[$i]}" "${RINGS[$i]}" "${STATUSES[$i]}" \
    "${CURRENTS[$i]}" "${AVAILABLES[$i]}" "${REASONS[$i]}"
done >"$RECORDS"

if [ "$JSON" -eq 1 ]; then
  python3 - "$RECORDS" "$STRICT_RING" <<'PY'
import json, sys

rows = []
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        name, ring, status, current, available, reason = line.rstrip("\n").split("\t")
        rows.append({
            "component": name,
            "ring": int(ring),
            "status": status,
            "current": current,
            "available": available,
            "reason": reason,
        })
print(json.dumps({"strictThroughRing": int(sys.argv[2]), "components": rows},
                 indent=2, ensure_ascii=False))
PY
else
  printf '%-24s %-5s %-9s %s\n' component ring status detail
  printf '%-24s %-5s %-9s %s\n' ------------------------ ----- --------- ------
  for i in "${!NAMES[@]}"; do
    detail="${CURRENTS[$i]}"
    [ -n "${AVAILABLES[$i]}" ] && detail="${CURRENTS[$i]} -> ${AVAILABLES[$i]}"
    printf '%-24s %-5s %-9s %s\n' "${NAMES[$i]}" "${RINGS[$i]}" "${STATUSES[$i]}" "$detail"
    [ -n "${REASONS[$i]}" ] && printf '%-24s %-5s %-9s %s\n' "" "" "" "${STATUSES[$i]}: ${REASONS[$i]}"
  done
fi

# --- exitcode -----------------------------------------------------------------
# 2 wint van 1: een incompleet rapport zegt niets over wat er nog meer misging.
EXIT=0
for i in "${!NAMES[@]}"; do
  case "${STATUSES[$i]}" in
    UNKNOWN) EXIT=2 ;;
    OUTDATED)
      if [ "${RINGS[$i]}" -le "$STRICT_RING" ] && [ "$EXIT" -eq 0 ]; then EXIT=1; fi
      ;;
  esac
done
exit "$EXIT"
