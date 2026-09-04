#!/usr/bin/env bash
# Versheidscontrole voor de gegenereerde API-client.
#
# Dezelfde rol die de codegen-sectie in scripts/ci_checks.sh voor Dart speelt:
# een gegenereerd bestand dat achterloopt op zijn bron is een fout, geen
# waarschuwing. Hier is de bron het contract, dus de controle is scherper dan
# een tijdstempel: er wordt opnieuw gegenereerd en byte-voor-byte vergeleken.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

OUT="src/lib/api/schema.d.ts"
[ -f "$OUT" ] || { echo "✗ $OUT ontbreekt — draai scripts/gen-api-types.sh" >&2; exit 1; }

before=$(cat "$OUT")
./scripts/gen-api-types.sh >/dev/null
after=$(cat "$OUT")

if [ "$before" != "$after" ]; then
  # Met een newline, want $(cat) eet de laatste op en de generator zet hem er
  # wel. Zonder die \n laat een gefaalde controle het bestand een byte korter
  # achter dan hij hem aantrof, en dan meldt de volgende run drift die deze run
  # zelf heeft gemaakt.
  printf '%s\n' "$before" > "$OUT"
  echo "✗ $OUT loopt achter op docs/pleya-protocol/v1/openapi.yaml" >&2
  echo "  Draai: pleya_web/scripts/gen-api-types.sh" >&2
  exit 1
fi

echo "✓ de gegenereerde client komt overeen met het contract"
