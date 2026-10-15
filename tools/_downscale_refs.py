from PIL import Image
import os

refs = r".vision/refs/r35"
out = r".vision"
for f in os.listdir(refs):
    if "interior" not in f.lower():
        continue
    p = os.path.join(refs, f)
    im = Image.open(p)
    im.thumbnail((900, 900))
    dst = os.path.join(out, "tmp_ref_" + f.rsplit(".", 1)[0].replace("_", "")[-40:] + ".jpg")
    im.convert("RGB").save(dst, quality=85)
    print(dst, im.size)