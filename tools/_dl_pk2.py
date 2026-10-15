import os
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


# Press kit photo base hash from the page; try full-size variants
base = "https://wieck-nissanao-production.s3.amazonaws.com/photos/bac9845918dd8437cd48cb8a16c8d88489a9b6f4"
for size in ["thumbnail-720x404", "large", "full", "original", "1024", "2048"]:
    dl(f"{base}/{size}.jpg", f"pk_{size}.jpg")

# mad4wheels: 2017 GT-R gallery page - try extracting image urls
url = "https://www.mad4wheels.com/nissan/gt-r-r35--2017"
try:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        d = r.read().decode("utf-8", "replace")
    open(ROOT + "\\_mad4wheels.html", "w", encoding="utf-8").write(d)
    print("mad4wheels page len", len(d))
except Exception as e:
    print("mad4wheels err", e)