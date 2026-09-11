#!/usr/bin/env bash
# Deterministic loudness fixtures for scripts/loudness/prove.sh and the
# Android LoudnessDspTest WAV export.
#
#   fixtures.sh [out_dir]   (default: build/loudness/fixtures)
#
# Every fixture is 48 kHz 16-bit PCM WAV, built from fixed-seed lavfi sources.
# Level-targeted fixtures are generated, measured with measure.sh and scaled
# to the target, then measured again: a fixture more than 0.2 LU off its target
# fails the script. Drop freely usable speech/music into <out_dir>/../media and
# prove.sh picks it up as extra rows.
set -euo pipefail

GENERATOR_VERSION=1
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-build/loudness/fixtures}
mkdir -p "$out" "$out/../media"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ff() { ffmpeg -hide_banner -nostdin -loglevel error -y "$@"; }
integrated() { "$here/measure.sh" "$1" | sed -E 's/.*I=([^ ]+).*/\1/'; }

# Programme shape: pink noise with a slow swell plus a low tone, mono, 60 s.
# The shape is shared by the prog_* fixtures so only the level differs.
ff -f lavfi -i "anoisesrc=d=60:c=pink:r=48000:a=0.5:s=42" -f lavfi -i "sine=f=220:r=48000:d=60" \
  -filter_complex "[0]volume='0.55+0.45*sin(2*PI*0.2*t)':eval=frame[n];[1]volume=0.15[s];[n][s]amix=inputs=2:normalize=0" \
  -c:a pcm_f32le "$tmp/shape_mono.wav"
ff -i "$tmp/shape_mono.wav" -af "pan=stereo|c0=c0|c1=c0" -c:a pcm_f32le "$tmp/shape_stereo.wav"
ff -i "$tmp/shape_mono.wav" -af "pan=5.1|FL=c0|FR=c0|FC=c0|LFE=0*c0|BL=0.5*c0|BR=0.5*c0" -c:a pcm_f32le "$tmp/shape_5_1.wav"
# Loud and quiet halves of 10 s each: the dynamic case a fixed gain must
# leave alone and a realtime estimator must not pump on.
ff -i "$tmp/shape_stereo.wav" -af "volume='if(lt(mod(t,20),10),0.03,0.8)':eval=frame" -c:a pcm_f32le "$tmp/dynamic.wav"
# Reduce-loud-sounds: quiet dialogue, a 1 s passage 20 dB louder, quiet
# again. After the programme gain the burst sits about 8 dB over the
# compressor threshold and the quiet parts under its knee, so the jump in
# and out exercises attack and release. prove.sh --android compares the
# Android output with the ffmpeg reference in 10 ms windows (the D row).
ff -i "$tmp/shape_stereo.wav" -t 20 -af "volume='if(between(t,10,11),1,0.1)':eval=frame" -c:a pcm_f32le "$tmp/drc.wav"

# level <src> <target_lufs> <dst>: scale to the target, quantise, verify.
level() {
  local measured gain got
  measured=$(integrated "$1")
  gain=$(awk -v t="$2" -v m="$measured" 'BEGIN{printf "%.3f", t - m}')
  ff -i "$1" -af "volume=${gain}dB:precision=double" -c:a pcm_s16le -bitexact -map_metadata -1 "$3"
  got=$(integrated "$3")
  awk -v t="$2" -v g="$got" 'BEGIN{d=g-t; if (d<0) d=-d; exit !(d<=0.2)}' ||
    { echo "fixture $(basename "$3"): measured $got, target $2" >&2; exit 1; }
}

level "$tmp/shape_stereo.wav" -30 "$out/prog_-30.wav"
level "$tmp/shape_stereo.wav" -22 "$out/prog_-22.wav"
level "$tmp/shape_stereo.wav" -18 "$out/prog_-18.wav"
level "$tmp/shape_mono.wav" -28 "$out/mono.wav"
level "$tmp/shape_stereo.wav" -28 "$out/stereo.wav"
level "$tmp/shape_5_1.wav" -28 "$out/5_1.wav"
level "$tmp/dynamic.wav" -26 "$out/dynamic.wav"
level "$tmp/drc.wav" -26 "$out/drc.wav"

ff -f lavfi -i "anullsrc=r=48000:cl=stereo:d=20" -c:a pcm_s16le -bitexact -map_metadata -1 "$out/silence.wav"
# -75 LUFS sits under ebur128's -70 absolute gate, so it is set by gain
# against prog_-22 rather than measured.
ff -i "$out/prog_-22.wav" -t 20 -af "volume=-53dB:precision=double" -c:a pcm_s16le -bitexact -map_metadata -1 "$out/near_silence.wav"

# Intersample peaks: 2 ms bursts of fs/4 at a 45 degree phase every 5 s on
# top of prog_-30. The samples land at 0.707 of the waveform peak, so the
# bursts read about 3 dB lower as sample peak than as true peak.
ff -i "$out/prog_-30.wav" -f lavfi \
  -i "aevalsrc='if(lt(mod(t,5),0.002),0.89*sin(2*PI*12000*t+PI/4),0)|if(lt(mod(t,5),0.002),0.89*sin(2*PI*12000*t+PI/4),0)':s=48000:d=60" \
  -filter_complex "[0][1]amix=inputs=2:normalize=0" -c:a pcm_s16le -bitexact -map_metadata -1 "$out/isp.wav"

# Header still claims the full length; the data stops at 60 %.
size=$(wc -c <"$out/prog_-22.wav")
head -c $((size * 6 / 10)) "$out/prog_-22.wav" >"$out/truncated.wav"

{
  echo "generator_version=$GENERATOR_VERSION"
  echo "ffmpeg=$(ffmpeg -version | head -1)"
  for f in "$out"/*.wav; do printf '%s %s\n' "$(basename "$f")" "$("$here/measure.sh" "$f")"; done
} >"$out/manifest.txt"
cat "$out/manifest.txt"
