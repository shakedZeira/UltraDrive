"""Post-only Ollama vision call against an ALREADY-RUNNING server (no taskkill,
no respawn), so a warm model answers immediately instead of paying a cold start.
Usage: py tools\_ov_post.py <image> [question]"""
import base64
import json
import sys
import urllib.request

PORT = 11434


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
        with urllib.request.urlopen(req, timeout=500) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print("HTTP %d: %s" % (e.code, e.read().decode()[:600]))
        sys.exit(3)
    return data.get("response", "")


if __name__ == "__main__":
    img = sys.argv[1]
    q = sys.argv[2] if len(sys.argv) > 2 else "Describe this image in detail."
    print("IMG:", img)
    print(generate(img, q))