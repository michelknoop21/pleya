#!/usr/bin/env bash
# Loudness proof: renders every fixture through the candidate chains, measures
# the result with measure.sh (an independent meter), prints one table and
# exits non-zero when the chosen candidate misses the start criteria.
#
#   prove.sh                 fixtures from build/loudness/fixtures (run fixtures.sh first)
#   prove.sh --android DIR   measure <fixture>.android.wav files from LoudnessDspTest
#                            against CHOSEN on the same fixture, and the drc
#                            fixture against D, in time as well (the D row)
#
# Candidates (G = the canonical programme gain, see loudness_planner.dart):
#   A    volume=G, alimiter at -2 dBFS
#   A25  as A with the limiter at -2.5 dBFS (sample-peak margin for true peak)
#   A4x  as A with the limiter run at 192 kHz (true-peak limiting)
#   B    two-pass loudnorm, linear, with the measured_* set
#   C    volume=min(G, -2 - TP), no limiter
#   R    realtime loudnorm=I=-22:TP=-2:LRA=9, windows 0-10/0-30/0-60 s and a restart at 20 s
#   D    A4x with the reduce-loud-sounds compressor (-18 dB, 8:1) ahead of the limiter;
#        reported, not judged: compression lowers I by design
#        Under --android the drc fixture is judged on its dynamic response: the
#        level in 10 ms windows may differ from the ffmpeg D render by at most
#        DRC_TOL dB anywhere, reported separately for the jump in (attack,
#        10-10.5 s) and out (release, 11-11.5 s)
#   mpv  CHOSEN through `mpv --ao=pcm` with the same af string
#
# Criteria on CHOSEN (default A4x): I within 1 LU of -22 minus the planner's
# limiter reduction, TP <= -1.8 dBTP, no clipped samples. Fixtures the planner
# sends to realtime (silence, near silence) must stay below -50 LUFS under R.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fx=${LOUDNESS_FIXTURES:-build/loudness/fixtures}
out=${LOUDNESS_OUT:-build/loudness/out}
CHOSEN=${CHOSEN:-A4x}
mkdir -p "$out"

TARGET=-22 CEILING=-2 MAX_LOAD=6 DRC_TOL=0.5

ff() { ffmpeg -hide_banner -nostdin -loglevel fatal -y "$@"; }
field() { sed -E "s/.*$1=([^ ]+).*/\1/" <<<"$2"; }
lin() { awk -v d="$1" 'BEGIN{printf "%.4f", 10^(d/20)}'; }

# plan <I> <TP> -> "<gain> <reduction>" or "realtime"
plan() {
  awk -v i="$1" -v tp="$2" -v t=$TARGET -v c=$CEILING -v m=$MAX_LOAD 'BEGIN{
    if (i == "" || i+0 < -60 || i == "-inf" || tp+0 > 3) { print "realtime"; exit }
    g = t - i; if (g > 12) g = 12; if (g < -30) g = -30
    # No true peak: a boost is held at 0 (DEC-111 (6)); the held-back part is
    # the reduction, so the judge does not expect -22.
    if (tp == "") { r = g > 0 ? g : 0; printf "%.2f %.2f\n", g - r, r; exit }
    if (tp == "-inf") tp = -200
    load = (tp + g) - c; r = 0
    if (load > m) { r = load - m; g -= r }
    printf "%.2f %.2f\n", g, r }'
}

limiter() { echo "alimiter=limit=$(lin "$1"):level=false:attack=5:release=50:latency=1"; }
COMP="acompressor=threshold=-18dB:ratio=8:attack=5:release=250:makeup=1"

chain() { # chain <candidate> <G> <TP> [measured json]
  case $1 in
    A) echo "volume=${2}dB:precision=float,$(limiter -2)" ;;
    A25) echo "volume=${2}dB:precision=float,$(limiter -2.5)" ;;
    A4x) echo "volume=${2}dB:precision=float,aresample=192000,$(limiter -2),aresample=48000" ;;
    C) awk -v g="$2" -v tp="$3" 'BEGIN{v=-2-tp; if (g<v) v=g; printf "volume=%.2fdB:precision=float\n", v}' ;;
    D) echo "volume=${2}dB:precision=float,$COMP,aresample=192000,$(limiter -2),aresample=48000" ;;
  esac
}

# levels <wav> [skip]: RMS level in dB per 10 ms window, one per line, after
# dropping the first [skip] samples.
levels() {
  ffmpeg -hide_banner -nostdin -loglevel fatal -i "$1" -af "atrim=start_sample=${2:-0},asetpts=N/SR/TB,asetnsamples=n=480:p=0,astats=metadata=1:reset=1:measure_perchannel=none:measure_overall=RMS_level,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-" -f null - |
    awk -F= '/RMS_level/{print $2}'
}

row() { printf '%-16s %-5s %7s %7s %7s %6s %7s %5s  %s\n' "$@"; }
judge() { # judge <I> <TP> <clip> <expected I|any>
  # "any" when the planner already expects limiter work: the limited peaks
  # carried loudness of their own, so only the ceiling and clipping are judged.
  awk -v i="$1" -v tp="$2" -v c="$3" -v e="$4" 'BEGIN{d=(e=="any")?0:i-e; if (d<0) d=-d; exit !(d<=1 && tp+0<=-1.8 && c==0)}'
}

fail=0

if [[ "${1:-}" == "--android" ]]; then
  dir=$2
  row fixture cand gain I TP LRA SP clip verdict
  for f in "$dir"/*.android.wav; do
    name=$(basename "$f" .android.wav)
    src="$fx/$name.wav"
    m=$("$here/measure.sh" "$src")
    p=$(plan "$(field I "$m")" "$(field TP "$m")")
    [[ $p == realtime ]] && continue
    g=${p% *} cand=$CHOSEN
    [[ $name == drc ]] && cand=D
    ff -i "$src" -af "$(chain "$cand" "$g")" -ar 48000 -c:a pcm_f32le "$out/$name.ref.wav"
    ref=$("$here/measure.sh" "$out/$name.ref.wav")
    got=$("$here/measure.sh" "$f")
    d=$(awk -v a="$(field I "$got")" -v b="$(field I "$ref")" 'BEGIN{printf "%.2f", a-b}')
    ok=$(awk -v d="$d" -v tp="$(field TP "$got")" -v c="$(field CLIP "$got")" \
      'BEGIN{x=d<0?-d:d; print (x<=1 && tp+0<=-1.8 && c==0) ? "ok" : "FAIL"}')
    [[ $ok == ok ]] || fail=1
    row "$name" android "$g" "$(field I "$got")" "$(field TP "$got")" "$(field LRA "$got")" \
      "$(field SP "$got")" "$(field CLIP "$got")" "$ok (dI vs $cand $d)"
    [[ $name == drc ]] || continue
    # D: compared in time, the Android output shifted back by the limiter
    # latency the test reports. Silence (below -70 dB) is skipped.
    # The shift leaves the last Android window partly filled; it is dropped.
    dyn=$(paste <(levels "$f" "$(cat "$dir/latency_frames")" | sed '$d') <(levels "$out/$name.ref.wav") | awk -v tol=$DRC_TOL '
      NF < 2 || $1 ~ /inf/ || $2 ~ /inf/ || $2 < -70 { next }
      { t = (NR - 1) / 100; d = $1 - $2; if (d < 0) d = -d
        if (d > all) { all = d; at = t }
        if (t >= 10 && t < 10.5 && d > atk) atk = d
        if (t >= 11 && t < 11.5 && d > rel) rel = d }
      END { printf "%s max|dL| %.2f dB at %.2f s, attack %.2f, release %.2f, tol %s\n",
              (all <= tol && atk > 0 && rel > 0) ? "ok" : "FAIL", all, at, atk, rel, tol }')
    [[ $dyn == ok* ]] || fail=1
    row "$name" D "$g" - - - - - "$dyn"
  done
  exit $fail
fi

have_mpv=0
command -v mpv >/dev/null && have_mpv=1

row fixture cand gain I TP LRA SP clip verdict
for src in "$fx"/*.wav "$fx"/../media/*.{wav,flac,mka,mkv,mp4}; do
  [[ -f $src ]] || continue
  name=$(basename "${src%.*}")
  m=$("$here/measure.sh" "$src")
  I=$(field I "$m") TP=$(field TP "$m")
  row "$name" src - "$I" "$TP" "$(field LRA "$m")" "$(field SP "$m")" "$(field CLIP "$m")" ""
  p=$(plan "$I" "$TP")

  if [[ $p == realtime ]]; then
    ff -i "$src" -af "loudnorm=I=-22:TP=-2:LRA=9" -ar 48000 -c:a pcm_f32le "$out/$name.R.wav"
    r=$("$here/measure.sh" "$out/$name.R.wav")
    ok=$(awk -v i="$(field I "$r")" -v c="$(field CLIP "$r")" 'BEGIN{print (i+0<=-50 && c==0) ? "ok" : "FAIL"}')
    [[ $ok == ok ]] || fail=1
    row "$name" R rt "$(field I "$r")" "$(field TP "$r")" "$(field LRA "$r")" "$(field SP "$r")" "$(field CLIP "$r")" "$ok (planner: realtime)"
    continue
  fi

  g=${p% *} red=${p#* }
  expect=$(awk -v r="$red" -v t=$TARGET 'BEGIN{if (r>0) print "any"; else printf "%.2f", t - r}')
  for cand in A A25 A4x C D; do
    ff -i "$src" -af "$(chain $cand "$g" "$TP")" -ar 48000 -c:a pcm_f32le "$out/$name.$cand.wav"
    r=$("$here/measure.sh" "$out/$name.$cand.wav")
    verdict=""
    if judge "$(field I "$r")" "$(field TP "$r")" "$(field CLIP "$r")" "$expect"; then verdict=ok; else verdict=miss; fi
    [[ $cand == D ]] && verdict="reported"
    if [[ $cand == "$CHOSEN" ]]; then
      [[ $verdict == ok ]] || fail=1
      verdict="$verdict (chosen, expect I $expect)"
    fi
    row "$name" "$cand" "$g" "$(field I "$r")" "$(field TP "$r")" "$(field LRA "$r")" "$(field SP "$r")" "$(field CLIP "$r")" "$verdict"
  done

  # B: two-pass loudnorm. It silently falls back to dynamic mode when the
  # linear gain would push the true peak over its ceiling; say so.
  js=$("$here/measure.sh" --json "$src")
  mv() { awk -F'"' -v k="$1" '$2==k{print $4}' <<<"$js"; }
  bchain="loudnorm=I=-22:TP=-2:LRA=9:measured_I=$(mv input_i):measured_TP=$(mv input_tp):measured_LRA=$(mv input_lra):measured_thresh=$(mv input_thresh):linear=true"
  mode=$(ffmpeg -hide_banner -nostdin -nostats -i "$src" -af "$bchain:print_format=json" -ar 48000 -c:a pcm_f32le -y "$out/$name.B.wav" 2>&1 |
    awk -F'"' '$2=="normalization_type"{print $4}')
  r=$("$here/measure.sh" "$out/$name.B.wav")
  row "$name" B - "$(field I "$r")" "$(field TP "$r")" "$(field LRA "$r")" "$(field SP "$r")" "$(field CLIP "$r")" "loudnorm mode=$mode"

  # R: realtime, at start, over growing windows, and after a restart at 20 s.
  ff -i "$src" -af "loudnorm=I=-22:TP=-2:LRA=9" -ar 48000 -c:a pcm_f32le "$out/$name.R.wav"
  ff -ss 20 -i "$src" -af "loudnorm=I=-22:TP=-2:LRA=9" -ar 48000 -c:a pcm_f32le "$out/$name.R20.wav"
  w=""
  for win in 10 30 60; do w="$w ${win}s=$(field I "$("$here/measure.sh" "$out/$name.R.wav" 0 $win)")"; done
  w="$w seek20+10s=$(field I "$("$here/measure.sh" "$out/$name.R20.wav" 0 10)")"
  r=$("$here/measure.sh" "$out/$name.R.wav")
  row "$name" R rt "$(field I "$r")" "$(field TP "$r")" "$(field LRA "$r")" "$(field SP "$r")" "$(field CLIP "$r")" "windows:$w"

  if [[ $have_mpv == 1 ]]; then
    mpv --no-config --really-quiet --no-video --audio-samplerate=48000 --ao=pcm --ao-pcm-file="$out/$name.mpv.wav" \
      --af="$(chain "$CHOSEN" "$g" "$TP")" "$src" >/dev/null 2>&1 || true
    r=$("$here/measure.sh" "$out/$name.mpv.wav")
    d=$(awk -v a="$(field I "$r")" -v b="$(field I "$("$here/measure.sh" "$out/$name.$CHOSEN.wav")")" 'BEGIN{printf "%.2f", a-b}')
    verdict=miss
    judge "$(field I "$r")" "$(field TP "$r")" "$(field CLIP "$r")" "$expect" && verdict=ok
    [[ $verdict == ok ]] || fail=1
    row "$name" mpv "$g" "$(field I "$r")" "$(field TP "$r")" "$(field LRA "$r")" "$(field SP "$r")" "$(field CLIP "$r")" "$verdict (dI vs ffmpeg $d)"
  fi
done
[[ $have_mpv == 1 ]] || echo "mpv not on PATH: Apple row skipped (brew install mpv)" >&2
exit $fail
