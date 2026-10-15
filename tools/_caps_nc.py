import html
import re

d = open(r"D:\AI Projects\UltraDrive\_probe_netcarshow.html", encoding="utf-8").read()
caps = re.findall(r'<img[^>]+\balt="([^"]*)"', d)
print("alt captions:")
for c in caps:
    print("   ", html.unescape(c).strip())
# Also: find which 1280 images are interior via the caption text near them
for m in re.finditer(r'<img[^>]+src="([^"]+1280[^"]+\.jpg)"[^>]*alt="([^"]*)"', d):
    print("IMG", m.group(1), "->", html.unescape(m.group(2)).strip())