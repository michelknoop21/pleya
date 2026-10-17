"""Mockupset 44: schrijft de HTML en rendert de PNG's op 2x met de Playwright CLI (`pw`).

python3 gen44.py              alle HTML plus PNG's
python3 gen44.py --html       alleen HTML
python3 gen44.py 44-c         alleen beelden waarvan de naam zo begint

Elke pagina leest thema en formaat uit de URL (?t=dark|light&s=s|l|pad|mac&x=2). De zoom van
2 staat in hl44.js; daarom krijgt `pw` een viewport van twee keer de logische maat.
"""
import pathlib, subprocess, sys

D = pathlib.Path(__file__).resolve().parent
PHONE = ['44-a-home-ingang', '44-b-rijkop-lang-drukken', '44-c-aanpassen-lijst', '44-d-slepen',
         '44-e-eigen-rij-menu', '44-f-verwijderen', '44-g-nieuwe-rij-naam', '44-h-nieuwe-rij-filters',
         '44-i-nieuwe-rij-voorbeeld', '44-j-leeg-voorbeeld', '44-k-randgevallen']
SIZES = {'s': (375, 667), 'l': (430, 932), 'pad': (1180, 820), 'mac': (1440, 900)}
JOBS = [(n, s) for n in PHONE for s in ('s', 'l')] + [('44-l-ipad', 'pad'), ('44-m-mac-paneel', 'mac'), ('44-n-mac-rechtsklik', 'mac')]

HTML = """<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>{name}</title>
<link rel="stylesheet" href="hl44.css"></head><body><script src="hl44.js"></script><script>render('{name}')</script></body></html>
"""


def main(argv):
    only = [a for a in argv if not a.startswith('--')]
    for name in sorted({n for n, _ in JOBS}):
        (D / f'{name}.html').write_text(HTML.format(name=name))
    if '--html' in argv:
        return
    for name, size in JOBS:
        if only and not any(name.startswith(o) for o in only):
            continue
        w, h = SIZES[size]
        for theme in ('dark', 'light'):
            suffix = f'-{size}' if size in ('s', 'l') else ''
            out = D / f'{name}{suffix}-{theme}.png'
            url = f'file://{D}/{name}.html?t={theme}&s={size}&x=2'
            subprocess.run(['pw', 'screenshot', f'--viewport-size={w * 2},{h * 2}', '--wait-for-timeout=300', url, str(out)],
                           check=True, stdout=subprocess.DEVNULL)
            print(out.name)


if __name__ == '__main__':
    main(sys.argv[1:])
