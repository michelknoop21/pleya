#!/usr/bin/env bash
# Reconstructs the tvOS engine sources that the pinned engine fork ships, so a
# remote-input question can be answered from code instead of from device builds.
#
# The fork (github.com/edde746/flutter-tvos, see tvos/scripts/fetch_engine.sh) is
# a patch series on top of upstream Flutter, not a source tree. This script
# fetches the upstream file at the commit the fork pins, applies every patch of
# the pinned tag that touches it, and leaves a git repo with one commit per patch
# so `git log -p` shows who introduced what.
#
# Usage:
#   scripts/tvos_engine_source.sh [output-dir] [relative-engine-path ...]
#
# Defaults: output-dir = build/tvos-engine-source, paths = the two files that
# carry the whole Siri Remote press path. Reads the version from tvos/engine.version.
# Needs network access (raw.githubusercontent.com) and git; runs in under a minute.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/tvos-engine-source}"
shift || true

VERSION="$(tr -d '[:space:]' < "$ROOT/tvos/engine.version")"   # e.g. 3.44.0+3
FLUTTER_VERSION="${VERSION%%+*}"                                  # e.g. 3.44.0
FORK_URL="${FLUTTER_TVOS_FORK_URL:-https://github.com/edde746/flutter-tvos.git}"

DEFAULT_PATHS=(
  engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm
  engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterViewController.h
)
if [[ $# -gt 0 ]]; then PATHS=("$@"); else PATHS=("${DEFAULT_PATHS[@]}"); fi

FORK="$OUT/fork"
SRC="$OUT/src"
mkdir -p "$OUT"

if [[ ! -d "$FORK/.git" ]]; then
  echo "[engine-source] cloning fork patch series (v$VERSION)"
  git clone -q --depth 1 --branch "v$VERSION" "$FORK_URL" "$FORK"
fi
PATCH_DIR="$FORK/versions/$FLUTTER_VERSION/patches/engine"
LOCK="$FORK/versions/$FLUTTER_VERSION/sdk.lock"
[[ -d "$PATCH_DIR" ]] || { echo "error: $PATCH_DIR missing" >&2; exit 1; }

ENGINE_COMMIT="$(awk -F= '/^ENGINE_COMMIT=/{print $2}' "$LOCK")"
[[ -n "$ENGINE_COMMIT" ]] || { echo "error: ENGINE_COMMIT not in $LOCK" >&2; exit 1; }

rm -rf "$SRC"
mkdir -p "$SRC"
git -C "$SRC" init -q
INCLUDES=()
for rel in "${PATHS[@]}"; do
  mkdir -p "$SRC/$(dirname "$rel")"
  echo "[engine-source] fetching upstream $rel @ ${ENGINE_COMMIT:0:12}"
  curl -fsSL "https://raw.githubusercontent.com/flutter/flutter/$ENGINE_COMMIT/$rel" -o "$SRC/$rel"
  INCLUDES+=(--include="$rel")
done
git -C "$SRC" add -A
git -C "$SRC" -c user.name=engine-source -c user.email=none@localhost commit -qm "upstream flutter $FLUTTER_VERSION ($ENGINE_COMMIT)"

applied=0
for patch in "$PATCH_DIR"/*.patch; do
  touches=0
  for rel in "${PATHS[@]}"; do
    grep -q -- "$rel" "$patch" && touches=1 && break
  done
  [[ $touches -eq 1 ]] || continue
  name="$(basename "$patch")"
  if git -C "$SRC" apply "${INCLUDES[@]}" "$patch"; then
    git -C "$SRC" -c user.name=engine-source -c user.email=none@localhost commit -qam "$name" || true
    applied=$((applied + 1))
    echo "[engine-source] applied $name"
  else
    echo "error: $name did not apply; the reconstruction is not the fork's file" >&2
    exit 1
  fi
done

echo "[engine-source] $applied patches applied; sources in $SRC"
echo "[engine-source] press path: grep -n 'tvosHandlePressFromUIEvent\\|synthesizeRemotePressType\\|releaseAllSynthesizedPresses' $SRC/${PATHS[0]}"
