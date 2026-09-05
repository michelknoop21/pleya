#!/usr/bin/env bash
# Reads a Pleya app log (a file, or a log id from https://ice.pleya.app/logs/<id>)
# and prints the Siri Remote press trace with millisecond deltas, flagging the
# three shapes that mean the engine, not the viewer, produced an event:
#
#   EARLY-KEYUP    keyup of a key within 40 ms of its keydown while the press
#                  is still held: the engine released it (releaseAllSynthesizedPresses)
#   RE-TAP         a fresh keydown of the same key within 400 ms of an early keyup:
#                  the .ended phase re-tapped it (tapIfMissingKeyDown:YES), a second step
#   ENABLE-HELD    a menuPassthroughEnabled=true sent while a key is down: the
#                  message that triggers the release (needs 7786a952 or later to be logged)
#
# Exit 0 when nothing is flagged, 2 when something is. See
# docs/tvos-remote-press-pipeline.md for what each flag points at.
#
# Usage:
#   scripts/tvos_press_trace.sh wa6v9            # fetches the log
#   scripts/tvos_press_trace.sh path/to/log.txt

set -euo pipefail

SRC="${1:-}"
[[ -n "$SRC" ]] || { echo "usage: $0 <log-id|file>" >&2; exit 1; }
if [[ -f "$SRC" ]]; then
  LOG="$SRC"
else
  LOG="$(mktemp -t press-trace.XXXXXX)"
  trap 'rm -f "$LOG"' EXIT
  curl -fsS "https://ice.pleya.app/logs/$SRC" -o "$LOG"
fi

python3 - "$LOG" <<'PY'
import re, sys

path = sys.argv[1]
ts_re = re.compile(r'^\[(\d\d):(\d\d):(\d\d)\.(\d\d\d)\]')
interesting = re.compile(
    r'press-diag|native key(down|up)|TvosSystemNavigationService|NativeInputSession|native-input-session|'
    r'reason=onNavigate|consume native|swallow|yield to UIKit'
)
keydown = re.compile(r'native keydown logical=(\w+)')
keyup = re.compile(r'native keyup logical=(\w+)')
enable = re.compile(r'send menuPassthroughEnabled=true')

def ms(m):
    h, mi, s, f = (int(x) for x in m.groups())
    return ((h * 60 + mi) * 60 + s) * 1000 + f

down_at = {}          # key -> time of last keydown still held
early_up_at = {}      # key -> time of last early keyup
retap = set()         # keys whose current keydown was a re-tap; their keyup is part of it
flags = {'EARLY-KEYUP': 0, 'RE-TAP': 0, 'ENABLE-HELD': 0}
prev = None

with open(path, errors='replace') as fh:
    for raw in fh:
        line = raw.rstrip('\n')
        m = ts_re.match(line)
        if not m or not interesting.search(line):
            continue
        t = ms(m)
        delta = '' if prev is None else f'+{t - prev:4d}ms'
        prev = t
        tags = []

        kd = keydown.search(line)
        ku = keyup.search(line)
        if kd:
            k = kd.group(1)
            if k in early_up_at and t - early_up_at[k] <= 400:
                tags.append('RE-TAP')
                flags['RE-TAP'] += 1
                retap.add(k)
            else:
                retap.discard(k)
            down_at[k] = t
        elif ku:
            k = ku.group(1)
            if k in retap:
                tags.append('re-tap pair closes')
                retap.discard(k)
            elif k in down_at and t - down_at[k] <= 40:
                tags.append('EARLY-KEYUP')
                flags['EARLY-KEYUP'] += 1
                early_up_at[k] = t
            down_at.pop(k, None)
        elif enable.search(line) and down_at:
            tags.append('ENABLE-HELD(' + ','.join(down_at) + ')')
            flags['ENABLE-HELD'] += 1

        body = line[m.end():].strip()
        body = re.sub(r'\[DEBUG\] |\[INFO\] ', '', body)
        body = re.sub(r'key=\(type=(\w+).*?\)', r'key=\1', body)
        mark = ('  <-- ' + ' '.join(tags)) if tags else ''
        print(f'{line[1:13]} {delta:>8} {body[:150]}{mark}')

print()
print('summary: ' + ', '.join(f'{k}={v}' for k, v in flags.items()))
if any(flags.values()):
    print('verdict: the engine produced events the viewer did not; start at side door 1-3 in docs/tvos-remote-press-pipeline.md')
    sys.exit(2)
print('verdict: every keyup belongs to a real release')
PY
