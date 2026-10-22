# Generates R35 cockpit dial/screen textures matched to CockpitRig's needle sweep
# (angle = -0.75 + 1.5 * t rad about the face normal, +angle = clockwise to the driver,
#  needle at rest points straight up). Output -> assets/interiors/r35/.
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
OUT = sys.argv[1]
SS = 4  # supersample
def font(sz, bold=True):
    for f in (r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\segoeuib.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def polar(cx, cy, r, ang):  # ang: 0 = up, + = clockwise
    return cx + r * math.sin(ang), cy - r * math.cos(ang)

def dial(path, size, lo, hi, major, minor, label_every, label_div, red_from, title, sub):
    W = size * SS
    im = Image.new("RGB", (W, W), (4, 4, 6))
    d = ImageDraw.Draw(im)
    c = W / 2
    R = W * 0.47
    d.ellipse([c - R, c - R, c + R, c + R], fill=(10, 10, 13))
    # carbon-ish face rings
    for k in range(6):
        rr = R * (0.30 + 0.1 * k)
        d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=(14, 14, 18), width=SS)
    ang = lambda v: -0.75 + 1.5 * (v - lo) / (hi - lo)
    # red zone arc
    if red_from is not None:
        a0, a1 = ang(red_from), 0.75
        for i in range(60):
            a = a0 + (a1 - a0) * i / 59
            x0, y0 = polar(c, c, R * 0.86, a); x1, y1 = polar(c, c, R * 0.95, a)
            d.line([x0, y0, x1, y1], fill=(210, 30, 20), width=3 * SS)
    v = math.ceil(lo / minor - 1e-9) * minor
    while v <= hi + 1e-6:
        a = ang(v)
        is_major = abs((v / major) - round(v / major)) < 1e-6
        r0 = R * (0.80 if is_major else 0.87)
        x0, y0 = polar(c, c, r0, a); x1, y1 = polar(c, c, R * 0.95, a)
        col = (235, 235, 240) if (red_from is None or v < red_from) else (240, 60, 40)
        d.line([x0, y0, x1, y1], fill=col, width=(4 if is_major else 2) * SS)
        if abs((v / label_every) - round(v / label_every)) < 1e-6:
            txt = str(int(round(v / label_div)))
            f = font(int(W * 0.10))
            tx, ty = polar(c, c, R * 0.64, a)
            bb = d.textbbox((0, 0), txt, font=f)
            d.text((tx - (bb[2] - bb[0]) / 2, ty - (bb[3] - bb[1]) / 2 - bb[1]), txt, font=f, fill=col)
        v += minor
    f2 = font(int(W * 0.06)); f3 = font(int(W * 0.045), bold=False)
    for txt, y, f, col in ((title, 0.62, f2, (230, 230, 235)), (sub, 0.72, f3, (150, 150, 160))):
        bb = d.textbbox((0, 0), txt, font=f)
        d.text((c - (bb[2] - bb[0]) / 2, W * y), txt, font=f, fill=col)
    # hub
    d.ellipse([c - W * 0.045, c - W * 0.045, c + W * 0.045, c + W * 0.045], fill=(30, 30, 34))
    im = im.resize((size, size), Image.LANCZOS)
    im.save(path)

def mfd(path):
    W, H = 512 * 2, 320 * 2
    im = Image.new("RGB", (W, H), (6, 10, 18))
    d = ImageDraw.Draw(im)
    # top tabs
    f = font(26); fs = font(20, bold=False)
    for i, t in enumerate(("BOOST", "OIL", "G", "TRQ", "LAP")):
        x = 24 + i * 196
        d.rounded_rectangle([x, 14, x + 180, 56], radius=8, fill=(20, 40, 70) if i == 0 else (12, 20, 34))
        d.text((x + 50, 22), t, font=f, fill=(200, 225, 255))
    # boost dial (left)
    cx, cy, r = 300, 400, 190
    for a in range(-120, 121, 2):
        aa = math.radians(a)
        x0, y0 = polar(cx, cy, r * 0.82, aa); x1, y1 = polar(cx, cy, r, aa)
        col = (90, 170, 255) if a < 60 else (255, 90, 60)
        d.line([x0, y0, x1, y1], fill=col, width=3)
    d.arc([cx - r * 0.78, cy - r * 0.78, cx + r * 0.78, cy + r * 0.78], 150, 300, fill=(240, 250, 255), width=16)
    d.text((cx - 70, cy + 40), "BOOST", font=f, fill=(170, 200, 240))
    d.text((cx - 60, cy - 30), "+0.8", font=font(54), fill=(240, 250, 255))
    # right: oil temp / pressure small dials
    for (cx, cy, lab, val) in ((760, 270, "OIL TEMP", "98"), (760, 500, "OIL PRES", "4.2")):
        r = 95
        d.arc([cx - r, cy - r, cx + r, cy + r], 135, 405, fill=(60, 90, 130), width=10)
        d.arc([cx - r, cy - r, cx + r, cy + r], 135, 300, fill=(120, 200, 255), width=10)
        d.text((cx - 38, cy - 26), val, font=font(44), fill=(240, 250, 255))
        d.text((cx - 60, cy + 30), lab, font=fs, fill=(150, 180, 220))
    im = im.resize((512, 320), Image.LANCZOS)
    im.save(path)

def climate(path):
    W, H = 512, 168
    im = Image.new("RGB", (W, H), (5, 8, 12))
    d = ImageDraw.Draw(im)
    f = font(64); fs = font(22, bold=False)
    d.text((30, 40), "22.0", font=f, fill=(150, 210, 255))
    d.text((340, 40), "22.0", font=f, fill=(150, 210, 255))
    d.text((210, 30), "AUTO", font=font(30), fill=(220, 235, 255))
    for i in range(7):
        d.rectangle([205 + i * 15, 90 - i * 4, 215 + i * 15, 100], fill=(90, 160, 230))
    d.text((200, 120), "A/C   ECO", font=fs, fill=(130, 170, 220))
    im.save(path)

os.makedirs(OUT, exist_ok=True)
dial(os.path.join(OUT, "r35_tach_face.png"), 256, 800, 7000, 1000, 500, 1000, 1000, 6500, "x1000", "r/min")
dial(os.path.join(OUT, "r35_speedo_face.png"), 256, 0, 320, 40, 20, 80, 1, None, "km/h", "")
mfd(os.path.join(OUT, "r35_mfd_screen.png"))
climate(os.path.join(OUT, "r35_climate_screen.png"))
print("ok")
