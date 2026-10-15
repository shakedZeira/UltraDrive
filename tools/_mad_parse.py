import os
import re

ROOT = r"D:\AI Projects\UltraDrive"
d = open(ROOT + "\\_mad.html", encoding="utf-8").read()
# look for the JS-driven gallery config or full-size image URLs
full = re.findall(r'(https?://[^"\']+?(?:wallpapers|full|frontend|media|img)[^"\']*?)', d)
uniq = list(dict.fromkeys(full))
print("candidate full urls:", len(uniq))
for u in uniq[:40]:
    print("  ", u)
# maxres / other patterns
for pat in [r'data-zoom="([^"]+)"', r'class="[^"]*fancybox[^"]*"[^>]+href="([^"]+)"',
            r'href="([^"]+\.(?:jpg|jpeg|png)[^"]*)"']:
    m = re.findall(pat, d)
    print(pat, "->", len(m), list(dict.fromkeys(m))[:10])