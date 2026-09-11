#!/usr/bin/env bash
# Independent loudness meter for the loudness proof (DEC on the loudness engine).
#
#   measure.sh <file> [start_s duration_s]   -> "I=<LUFS> TP=<dBTP> LRA=<LU> SP=<dBFS> CLIP=<n>"
#   measure.sh --json <file>                 -> loudnorm's measured_* set as JSON
#
# I/TP/LRA come from ebur128 (true peak, 4x oversampled). SP is the sample peak
# and CLIP the number of samples at or beyond full scale, both from astats on
# a 16-bit quantisation, which is where a real output clips. Silence reports
# I=-70.0, ebur128's absolute gate.
set -euo pipefail

if [[ "${1:-}" == "--json" ]]; then
  ffmpeg -hide_banner -nostdin -nostats -i "$2" -af loudnorm=I=-22:TP=-2:LRA=9:print_format=json -f null - 2>&1 |
    awk '/^\{/{p=1} p{print} /^\}/{p=0}'
  exit 0
fi

file="$1"
trim=()
if [[ $# -ge 3 ]]; then trim=(-ss "$2" -t "$3"); fi

ebu=$(ffmpeg -hide_banner -nostdin -nostats ${trim[@]+"${trim[@]}"} -i "$file" -af ebur128=peak=true -f null - 2>&1 |
  awk '/Summary:/{s=1} s')
i=$(awk '/^ *I:/{print $2; exit}' <<<"$ebu")
lra=$(awk '/^ *LRA:/{print $2; exit}' <<<"$ebu")
tp=$(awk '/True peak:/{t=1} t && /Peak:/{print $2; exit}' <<<"$ebu")

st=$(ffmpeg -hide_banner -nostdin -nostats ${trim[@]+"${trim[@]}"} -i "$file" -af aformat=sample_fmts=s16,astats=measure_perchannel=none -f null - 2>&1 |
  awk '/Overall/{o=1} o')
sp=$(awk -F': ' '/Peak level dB/{print $2; exit}' <<<"$st")
pc=$(awk -F': ' '/ Peak count/{print int($2); exit}' <<<"$st")
clip=$(awk -v sp="$sp" -v pc="$pc" 'BEGIN{print (sp+0 > -0.001) ? pc : 0}')

printf 'I=%s TP=%s LRA=%s SP=%.2f CLIP=%s\n' "$i" "${tp:-nan}" "$lra" "$sp" "$clip"
