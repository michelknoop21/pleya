#!/bin/bash
# Checks the lipo shim against a fat binary it builds itself: present archs pass, a missing one fails.
set -euo pipefail
L="$(cd "$(dirname "$0")" && pwd)/lipo"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'int main(void){return 0;}\n' > "$T/m.c"
for a in arm64 x86_64; do xcrun clang -arch $a -o "$T/m.$a" "$T/m.c"; done
/usr/bin/lipo -create "$T/m.arm64" "$T/m.x86_64" -output "$T/fat"
"$L" "$T/fat" -verify_arch arm64 x86_64
"$L" -verify_arch arm64 "$T/fat"
! "$L" "$T/fat" -verify_arch arm64 i386
! "$L" "$T/m.arm64" -verify_arch x86_64
"$L" -info "$T/fat" | grep -q "x86_64 arm64"
echo "lipo-shim selftest OK"
