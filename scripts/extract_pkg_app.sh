#!/usr/bin/env bash
# Pakt de .app uit een flat installer-pkg met behoud van framework-symlinks.
#
# `pkgutil --expand-full` is de enige stock one-shot uitpakker, maar die
# dereferenced symlinks: `Versions/Current` en `Resources` worden echte
# directories terwijl de Bom ze als symlink verwacht → ITMS-90229 bij de macOS
# App Store-validatie. Deze route pakt de Payload zelf uit (`cpio -idm` behoudt
# symlinks), zodat `productbuild --component` daarna een correcte pkg bouwt.
#
# Gebruik: extract_pkg_app.sh <pkg> <dest-dir>
set -euo pipefail

pkg="${1:?pkg-pad ontbreekt}"
dest="${2:?doel-dir ontbreekt}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pkgutil --expand "$pkg" "$work/exp"
payload="$(/usr/bin/find "$work/exp" -name Payload | head -1)"
[ -n "$payload" ] || { echo "geen Payload in $pkg" >&2; exit 1; }

rm -rf "$dest"; mkdir -p "$dest"

magic="$(head -c4 "$payload" 2>/dev/null || true)"
if [ "$magic" = "pbzx" ]; then
  # pbzx-container (moderne pkg): chunks van [8B decomp-len][8B comp-len][data];
  # data is een xz-stream tenzij opgeslagen. Decode via stdlib lzma → cpio.
  /usr/bin/python3 - "$payload" <<'PY' | ( cd "$dest" && cpio -idm 2>/dev/null )
import sys, struct, lzma
f = open(sys.argv[1], "rb")
assert f.read(4) == b"pbzx", "geen pbzx-magic"
f.read(8)  # flags
out = sys.stdout.buffer
while True:
    hdr = f.read(16)
    if len(hdr) < 16:
        break
    _dlen, clen = struct.unpack(">QQ", hdr)
    chunk = f.read(clen)
    out.write(lzma.decompress(chunk) if chunk[:6] == b"\xfd7zXZ\x00" else chunk)
PY
else
  # oudere gzip-cpio Payload
  gzip -dc "$payload" | ( cd "$dest" && cpio -idm 2>/dev/null )
fi

# cpio schrijft de xattrs van symlinks als AppleDouble-sidecars (._naam) weg op
# volumes die geen symlink-xattrs ondersteunen. codesign weigert dan een framework
# met "unsealed contents present in the root directory". Weg ermee.
/usr/bin/find "$dest" -name '._*' -delete 2>/dev/null || true

app="$(/usr/bin/find "$dest" -maxdepth 3 -name '*.app' -type d | head -1)"
[ -n "$app" ] || { echo "geen .app in uitgepakte Payload" >&2; exit 1; }
echo "$app"
