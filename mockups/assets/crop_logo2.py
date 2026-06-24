# -*- coding: utf-8 -*-
import os
from PIL import Image

outdir = r"E:\Work\jangbi_nara_project\mockups\assets"
full = Image.open(os.path.join(outdir, "logo_full.png")).convert("RGBA")

def trim_alpha(im, pad=10):
    bbox = im.split()[-1].getbbox()
    if bbox:
        l, t, r, b = bbox
        l = max(0, l-pad); t = max(0, t-pad)
        r = min(im.size[0], r+pad); b = min(im.size[1], b+pad)
        im = im.crop((l, t, r, b))
    return im

def chroma_key(im, thr=78):
    im = im.convert("RGBA"); px = im.load(); w, h = im.size
    br, bg_, bb, _ = px[2, 2]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r-br) < thr and abs(g-bg_) < thr and abs(b-bb) < thr:
                px[x, y] = (r, g, b, 0)
    return im

# bottom-right: white mono on navy
br = full.crop((3148, 2118, 4268, 3238))
white = trim_alpha(chroma_key(br, thr=85))
white.save(os.path.join(outdir, "logo_white_mono.png"))
print("logo_white_mono:", white.size)

# preview: color on white-plate(navy bg) + white mono on navy
canvas = Image.new("RGB", (1040, 560), (0, 47, 108))
# left: color logo on white circle plate
plate = Image.new("RGBA", (460, 460), (0,0,0,0))
from PIL import ImageDraw
d = ImageDraw.Draw(plate); d.ellipse((0,0,459,459), fill=(255,255,255,255))
c = Image.open(os.path.join(outdir,"logo_color.png")).convert("RGBA")
s = 360/max(c.size); c = c.resize((int(c.size[0]*s), int(c.size[1]*s)))
plate.alpha_composite(c, (50, 50))
canvas.paste(plate, (40, 50), plate)
# right: white mono direct on navy
w = Image.open(os.path.join(outdir,"logo_white_mono.png")).convert("RGBA")
s2 = 420/max(w.size); w = w.resize((int(w.size[0]*s2), int(w.size[1]*s2)))
canvas.paste(w, (560, 70), w)
canvas.save(os.path.join(outdir, "logo_check2.png"))
print("done")
