#!/usr/bin/env bash
set -euo pipefail
# background_downloader eist iOS 14.0, maar de door Flutter gegenereerde
# FlutterGeneratedPluginSwiftPackage/Package.swift zet standaard .iOS("13.0").
# Flutter hoogt dat pas op tijdens `flutter build ios` (updateMinimumDeployment),
# maar een directe Xcode-build resolvet de Swift-packages daarvóór en faalt met
# "requires minimum platform version 14.0 ... but this target supports 13.0".
# Na elke `flutter clean`/`pub get` reset het manifest terug naar 13.0.
#
# Dit script forceert het manifest naar de project-deployment-target (15.5),
# zodat een Xcode/CLI-build zonder Flutter-tussenstap ook slaagt. Idempotent.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
TARGET="15.5"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest ontbreekt, genereren via config-only build..."
  (cd "$ROOT" && flutter build ios --config-only --no-codesign)
fi

if grep -q '.iOS("13.0")' "$MANIFEST"; then
  sed -i '' "s/\.iOS(\"13\.0\")/.iOS(\"${TARGET}\")/" "$MANIFEST"
  echo "Gepatcht: .iOS(\"13.0\") -> .iOS(\"${TARGET}\")"
else
  echo "Al goed: geen .iOS(\"13.0\") in manifest"
fi
