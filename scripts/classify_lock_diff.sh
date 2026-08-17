#!/usr/bin/env bash
set -uo pipefail

# Vergelijkt twee pubspec.lock-bestanden en geeft per gewijzigd pakket een ring,
# met het bewijs waarop die ring rust.
#
#   ring 1  gereedschap en aantoonbaar pure Dart-updates
#   ring 2  codegen-deelnemers en plugins waarvan de native kant identiek is
#   ring 3  elke binaire, native of platformwijziging
#
# De regel achter de indeling: de wijziging bepaalt de ring, niet de naam of de
# locatie van de dependency, en een wijziging promoveert altijd naar de hoogste
# ring waarvan de risico-eigenschappen van toepassing zijn. UNKNOWN promoveert
# mee: niet kunnen aantonen dat iets veilig is telt hier als niet veilig.
#
#   scripts/classify_lock_diff.sh                       # HEAD vs. working tree
#   scripts/classify_lock_diff.sh --old a --new b
#   scripts/classify_lock_diff.sh --cache /pad/naar/pub-cache
#
# De pub-cache is een hulpmiddel, geen waarheid: een oude versie kan eruit zijn
# opgeschoond en een nieuwe kan er al in staan van ander werk. Het script haalt
# daarom nooit stilzwijgend een pakket op om het daarna als ring 1 af te vinken.
# Ontbreekt een bron, dan is de uitkomst UNKNOWN en staat dat in het bewijs.
#
# Exit: 0 rapport geproduceerd, 1 harde fout (onleesbare of onvolledige
# lockfile, ontbrekend bestand, verkeerd argument). Een rapport met UNKNOWN of
# ring 3 erin is geen fout — het is precies waar dit script voor bestaat.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Pakketten die door codegen heen lopen: hun output kan veranderen zonder dat
# er een regel Dart in dit project wijzigt. Dit is een routeringsheuristiek,
# geen bewijs — het bewijs is `scripts/codegen.sh` draaien en zien of de
# gegenereerde diff leeg blijft. Blijft hij dat niet, dan promoveert het pakket
# alsnog naar ring 2, ook als het hier niet in staat.
GENERATOR_PACKAGES=(build_runner json_serializable drift_dev freezed slang_build_runner)

# Mappen waarin een plugin zijn platformcode bewaart.
PLATFORM_DIRS=(android ios macos darwin windows linux)

OLD_LOCK=""
NEW_LOCK=""
PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"

die() { echo "classify_lock_diff: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --old)   OLD_LOCK="${2:-}"; shift 2 || die "--old zonder pad" ;;
    --new)   NEW_LOCK="${2:-}"; shift 2 || die "--new zonder pad" ;;
    --cache) PUB_CACHE_DIR="${2:-}"; shift 2 || die "--cache zonder pad" ;;
    -h|--help) sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "onbekend argument: $1" ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -z "$NEW_LOCK" ]; then
  NEW_LOCK="$ROOT/pubspec.lock"
fi
if [ -z "$OLD_LOCK" ]; then
  # Geen expliciete oude kant: neem de laatst vastgelegde lockfile.
  OLD_LOCK="$TMP/head.lock"
  git -C "$ROOT" show HEAD:pubspec.lock >"$OLD_LOCK" 2>/dev/null ||
    die "kon HEAD:pubspec.lock niet lezen; geef --old expliciet mee"
fi

[ -f "$OLD_LOCK" ] || die "bestaat niet: $OLD_LOCK"
[ -f "$NEW_LOCK" ] || die "bestaat niet: $NEW_LOCK"

# --- lockfile lezen -----------------------------------------------------------
# Een lockfile heeft een strakke, voorspelbare vorm. Alles wat daarvan afwijkt
# is een harde fout: liever geen rapport dan een rapport dat pakketten mist en
# de rest als ring 1 afvinkt.
read_lock() {
  python3 - "$1" <<'PY'
import sys

path = sys.argv[1]


def die(msg):
    sys.stderr.write("classify_lock_diff: %s: %s\n" % (path, msg))
    sys.exit(2)


try:
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
except OSError as exc:
    die(str(exc))

top = None
pkg = None
packages = {}
order = []
saw_packages_key = False

for lineno, line in enumerate(raw.splitlines(), 1):
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    indent = len(line) - len(line.lstrip(" "))
    stripped = line.strip()

    if indent == 0:
        if ":" not in stripped:
            die("regel %d: onverwachte inhoud op topniveau: %r" % (lineno, stripped))
        top = stripped.split(":", 1)[0].strip()
        if top == "packages":
            saw_packages_key = True
        pkg = None
        continue

    if top != "packages":
        continue

    if indent == 2:
        if not stripped.endswith(":"):
            die("regel %d: verwachtte een pakketnaam, kreeg %r" % (lineno, stripped))
        pkg = stripped[:-1].strip("\"'")
        if pkg in packages:
            die("regel %d: pakket %s staat er twee keer in" % (lineno, pkg))
        packages[pkg] = {}
        order.append(pkg)
        continue

    if pkg is None:
        die("regel %d: pakketveld buiten een pakketblok" % lineno)

    if indent in (4, 6):
        if ":" not in stripped:
            die("regel %d: verwachtte 'sleutel: waarde', kreeg %r" % (lineno, stripped))
        key, _, value = stripped.partition(":")
        value = value.strip().strip("\"'")
        if value:
            packages[pkg].setdefault(key.strip(), value)
        continue

    die("regel %d: onverwachte inspringing %d" % (lineno, indent))

if not saw_packages_key:
    die("geen 'packages:'-sleutel gevonden")

for name in order:
    fields = packages[name]
    for required in ("source", "version"):
        if required not in fields:
            die("pakket %s mist '%s'" % (name, required))
    print(
        "\t".join(
            [
                name,
                fields["source"],
                fields["version"],
                fields.get("resolved-ref", ""),
                fields.get("path", ""),
                fields.get("url", ""),
            ]
        )
    )
PY
}

# Declareert het pakket zelf flutter.plugin.platforms in zijn pubspec.yaml?
has_plugin_platforms() {
  [ -f "$1/pubspec.yaml" ] || return 1
  python3 - "$1/pubspec.yaml" <<'PY'
import sys

want = ("flutter", "plugin", "platforms")
stack = []
found = False

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
            found = True
            break

sys.exit(0 if found else 1)
PY
}

# Waar bewaart de pub-cache dit pakket? Leeg antwoord = niet cache-backed.
cache_dir_for() {
  local name="$1" source="$2" version="$3" ref="$4" subpath="$5" url="$6"
  case "$source" in
    hosted)
      local host
      for host in pub.dev pub.dartlang.org; do
        if [ -d "$PUB_CACHE_DIR/hosted/$host/$name-$version" ]; then
          echo "$PUB_CACHE_DIR/hosted/$host/$name-$version"
          return 0
        fi
      done
      ;;
    git)
      [ -n "$ref" ] || return 1
      # pub noemt de checkout naar de *repo*, niet naar het pakket. Een monorepo
      # als edde746/sentry-dart levert zo sentry-dart-<sha> voor zowel `sentry`
      # als `sentry_flutter`; op de pakketnaam zoeken geeft daar een cache-miss
      # die er niet is.
      local repo="${url%.git}"
      repo="${repo##*/}"
      local base
      for base in "$PUB_CACHE_DIR/git/$repo-$ref" "$PUB_CACHE_DIR/git/$name-$ref"; do
        [ -d "$base" ] || continue
        if [ -n "$subpath" ]; then
          [ -d "$base/$subpath" ] || continue
          echo "$base/$subpath"
        else
          echo "$base"
        fi
        return 0
      done
      ;;
  esac
  return 1
}

is_generator() {
  local name="$1" g
  for g in "${GENERATOR_PACKAGES[@]}"; do
    [ "$name" = "$g" ] && return 0
  done
  return 1
}

# differs | identical
native_diff() {
  local old="$1" new="$2" d
  for d in "${PLATFORM_DIRS[@]}"; do
    local a="$old/$d" b="$new/$d"
    if [ -d "$a" ] && [ -d "$b" ]; then
      diff -rq "$a" "$b" >/dev/null 2>&1 || { echo differs; return; }
    elif [ -d "$a" ] || [ -d "$b" ]; then
      echo differs
      return
    fi
  done
  echo identical
}

# --- inlezen ------------------------------------------------------------------
read_lock "$OLD_LOCK" >"$TMP/old.tsv" || die "kon $OLD_LOCK niet lezen"
read_lock "$NEW_LOCK" >"$TMP/new.tsv" || die "kon $NEW_LOCK niet lezen"

line_for() { awk -F'\t' -v n="$2" '$1==n{print; exit}' "$1"; }

changed=0
declare -i r1=0 r2=0 r3=0 runknown=0

emit() {
  # emit <naam> <van> <naar> <ring> <plugin> <generator> <nativeDiff> <sources>
  printf 'package: %s\n%s -> %s\nring: %s\nevidence:\n  plugin: %s\n  generatedCodeParticipant: %s\n  nativeDiff: %s\n  sources: %s\n\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
  changed=$((changed + 1))
  case "$4" in
    1) r1+=1 ;;
    2) r2+=1 ;;
    3) r3+=1 ;;
    *) runknown+=1 ;;
  esac
}

# Sleutel waarop "veranderd" wordt bepaald: versie voor hosted, resolved-ref
# voor git. Een git-fork die op dezelfde versie een andere commit krijgt is wél
# een wijziging.
identity_of() {
  local src="$2" version="$3" ref="$4"
  if [ "$src" = "git" ] && [ -n "$ref" ]; then
    echo "${ref:0:12}"
  else
    echo "$version"
  fi
}

classify_pair() {
  local name="$1"
  local old_line new_line
  old_line="$(line_for "$TMP/old.tsv" "$name")"
  new_line="$(line_for "$TMP/new.tsv" "$name")"

  local o_src o_ver o_ref o_path o_url n_src n_ver n_ref n_path n_url
  IFS=$'\t' read -r _ o_src o_ver o_ref o_path o_url <<<"$old_line"
  IFS=$'\t' read -r _ n_src n_ver n_ref n_path n_url <<<"$new_line"

  local from to
  if [ -n "$old_line" ]; then from="$(identity_of "$name" "$o_src" "$o_ver" "$o_ref")"; else from="(afwezig)"; fi
  if [ -n "$new_line" ]; then to="$(identity_of "$name" "$n_src" "$n_ver" "$n_ref")"; else to="(verwijderd)"; fi
  [ "$from" = "$to" ] && return 0

  local generator=false
  is_generator "$name" && generator=true

  # SDK-pakketten (flutter, flutter_test, sky_engine) bewegen alleen mee met een
  # SDK-bump. Die is per definitie ring 3 en wordt daar ook getest.
  if [ "${n_src:-${o_src:-}}" = "sdk" ]; then
    emit "$name" "$from" "$to" 3 n/a "$generator" n/a "sdk/sdk"
    return 0
  fi

  local old_dir="" new_dir="" old_state=cache-miss new_state=cache-miss
  if [ -n "$old_line" ]; then
    old_dir="$(cache_dir_for "$name" "$o_src" "$o_ver" "$o_ref" "$o_path" "$o_url" || true)"
    [ -n "$old_dir" ] && old_state=cache-hit
  else
    old_state=n/a
  fi
  if [ -n "$new_line" ]; then
    new_dir="$(cache_dir_for "$name" "$n_src" "$n_ver" "$n_ref" "$n_path" "$n_url" || true)"
    [ -n "$new_dir" ] && new_state=cache-hit
  else
    new_state=n/a
  fi
  local sources="$old_state/$new_state"

  # Ontbreekt een bron die er wél had moeten zijn, dan is er niets aan te tonen.
  if { [ -n "$old_line" ] && [ -z "$old_dir" ]; } || { [ -n "$new_line" ] && [ -z "$new_dir" ]; }; then
    emit "$name" "$from" "$to" UNKNOWN unknown "$generator" unavailable "$sources"
    return 0
  fi

  local plugin=false
  if [ -n "$old_dir" ] && has_plugin_platforms "$old_dir"; then plugin=true; fi
  if [ -n "$new_dir" ] && has_plugin_platforms "$new_dir"; then plugin=true; fi

  # Toegevoegd of verwijderd pakket: er valt niets te vergelijken. Een plugin
  # brengt of haalt daarmee platformcode, dus dat is ring 3.
  if [ -z "$old_dir" ] || [ -z "$new_dir" ]; then
    if [ "$plugin" = true ]; then
      emit "$name" "$from" "$to" 3 true "$generator" "n/a (toegevoegd of verwijderd)" "$sources"
    elif [ "$generator" = true ]; then
      emit "$name" "$from" "$to" 2 false true "n/a (toegevoegd of verwijderd)" "$sources"
    else
      emit "$name" "$from" "$to" 1 false false "n/a (toegevoegd of verwijderd)" "$sources"
    fi
    return 0
  fi

  if [ "$plugin" = true ]; then
    local nd
    nd="$(native_diff "$old_dir" "$new_dir")"
    if [ "$nd" = differs ]; then
      emit "$name" "$from" "$to" 3 true "$generator" differs "$sources"
    else
      emit "$name" "$from" "$to" 2 true "$generator" identical "$sources"
    fi
    return 0
  fi

  if [ "$generator" = true ]; then
    emit "$name" "$from" "$to" 2 false true n/a "$sources"
  else
    emit "$name" "$from" "$to" 1 false false n/a "$sources"
  fi
}

names="$(cut -f1 "$TMP/old.tsv" "$TMP/new.tsv" | sort -u)"
report="$TMP/report.txt"
: >"$report"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  classify_pair "$name" >>"$report"
done <<<"$names"

echo "old: $OLD_LOCK"
echo "new: $NEW_LOCK"
echo "cache: $PUB_CACHE_DIR"
echo
if [ "$changed" -eq 0 ]; then
  echo "Geen gewijzigde pakketten."
else
  cat "$report"
fi
printf 'summary: %d gewijzigd — ring1=%d ring2=%d ring3=%d unknown=%d\n' \
  "$changed" "$r1" "$r2" "$r3" "$runknown"
exit 0
