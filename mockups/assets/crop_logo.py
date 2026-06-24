# -*- coding: utf-8 -*-
import os
from PIL import Image

outdir = r"E:\Work\jangbi_nara_project\mockups\assets"
full = Image.open(os.path.join(outdir, "logo_full.png")).convert("RGBA")
print("full:", full.size)

def trim_alpha(im, pad=10):
    bbox = im.split()[-1].getbbox()
    if bbox:
        l, t, r, b = bbox
        l = max(0, l-pad); t = max(0, t-pad)
        r = min(im.size[0], r+pad); b = min(im.size[1], b+pad)
        im = im.crop((l, t, r, b))
    return im

def chroma_key(im, thr=70):
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    # bg = top-left corner color
    br, bg_, bb, _ = px[2, 2]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r-br) < thr and abs(g-bg_) < thr and abs(b-bb) < thr:
                px[x, y] = (r, g, b, 0)
    return im

# quadrant crop boxes (measured from preview)
boxes = {
    "logo_color": (740, 418, 1860, 1538),    # top-left: color on transparent
    "logo_dark_src": (740, 2118, 1860, 3238) # bottom-left: color on navy
}

# light color logo (already transparent bg)
tl = trim_alpha(full.crop(boxes["logo_color"]))
tl.save(os.path.join(outdir, "logo_color.png"))
print("logo_color:", tl.size)

# dark logo: chroma-key the navy rectangle to transparent
bl = full.crop(boxes["logo_dark_src"])
bl_keyed = trim_alpha(chroma_key(bl, thr=78))
bl_keyed.save(os.path.join(outdir, "logo_dark.png"))
print("logo_dark:", bl_keyed.size)

# small previews side by side on checker + navy
def make_preview():
    cw = 520
    canvas = Image.new("RGB", (cw*2, 600), (240, 242, 246))
    # color on white
    c = Image.open(os.path.join(outdir, "logo_color.png")).convert("RGBA")
    s = 460/max(c.size); c = c.resize((int(c.size[0]*s), int(c.size[1]*s)))
    canvas.paste(c, (30, 70), c)
    # dark on navy
    navy = Image.new("RGB", (cw, 600), (0, 47, 108))
    d = Image.open(os.path.join(outdir, "logo_dark.png")).convert("RGBA")
    s2 = 460/max(d.size); d = d.resize((int(d.size[0]*s2), int(d.size[1]*s2)))
    navy.paste(d, (30, 70), d)
    canvas.paste(navy, (cw, 0))
    canvas.save(os.path.join(outdir, "logo_check.png"))
make_preview()
print("done")
