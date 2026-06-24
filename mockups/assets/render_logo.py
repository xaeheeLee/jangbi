# -*- coding: utf-8 -*-
import fitz, os
from PIL import Image, ImageChops

src = r"E:\Work\jangbi_nara_project\docs\전중배_logo_out-5.pdf"
outdir = r"E:\Work\jangbi_nara_project\mockups\assets"
os.makedirs(outdir, exist_ok=True)

doc = fitz.open(src)
print("pages:", doc.page_count)
page = doc[0]
print("page rect:", page.rect)

zoom = 6.0
mat = fitz.Matrix(zoom, zoom)
pix = page.get_pixmap(matrix=mat, alpha=True)
raw = os.path.join(outdir, "logo_full.png")
pix.save(raw)
img = Image.open(raw).convert("RGBA")
print("rendered size:", img.size)

alpha = img.split()[-1]
bbox = alpha.getbbox()
if bbox is None:
    rgb = img.convert("RGB")
    bg = Image.new("RGB", rgb.size, (255, 255, 255))
    diff = ImageChops.difference(rgb, bg)
    bbox = diff.getbbox()
print("bbox:", bbox)
if bbox:
    pad = 14
    l, t, r, b = bbox
    l = max(0, l - pad); t = max(0, t - pad)
    r = min(img.size[0], r + pad); b = min(img.size[1], b + pad)
    img = img.crop((l, t, r, b))
img.save(os.path.join(outdir, "logo_trim.png"))
print("trimmed size:", img.size)

white = Image.new("RGBA", img.size, (255, 255, 255, 255))
white.alpha_composite(img)
white.convert("RGB").save(os.path.join(outdir, "logo_white.png"), quality=95)
print("done; files:", os.listdir(outdir))
