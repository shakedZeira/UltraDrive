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


# netcarshow "show all pictures" page lists every full-res image
try:
    d = get_bytes("https://www.netcarshow.com/nissan/2017-gt-r/1280x1024/").decode("utf-8", "replace")
    open(ROOT + "\\_nc_all.html", "w", encoding="utf-8").write(d)
    hrefs = re.findall(r'href="(/nissan/2017-gt-r/1280x1024/[^"]+\.jpg)"', d)
    seen, uniq = set(), []
    for h in hrefs:
        if h not in seen:
            seen.add(h)
            uniq.append(h)
    print("netcarshow 1280x1024 gallery images:", len(uniq))
    for i, h in enumerate(uniq):
        print("  ", h)
        dl("https://www.netcarshow.com" + h, "nc1280_%02d_%s" % (i, h.split("/")[-1]))
except Exception as e:
    print("netcarshow gallery err", e)

# caricos interior pages (numbered 101.. with per-size wallpaper URLs)
for idx in range(101, 106):
    u = "https://www.caricos.com/cars/n/nissan/2017_nissan_gt-r/images/%d.html" % idx
    try:
        d = get_bytes(u).decode("utf-8", "replace")
        imgs = re.findall(r'(https://[^"\']+\.(?:jpg|jpeg|png))', d)
        big = [x for x in imgs if "wallpaper" not in x.lower()]
        print("caricos", idx, "imgs:", len(imgs))
        for x in dict.fromkeys(big)[:1]:
            print("   ", x)
            dl(x, "car_%d.jpg" % idx)
    except Exception as e:
        print("caricos", idx, "err", e)