"""Direct Ollama vision call. Spawns `ollama serve` if not running, then POSTs
an image to /api/generate with qwen2.5vl:7b. Uses Vulkan runtime env so the
GTX 970 CUDA-PTX crash never happens. The LLM backend is forced to vulkan via
OLLAMA_LLM_LIBRARY (CUDA 12.8 PTX cannot be JIT-ed by driver 560.94 / CUDA 12.6).
Usage: py tools\_ollama_vision.py <image> [question]"""
import base64
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

OLLAMA_EXE = r"D:\Ollama\ollama.exe"
PORT = 11434


def is_up():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=1.0):
            return True
    except OSError:
        return False


def ensure_server():
    if is_up():
        # A serving instance may have been spawned by the vision-bridge plugin
        # WITHOUT the vulkan env (CUDA-PTX crash on this driver). Restart it
        # under the known-good env rather than relying on the stale one.
        subprocess.run(["taskkill", "/f", "/im", "ollama.exe"],
                       capture_output=True)
        time.sleep(1.0)
    env = dict(os.environ)
    env["OLLAMA_LLM_LIBRARY"] = "vulkan"
    print("starting ollama serve (vulkan)…")
    proc = subprocess.Popen(
        [OLLAMA_EXE, "serve"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # poll until the API responds (up to 30s)
    for _ in range(60):
        if is_up():
            return
        time.sleep(0.5)
    print("ERROR: ollama serve did not come up")
    sys.exit(2)


def generate(image_path, question):
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    payload = {
        "model": "qwen2.5vl:7b",
        "prompt": question,
        "images": [b64],
        "stream": False,
        "options": {"temperature": 0.0, "num_predict": 400},
    }
    req = urllib.request.Request(
        "http://127.0.0.1:%d/api/generate" % PORT,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=240) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print("HTTP %d: %s" % (e.code, e.read().decode()[:600]))
        sys.exit(3)
    return data.get("response", "")


if __name__ == "__main__":
    ensure_server()
    img = sys.argv[1]
    q = sys.argv[2] if len(sys.argv) > 2 else "Describe this image in detail."
    print("IMG:", img)
    print(generate(img, q))