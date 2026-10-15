import sys, json, base64, urllib.request, time

def call(prompt, images, np=350):
	payload = {"model": "qwen2.5vl:7b", "prompt": prompt, "images": images,
			   "stream": False, "options": {"num_predict": np, "num_ctx": 8192}}
	req = urllib.request.Request("http://127.0.0.1:11434/api/generate",
								data=json.dumps(payload).encode(),
								headers={"Content-Type": "application/json"})
	t = time.time()
	with urllib.request.urlopen(req, timeout=300) as r:
		out = json.loads(r.read())
	print("[%.0fs] %s" % (time.time() - t, out.get("response", "")))

if __name__ == "__main__":
	prompt = sys.argv[1]
	b64 = [base64.b64encode(open(p, "rb").read()).decode() for p in sys.argv[2:]]
	for attempt in range(3):
		try:
			call(prompt, b64)
			break
		except urllib.error.HTTPError as e:
			print("HTTP %d: %s" % (e.code, e.read().decode("utf-8", "replace")[:500]))
			time.sleep(4)
		except Exception as e:
			print("ERR attempt %d: %s" % (attempt + 1, e))
			time.sleep(4)
