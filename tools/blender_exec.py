"""Run Python inside the live Blender session via the blender-mcp addon socket.

Usage:
    py tools\\blender_exec.py script.py        # run a file
    echo "import bpy; print(bpy.app.version_string)" | py tools\\blender_exec.py -

The Blender MCP addon must be running (Blender > N panel > BlenderMCP >
Connect), listening on localhost:9876 (override with BLENDER_PORT).
Prints whatever the code printed; exits 1 if Blender reported an error.
"""
import json
import os
import socket
import sys


def run(code: str, host: str = "localhost", port=None, timeout: float = 600.0) -> dict:
    port = port or int(os.environ.get("BLENDER_PORT", "9876"))
    with socket.create_connection((host, port), timeout=timeout) as s:
        s.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            try:
                return json.loads(buf)
            except json.JSONDecodeError:
                continue
    return json.loads(buf)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    code = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()
    resp = run(code)
    if resp.get("status") != "success":
        print(json.dumps(resp, indent=2))
        return 1
    result = resp.get("result", {})
    print(result.get("result", result) if isinstance(result, dict) else result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
