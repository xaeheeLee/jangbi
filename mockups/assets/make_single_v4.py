# -*- coding: utf-8 -*-
import os, base64, io
from PIL import Image
base = r"E:\Work\jangbi_nara_project\mockups"
d = os.path.join(base, "assets")

def data_uri(path, target=300):
    im = Image.open(path).convert("RGBA")
    s = target / max(im.size)
    if s < 1:
        im = im.resize((int(im.size[0]*s), int(im.size[1]*s)))
    buf = io.BytesIO(); im.save(buf, format="PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

color = data_uri(os.path.join(d, "logo_color.png"))
src = os.path.join(base, "전중배_시안_v4.html")
with open(src, "r", encoding="utf-8") as f:
    html = f.read()
html = html.replace('const LOGO="assets/logo_color.png";', 'const LOGO="%s";' % color)
out = os.path.join(base, "전중배_시안_v4_단일파일.html")
with open(out, "w", encoding="utf-8") as f:
    f.write(html)
print("written", os.path.getsize(out))
