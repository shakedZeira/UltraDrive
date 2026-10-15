import os
import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"}


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


html = open(ROOT + "\\_probe_netcarshow.html", encoding="utf-8").read()
# netcarshow thumblist images: /Nissan-GT-R-2017-<tag>.<hash>.jpg  (the main index)
# The 2017 GT-R page shows several interior shots. Grab each unique car-image name.
names = re.findall(r"(/Nissan-GT-R-2017-[^\"'()]+\.jpg)", html)
seen, uniq = set(), []
for n in names:
    if n not in seen:
        seen.add(n)
        uniq.append(n)
print("unique image names:", len(uniq))
for i, rel in enumerate(uniq):
    print("  ", rel)
    leaf = rel.split("/")[-1]
    dl("https://www.netcarshow.com" + rel, "nc_%02d_%s" % (i, leaf))