"""Zet per platform het scherm van vandaag (ASC-screenshots 24 september 2026) links en de
Liquid Glass-mockup rechts in één beeld. Gebruik: python3 compare.py [bronmap]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / 'Pictures/pleya-asc/2026-09-24')
HERE = Path(__file__).parent
OUT = HERE.parent / 'mockups-2026-09-24'
FONT = HERE.parent.parent / 'tvos-unified/src/assets/Inter-Bold.otf'
BG = (20, 20, 20)

def pair(today, mock, out, h, gap, label_px):
    a = Image.open(today).convert('RGB')
    b = Image.open(mock).convert('RGB')
    a = a.resize((round(a.width * h / a.height), h), Image.LANCZOS)
    b = b.resize((round(b.width * h / b.height), h), Image.LANCZOS)
    top = label_px * 3
    im = Image.new('RGB', (a.width + b.width + gap * 3, h + top + gap), BG)
    im.paste(a, (gap, top)); im.paste(b, (gap * 2 + a.width, top))
    d = ImageDraw.Draw(im); f = ImageFont.truetype(str(FONT), label_px)
    d.text((gap, label_px), 'Today (App Store screenshot, 24 Sep 2026)', font=f, fill=(255, 255, 255))
    d.text((gap * 2 + a.width, label_px), 'Liquid Glass mockup', font=f, fill=(255, 255, 255))
    im.save(OUT / out, optimize=True)
    print(out, im.size)

pair(SRC / 'iphone69/06-home.png', OUT / 'LG-01-home.png', 'LG-07-iphone-vergelijking.png', 2622, 60, 48)
pair(SRC / 'tvos/01-home.png', OUT / 'LG-04-home.png', 'LG-08-appletv-vergelijking.png', 1080, 40, 30)
