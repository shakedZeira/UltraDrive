import os
import re
import urllib.parse
import urllib.request
import json

ROOT = r"D:\AI Projects\UltraDrive"
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "UltraDriveDevBot/1.0 (local reference fetch)"}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


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


titles = [
    "File:Nissan GT-R Premium edition (4BA-R35) interior.jpg",
    "File:Nissan GT-R Premium edition T-Spec (4BA-R35) interior.jpg",
    "File:The interior of Nissan GT-R Premium Edition 2017 year model at Nissan Global Headquarters Gallery.jpg",
    "File:2012 Nissan GT-R Egoist interior.jpg",
]

for t in titles:
    api = ("https://commons.wikimedia.org/w/api.php?action=query&format=json"
           "&titles=" + urllib.parse.quote(t) +
           "&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1920")
    d = get_json(api)
    for p in d["query"]["pages"].values():
        ii = p.get("imageinfo", [{}])[0]
        thumb = ii.get("thumburl")
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", t)[:70] + ".jpg"
        print("SUBMIT", t, "->", safe)
        if thumb:
            dl(thumb, safe)