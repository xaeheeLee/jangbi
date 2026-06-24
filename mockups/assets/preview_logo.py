# -*- coding: utf-8 -*-
import os
from PIL import Image

outdir = r"E:\Work\jangbi_nara_project\mockups\assets"
img = Image.open(os.path.join(outdir, "logo_white.png")).convert("RGB")
w, h = img.size
scale = 1100 / w
preview = img.resize((1100, int(h * scale)))
preview.save(os.path.join(outdir, "logo_preview.png"))
print("preview size:", preview.size)
