from PIL import Image
import os

DIR = r"D:\AI Projects\UltraDrive\.vision\captures"
for f in ["r35_cockpit_forward.png", "r35_cockpit_binnacle_stack.png", "r35_cockpit_console.png"]:
    p = os.path.join(DIR, f)
    im = Image.open(p).convert("RGB")
    stats = im.resize((64, 36))
    px = list(stats.getdata())
    vals = [sum(c) / 3 for c in px]
    mean = sum(vals) / len(vals)
    var = sum((v - mean) ** 2 for v in vals) / len(vals)
    print(f, im.size, "mean_lum %.1f" % mean, "std %.1f" % (var ** 0.5))
    hist = im.histogram()
    print("   unique-ish colors:", len([x for x in im.resize((256,144)).getcolors(maxcolors=100000)]) if im.resize((256,144)).getcolors(maxcolors=100000) else ">100k")