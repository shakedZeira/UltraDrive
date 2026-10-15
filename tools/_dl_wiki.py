import json
import os
import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
UA = {"User-Agent": "UltraDriveDevBot/1.0 (local reference fetch)"}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def dl(url, name):
    path = os.path.join(OUT, name)
    if os.path.exists(path) and os.path.getsize(path) > 8000:
        print("cached", name)
        return True
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=90) as r:
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


# Search Commons for Nissan GT-R interior images
api = ("https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search"
       "&gsrsearch=" + urllib.parse.quote("Nissan GT-R interior") + "&gsrlimit=20"
       "&prop=imageinfo&iiprop=url|size&iiurlwidth=1600")
data = get_json(api)
pages = data.get("query", {}).get("pages", {})
print("commons search pages:", len(pages))
for pid in sorted(pages, key=lambda p: int(p))[:8]:
    page = pages[pid]
    title = page.get("title", "")
    ii = page.get("imageinfo", [{}])[0]
    thumb = ii.get("thumburl") or ii.get("url")
    desc = page.get("extract", "")
    print("  ", title)
    print("      thumb:", thumb)
    if thumb:
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", title)
        dl(thumb, "wik_" + safe[:60] + ".jpg")