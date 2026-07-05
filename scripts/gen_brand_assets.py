#!/usr/bin/env python3
"""Regenereer alle Pleya-merkassets uit de transparante P-mark + wordmark.

Idempotent: draai vanuit de repo-root (`python3 scripts/gen_brand_assets.py`).
Homescreen-icons tonen alleen de P; tvOS en grote formaten (Top Shelf, TV-banner,
OG-image) tonen de volledige lockup mét tagline. Eén script, geen ImageMagick/rsvg.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = (11, 11, 11, 255)                       # #0B0B0B
SRC_MARK = f"{ROOT}/assets/branding/pleya_mark.png"      # transparant, alleen de P
SRC_WORD = f"{ROOT}/assets/branding/pleya_wordmark.png"  # transparant, 'Pleya' wordmark
FONT = f"{ROOT}/assets/fonts/Inter-Medium.otf"
TAGLINE = "YOUR MEDIA. YOUR WAY."


def load_cropped(path):
    im = Image.open(path).convert("RGBA")
    return im.crop(im.split()[3].getbbox())


MARK = load_cropped(SRC_MARK)
WORD = load_cropped(SRC_WORD)


def fitted(img, box_w, box_h):
    r = min(box_w / img.width, box_h / img.height)
    return img.resize((max(1, round(img.width * r)), max(1, round(img.height * r))), Image.LANCZOS)


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


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", path.replace(ROOT + "/", ""), img.size)


# ---- iOS + macOS .icon: transparante P (icon.json levert de #0B0B0B fill) ----
for plat in ("ios", "macos"):
    save(mark_canvas(1024, 1024, 0.74), f"{ROOT}/{plat}/pleya.icon/Assets/pleya-cropped.png")

# ---- macOS legacy AppIcon.appiconset (overschaduwd door .icon, maar consistent) ----
MAC = f"{ROOT}/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if os.path.isdir(MAC):
    for s in (16, 32, 64, 128, 256, 512, 1024):
        save(mark_canvas(s, s, 0.80, BG).convert("RGBA"), f"{MAC}/app_icon_{s}.png")

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
    mark_canvas(256, 256, 0.80, BG).convert("RGBA").save(
        ico_path, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote windows/runner/resources/app_icon.ico multi-size")

# ---- Linux hicolor PNG's (vervangt de kapotte SVG-route) ----
LIN = f"{ROOT}/linux/packaging/icons"
for s in (16, 32, 48, 64, 128, 256, 512):
    save(mark_canvas(s, s, 0.80, BG), f"{LIN}/{s}x{s}/pleya.png")

# ---- tvOS layered brand assets: Back #0B0B0B / Middle ember / Front = lockup mét tagline ----
TV = f"{ROOT}/tvos/Runner/Assets.xcassets/AppIcon.brandassets"


def tv_layer(stack, name, img, at2x=None):
    p = f"{TV}/{stack}/{name}.imagestacklayer/Content.imageset"
    img.save(f"{p}/{name}.png")
    if at2x is not None:
        at2x.save(f"{p}/{name}@2x.png")
    print("wrote tvOS", stack, name, img.size)


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

# ---- Website ----
W = f"{ROOT}/website/src/lib/assets"
save(mark_canvas(1024, 1024, 0.92), f"{W}/pleya_logo.png")   # footer + hero-watermark (transparant)
save(mark_canvas(128, 128, 0.90), f"{W}/favicon.png")        # browser-tab (P-only)
old_mark = f"{W}/pleya-mark.png"
if os.path.exists(old_mark):
    os.remove(old_mark)
    print("removed", old_mark.replace(ROOT + "/", ""))
og = og_background(1200, 630)
og.alpha_composite(lockup(1200, 630, (0, 0, 0, 0)))
save(og.convert("RGB"), f"{ROOT}/website/static/og/pleya-social.png")

print("DONE")
