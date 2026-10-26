#!/usr/bin/env bash
# Zelftest voor prune_after_upload.sh in een nep-repo en nep-HOME: na een upload
# gaan de exports en de archive van dat buildnummer op dat platform weg, en niets
# anders. Een archive van een ander nummer, van een ander platform onder
# hetzelfde nummer (een beta-run uploadt drie platforms onder één nummer), van
# een andere bundle of een bevroren tvOS-archive van een ander nummer blijft
# staan. --dry-run en PLEYA_KEEP_BUILDS=1 wissen niets; een ongeldig argument
# wist niets en geeft een foutcode.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/prune_after_upload.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox"

PB=/usr/libexec/PlistBuddy

# mkarchive <map> <bundle-id> <buildnummer> <DTPlatformName> <app-pad> <plist-pad>
mkarchive() {
  local dir="$1" id="$2" version="$3" dt="$4" app="$5" plist="$6"
  mkdir -p "$dir/Products/$app"
  "$PB" -c "Add :ApplicationProperties dict" \
    -c "Add :ApplicationProperties:CFBundleIdentifier string $id" \
    -c "Add :ApplicationProperties:CFBundleVersion string $version" \
    -c "Add :ApplicationProperties:ApplicationPath string $app" "$dir/Info.plist" >/dev/null
  mkdir -p "$(dirname "$dir/Products/$app/$plist")"
  "$PB" -c "Add :DTPlatformName string $dt" "$dir/Products/$app/$plist" >/dev/null
}

setup() {
  rm -rf repo home
  mkdir -p repo/scripts repo/build/fastlane/{ios,macos,tvos/device,tvos/upload}
  cp "$script" repo/scripts/prune_after_upload.sh
  touch repo/build/fastlane/ios/{Runner.ipa,Runner.app.dSYM.zip}
  touch repo/build/fastlane/macos/Pleya-signed.pkg
  touch repo/build/fastlane/tvos/{Runner.ipa,Runner.app.dSYM.zip} repo/build/fastlane/tvos/device/x repo/build/fastlane/tvos/upload/y
  mkarchive repo/build/fastlane/tvos/Pleya-tvOS-412-aaaa.xcarchive nl.michelknoop.pleya 412 appletvos Applications/Runner.app Info.plist
  mkarchive repo/build/fastlane/tvos/Pleya-tvOS-413-bbbb.xcarchive nl.michelknoop.pleya 413 appletvos Applications/Runner.app Info.plist
  local a=home/Library/Developer/Xcode/Archives/2026-10-26
  mkarchive "$a/Runner ios412.xcarchive" nl.michelknoop.pleya 412 iphoneos Applications/Runner.app Info.plist
  mkarchive "$a/Runner tv412.xcarchive" nl.michelknoop.pleya 412 appletvos Applications/Runner.app Info.plist
  mkarchive "$a/Runner mac412.xcarchive" nl.michelknoop.pleya 412 macosx Applications/Pleya.app Contents/Info.plist
  mkarchive "$a/Runner ios410.xcarchive" nl.michelknoop.pleya 410 iphoneos Applications/Runner.app Info.plist
  mkarchive "$a/Runner verify412.xcarchive" nl.michelknoop.pleya.verify 412 iphoneos Applications/Runner.app Info.plist
}

run() { HOME="$sandbox/home" "$sandbox/repo/scripts/prune_after_upload.sh" "$@"; }

A="home/Library/Developer/Xcode/Archives/2026-10-26"
F=repo/build/fastlane
everything=("$F/ios/Runner.ipa" "$F/ios/Runner.app.dSYM.zip" "$F/macos/Pleya-signed.pkg"
  "$F/tvos/Runner.ipa" "$F/tvos/Runner.app.dSYM.zip" "$F/tvos/device/x" "$F/tvos/upload/y"
  "$F/tvos/Pleya-tvOS-412-aaaa.xcarchive" "$F/tvos/Pleya-tvOS-413-bbbb.xcarchive"
  "$A/Runner ios412.xcarchive" "$A/Runner tv412.xcarchive" "$A/Runner mac412.xcarchive"
  "$A/Runner ios410.xcarchive" "$A/Runner verify412.xcarchive")

expect() { # expect <gone|kept> <pad>...
  local want="$1" p; shift
  for p in "$@"; do
    if [[ "$want" == gone && -e "$p" ]]; then echo "FOUT: $p staat er nog"; exit 1; fi
    if [[ "$want" == kept && ! -e "$p" ]]; then echo "FOUT: $p is gewist"; exit 1; fi
  done
}

# Ongeldige aanroepen: foutcode en niets gewist.
setup
for bad in "" "ios" "watchos 412" "ios abc" "ios 412 --dryrun"; do
  # shellcheck disable=SC2086
  if run $bad >/dev/null 2>&1; then echo "FOUT: '$bad' werd geaccepteerd"; exit 1; fi
done
expect kept "${everything[@]}"

# --dry-run en PLEYA_KEEP_BUILDS=1 wissen niets.
out=$(run ios 412 --dry-run)
expect kept "${everything[@]}"
grep -qF "$F/ios/Runner.ipa" <<<"$out" || { echo "FOUT: dry-run noemt de ipa niet"; exit 1; }
grep -qF "Runner ios412.xcarchive" <<<"$out" || { echo "FOUT: dry-run noemt de archive niet"; exit 1; }
PLEYA_KEEP_BUILDS=1 run ios 412 >/dev/null
expect kept "${everything[@]}"

# iOS 412: de exports en alleen de iOS-archive van 412.
run ios 412 >/dev/null
expect gone "$F/ios/Runner.ipa" "$F/ios/Runner.app.dSYM.zip" "$A/Runner ios412.xcarchive"
expect kept "$F/macos/Pleya-signed.pkg" "$F/tvos/Runner.ipa" "$F/tvos/Pleya-tvOS-412-aaaa.xcarchive" \
  "$A/Runner tv412.xcarchive" "$A/Runner mac412.xcarchive" "$A/Runner ios410.xcarchive" "$A/Runner verify412.xcarchive"

# tvOS 412: de losse exports, device/, upload/ en de bevroren archive van 412,
# maar niet die van 413.
setup
run appletvos 412 >/dev/null
expect gone "$F/tvos/Runner.ipa" "$F/tvos/Runner.app.dSYM.zip" "$F/tvos/device/x" "$F/tvos/upload/y" \
  "$F/tvos/Pleya-tvOS-412-aaaa.xcarchive" "$A/Runner tv412.xcarchive"
expect kept "$F/tvos/Pleya-tvOS-413-bbbb.xcarchive" "$F/ios/Runner.ipa" "$F/macos/Pleya-signed.pkg" \
  "$A/Runner ios412.xcarchive" "$A/Runner mac412.xcarchive" "$A/Runner ios410.xcarchive" "$A/Runner verify412.xcarchive"

# macOS 412: de pkg en de macOS-archive, de rest blijft.
setup
run osx 412 >/dev/null
expect gone "$F/macos/Pleya-signed.pkg" "$A/Runner mac412.xcarchive"
expect kept "$F/ios/Runner.ipa" "$F/tvos/Runner.ipa" "$A/Runner ios412.xcarchive" "$A/Runner tv412.xcarchive" \
  "$A/Runner ios410.xcarchive" "$A/Runner verify412.xcarchive"

echo "test_prune_after_upload: OK"
