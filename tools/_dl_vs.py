import os
import re
import ssl
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"}
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def get(url, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout, context=ctx).read()


def dl(url, name):
    path = os.path.join(OUT, name)
    if os.path.exists(path) and os.path.getsize(path) > 8000:
        print("cached", name)
        return True
    try:
        d = get(url)
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


# vehiclesizes labelled interior gallery
for page in ["https://www.vehiclesizes.com/cars/nissan/gt-r/gt-r-r35-facelift-2016-coupe-2017/images/"]:
    try:
        d = get(page).decode("utf-8", "replace")
        open(ROOT + "\\_vs.html", "w", encoding="utf-8").write(d)
        pairs = re.findall(r'<img[^>]+src="([^"]+)"[^>]*alt="([^"]*)"', d)
        print("vehiclesizes imgs:", len(pairs))
        labels = ["dashboard", "steering", "interior", "cluster", "tachometer",
                  "console", "gearshift", "shifter", "start/stop", "gauge"]
        seen = set()
        n = 0
        for src, alt in pairs:
            low = alt.lower()
            if not any(k in low for k in labels):
                continue
            if src in seen:
                continue
            seen.add(src)
            ext = os.path.splitext(src.split("/")[-1].split("?")[0])[1] or ".jpg"
            if dl(src if src.startswith("http") else "https://www.vehiclesizes.com" + src, f"vs_{n:02d}{ext}"):
                n += 1
            if n >= 6:
                break
        print("vehiclesizes saved:", n)
    except Exception as e:
        print("vehiclesizes err:", e)

# mad4wheels
try:
    d = get("https://www.mad4wheels.com/nissan/gt-r-r35--2017").decode("utf-8", "replace")
    open(ROOT + "\\_mad.html", "w", encoding="utf-8").write(d)
    imgs = re.findall(r'(https?://[^"\']+\.(?:jpg|jpeg|png))', d)
    uniq = list(dict.fromkeys(imgs))
    print("mad4wheels imgs:", len(uniq))
    for i, u in enumerate(uniq[:30]):
        print("   ", u)
        dl(u, "mad_%02d.jpg" % i) if i < 15 else None
except Exception as e:
    print("mad4wheels err:", e)