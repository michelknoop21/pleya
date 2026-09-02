#!/usr/bin/env python3
"""Regenereer alle Pleya-merkassets uit de transparante P-mark + wordmark.

Idempotent: draai vanuit de repo-root (`python3 scripts/gen_brand_assets.py`).
Homescreen-icons tonen alleen de P; tvOS en grote formaten (Top Shelf, TV-banner,
OG-image) tonen de volledige lockup mét tagline. Eén script, geen ImageMagick/rsvg.
"""
import io
import os

import PIL
from PIL import Image, ImageDraw, ImageFilter, ImageFont, features

# ---- De canonieke generatieomgeving ----------------------------------------
# PNG-bytes zijn niet draagbaar tussen Pillow-builds. Twee dingen bepalen de
# uitvoer naast de pixels zelf: de deflate-implementatie waartegen Pillow is
# gelinkt (stock zlib versus zlib-ng comprimeren dezelfde scanlines anders) en
# FreeType, dat de tagline rastert. Byte-identieke uitvoer is daarom alleen
# binnen deze pin te garanderen, niet erbuiten.
#
# Daarom doet dit script twee dingen expliciet in plaats van op de standaarden
# te vertrouwen:
#   1. het noemt zijn encoderinstellingen (PNG_SAVE), zodat een nieuwe
#      Pillow-standaard de uitvoer niet stilletjes verschuift;
#   2. het schrijft een bestand alleen als de *pixels* veranderen (zie save()),
#      zodat een tweede run een schone tree oplevert — ook op een omgeving die
#      anders comprimeert dan die van de vorige generatie.
PILLOW_PIN = "12.3.0"  # zie scripts/requirements-brand.txt

# `optimize` en `compress_level` staan hier op de Pillow-standaarden van de pin.
# Ze staan er om vastgelegd te zijn, niet om de uitvoer te veranderen: een
# andere waarde zou zevenenveertig getrackte iconen opnieuw comprimeren zonder
# dat er één pixel verandert.
PNG_SAVE = {"optimize": False, "compress_level": 6}
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def generation_environment():
    """De eigenschappen die de bytes bepalen, als één regel."""
    try:
        zlib = f"zlib-ng {features.version_feature('zlib_ng')}" if features.check_feature(
            "zlib_ng") else f"zlib {features.version('zlib')}"
    except (ValueError, AttributeError):  # oudere Pillow kent de feature niet
        zlib = f"zlib {features.version('zlib')}"
    return f"Pillow {PIL.__version__} ({zlib}), FreeType {features.version('freetype2')}"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (11, 11, 11, 255)                       # #0B0B0B
SRC_MARK = f"{ROOT}/assets/branding/pleya_mark.png"          # transparant, alleen de P
SRC_LETTERING = f"{ROOT}/assets/branding/pleya_lettering.png"  # transparant, alleen "LEYA"
FONT = f"{ROOT}/assets/fonts/Inter-Medium.otf"
TAGLINE = "YOUR MEDIA. YOUR WAY."


def load_cropped(path):
    im = Image.open(path).convert("RGBA")
    return im.crop(im.split()[3].getbbox())


MARK = load_cropped(SRC_MARK)

# De belettering blijft op zijn eigen kanvashoogte staan: die draagt de verticale
# plaatsing én de marge rechts van het lockup, en allebei horen bij de tekening.
LETTERING = Image.open(SRC_LETTERING).convert("RGBA")

# De goedgekeurde compositieparameters van het lockup. Ze staan hier als getal en
# niet in een bestand, want dít is de bron van waarheid: de wordmark wordt
# samengesteld, niet ingelezen.
WORDMARK_CAP_HEIGHT = 658  # de hoogte die de P in het oude lockup had
WORDMARK_GAP = 20  # ruimte tussen de P en de "L"
WORDMARK_CAP_TOP = 1  # y waarop de P begint, gelijk aan de belettering


def build_wordmark():
    """Het Pleya-lockup, samengesteld uit de *huidige* mark plus de belettering.

    Dit bestond eerder als handgemaakt bestand, en dat is precies misgegaan: de
    P erin was een oudere tekening — dichte donkere binnenvorm, flauwe rode
    snelheidslijnen — terwijl `pleya_mark.png` allang een open binnenvorm en
    amberkleurige lijnen had. Omdat `lockup()` uit dat bestand werd opgebouwd,
    droeg alles wat eruit volgt die oude P mee: het tvOS-app-icoon, alle drie de
    Top Shelf-beelden, de Android TV-banner en het OG-beeld van de site, terwijl
    de iOS-, macOS-, Android- en Linux-iconen (via `mark_canvas`) de nieuwe
    droegen. Eén merk, twee P's, en niets dat ze bij elkaar hield.

    Daarom wordt het lockup nu samengesteld in plaats van bewaard. `pleya_mark.png`
    is de enige plek waar de P bestaat, en hij kan dus niet opnieuw los van
    zichzelf verouderen. Zie [DEC-074].

    De verhoudingen van het oude lockup blijven: dezelfde cap-height, dezelfde
    tussenruimte, dezelfde verticale uitlijning. De huidige mark is wel echt
    breder (1,099 tegen 1,002), en die wordt niet platgedrukt om binnen de oude
    kanvasbreedte te passen — het kanvas groeit mee.
    """
    p = fitted(MARK, MARK.width * 10, WORDMARK_CAP_HEIGHT)
    width = p.width + WORDMARK_GAP + LETTERING.width
    out = Image.new("RGBA", (width, LETTERING.height), (0, 0, 0, 0))
    out.alpha_composite(p, (0, WORDMARK_CAP_TOP))
    out.alpha_composite(LETTERING, (p.width + WORDMARK_GAP, 0))
    # De splitskolom hoort bij de compositie en wordt dus teruggegeven, niet
    # achteraf uit de pixels geraden: dat is precies waar de vorige versie op
    # stukliep toen de mark amberkleurige lijnen bleek te hebben.
    return out, p.width + WORDMARK_GAP // 2


def wordmark_layers():
    """Het lockup als twee lagen: de merklaag, en de belettering.

    De TV-topbar tekent het lockup rechtstreeks op de themakleur. Witte letters
    vallen op het lichte palet weg (1,12:1 tegen de paginagrond) terwijl de P
    blijft staan, en hoofdstuk 8.2 wil daar donkere tekst én een merkrode P. Uit
    één beeld met twee kleuren kan dat niet, dus de app krijgt de twee helften
    apart: de merklaag houdt altijd zijn eigen kleuren, de belettering neemt de
    inkt van het thema aan waar dat nodig is.

    Allebei de lagen houden het volledige kanvas, met de andere helft leeg. Ze
    zijn dus in hetzelfde rect te tekenen en reproduceren samen exact het lockup
    — geen naad, en geen marge die uit de pas kan gaan lopen.
    """
    split = WORDMARK_SPLIT
    _assert_layers_separable(WORDMARK, split)

    def layer(x0, x1):
        out = Image.new("RGBA", WORDMARK.size, (0, 0, 0, 0))
        out.paste(WORDMARK.crop((x0, 0, x1, WORDMARK.height)), (x0, 0))
        return out

    return layer(0, split), layer(split, WORDMARK.width)


def _assert_layers_separable(img, split):
    """Controleert wat er zojuist samengesteld is, in plaats van het te raden.

    De splitskolom komt uit de compositie; dit is de controle dat de twee helften
    werkelijk uit elkaar liggen. Het onderscheid is kleur en niet helderheid: de
    belettering is grijswaarden (wit, met donkere randpixels van de
    antialiasing), de mark is verzadigd rood en amber. Op helderheid toetsen
    liep stuk op precies die randpixels.
    """
    px = img.load()
    mark_chroma = 0
    for x in range(img.width):
        for y in range(img.height):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            saturated = max(r, g, b) - min(r, g, b) > 60
            if x < split and saturated:
                mark_chroma += 1
            elif x >= split and saturated:
                raise SystemExit(f"wordmark: merkinkt in de beletteringshelft op x={x}")
    if mark_chroma == 0:
        raise SystemExit("wordmark: geen merkinkt gevonden in de merkhelft")


def fitted(img, box_w, box_h):
    r = min(box_w / img.width, box_h / img.height)
    return img.resize((max(1, round(img.width * r)), max(1, round(img.height * r))), Image.LANCZOS)


# Na `fitted`, want [build_wordmark] gebruikt hem. Dit is de canonieke wordmark:
# alles hieronder dat een lockup tekent leest hém, niet een bewaard bestand.
WORDMARK, WORDMARK_SPLIT = build_wordmark()
WORD = WORDMARK.crop(WORDMARK.split()[3].getbbox())


def mark_canvas(w, h, frac, bg=None):
    """Canvas w×h (bg of transparant) met MARK gecentreerd, gevuld tot frac van het frame."""
    canvas = Image.new("RGBA", (w, h), bg if bg else (0, 0, 0, 0))
    m = fitted(MARK, int(w * frac), int(h * frac))
    canvas.alpha_composite(m, ((w - m.width) // 2, (h - m.height) // 2))
    return canvas


def tagline_image(px, color=(255, 255, 255, 102)):
    """Letter-spaced tagline (wit 40%), zoals de intro-splash."""
    font = ImageFont.truetype(FONT, px)
    spacing = px * 0.30
    total = sum(font.getlength(ch) + spacing for ch in TAGLINE) - spacing
    asc, desc = font.getmetrics()
    img = Image.new("RGBA", (int(total) + px, asc + desc + px // 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = px // 2
    for ch in TAGLINE:
        d.text((x, 0), ch, font=font, fill=color)
        x += font.getlength(ch) + spacing
    bb = img.getbbox()
    return img.crop(bb) if bb else img


def lockup(w, h, bg, tagline=True):
    """Wordmark (bevat de P) gecentreerd, met de tagline eronder wanneer tagline=True."""
    canvas = Image.new("RGBA", (w, h), bg)
    wd = fitted(WORD, int(w * 0.80), int(h * (0.50 if tagline else 0.66)))
    if not tagline:
        canvas.alpha_composite(wd, ((w - wd.width) // 2, (h - wd.height) // 2))
        return canvas
    tag = tagline_image(max(9, int(wd.height * 0.12)))
    max_tw = int(wd.width * 0.94)
    if tag.width > max_tw:
        r = max_tw / tag.width
        tag = tag.resize((max_tw, max(1, int(tag.height * r))), Image.LANCZOS)
    gap = int(wd.height * 0.12)
    group_h = wd.height + gap + tag.height
    oy = (h - group_h) // 2
    canvas.alpha_composite(wd, ((w - wd.width) // 2, oy))
    canvas.alpha_composite(tag, ((w - tag.width) // 2, oy + wd.height + gap))
    return canvas


def silhouette(w, h, frac):
    """Wit silhouet van de mark (alpha ≥50% → wit) op transparant — voor Android monochroom/notificatie."""
    m = fitted(MARK, int(w * frac), int(h * frac))
    a = m.split()[3].point(lambda v: 255 if v >= 128 else 0)
    white = Image.new("RGBA", m.size, (255, 255, 255, 0))
    white.putalpha(a)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.alpha_composite(white, ((w - m.width) // 2, (h - m.height) // 2))
    return canvas


def ember(w, h):
    """Transparante middenlaag met een zachte rood→amber radial glow (tvOS parallax)."""
    g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    cx, cy, r = w // 2, h // 2, int(min(w, h) * 0.55)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(229, 20, 15, 150))
    r2 = int(r * 0.5)
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(255, 176, 32, 120))
    return g.filter(ImageFilter.GaussianBlur(min(w, h) * 0.10))


def og_background(w, h):
    """Donker vlak met een subtiele rode radial achter het midden (OG-social)."""
    base = Image.new("RGBA", (w, h), BG)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    cx, cy, r = w // 2, int(h * 0.46), int(w * 0.40)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(229, 20, 15, 70))
    base.alpha_composite(glow.filter(ImageFilter.GaussianBlur(w * 0.08)))
    return base


def _encode(img, path):
    """Codeer `img` precies zoals het naar `path` geschreven zou worden."""
    fmt = "ICO" if path.lower().endswith(".ico") else "PNG"
    buf = io.BytesIO()
    if fmt == "ICO":
        img.save(buf, format="ICO", sizes=ICO_SIZES)
    else:
        img.save(buf, format="PNG", **PNG_SAVE)
    return fmt, buf.getvalue()


def _pixels(source, fmt):
    """De pixels van een gecodeerd beeld, per subbeeld en inclusief mode/size.

    Vergelijken op déze waarde en niet op de bestandsbytes is het hele punt: de
    bytes verschillen tussen Pillow-builds terwijl de tekening gelijk is.
    """
    im = Image.open(io.BytesIO(source) if isinstance(source, bytes) else source)
    if fmt == "ICO":
        return [(s, im.ico.getimage(s).convert("RGBA").tobytes()) for s in sorted(im.ico.sizes())]
    return [((im.mode, im.size), im.tobytes())]


def save(img, path):
    """Schrijf alleen als de tekening verandert; geef terug of dat gebeurd is.

    Een kale run herschreef eerder zevenenveertig getrackte iconen die
    pixel-identiek bleven, puur omdat deze Pillow anders comprimeert dan die van
    de vorige generatie. Dat is geen visuele regressie maar wel een
    determinisme-defect: run #2 hoorde een schone tree op te leveren en deed dat
    niet. De vergelijking gaat daarom over de pixels, niet over de bytes.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fmt, data = _encode(img, path)
    rel = path.replace(ROOT + "/", "")
    if os.path.exists(path):
        # Alleen het decoderen staat in de try. Een `print` erbinnen zetten is een
        # val: `BrokenPipeError` is een `OSError`, dus een afgekapte pipe
        # (`| head`) zou hier stil in het schrijfpad vallen en het bestand alsnog
        # herschrijven.
        try:
            same = _pixels(data, fmt) == _pixels(path, fmt)
        except OSError:  # onleesbaar of geen beeld: gewoon overschrijven
            same = False
        if same:
            print("unchanged", rel, img.size)
            return False
    with open(path, "wb") as fh:
        fh.write(data)
    print("wrote", rel, img.size)
    return True


print("generatieomgeving:", generation_environment())
if PIL.__version__ != PILLOW_PIN:
    print(f"  let op: de canonieke omgeving is Pillow {PILLOW_PIN}. Pixels horen gelijk te blijven,\n"
          "  maar nieuw geschreven bestanden kunnen andere bytes krijgen (zie scripts/requirements-brand.txt).")


# ---- iOS + macOS .icon: transparante P (icon.json levert de #0B0B0B fill) ----
for plat in ("ios", "macos"):
    save(mark_canvas(1024, 1024, 0.74), f"{ROOT}/{plat}/pleya.icon/Assets/pleya-cropped.png")

# ---- Android ----
A = f"{ROOT}/android/app/src/main/res"
launcher = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
fg = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
notif = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
banner = {"xhdpi": (320, 180), "xxhdpi": (480, 270), "xxxhdpi": (640, 360)}
for dpi, s in launcher.items():
    save(mark_canvas(s, s, 0.80, BG), f"{A}/mipmap-{dpi}/ic_launcher.png")
for dpi, s in fg.items():
    fgimg = mark_canvas(s, s, 0.62)                  # adaptief fg; xml voegt 16% inset toe
    save(fgimg, f"{A}/mipmap-{dpi}/ic_launcher_foreground.png")
    save(fgimg, f"{A}/drawable-{dpi}/ic_launcher_foreground.png")
    save(silhouette(s, s, 0.62), f"{A}/drawable-{dpi}/ic_launcher_monochrome.png")
for dpi, s in notif.items():
    save(silhouette(s, s, 0.90), f"{A}/drawable-{dpi}/ic_stat_notification.png")
for dpi, (w, h) in banner.items():
    save(lockup(w, h, BG), f"{A}/drawable-{dpi}/tv_banner.png")

# ---- Windows multi-size ico ----
ico_path = f"{ROOT}/windows/runner/resources/app_icon.ico"
if os.path.isdir(os.path.dirname(ico_path)):
    save(mark_canvas(256, 256, 0.80, BG).convert("RGBA"), ico_path)

# ---- Linux hicolor PNG's (vervangt de kapotte SVG-route) ----
LIN = f"{ROOT}/linux/packaging/icons"
for s in (16, 32, 48, 64, 128, 256, 512):
    save(mark_canvas(s, s, 0.80, BG), f"{LIN}/{s}x{s}/pleya.png")

# ---- tvOS layered brand assets: Back #0B0B0B / Middle ember / Front = lockup mét tagline ----
TV = f"{ROOT}/tvos/Runner/Assets.xcassets/AppIcon.brandassets"


def tv_layer(stack, name, img, at2x=None):
    p = f"{TV}/{stack}/{name}.imagestacklayer/Content.imageset"
    save(img, f"{p}/{name}.png")
    if at2x is not None:
        save(at2x, f"{p}/{name}@2x.png")


w1, h1 = 400, 240
tv_layer("App Icon.imagestack", "Back", Image.new("RGBA", (w1, h1), BG), Image.new("RGBA", (w1 * 2, h1 * 2), BG))
tv_layer("App Icon.imagestack", "Middle", ember(w1, h1), ember(w1 * 2, h1 * 2))
tv_layer("App Icon.imagestack", "Front", lockup(w1, h1, (0, 0, 0, 0)), lockup(w1 * 2, h1 * 2, (0, 0, 0, 0)))
w2, h2 = 1280, 768
tv_layer("App Icon - App Store.imagestack", "Back", Image.new("RGBA", (w2, h2), BG))
tv_layer("App Icon - App Store.imagestack", "Middle", ember(w2, h2))
tv_layer("App Icon - App Store.imagestack", "Front", lockup(w2, h2, (0, 0, 0, 0)))

# Top Shelf (lockup mét tagline)
save(lockup(1920, 720, BG), f"{TV}/Top Shelf Image.imageset/top-shelf.png")
save(lockup(2320, 720, BG), f"{TV}/Top Shelf Image Wide.imageset/top-shelf-wide.png")
save(lockup(4640, 1440, BG), f"{TV}/Top Shelf Image Wide.imageset/top-shelf-wide@2x.png")

# ---- iOS LaunchImage (storyboard) ----
LI = f"{ROOT}/ios/Runner/Assets.xcassets/LaunchImage.imageset"
if os.path.isdir(LI):
    for suf, s in (("", 256), ("@2x", 512), ("@3x", 768)):
        save(mark_canvas(s, s, 0.90), f"{LI}/LaunchImage{suf}.png")

# ---- Flutter-app: vrijstaande P voor topbar, zijbalk, splash, auth en about ----
save(mark_canvas(512, 512, 0.96), f"{ROOT}/assets/branding/pleya_logo.png")

# ---- Flutter-app: het canonieke lockup, en zijn twee lagen ----
# `pleya_wordmark.png` is vanaf nu een *product* van deze generator en geen
# handgemaakte bron meer, zodat de P er niet opnieuw los van `pleya_mark.png`
# kan verouderen. De app tekent de twee lagen (zie [PleyaWordmark]); het hele
# beeld staat er voor consumenten buiten de app, zoals de site.
save(WORDMARK, f"{ROOT}/assets/branding/pleya_wordmark.png")
_wm_mark, _wm_text = wordmark_layers()
save(_wm_mark, f"{ROOT}/assets/branding/pleya_wordmark_mark.png")
save(_wm_text, f"{ROOT}/assets/branding/pleya_wordmark_text.png")

# ---- Website ----
W = f"{ROOT}/website/src/lib/assets"
save(mark_canvas(1024, 1024, 0.92), f"{W}/pleya_logo.png")   # footer + hero-watermark (transparant)
save(mark_canvas(128, 128, 0.90), f"{W}/favicon.png")        # browser-tab (P-only)
save(WORDMARK, f"{W}/pleya_wordmark.png")                   # Hero.svelte — was een handmatige kopie
old_mark = f"{W}/pleya-mark.png"
if os.path.exists(old_mark):
    os.remove(old_mark)
    print("removed", old_mark.replace(ROOT + "/", ""))
# ---- Pleya Web: de merkmarkeringen van de browserclient ----
# Deze twee stonden als handmatige `sips`-verkleining in pleya_web/README.md en
# waren daardoor blijven staan op de oude, handgemaakte P: `app.html`,
# `NavRail.svelte`, `+layout.svelte`, `login/` en `setup/` tekenden hem nog.
# Ze horen bij dezelfde autoriteitsketen als de rest en worden hier dus
# meegegenereerd. De ondoorzichtige merkgrond blijft zoals hij was; alleen de P
# is die van nu.
PW = f"{ROOT}/pleya_web/static/brand"
if os.path.isdir(os.path.dirname(PW)):
    for s_ in (64, 256):
        save(mark_canvas(s_, s_, 0.96, BG), f"{PW}/pleya-mark-{s_}.png")

# ---- README-beeld ----
# Ook een afgeleide die nooit meebewoog. Niet gebundeld (geen `assets/`-glob in
# pubspec.yaml), dus geen runtime-autoriteit, maar wel het beeld bovenaan de
# repo.
save(mark_canvas(650, 650, 0.96, BG), f"{ROOT}/assets/pleya.png")

og = og_background(1200, 630)
og.alpha_composite(lockup(1200, 630, (0, 0, 0, 0)))
save(og.convert("RGB"), f"{ROOT}/website/static/og/pleya-social.png")

print("DONE")
