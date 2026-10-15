import json
import re
import urllib.request
import urllib.parse


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "UltraDriveDevBot/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


# page images of the Nissan GT-R article
u = ("https://en.wikipedia.org/w/api.php?action=query&format=json"
     "&titles=Nissan%20GT-R&prop=images&imlimit=200")
d = get_json(u)
for p in d["query"]["pages"].values():
    for im in p.get("images", []):
        t = im["title"]
        if "nterior" in t or "ash" in t or "nstrument" in t or "onsol" in t or "teering" in t:
            print("IMG:", t)