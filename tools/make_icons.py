"""Make Binah's icons: the letter bet (ב) in Frank Ruhl Libre, ink on a flat parchment tile.

    .venv/bin/python tools/make_icons.py

Writes web/icon.svg, web/icon-192.png, web/icon-512.png, web/icon-maskable-512.png
and web/apple-touch-icon.png. Needs fonttools, brotli and Pillow.
"""
import io
import os

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), '..')
WOFF = os.path.join(ROOT, 'web', 'fonts', 'frank-ruhl-libre-hebrew-wght-normal.woff2')
PAPER, INK, ACCENT = '#ece3d7', '#2b2744', '#12617f'

font = TTFont(WOFF)
font.flavor = None
if 'fvar' in font:                      # pin the variable font to a bold-ish weight
    from fontTools.varLib.instancer import instantiateVariableFont
    font = instantiateVariableFont(font, {'wght': 620})
buf = io.BytesIO()
font.save(buf)
ttf = buf.getvalue()

# SVG: the glyph as a path, centred on a 512 tile
gs = font.getGlyphSet()
name = font.getBestCmap()[ord('ב')]
upm = font['head'].unitsPerEm
glyph = gs[name]
pen = SVGPathPen(gs)
scale = 300 / upm
from fontTools.pens.boundsPen import BoundsPen
bp = BoundsPen(gs)
glyph.draw(bp)
x0, y0, x1, y1 = bp.bounds
w, h = (x1 - x0) * scale, (y1 - y0) * scale
tx = (512 - w) / 2 - x0 * scale
ty = (512 + h) / 2 + y0 * scale - 14
glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, tx, ty)))
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="112" fill="{PAPER}"/>'
       f'<path d="{pen.getCommands()}" fill="{INK}"/><rect x="186" y="404" width="140" height="14" rx="7" fill="{ACCENT}"/></svg>')
open(os.path.join(ROOT, 'web', 'icon.svg'), 'w').write(svg)


def tile(size, pad=0.0, rounded=True):
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if rounded:
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=PAPER)
    else:
        d.rectangle([0, 0, size, size], fill=PAPER)
    inner = size * (1 - 2 * pad)
    f = ImageFont.truetype(io.BytesIO(ttf), int(inner * 0.66))
    bbox = d.textbbox((0, 0), 'ב', font=f)
    gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((size - gw) / 2 - bbox[0], (size - gh) / 2 - bbox[1] - inner * 0.03), 'ב', font=f, fill=INK)
    bw = inner * 0.27
    y = size / 2 + gh / 2 + inner * 0.06
    d.rounded_rectangle([(size - bw) / 2, y, (size + bw) / 2, y + inner * 0.028], radius=int(inner * 0.014), fill=ACCENT)
    return im


tile(192).save(os.path.join(ROOT, 'web', 'icon-192.png'))
tile(512).save(os.path.join(ROOT, 'web', 'icon-512.png'))
tile(512, pad=0.1, rounded=False).save(os.path.join(ROOT, 'web', 'icon-maskable-512.png'))
tile(180, rounded=False).save(os.path.join(ROOT, 'web', 'apple-touch-icon.png'))
print('icons written')
