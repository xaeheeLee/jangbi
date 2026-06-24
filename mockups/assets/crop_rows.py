# -*- coding: utf-8 -*-
import os
from PIL import Image
d = r"E:\Work\jangbi_nara_project\mockups\assets"
im = Image.open(os.path.join(d, "v4_full.png"))
w, h = im.size
print("full", im.size)
rows = {"row_login": (140, 880), "row_list": (880, 1600), "row_detail": (1600, 2330)}
for name, (t, b) in rows.items():
    c = im.crop((0, t, w, b))
    s = 1100 / c.size[0]
    c = c.resize((1100, int(c.size[1]*s)))
    c.save(os.path.join(d, name + ".png"))
print("done")
