from PIL import Image
import sys, os

D = r"D:\AI Projects\UltraDrive\.vision\captures"
for n in ["r35_cockpit_console.png"]:
    p = os.path.join(D, n)
    im = Image.open(p).convert("RGB")
    w, h = im.size
    im2 = im.resize((w // 2, h // 2))
    out = os.path.join(D, n.replace(".png", "_small.png"))
    im2.save(out)
    print(out, im2.size)