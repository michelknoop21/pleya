#!/usr/bin/env bash
# Converts the Big P avatar layers (PNG with alpha, 1122 x 1402 canvas) to the
# WebP files the rig in src/lib/bigp loads. The source layers are not in this
# repo; point BIGP_SRC at the directory that holds them.
#
#   BIGP_SRC=/path/to/bigp website/scripts/gen-bigp-layers.sh
set -euo pipefail

SRC="${BIGP_SRC:?set BIGP_SRC to the directory with the PNG layers}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/src/lib/assets/bigp"
command -v cwebp >/dev/null || { echo "cwebp not found (brew install webp)" >&2; exit 1; }
[ -d "$SRC" ] || { echo "source directory not found: $SRC" >&2; exit 1; }
mkdir -p "$OUT"

# Full-canvas layers: lossy colour, sharp alpha so the cut-out edge stays clean.
FULL=(body body-noleg body-wijzen-noleg pose-zwaaien pose-juichen pose-duim_presenteren pose-vinger_presenteren pose-wijzen_links)
# Small layers that sit on top of the body. Mouths and brows must match the
# body underneath, so they get a higher quality than the full canvases.
SMALL=(mouth-rest mouth-small mouth-mid mouth-big mouth-o mouth-e mouth-laugh brow-l brow-r wave-arm aim-arm leg-l-upper leg-l-lower leg-r-upper leg-r-lower)

for name in "${FULL[@]}"; do
  cwebp -quiet -q 82 -alpha_q 100 -m 6 -sharp_yuv "$SRC/$name.png" -o "$OUT/$name.webp"
done
for name in "${SMALL[@]}"; do
  cwebp -quiet -q 92 -alpha_q 100 -m 6 -sharp_yuv "$SRC/$name.png" -o "$OUT/$name.webp"
done

du -ch "$OUT"/*.webp | tail -1

du -ch "$OUT"/*.webp | tail -1

# Posters in the example answer: Blender open movies only (CC BY), 300 px wide.
POSTERS="${BIGP_POSTERS:-}"
if [ -n "$POSTERS" ] && [ -d "$POSTERS" ]; then
  mkdir -p "$OUT/posters"
  for name in sintel spring charge; do
    cwebp -quiet -q 80 -resize 300 0 "$POSTERS/$name.jpg" -o "$OUT/posters/$name.webp"
  done
fi
