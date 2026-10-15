import os
import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0"}


def get_bytes(url, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def dl(url, name):
    path = os.path.join(OUT, name)
    if os.path.exists(path) and os.path.getsize(path) > 10000:
        print("cached", name)
        return True
    try:
        d = get_bytes(url)
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


# caricos index pages: dump hrefs/images from 101.html to find real interior
d = get_bytes("https://www.caricos.com/cars/n/nissan/2017_nissan_gt-r/images/101.html").decode("utf-8", "replace")
imgs = re.findall(r'https://[^"\']+\.(?:jpg|jpeg|png)', d)
uniq = list(dict.fromkeys(imgs))
print("caricos 101 raw imgs:", len(uniq))
for i, u in enumerate(uniq):
    print("  ", u)
    dl(u, "car101_%d.jpg" % i)