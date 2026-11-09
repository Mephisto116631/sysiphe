"""Génère le logo Sysiphe et les icônes Android depuis source_illustration.jpg.

Usage (depuis la racine du repo) : python assets/logo/generate_logo.py
Dépendances : pillow, numpy, scipy
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

HERE = Path(__file__).parent
RES = HERE.parent.parent / "flutter/android/app/src/main/res"
DENSITES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# 1. Upscale x2 + netteté
src = Image.open(HERE / "source_illustration.jpg").convert("RGB")
src = src.resize((src.width * 2, src.height * 2), Image.LANCZOS)
src = src.filter(ImageFilter.UnsharpMask(2, 80, 2))
a = np.array(src).astype(float)

# 2. Détourage : blanc + ombre grise -> transparent, bords « dé-mélangés » du blanc
mx, mn = a.max(2), a.min(2)
bg = (mn > 225) | ((mx - mn < 28) & (mn > 110))
bg = ndimage.binary_opening(bg, iterations=1)
zone = ndimage.binary_dilation(bg, iterations=5) & ~bg
alpha = np.ones(mn.shape)
alpha[zone] = np.clip((255 - a).max(2)[zone] / 255 * 1.15, 0, 1)
alpha[bg] = 0
col = a.copy()
ok = (alpha > 0.02) & zone
for c in range(3):
    col[..., c][ok] = np.clip((a[..., c][ok] - 255 * (1 - alpha[ok])) / alpha[ok], 0, 255)
cut = Image.fromarray(np.dstack([col, alpha * 255]).astype(np.uint8), "RGBA")
cut.save(HERE / "logo_transparent.png")


def fond(w, h, cy=0.42):
    """Dégradé radial vert sombre."""
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x - w / 2) / w) ** 2 + ((y - h * cy) / h) ** 2)
    t = np.clip(d / 0.6, 0, 1)[..., None] ** 1.2
    c0, c1 = np.array([30, 56, 34]), np.array([9, 13, 10])
    return Image.fromarray((c0 * (1 - t) + c1 * t).astype(np.uint8), "RGB").convert("RGBA")


def halo(img, r):
    g = img.split()[3].filter(ImageFilter.GaussianBlur(r)).point(lambda v: int(v * 0.45))
    layer = Image.new("RGBA", img.size, (120, 230, 110, 0))
    layer.putalpha(g)
    return layer


# 3. Logo complet sur fond sombre
W, H = cut.size
S = max(W, H) + 240
full = fond(S, S)
calque = Image.new("RGBA", (S, S), (0, 0, 0, 0))
calque.alpha_composite(cut, ((S - W) // 2, (S - H) // 2))
full.alpha_composite(halo(calque, 18))
full.alpha_composite(calque)
full.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(HERE / "logo_sysiphe.png")

# 4. Emblème seul (sans texte), carré transparent
m = np.array(cut)[..., 3] > 60
m[1550:] = False  # coupe sous le cercle (texte)
ys, xs = np.where(m)
em = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
w, h = em.size
E = max(w, h)
emb = Image.new("RGBA", (E, E), (0, 0, 0, 0))
emb.alpha_composite(em, ((E - w) // 2, (E - h) // 2))
emb.save(HERE / "emblem_transparent.png")


def icone(size, frac, arrondi=True, avec_fond=True):
    c = fond(size, size, 0.5) if avec_fond else Image.new("RGBA", (size, size), (0, 0, 0, 0))
    n = int(size * frac)
    e = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    e.alpha_composite(emb.resize((n, n), Image.LANCZOS), ((size - n) // 2, (size - n) // 2))
    if avec_fond:
        c.alpha_composite(halo(e, size // 60))
    c.alpha_composite(e)
    if arrondi:
        mk = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mk).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255)
        o = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        o.paste(c, (0, 0), mk)
        c = o
    return c


# 5. Icônes Android (legacy + adaptative)
for d, s in DENSITES.items():
    icone(s * 4, 0.84).resize((s, s), Image.LANCZOS).save(RES / f"mipmap-{d}/ic_launcher.png")
    f = s * 9 // 4
    icone(f * 2, 0.62, False, False).resize((f, f), Image.LANCZOS).save(
        RES / f"mipmap-{d}/ic_launcher_foreground.png")
icone(1024, 0.84).resize((512, 512), Image.LANCZOS).save(HERE / "icon_512.png")
print("Logo et icônes générés.")
