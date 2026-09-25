#!/usr/bin/env bash
set -uo pipefail

# Git sets GIT_DIR (and friends) for hook invocations. Inside `flutter pub
# run`, that leaks into Flutter's own SDK-version probe (`git describe` from
# Flutter's checkout) and makes Flutter misreport its version as
# `1.35.1-0.0.pre-1`, which then fails dependency resolution. Strip those
# vars so the script behaves the same when invoked from a hook as it does
# from a plain shell.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# check-unused-code en check-unused-files kosten samen ruim anderhalve minuut
# (gemeten 23 sep 2026: 50 s en 41 s), en ze kunnen per definitie niets vinden
# dat aan de commit zelf ligt: ze beoordelen de hele lib-boom, niet de diff.
# In CI draaien ze onverkort door, dus de dekking verandert niet; hier zijn ze
# opt-in zodat een commit niet elke keer op een boombrede scan wacht.
WITH_UNUSED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --with-unused) WITH_UNUSED=1; shift ;;
    -h|--help)
      echo "gebruik: scripts/ci_checks.sh [--with-unused]"
      echo "  --with-unused  draai ook de harde dart_code_linter-regels, check-unused-code en check-unused-files (CI doet dit altijd)"
      exit 0 ;;
    *) echo "ci_checks: onbekend argument: $1" >&2; exit 64 ;;
  esac
done

if [ -t 1 ]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GRN=$'\e[32m'; DIM=$'\e[2m'; RST=$'\e[0m'
else
  BOLD=""; RED=""; GRN=""; DIM=""; RST=""
fi
section() { printf "\n%s==> %s%s\n" "$BOLD" "$1" "$RST"; }
ok()   { printf "  %sPASS%s  %s\n" "$GRN" "$RST" "$1"; }
fail() { printf "  %sFAIL%s  %s\n" "$RED" "$RST" "$1"; }
skip() { printf "  %sSKIP%s  %s\n" "$DIM" "$RST" "$1"; }

if ! command -v flutter >/dev/null 2>&1 || ! command -v dart >/dev/null 2>&1; then
  fail "flutter/dart not in PATH"
  echo "  Install Flutter: https://docs.flutter.dev/get-started/install"
  echo "  Bypass temporarily: SKIP_HOOKS=1 git commit ..."
  exit 1
fi

have_dart_code_linter() {
  [ -f "$ROOT/.dart_tool/package_config.json" ] && \
    grep -q '"name": *"dart_code_linter"' "$ROOT/.dart_tool/package_config.json" 2>/dev/null
}

FAILED=0

# Adviserend en niet meegeteld in FAILED: draait deze run als pre-commit hook,
# dan staan de hooks per definitie aan en zegt hij niets. Draait iemand hem met
# de hand op een clone waar setup_hooks.sh nooit liep, dan is dit de plek waar
# dat opvalt.
scripts/check_hooks_installed.sh || true

# 0. SDK-pin (.fvmrc) — dart format verschilt per SDK-versie, dus drift hier
#    maakt elke volgende check onbetrouwbaar.
section "flutter sdk pin"
out="$(mktemp)"
if scripts/check_flutter_version.sh >"$out" 2>&1; then
  ok "flutter $(scripts/check_flutter_version.sh --print) (.fvmrc)"
else
  fail "SDK-versie wijkt af van .fvmrc"
  sed 's/^/    /' "$out"
  FAILED=1
fi
rm -f "$out"

# 1. dart format (mirrors ci.yml "Verify formatting")
section "dart format"
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
  find lib $([ -d test ] && echo test) \
    -name "*.dart" ! -name "*.g.dart" ! -name "*.freezed.dart" \
    -type f -print0 2>/dev/null
)
if [ ${#files[@]} -eq 0 ]; then
  skip "no dart files"
else
  out="$(mktemp)"
  if dart format --output=none --set-exit-if-changed "${files[@]}" >"$out" 2>&1; then
    ok "${#files[@]} file(s) correctly formatted"
  else
    fail "formatting issues"
    sed 's/^/    /' "$out"
    FAILED=1
  fi
  rm -f "$out"
fi

# 2. Codegen freshness (build_runner outputs newer than their sources)
section "codegen freshness"
stale=()
while IFS= read -r -d '' src; do
  for gen in "${src%.dart}.g.dart" "${src%.dart}.freezed.dart"; do
    if [ -f "$gen" ] && [ "$src" -nt "$gen" ]; then
      stale+=("${src#./}")
      break
    fi
  done
done < <(find lib -name "*.dart" ! -name "*.g.dart" ! -name "*.freezed.dart" -type f -print0 2>/dev/null)
if [ ${#stale[@]} -eq 0 ]; then
  ok "no stale generated files"
else
  fail "${#stale[@]} dart source(s) newer than their generated .g/.freezed:"
  printf '    %s\n' "${stale[@]}"
  echo "    Run: scripts/codegen.sh"
  FAILED=1
fi

# 3. Native formatting
section "native format"
out="$(mktemp)"
if scripts/format_native.sh --check >"$out" 2>&1; then
  ok "native files correctly formatted"
else
  fail "native formatting issues"
  sed 's/^/    /' "$out"
  FAILED=1
fi
rm -f "$out"

# 3. flutter analyze (mirrors ci.yml "Analyze code")
section "flutter analyze"
# Alleen de diagnostics van de analyzer zelf tellen mee. Regels van de
# dart_code_linter-plugin (kebab-case, bv. `prefer-first`) komen bij een
# eenmalige `flutter analyze` willekeurig binnen: de CLI stopt zodra de server
# klaar is en wacht niet op de plugin, die bestand voor bestand in mapvolgorde
# werkt. Lokaal kwam test/ binnen en lib/ niet, in CI andersom, en soms elke
# melding dubbel. Een steekproef kan geen gate zijn; ci.yml filtert hetzelfde.
# De pluginmeldingen blijven hieronder zichtbaar als advies, en in de IDE.
# Het filter kijkt naar de regelcode, niet naar de ernst: ook een pluginregel
# die in analysis_options.yaml op `severity: error` staat, telt hier niet mee.
# Wat echt moet blokkeren, staat in scripts/dcl_hard_rules.sh (stap 4).
# Zonder "No issues found!" of "issues found" is analyze zelf niet klaar
# gekomen (crash, pub niet opgehaald); dat telt als fout, niet als groen.
out="$(mktemp)"
flutter analyze >"$out" 2>&1 || true
plugin_rule='• [a-z0-9]+(-[a-z0-9]+)+[[:space:]]*$'
core="$(grep -E "error •|warning •" "$out" | grep -vE "$plugin_rule" || true)"
if ! grep -qE "No issues found!|issues? found" "$out"; then
  fail "flutter analyze kwam niet tot een resultaat"
  tail -n 20 "$out" | sed 's/^/    /'
  FAILED=1
elif printf '%s\n' "$core" | grep -q "error •"; then
  fail "errors"
  printf '%s\n' "$core" | sed 's/^/    /'
  FAILED=1
elif [ -n "$core" ]; then
  fail "warnings (treated as failure, matching CI)"
  printf '%s\n' "$core" | sed 's/^/    /'
  FAILED=1
else
  ok "no errors or warnings"
fi
advice="$(grep -E "error •|warning •" "$out" | grep -E "$plugin_rule" | sort -u || true)"
if [ -n "$advice" ]; then
  printf "  %sadvies van dart_code_linter, telt niet mee:%s\n" "$DIM" "$RST"
  printf '%s\n' "$advice" | sed 's/^/    /'
fi
rm -f "$out"

# 4. Harde dart_code_linter-regels (mirrors ci.yml "Check hard dart_code_linter rules")
section "dart_code_linter: harde regels"
if [ "$WITH_UNUSED" -eq 0 ]; then
  skip "boombrede scan, draait in CI — lokaal met --with-unused"
elif ! have_dart_code_linter; then
  skip "dart_code_linter unresolved — run 'flutter pub get'"
else
  out="$(mktemp)"
  if scripts/dcl_hard_rules.sh >"$out" 2>&1; then
    ok "$(tail -n 1 "$out")"
  else
    fail "harde regels"
    sed 's/^/    /' "$out"
    FAILED=1
  fi
  rm -f "$out"
fi

# 5. Unused code (mirrors ci.yml "Check for unused code")
section "dart_code_linter: unused code"
if [ "$WITH_UNUSED" -eq 0 ]; then
  skip "boombrede scan, draait in CI — lokaal met --with-unused"
elif ! have_dart_code_linter; then
  skip "dart_code_linter unresolved — run 'flutter pub get'"
else
  out="$(mktemp)"
  flutter pub run dart_code_linter:metrics check-unused-code lib >"$out" 2>&1 || true
  if grep -qi "no unused code found" "$out"; then
    ok "none"
  else
    fail "unused code detected:"
    sed 's/^/    /' "$out"
    FAILED=1
  fi
  rm -f "$out"
fi

# 6. Unused files (mirrors ci.yml "Check for unused files")
section "dart_code_linter: unused files"
if [ "$WITH_UNUSED" -eq 0 ]; then
  skip "boombrede scan, draait in CI — lokaal met --with-unused"
elif ! have_dart_code_linter; then
  skip "dart_code_linter unresolved — run 'flutter pub get'"
else
  out="$(mktemp)"
  flutter pub run dart_code_linter:metrics check-unused-files lib >"$out" 2>&1 || true
  if grep -qi "no unused files found" "$out"; then
    ok "none"
  else
    fail "unused files detected:"
    sed 's/^/    /' "$out"
    FAILED=1
  fi
  rm -f "$out"
fi

if [ "$FAILED" -ne 0 ]; then
  printf "\n%sOne or more checks failed.%s Bypass with SKIP_HOOKS=1 (or --no-verify).\n" "$RED" "$RST"
  exit 1
fi
printf "\n%sAll checks passed.%s\n" "$GRN" "$RST"
