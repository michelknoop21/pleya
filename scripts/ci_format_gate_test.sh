#!/usr/bin/env bash
# Executes the Dart-format run block from ci.yml in isolation. This catches
# shell scoping mistakes that a textual workflow check would miss.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo/lib" "$TMP/bin"
printf 'void main() {}\n' > "$TMP/repo/lib/main.dart"
cat > "$TMP/bin/dart" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DART_CALLS"
EOF
chmod +x "$TMP/bin/dart"

awk '
  /^      - name: Verify formatting$/ { in_step = 1; next }
  /^      - name: Analyze code$/ { in_step = 0 }
  in_step && /^        run: \|$/ { next }
  in_step { sub(/^          /, ""); print }
' "$ROOT/.github/workflows/ci.yml" > "$TMP/format-step.sh"

export DART_CALLS="$TMP/dart-calls"
(
  cd "$TMP/repo"
  PATH="$TMP/bin:$PATH" bash "$TMP/format-step.sh"
)

if ! grep -q '^format --output=none --set-exit-if-changed' "$DART_CALLS" 2>/dev/null; then
  echo 'FAIL: de CI-formatstap riep dart format niet aan voor lib/main.dart' >&2
  exit 1
fi

echo 'PASS: de CI-formatstap roept dart format aan voor Dart-bronnen'
