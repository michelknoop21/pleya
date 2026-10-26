#!/usr/bin/env bash
# Ruimt na een geslaagde upload naar App Store Connect op wat díe build nog liet
# liggen: de ipa of pkg met zijn export- en dSYM-bestanden en de archive van
# precies dat buildnummer op dat platform. De TestFlight-lanes roepen dit direct
# achter de upload aan (fastlane/Fastfile, prune_after_upload), dus het gebeurt
# bij elke upload, ook buiten een sessie. Overslaan met PLEYA_KEEP_BUILDS=1; met
# --dry-run (of PLEYA_PRUNE_DRY_RUN=1) alleen tonen wat weg zou gaan.
#
# Gebruik: scripts/prune_after_upload.sh <ios|appletvos|osx> <buildnummer> [--dry-run]
#
# Wat weg mag en wat blijft:
#   build/fastlane/ios en /macos        alles erin: dat zijn alleen de exports
#                                       van de lane (ipa, pkg, dSYM-zip, archive)
#   build/fastlane/tvos                 de losse exportbestanden, upload/ en de
#                                       bevroren archive Pleya-tvOS-<nummer>-
#                                       <sha>.xcarchive met zijn .sha256 van
#                                       dit nummer. Archives en .sha256 van
#                                       andere nummers blijven (tvos_upload
#                                       weigert een archive zonder sidecar) en
#                                       device/ ook: dat is de export van een
#                                       bevroren archive voor de hardwareronde
#   Xcode Archives                      een archive van nl.michelknoop.pleya met
#                                       dit buildnummer ÉN dit platform. Een
#                                       beta-run uploadt iOS, tvOS en macOS onder
#                                       hetzelfde nummer, dus het platform in de
#                                       app zelf (DTPlatformName) beslist
# De upload geldt als geslaagd zodra Apple het binary heeft ontvangen; de lanes
# wachten niet op de verwerking. Wijst Apple de build daarna af, dan moet er een
# nieuwe archive komen. Incrementele mappen (build/ios, tvos/build/dd,
# SourcePackages, DerivedData)
# blijven: die worden bij elke build hergebruikt. De generieke opruiming vóór
# een build staat in scripts/prune_old_builds.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() { echo "gebruik: prune_after_upload.sh <ios|appletvos|osx> <buildnummer> [--dry-run]" >&2; exit 2; }

[[ $# -ge 2 ]] || usage
platform="$1"
build="$2"
shift 2
DRY_RUN="${PLEYA_PRUNE_DRY_RUN:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) usage ;;
  esac
done
[[ "$build" =~ ^[0-9]+$ ]] || usage
case "$platform" in
  ios) dt_platform=iphoneos; out_dir=ios ;;
  appletvos) dt_platform=appletvos; out_dir=tvos ;;
  osx) dt_platform=macosx; out_dir=macos ;;
  *) usage ;;
esac

[[ "${PLEYA_KEEP_BUILDS:-}" == 1 ]] && exit 0

fastlane_out="$ROOT/build/fastlane/$out_dir"
archives="$HOME/Library/Developer/Xcode/Archives"
freed=0

remove() {
  local kb
  kb=$(du -sk "$1" 2>/dev/null | cut -f1 || echo 0)
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "prune_after_upload: zou verwijderen ($((kb / 1024)) MB) $1"
    freed=$((freed + kb))
  else
    rm -rf "$1" && freed=$((freed + kb))
  fi
}

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

# De Info.plist van de app in een archive: iOS en tvOS hebben hem naast de app,
# macOS onder Contents/.
app_plist() {
  local archive="$1" path
  path=$(plist_get "$archive/Info.plist" ApplicationProperties:ApplicationPath)
  [[ -n "$path" ]] || return 0
  for candidate in "$archive/Products/$path/Info.plist" "$archive/Products/$path/Contents/Info.plist"; do
    [[ -f "$candidate" ]] && { echo "$candidate"; return 0; }
  done
}

# Is dit de archive van de build die zojuist is geüpload?
is_uploaded_archive() {
  local archive="$1" id version plist
  id=$(plist_get "$archive/Info.plist" ApplicationProperties:CFBundleIdentifier)
  version=$(plist_get "$archive/Info.plist" ApplicationProperties:CFBundleVersion)
  [[ "$id" == nl.michelknoop.pleya && "$version" == "$build" ]] || return 1
  plist=$(app_plist "$archive")
  [[ -n "$plist" && "$(plist_get "$plist" DTPlatformName)" == "$dt_platform" ]]
}

if [[ -d "$fastlane_out" ]]; then
  if [[ "$out_dir" == tvos ]]; then
    # Bevroren archives (Pleya-tvOS-<nummer>-<sha>.xcarchive) van andere nummers
    # wachten mogelijk nog op tvos_upload; alleen die van dit nummer gaat weg.
    while IFS= read -r -d '' entry; do
      case "$(basename "$entry")" in
        Pleya-tvOS-"$build"-*.xcarchive | Pleya-tvOS-"$build"-*.xcarchive.sha256) remove "$entry" ;;
        # Archive en .sha256 van een ander nummer: tvos_upload weigert een
        # archive zonder zijn sidecar. device/ is de export van een bevroren
        # archive voor de hardwareronde en kan bij een ander nummer horen.
        *.xcarchive | *.xcarchive.sha256 | device) ;;
        *) remove "$entry" ;;
      esac
    done < <(find "$fastlane_out" -mindepth 1 -maxdepth 1 -print0)
  else
    while IFS= read -r -d '' entry; do
      remove "$entry"
    done < <(find "$fastlane_out" -mindepth 1 -maxdepth 1 -print0)
  fi
fi

if [[ -d "$archives" ]]; then
  while IFS= read -r -d '' archive; do
    if is_uploaded_archive "$archive"; then remove "$archive"; fi
  done < <(find "$archives" -maxdepth 2 -name '*.xcarchive' -print0)
  [[ "$DRY_RUN" == 1 ]] || find "$archives" -mindepth 1 -maxdepth 1 -type d -empty -delete
fi

if [[ "$DRY_RUN" == 1 ]]; then
  echo "prune_after_upload (dry-run): $((freed / 1024)) MB kan weg, $platform build $build"
else
  echo "prune_after_upload: $((freed / 1024)) MB vrijgemaakt na upload van $platform build $build"
fi
