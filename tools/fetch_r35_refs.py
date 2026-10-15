#!/usr/bin/env python3
"""Fetch real Nissan GT-R R35 interior reference images into .vision/refs/r35/.

Sources (all free/editorial sites, downloaded for local visual comparison only):
  - netcarshow.com: 2017 GT-R gallery (exact 2017 / facelift car)
  - vehiclesizes.com: interior pages WITH alt-text labels (dashboard/cluster/
    console/gearshift/start-button shots)

Usage: py tools\\fetch_r35_refs.py  (PC) | python tools\\fetch_r35_refs.py (laptop)
"""
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".vision", "refs", "r35")
os.makedirs(OUT, exist_ok=True)

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}


def get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def save(url: str, name: str) -> bool:
    path = os.path.join(OUT, name)
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return True
    try:
        data = get(url)
        if len(data) < 5000:
            print(f"  SKIP {name}: tiny body {len(data)}B")
            return False
        with open(path, "wb") as f:
            f.write(data)
        print(f"  OK   {name} ({len(data)//1024} KB)")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"  FAIL {name}: {e}")
        return False


def fetch_vehiclesizes() -> int:
    """Parse the labelled interior gallery. Returns count saved."""
    done = 0
    base = "https://www.vehiclesizes.com/cars/nissan/gt-r/"
    # main spec page links to the interior image page; we use the known route
    page_url = base + "gt-r-r35-facelift-2016-coupe-2017/images/"
    try:
        html = get(page_url).decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        print("vehiclesizes page fetch failed:", e)
        return 0
    # <img ... alt="Dashboard, steering wheel..." src="...">
    imgs = re.findall(r'<img[^>]+src="([^"]+)"[^>]*>', html)
    alts = re.findall(r'<img[^>]+alt="([^"]*)"', html)
    labels = ["dashboard", "steering wheel", "interior", "cluster", "tachometer",
              "console", "gearshift", "shifter", "start/stop", "gauge", "sporty interior"]
    picked = 0
    for img, alt in zip(imgs, alts):
        low = alt.lower()
        if not any(k in low for k in labels):
            continue
        src = img if img.startswith("http") else "https://www.vehiclesizes.com" + img
        ext = os.path.splitext(src.split("/")[-1].split("?")[0])[1] or ".jpg"
        name = f"vs_{picked:02d}{ext}"
        if save(src, name):
            picked += 1
            done += 1
        if picked >= 6:
            break
    return done


def fetch_netcarshow() -> int:
    """Download the 2017 GT-R gallery (interior shots interspersed)."""
    done = 0
    page_url = "https://www.netcarshow.com/nissan/2017-gt-r/"
    try:
        html = get(page_url).decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        print("netcarshow page fetch failed:", e)
        return 0
    # thumbnails: href="/nissan/2017-gt-r/<size>/<file>.jpg"
    hrefs = re.findall(r'href="(/nissan/2017-gt-r/\d+x\d+/[^"]+\.jpg)"', html)
    seen = set()
    files = []
    for h in hrefs:
        leaf = h.split("/")[-1]
        if leaf in seen:
            continue
        seen.add(leaf)
        files.append(h)
    if not files:
        print("netcarshow: no gallery hrefs parsed")
        return 0
    # At 1280x960 they are a good reference resolution; take a spread so the
    # interior photos (roughly the first third of the set) are covered.
    step = max(1, len(files) // 14)
    for i in range(0, min(len(files), 40), step):
        h = files[i]
        leaf = h.split("/")[-1]
        name = f"nc_{i:02d}_{leaf}"
        src = "https://www.netcarshow.com" + h.replace("/1280x960/", "/1600x1200/")
        if save(src, name):
            done += 1
    return done


if __name__ == "__main__":
    print("== vehiclesizes (labelled interior) ==")
    vs = fetch_vehiclesizes()
    print("== netcarshow (2017 gallery spread) ==")
    nc = fetch_netcarshow()
    print(f"\nTOTAL saved: {vs + nc} (vehiclesizes={vs}, netcarshow={nc}) -> {OUT}")