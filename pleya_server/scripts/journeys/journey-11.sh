#!/usr/bin/env bash
# Golden journey 11 (L.5): verzameling delen.
#
# Michel maakt een verzameling en deelt hem met Sanne, Sanne ziet hem in web en
# app, Kids niet, en een afspeellijst speelt op volgorde. Begint op een lege
# wegwerpstack en eindigt met één exit-code.
#
# De appkant loopt hier over `PleyaServerClient` tegen dezelfde server, zonder
# scherm. De Verify-bundel op een toestel uit L.5 hoort daar niet bij en staat
# open in de masterlijst.
#
# Vraagt Docker, bun met Playwright en de gepinde Flutter-SDK op PATH. Op Apple
# Silicon met DOCKER_DEFAULT_PLATFORM=linux/amd64: de image installeert Intel-
# VA-drivers die voor arm64 niet bestaan.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

cleanup() { "$ROOT/pleya_web/scripts/e2e-stack.sh" down; }
trap cleanup EXIT

cd "$ROOT"
pleya_web/scripts/e2e-stack.sh down
eval "$(pleya_web/scripts/e2e-stack.sh up)"
export PLEYA_E2E_PERSONAL=1

(cd pleya_web && bunx playwright test tests/e2e/journey-11.spec.ts --project=chromium)
flutter test test/pleya_server/pleya_journey_11_live_test.dart --reporter=compact
echo "journey 11 groen"
