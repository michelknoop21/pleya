#!/usr/bin/env bash
# Legt build/, tvos/build/ en .build/ van deze worktree op de externe SSD
# (PLEYA_BUILD_HOME); de worktree houdt een symlink. Een bestaande map verhuist
# één keer. Is de SSD niet gekoppeld (of draait dit op CI), dan gebeurt er
# niets. `flutter clean` wist alleen de symlink; de volgende run legt hem
# opnieuw naar dezelfde map. Een kapotte symlink (doelmap opgeruimd) wordt
# hersteld: de doelmap komt terug en de symlink wijst er weer naar. In elke
# sleutelmap waar een symlink van deze worktree naar wijst, staat deze worktree
# in .owner (één pad per regel); bestaande regels blijven staan. Zo blijft een
# verhuisde worktree, of een tweede worktree met dezelfde sleutel, eigenaar.
# prune_old_builds.sh ruimt een sleutelmap alleen op als elke eigenaar weg is.
# Aangeroepen door prune_old_builds.sh en door de iOS- en macOS-driver van
# Pleya Verify.
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
for rel in build tvos/build .build; do
  dest=$(readlink "$ROOT/$rel" 2>/dev/null) || continue
  [[ "$dest" == "$BUILD_HOME"/?* ]] || continue
  dest="${dest#"$BUILD_HOME"/}"
  # Een sleutel `.` of `..` zou .owner buiten BUILD_HOME schrijven.
  [[ "${dest%%/*}" == "." || "${dest%%/*}" == ".." ]] && continue
  owner="$BUILD_HOME/${dest%%/*}/.owner"
  [[ -d "${owner%/.owner}" ]] || continue
  grep -qxF -- "$ROOT" "$owner" 2>/dev/null && continue
  # Een bestand zonder slotregeleinde eerst afsluiten, anders plakt het pad vast.
  if [[ -s "$owner" && -n "$(tail -c 1 "$owner")" ]]; then echo >>"$owner"; fi
  printf '%s\n' "$ROOT" >>"$owner"
done
