#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# Gegenereerde code hangt aan de SDK-versie; drift hier geeft diffs die pas in
# CI opvallen.
scripts/check_flutter_version.sh
dart run slang
exec dart run build_runner build --delete-conflicting-outputs "$@"
