"""Mockupset 45: schrijft de HTML en rendert de PNG's op 2x met de Playwright CLI (`pw`).

python3 gen45.py            alle HTML plus PNG's
python3 gen45.py --html     alleen HTML
python3 gen45.py 45-d       alleen beelden waarvan de naam zo begint

Elke pagina leest thema en formaat uit de URL (?t=dark|light&s=ph|pad|tv&x=2). De zoom van 2
staat in kd45.js; daarom krijgt `pw` een viewport van twee keer de logische maat.
"""
import pathlib, subprocess, sys

D = pathlib.Path(__file__).resolve().parent
PHONE = ['45-a-ingang', '45-b-lijst', '45-c-leeg', '45-d-toevoegen', '45-e-bewerken', '45-f-wissen',
         '45-g-kaart', '45-h-kinderprofiel']
TV = ['45-j-tv-lijst', '45-k-tv-naam', '45-l-tv-maand']
SIZES = {'ph': (402, 874), 'pad': (1180, 820), 'tv': (1920, 1080)}
JOBS = [(n, 'ph', ('dark', 'light')) for n in PHONE] + [('45-i-ipad', 'pad', ('dark', 'light'))] + [(n, 'tv', ('dark',)) for n in TV]

HTML = """<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>{name}</title>
<link rel="stylesheet" href="kd45.css"></head><body><script src="kd45.js"></script><script>render('{name}')</script></body></html>
"""


def main(argv):
    only = [a for a in argv if not a.startswith('--')]
    for name, _, _ in JOBS:
        (D / f'{name}.html').write_text(HTML.format(name=name))
    if '--html' in argv:
        return
    for name, size, themes in JOBS:
        if only and not any(name.startswith(o) for o in only):
            continue
        w, h = SIZES[size]
        for theme in themes:
            out = D / f'{name}-{theme}.png'
            url = f'file://{D}/{name}.html?t={theme}&s={size}&x=2'
            subprocess.run(['pw', 'screenshot', f'--viewport-size={w * 2},{h * 2}', '--wait-for-timeout=300', url, str(out)],
                           check=True, stdout=subprocess.DEVNULL)
            print(out.name)


if __name__ == '__main__':
    main(sys.argv[1:])
