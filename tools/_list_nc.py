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


u = "https://www.netcarshow.com/nissan/2017-gt-r/"
req = urllib.request.Request(u, headers=UA)
d = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
# dump every internal jpg link with size discriminator
all_hrefs = re.findall(r'href="(/nissan/2017-gt-r/[^"]+\.jpg)"', d)
uniq = list(dict.fromkeys(all_hrefs))
print("all gallery links:", len(uniq))
for h in uniq:
    print("  ", h)