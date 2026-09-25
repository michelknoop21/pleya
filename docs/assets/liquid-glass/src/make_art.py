"""Knipt het beeldmateriaal voor de Liquid Glass-mockups uit de ASC-screenshots van
24 september 2026 (Blender-content van de demoserver). Schrijft naar art/, dat niet in git
staat. Gebruik: python3 make_art.py [bronmap]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / 'Pictures/pleya-asc/2026-09-24')
OUT = Path(__file__).parent / 'art'
OUT.mkdir(exist_ok=True)

# naam: (bestand, (links, boven, rechts, onder)) in pixels van de bron
CROPS = {
    # iPhone 6.9 (1320x2868): de schone hero's van de detailpagina
    'bbb-wide':     ('iphone69/02-detail-bbb.png',    (58, 352, 1262, 1020)),
    'sintel-wide':  ('iphone69/01-detail-sintel.png', (58, 352, 1262, 1020)),
    # tvOS (3840x2160): videobeeld uit de speler, zonder titel en bediening
    'bbb-frame':    ('tvos/04-player.png',            (622, 280, 3218, 1740)),
    # posters zonder badge
    'caminandes-poster': ('tvos/02-movies.png',       (752, 506, 1257, 1268)),
    'elephants-poster':  ('tvos/02-movies.png',       (3192, 506, 3697, 1268)),
    'charge-poster':     ('tvos/alt/alt-home-rows.png', (172, 1524, 624, 2160)),
    'spring-poster':     ('tvos/alt/alt-home-rows.png', (2030, 418, 2476, 1100)),
    'tears-poster':      ('tvos/alt/alt-home-rows.png', (2572, 418, 3020, 1100)),
    'sintel-poster':     ('tvos/alt/alt-home-rows.png', (1484, 418, 1932, 1100)),
    # posters met een bekeken-vinkje van de bron (klein, rechtsboven)
    'coffeerun-poster':  ('tvos/05-search.png',       (130, 716, 662, 1520)),
    'dweebs-poster':     ('tvos/05-search.png',       (1362, 742, 1866, 1500)),
}

# het bekeken-vinkje van de bron (middelpunt, straal in het uitsnijdsel) wordt overgeschilderd
# met het stuk poster links ervan, zodat een poster ook in een verder-kijkenrij kan staan
BADGES = {'sintel-poster': (405, 45, 30), 'coffeerun-poster': (473, 54, 48), 'dweebs-poster': (449, 53, 48)}

for name, (f, box) in CROPS.items():
    im = Image.open(SRC / f).convert('RGB').crop(box)
    if name in BADGES:
        x, y, r = BADGES[name]
        r += 6
        patch = im.crop((x - 3 * r, y - r, x - r, y + r))
        mask = Image.new('L', patch.size, 0)
        ImageDraw.Draw(mask).ellipse((4, 4, 2 * r - 4, 2 * r - 4), fill=255)
        im.paste(patch, (x - r, y - r), mask.filter(ImageFilter.GaussianBlur(3)))
    im.save(OUT / f'{name}.jpg', quality=92)
    print(name, im.size)
