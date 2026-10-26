#!/usr/bin/env bash
set -uo pipefail

# Major-baan: tilt één kandidaat (een pakket of een bundel uit deps_backlog.py
# --next-major) naar zijn nieuwe major, resolveert de graph en draait de gates
# van ring 2. Schrijft alleen pubspec.yaml en pubspec.lock; branch, commit,
# draft-PR en CI doet dependency-health.yml. Migratiecode schrijft dit script
# nooit, en de uitkomst wordt nooit automatisch gemerged.
#
#   scripts/deps_major.sh plus device_info_plus package_info_plus share_plus
#   scripts/deps_major.sh --probe file_picker      # alleen: resolveert het? (geen wijziging)
#
# Exit: 0 gates groen (bij --probe: er verschuift een constraint), 3 niets bewogen (de
# resolutie laat deze major nog niet toe),
# 1 resolutie faalde (bestanden teruggezet), 4 een gate is rood (naam op stdout
# als "gate: <naam>"; de wijziging blijft staan als startpunt voor de migratie).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE=0
[ "${1:-}" = "--probe" ] && { PROBE=1; shift; }
NAME="${1:-}"
[ $# -ge 1 ] && shift
PACKAGES=("$@")
if [ -z "$NAME" ]; then
  # In probe-modus is de naam het eerste pakket; dit vangt alleen een lege aanroep.
  echo "deps_major: kandidaat en pakketten verwacht" >&2
  exit 64
fi
# macOS-bash 3.2 faalt onder set -u op een lege array; vandaar de ${arr[@]+...}-vorm.
[ $PROBE = 1 ] && PACKAGES=("$NAME" ${PACKAGES[@]+"${PACKAGES[@]}"})
[ ${#PACKAGES[@]} -gt 0 ] || { echo "deps_major: geen pakketten" >&2; exit 64; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/pubspec.yaml" "$TMP/pubspec.yaml"
cp "$ROOT/pubspec.lock" "$TMP/old.lock"
restore() {
  cp "$TMP/pubspec.yaml" "$ROOT/pubspec.yaml"
  cp "$TMP/old.lock" "$ROOT/pubspec.lock"
}

if [ $PROBE = 1 ]; then
  (cd "$ROOT" && flutter pub upgrade --major-versions --dry-run "${PACKAGES[@]}" >"$TMP/probe.txt" 2>&1) || exit 1
  # Alleen een constraint-wijziging in pubspec.yaml telt; "> pakket" kan ook een minor-bump zijn.
  grep -qE '^  [a-z_0-9]+: .* -> ' "$TMP/probe.txt" && exit 0
  exit 3
fi

if [ -n "$(git -C "$ROOT" status --porcelain pubspec.yaml pubspec.lock)" ]; then
  echo "deps_major: pubspec.yaml of pubspec.lock heeft al wijzigingen" >&2
  exit 64
fi

(cd "$ROOT" && flutter pub upgrade --major-versions "${PACKAGES[@]}") || {
  restore
  echo "deps_major: flutter pub upgrade --major-versions faalde" >&2
  exit 1
}
(cd "$ROOT" && flutter pub get --enforce-lockfile) || {
  restore
  echo "deps_major: volledige resolutie faalde" >&2
  exit 1
}
if cmp -s "$TMP/pubspec.yaml" "$ROOT/pubspec.yaml"; then
  echo "deps_major: niets bewogen; de resolutie laat deze major nog niet toe"
  exit 3
fi

# Alleen ter rapportage: een plugin-major is ring 3 en wordt dus nooit auto-gemerged.
"$SCRIPT_DIR/classify_lock_diff.sh" --old "$TMP/old.lock" --new "$ROOT/pubspec.lock" | tee "$TMP/classify.txt"
echo "deps_major: kandidaat $NAME: ${PACKAGES[*]}"

# Gates van ring 2: codegen mag geen gegenereerde diff geven, daarna de CI-gate.
# Status plus inhoud van de diff: een al gewijzigd bestand blijft anders " M".
snapshot() { { git -C "$ROOT" status --porcelain; git -C "$ROOT" diff; } | shasum | cut -d' ' -f1; }
before="$(snapshot)"
if ! "$SCRIPT_DIR/codegen.sh" >"$TMP/codegen.log" 2>&1; then
  tail -30 "$TMP/codegen.log"
  echo "gate: codegen"
  exit 4
fi
if [ "$(snapshot)" != "$before" ]; then
  git -C "$ROOT" status --short | head -20
  echo "gate: codegen-diff"
  exit 4
fi
if ! "$SCRIPT_DIR/ci_checks.sh" >"$TMP/gate.log" 2>&1; then
  tail -30 "$TMP/gate.log"
  echo "gate: ci_checks"
  exit 4
fi
echo "deps_major: gates groen"
exit 0
