import json
import os
import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}


def get_bytes(url, timeout=45):
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
            print("skip", name, "body", len(d))
            return False
        with open(path, "wb") as f:
            f.write(d)
        print("ok", name, len(d) // 1024, "KB")
        return True
    except Exception as e:
        print("fail", name, e)
        return False


html = open(os.path.join(ROOT, "_dk_presskit.html"), "rb").read().decode("utf-8", "replace")
# Grab every S3 photo URL from the release page HTML
urls = re.findall(r"https://wieck-nissanao-production\.s3\.amazonaws\.com/photos/[^\"'\\\s]+", html)
seen, uniq = set(), []
for u in urls:
    if u not in seen:
        seen.add(u)
        uniq.append(u)
print("s3 photo urls:", len(uniq))
for i, u in enumerate(uniq[:30]):
    print("  ", u)

# Photos typically have a URL like .../photos/<hash>/<size>-<name>.jpg
# The page also may embed a 'photos' JSON. Let's drop the thumbnail size suffix
# variants so we can request larger images.
for i, u in enumerate(uniq):
    name = "pk_%02d.jpg" % i
    dl(u, name)