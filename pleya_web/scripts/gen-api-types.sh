#!/usr/bin/env bash
# Genereer de TypeScript-types uit het bevroren wire-contract.
#
# De bron is docs/pleya-protocol/v1/openapi.yaml en niets anders. Er wordt
# nooit met de hand in het resultaat geschreven; check-api-types.sh bewijst dat
# door opnieuw te genereren en te vergelijken.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SPEC="../docs/pleya-protocol/v1/openapi.yaml"
OUT="src/lib/api/schema.d.ts"

if [ ! -f "$SPEC" ]; then
  echo "✗ contract niet gevonden op $SPEC" >&2
  exit 1
fi

hash=$(shasum -a 256 "$SPEC" | cut -d' ' -f1)
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

bunx openapi-typescript "$SPEC" -o "$tmp" >/dev/null

{
  echo "// Gegenereerd uit docs/pleya-protocol/v1/openapi.yaml. Niet met de hand wijzigen."
  echo "// Opnieuw genereren: pleya_web/scripts/gen-api-types.sh"
  echo "// bron-sha256: $hash"
  cat "$tmp"
} > "$OUT"

echo "→ $OUT (bron-sha256 $hash)"
