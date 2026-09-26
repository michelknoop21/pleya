#!/usr/bin/env bash
# Reads a Pleya app log (a file, or a log id from https://ice.pleya.app/logs/<id>)
# and prints the Siri Remote press trace with millisecond deltas, flagging the
# shapes that mean the engine, not the viewer, produced an event:
#
#   EARLY-KEYUP    keyup of a key within 40 ms of its keydown while the press
#                  is still held: the engine released it (releaseAllSynthesizedPresses).
#                  Menu (escape) never counts here: tvOS delivers it on release,
#                  which is expected, not a defect (NAV2).
#   KEYUP-ONLY     a keyup with no keydown seen for that key: a lost click
#                  (SEL2, log ijqxp 23:07:33.053: Select stuck from the
#                  keyboard session ate the next real press).
#   RE-TAP         a fresh keydown of the same key within 400 ms of an early keyup:
#                  the .ended phase re-tapped it (tapIfMissingKeyDown:YES), a second step.
#                  Judged by whether the re-tap keydown has its own `native press=...
#                  phase=0` line (NAV2): uikit-began (UIKit delivered a new press
#                  lifecycle, station 1, the engine is not involved) or engine-synth
#                  (no began reached the hook: side door 2/4, tapIfMissingKeyDown);
#                  unknown when the build predates that channel. The `uipress` hash is
#                  no evidence either way: UIKit reuses one UIPress object per press
#                  type, so it is equal for every press of a direction (log oc8pw, DBL1).
#   NATIVE-BOUNCE  UIKit itself delivers a began for a key within 40 ms after that
#                  key's ended, and that second lifecycle is itself shorter than
#                  40 ms: no finger releases and re-clicks that fast. Station 1
#                  (remote or tvOS), not the engine (DBL1, first seen in log oc8pw,
#                  build 303). Shows `uikit=` gaps when the log carries `ts=` (DBL1
#                  diagnostic, UIPress.timestamp).
#                  With the DBL1 hardware fields (`gcA=` clickpad click,
#                  `gcX=`/`gcY=` thumb position, `gcN=` controllers) each bounce
#                  also says what the remote reported at the ended before it, at
#                  its began and at its ended: click-held (one held click became two
#                  presses), no-click (presses from the touch position alone) or
#                  click-toggles (the switch itself went up and down).
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
    r'press-diag|native press=|native key(down|up)|TvosSystemNavigationService|NativeInputSession|'
    r'native-input-session|reason=onNavigate|consume native|swallow|yield to UIKit'
)
keydown = re.compile(r'native keydown logical=(\w+)')
keyup = re.compile(r'native keyup logical=(\w+)')
enable = re.compile(r'send menuPassthroughEnabled=true')
pressdiag = re.compile(r'native press=(\w+)(?:\(\d+\))? phase=(-?\d+) uipress=([0-9a-fA-F]+)'
                       r'(?: t=\d+)?(?: ts=(\d+))?')
DIRECTION_KEYS = {'up': 'arrowUp', 'down': 'arrowDown', 'left': 'arrowLeft', 'right': 'arrowRight'}
BOUNCE_MS = 40
hwfield = re.compile(r'\b(gcN|gcA|gcX|gcY|resp|gr)=(\S+)')

def hw_of(line):
    return dict(hwfield.findall(line))

def hw_summary(states):
    """states: hw dicts at the ended before a bounce, at its began and at its ended."""
    clicks = [st.get('gcA') for st in states]
    if None in clicks:
        return ''
    prev_end, began, _ = clicks
    if prev_end == '1':
        verdict = 'click-held'      # UIKit ended a press while the click was still down
    elif began == '0':
        verdict = 'no-click'        # a began without any click: the touch position made it
    else:
        verdict = 'click-toggles'   # the click really went up and down again
    last = states[-1]
    pos = f" x={last.get('gcX', '?')} y={last.get('gcY', '?')}" if 'gcX' in last else ''
    return f" hw={verdict} gcA={''.join(c or '?' for c in clicks)}{pos} gcN={last.get('gcN', '?')}"

MENU_KEY = 'escape'  # tvOS delivers Menu on release; expected, not a defect (NAV2)
RETAP_WINDOW_MS = 400
NEAREST_DIAG_WINDOW_MS = 30
# A keyup whose tracked keydown is older than this is not that keydown's
# release: no button stays physically down for seconds. It is the tell that
# the *real* keydown for this keyup was swallowed by the engine ("negeert een
# .began voor een toets die al in de set staat", SEL2) while a stale entry
# from an earlier, unrelated press was still sitting in down_at.
STALE_KEYDOWN_MS = 2000

def ms(m):
    h, mi, s, f = (int(x) for x in m.groups())
    return ((h * 60 + mi) * 60 + s) * 1000 + f

def began_line_for(diag_events, key, t, window=NEAREST_DIAG_WINDOW_MS):
    """The nearest `native press=` line at or before a keydown, if it is this key's began."""
    for (dt, name, phase) in reversed(diag_events):
        if t - dt > window:
            return False
        if dt <= t:
            return DIRECTION_KEYS.get(name) == key and phase == '0'
    return False

down_at = {}          # key -> time of last keydown still held
early_up_at = {}      # key -> time of last early keyup
retap = set()         # keys whose current keydown was a re-tap; their keyup is part of it
diag_events = []      # (time, press name, phase) from `native press=` lines (NAV2)
native_ended = {}     # press name -> (time, uikit ts) of its last native ended (phase 3)
native_began = {}     # press name -> (time, uikit ts, bounce candidate) of its open began
last_end_hw = {}      # press name -> hw dict at its last native ended
flags = {'EARLY-KEYUP': 0, 'KEYUP-ONLY': 0, 'RE-TAP': 0, 'NATIVE-BOUNCE': 0, 'ENABLE-HELD': 0}
verdicts = {'uikit-began': 0, 'engine-synth': 0, 'unknown': 0}
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

        pd = pressdiag.search(line)
        kd = keydown.search(line)
        ku = keyup.search(line)
        if pd:
            name, phase, uikit = pd.group(1), pd.group(2), pd.group(4)
            uikit = int(uikit) if uikit else None
            diag_events.append((t, name, phase))
            if phase == '0':
                prev_end = native_ended.get(name)
                candidate = prev_end is not None and t - prev_end[0] <= BOUNCE_MS
                native_began[name] = (t, uikit, candidate and prev_end, hw_of(line))
            elif phase == '3' and name in native_began:
                bt, buikit, prev_end, began_hw = native_began.pop(name)
                if prev_end and t - bt <= BOUNCE_MS:
                    detail = f'gap={bt - prev_end[0]}ms hold={t - bt}ms'
                    if buikit is not None and prev_end[1] is not None and uikit is not None:
                        detail += f' uikit gap={buikit - prev_end[1]}ms hold={uikit - buikit}ms'
                    detail += hw_summary([last_end_hw.get(name, {}), began_hw, hw_of(line)])
                    tags.append(f'NATIVE-BOUNCE({detail})')
                    flags['NATIVE-BOUNCE'] += 1
                native_ended[name] = (t, uikit)
                last_end_hw[name] = hw_of(line)
        elif kd:
            k = kd.group(1)
            if k in early_up_at and t - early_up_at[k] <= RETAP_WINDOW_MS:
                if not diag_events:
                    verdict = 'unknown'
                elif began_line_for(diag_events, k, t):
                    verdict = 'uikit-began'
                else:
                    verdict = 'engine-synth'
                verdicts[verdict] += 1
                tags.append(f'RE-TAP({verdict})')
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
                if k != MENU_KEY:
                    tags.append('EARLY-KEYUP')
                    flags['EARLY-KEYUP'] += 1
                    early_up_at[k] = t
            elif k not in down_at or t - down_at[k] > STALE_KEYDOWN_MS:
                tags.append('KEYUP-ONLY')
                flags['KEYUP-ONLY'] += 1
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
if flags['RE-TAP']:
    print('re-tap origin: ' + ', '.join(f'{k}={v}' for k, v in verdicts.items()))
if verdicts['engine-synth']:
    print(f"verdict: {verdicts['engine-synth']} RE-TAP(engine-synth): a keydown without its own UIKit "
          'began, the engine synthesized it; side door 2/4 in docs/tvos-remote-press-pipeline.md')
    sys.exit(2)
if flags['NATIVE-BOUNCE'] or verdicts['uikit-began']:
    print('verdict: UIKit delivered a second press lifecycle itself (station 1, NATIVE-BOUNCE); the '
          'engine is not involved, see the DBL1 row in docs/tvos-remote-press-pipeline.md')
    sys.exit(2)
if any(flags.values()):
    print('verdict: the engine produced events the viewer did not; start at side door 1-3 in docs/tvos-remote-press-pipeline.md')
    sys.exit(2)
print('verdict: every keyup belongs to a real release')
PY
