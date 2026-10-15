import re
d = open(r"D:\AI Projects\UltraDrive\_dk_presskit.html", "rb").read().decode("utf-8", "replace")
urls = re.findall(r'https://[^"\s\\]+\.(?:jpg|jpeg|png)', d)
seen = []
for u in urls:
    if u not in seen:
        seen.append(u)
print("total", len(seen))
for u in seen[:40]:
    print(u)