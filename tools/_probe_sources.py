import re
import urllib.request

ROOT = r"D:\AI Projects\UltraDrive"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"}


def body(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode("utf-8", "replace")


for url, tag in [
    ("https://www.netcarshow.com/nissan/2017-gt-r/", "netcarshow"),
    ("https://www.caricos.com/cars/n/nissan/2017_nissan_gt-r/images/index.html", "caricos"),
]:
    try:
        d = body(url)
        open(ROOT + "\\_probe_" + tag + ".html", "w", encoding="utf-8").write(d)
        imgs = re.findall(r'(?:src|href)="([^"]+\.(?:jpg|jpeg|png))"', d)
        print(tag, "len", len(d))
        for i in imgs[:25]:
            print("   ", i)
    except Exception as e:
        print(tag, "ERR", e)