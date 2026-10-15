import os
import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0"}


def dl(url, name):
    path = os.path.join(OUT, name)
    if os.path.exists(path) and os.path.getsize(path) > 8000:
        print("cached", name)
        return True
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=60) as r:
            d = r.read()
        if len(d) < 8000:
            print("skip", name, len(d))
            return False
        with open(path, "wb") as f:
            f.write(d)
        print("ok", name, len(d) // 1024, "KB")
        return True
    except Exception as e:
        print("fail", name, e)
        return False


# The 2017 GT-R gallery page in full-res size (each shot viewable at 5120x3840)
# The 'Show all pictures' page lists all images.
u = "https://www.netcarshow.com/nissan/2017-gt-r/"
req = urllib.request.Request(u, headers=UA)
d = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
# find links to the per-image size pages e.g. /nissan/2017-gt-r/5120x3840/xxx.jpg
shots = re.findall(r'href="(/nissan/2017-gt-r/5120x3840/[^"]+\.jpg)"', d)
uniq = list(dict.fromkeys(shots))
print("5120x3840 shots:", len(uniq))
for i, h in enumerate(uniq):
    print("  ", h)
    dl("https://www.netcarshow.com" + h, "ncfull_%02d_%s" % (i, h.split("/")[-1]))