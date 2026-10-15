from PIL import Image
import numpy as np

D = r"D:\AI Projects\UltraDrive\.vision\captures"
names = ["r35_cockpit_forward.png", "r35_cockpit_binnacle_stack.png", "r35_cockpit_console.png"]
ims = [np.asarray(Image.open(D + "\\" + n).convert("RGB"), dtype=np.float32) for n in names]

for i in range(3):
    im = ims[i]
    print(names[i], im.shape, "mean", im.mean(axis=(0,1)).round(1))

for i in range(len(ims)):
    for j in range(i+1, len(ims)):
        diff = np.abs(ims[i] - ims[j])

        # mean abs diff + color-other diff
        print(f"diff {i}->{j} mean_abs_diff", diff.mean().round(2), "px>20:", (diff.mean(axis=2) > 20).mean().round(3))

# ring-forward aside: measure sky presence at top rows
f = ims[0]
top = f[:int(f.shape[0]*0.3)]
print("forward top mean (sky if bright):", top.mean().round(1))
bot = f[int(f.shape[0]*0.6):]
print("forward bottom mean (dash if dark):", bot.mean().round(1))