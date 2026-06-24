# -*- coding: utf-8 -*-
import os
from PIL import Image
d = r"E:\Work\jangbi_nara_project\mockups\assets"
im = Image.open(os.path.join(d, "v3_2x.png"))
print("shot:", im.size)
w, h = im.size
# three phones row: crop login (left third) and list (mid third) tall
third = w // 3
login = im.crop((0, int(h*0.06), third, h))
lst = im.crop((third, int(h*0.06), third*2, h))
det = im.crop((third*2, int(h*0.06), w, h))
for name, c in [("v3_login", login), ("v3_list", lst), ("v3_detail", det)]:
    s = 760 / c.size[1]
    c = c.resize((int(c.size[0]*s), 760))
    c.save(os.path.join(d, name + ".png"))
print("done")
