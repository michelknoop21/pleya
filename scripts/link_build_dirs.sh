#!/usr/bin/env bash
# Legt build/, tvos/build/ en .build/ van deze worktree op de externe SSD
# (PLEYA_BUILD_HOME); de worktree houdt een symlink. Een bestaande map verhuist
# één keer. Is de SSD niet gekoppeld (of draait dit op CI), dan gebeurt er
# niets. `flutter clean` wist alleen de symlink; de volgende run legt hem
# opnieuw naar dezelfde map. Een kapotte symlink (doelmap opgeruimd) wordt
# hersteld: de doelmap komt terug en de symlink wijst er weer naar. Aangeroepen door prune_old_builds.sh en door de
# iOS- en macOS-driver van Pleya Verify.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_HOME="${PLEYA_BUILD_HOME:-/Volumes/SSD/pleya-builds}"
[[ -d "$(dirname "$BUILD_HOME")" ]] || exit 0

key="${ROOT#"$HOME"/}"
key="${key//\//_}"
key="${key#.}"
for rel in build tvos/build .build; do
  link="$ROOT/$rel"
  target="$BUILD_HOME/$key/$rel"
  if [[ -L "$link" ]]; then
    # Heel symlink: niets te doen. Kapotte symlink (doel is opgeruimd of hoort
    # bij een andere sleutel): weghalen en hieronder opnieuw naar $target leggen.
    [[ -e "$link" ]] && continue
    rm "$link"
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -d "$link" ]]; then
    rm -rf "$target"
    mv "$link" "$target"
  else
    mkdir -p "$target"
  fi
  ln -s "$target" "$link"
done
