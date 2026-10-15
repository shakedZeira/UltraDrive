import os
from PIL import Image

DIR = r"D:\AI Projects\UltraDrive\.vision\refs\r35"
for f in sorted(os.listdir(DIR)):
    p = os.path.join(DIR, f)
    try:
        im = Image.open(p)
        print(f"{f:70s} {im.size[0]}x{im.size[1]}")
    except Exception as e:
        print(f"{f:70s} ERR {e}")