#!/usr/bin/env python3
"""Gemini web automation for UltraDrive.

Drives your real Chrome binary against a COPY of your Chrome profile so the
Google login carries over (Chrome >= 136 refuses to let any tool automate the
default user-data-dir, hence the copy).

Subcommands:
  sync-profile   copy the real Chrome profile into .vision/chrome_profile (Chrome must be closed)
  login          open Gemini so you can sign in by hand; keeps the session
  ask            upload images, send a prompt, save Gemini's reply as markdown
  probe          dump the DOM selectors + chat history html (debugging)

Run through the wrapper (sets uv cache + utf-8):
  gemini_vision.bat ask --image .vision\\captures\\Capture.PNG --prompt "critique this"
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / ".vision" / "chrome_profile"
OUT_DIR = ROOT / ".vision" / "gemini"
GEMINI_URL = "https://gemini.google.com/app?hl=en"

# Chrome's default user data dir (this machine's real login lives here).
SRC_USER_DATA = Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "User Data"

CHROME_CANDIDATES = [
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "application" / "chrome.exe",
]

# Profile subdirs that are pure cache / regenerated on demand.
# Sessions / Session Storage are excluded too: otherwise Chrome re-opens every
# tab you had, which is slow and noisy during a run.
COPY_EXCLUDE_DIRS = [
    "Cache", "Code Cache", "GPUCache", "Service Worker", "DawnGraphiteCache",
    "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "component_crx_cache",
    "extensions_crx_cache", "Crashpad", "CrashpadMetrics", "optimization_guide_model_store",
    "GraphiteDawnCache", "BrowserMetrics", "Snapshots", "SwReporter", "segmentation_platform",
    "Sessions", "Sessions_Encrypted", "Session Storage",
]
COPY_EXCLUDE_FILES = ["*.lock", "Singleton*", "DevToolsActivePort", "Preferences.bak"]

PROMPT_BOX = "div.ql-editor[contenteditable='true']"
UPLOAD_BTN = "button[aria-label='Upload & tools']"
SEND_BTN = "button[aria-label='Send message']"

# Tried in order to pull the assistant reply out of the chat DOM.
RESPONSE_SELECTORS = [
    "model-response",
    "[data-test-id='message-content']",
    "message-content",
    ".model-response-text",
    "response-container .markdown",
    "#chat-history .response-container",
]


def log(msg: str) -> None:
    print(msg, flush=True)


def note(events: list, msg: str) -> None:
    """Record an event and print it right away, so a run never looks hung."""
    events.append(msg)
    log("  " + msg)


def find_chrome() -> Path:
    for c in CHROME_CANDIDATES:
        if c and Path(c).is_file():
            return Path(c)
    raise SystemExit("chrome.exe not found; set CHROME_EXE or edit CHROME_CANDIDATES")


def chrome_running() -> bool:
    try:
        out = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq chrome.exe"],
            capture_output=True, text=True, check=False,
        ).stdout.lower()
        return "chrome.exe" in out
    except Exception:
        return False


def cmd_sync_profile(_args: argparse.Namespace) -> int:
    if not SRC_USER_DATA.is_dir():
        raise SystemExit(f"real profile not found: {SRC_USER_DATA}")
    if chrome_running():
        raise SystemExit("Chrome is running - close every Chrome window first, then re-run sync-profile.")

    PROFILE.mkdir(parents=True, exist_ok=True)
    src_default = SRC_USER_DATA / "Default"
    dst_default = PROFILE / "Default"
    if not src_default.is_dir():
        raise SystemExit(f"no 'Default' profile under {SRC_USER_DATA}")

    cmd = ["robocopy", str(src_default), str(dst_default), "/MIR", "/R:1", "/W:1",
           "/NFL", "/NDL", "/NJH", "/NP"]
    for d in COPY_EXCLUDE_DIRS:
        cmd += ["/XD", d]
    for f in COPY_EXCLUDE_FILES:
        cmd += ["/XF", f]
    log("copying profile (this takes a few seconds)...")
    res = subprocess.run(cmd)
    rc = res.returncode
    if rc >= 8:
        raise SystemExit(f"robocopy failed with {rc}")

    shutil.copy2(SRC_USER_DATA / "Local State", PROFILE / "Local State")
    prune_profile_picker()
    log(f"profile copied -> {PROFILE} (robocopy rc={rc})")
    log("next: gemini_vision.bat ask ... (or 'login' if Gemini still asks you to sign in)")
    return 0


def prune_profile_picker() -> None:
    """Keep only the Default profile in Local State, else Chrome shows a
    'who's using Chrome?' chooser before the automation can start."""
    import json

    ls_path = PROFILE / "Local State"
    try:
        ls = json.loads(ls_path.read_text(encoding="utf-8"))
    except Exception as e:
        log(f"  (could not prune Local State: {e})")
        return
    prof = ls.setdefault("profile", {})
    info = prof.get("info_cache", {})
    dropped = [k for k in info if k != "Default"]
    for k in dropped:
        info.pop(k)
    prof["last_used"] = "Default"
    ls_path.write_text(json.dumps(ls, ensure_ascii=False), encoding="utf-8")
    if dropped:
        log(f"  removed from profile picker: {', '.join(dropped)}")


def launch(p, headless: bool = False):
    chrome = find_chrome()
    if not PROFILE.is_dir():
        raise SystemExit(f"no automation profile at {PROFILE} - run: gemini_vision.bat sync-profile")
    ctx = p.chromium.launch_persistent_context(
        user_data_dir=str(PROFILE),
        executable_path=str(chrome),
        headless=headless,
        # NOTE: ignore_default_args=True also strips Playwright's own
        # --remote-debugging-pipe, so Chrome never connects and the launch
        # hangs for 180s. Only drop the flags that hurt us.
        ignore_default_args=["--enable-automation"],
        chromium_sandbox=True,          # never inject --no-sandbox (Chrome rejects it here)
        args=[
            "--profile-directory=Default",
            "--disable-blink-features=AutomationControlled",
        ],
        viewport={"width": 1500, "height": 950},
    )
    return ctx


def wire_dialogs(ctx, events: list) -> None:
    def on_dialog(d):
        note(events, f"DIALOG[{d.type}]: {d.message}")
        try:
            d.dismiss()
        except Exception:
            pass
    ctx.on("dialog", on_dialog)


def open_gemini(ctx):
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    log("  loading " + GEMINI_URL)
    page.goto(GEMINI_URL, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(4000)
    return page


def signed_in(ctx) -> bool:
    """Cookie-based, so it does not depend on the UI language."""
    try:
        return any(c.get("name") == "__Secure-1PSID" for c in ctx.cookies())
    except Exception:
        return False


def start_new_chat(page) -> None:
    for s in ["a[aria-label*='New chat' i]", "button[aria-label*='New chat' i]",
              "button:has-text('New chat')"]:
        loc = page.locator(s)
        if loc.count():
            try:
                loc.first.click()
                page.wait_for_timeout(1200)
                return
            except Exception:
                continue


def upload_images(page, images: list[Path], events: list) -> None:
    if not images:
        return
    log("  opening the upload menu")
    page.locator(UPLOAD_BTN).first.click(timeout=10000)
    page.wait_for_timeout(900)
    fi = page.locator("input[type=file]")
    if not fi.count():
        # menu item click may be what opens the picker on some builds
        item = page.locator("[role='menuitem']").filter(has_text="Upload files")
        if item.count():
            item.first.click()
            page.wait_for_timeout(700)
        fi = page.locator("input[type=file]")
    if not fi.count():
        raise SystemExit("could not find the file input (upload menu did not open?)")
    paths = [str(p) for p in images]
    fi.first.set_input_files(paths, timeout=20000)
    note(events, f"attached {len(paths)} image(s)")
    # wait for thumbnails / upload chips to settle
    page.wait_for_timeout(2500 + 1200 * len(paths))


def send_prompt(page, prompt: str, events: list) -> None:
    log("  typing the prompt")
    box = page.locator(PROMPT_BOX).first
    box.click(timeout=10000)
    page.keyboard.insert_text(prompt)
    page.wait_for_timeout(700)
    send = page.locator(SEND_BTN)
    if not send.count():
        raise SystemExit("send button never appeared (prompt box not focused?)")
    send.first.click()
    note(events, "prompt sent " + time.strftime("%H:%M:%S"))


def wait_for_reply(page, timeout_s: int, events: list) -> None:
    """Wait until Gemini stops generating."""
    log(f"  waiting for the reply (up to {timeout_s}s)")
    deadline = time.time() + timeout_s
    started = time.time()
    last_print = started
    idle_since = None
    while time.time() < deadline:
        page.wait_for_timeout(800)
        streaming = (
            page.locator("button[aria-label*='Stop' i]").count()
            or page.locator("button[aria-label*='Cancel send' i]").count()
            or page.locator("text=Cancel send").count()
        )
        if time.time() - last_print >= 10:
            last_print = time.time()
            log(f"    ...still {'streaming' if streaming else 'idle'} "
                f"({int(time.time() - started)}s)")
        if streaming:
            idle_since = None
            continue
        if idle_since is None:
            idle_since = time.time()
        elif time.time() - idle_since >= 2.5:
            note(events, "reply settled " + time.strftime("%H:%M:%S"))
            return
    note(events, "TIMED OUT waiting for reply")


def extract_reply(page, prompt: str) -> tuple[str, str]:
    """Return (reply_markdown, which_selector)."""
    for sel in RESPONSE_SELECTORS:
        loc = page.locator(sel)
        try:
            if loc.count():
                txt = "\n\n".join(
                    (loc.nth(i).inner_text() or "").strip() for i in range(loc.count())
                ).strip()
                if txt:
                    return txt, sel
        except Exception:
            continue
    # fallback: whole chat history minus our own prompt
    hist = page.locator("#chat-history")
    if hist.count():
        txt = (hist.first.inner_text() or "").strip()
        if prompt and prompt in txt:
            txt = txt.split(prompt, 1)[-1].strip()
        return txt, "#chat-history (fallback)"
    return "", "none"


def select_mode(page, mode: str, events: list) -> None:
    """Pick the Gemini model. Default 'flash' - Pro rate-limits hard and the
    ask then hangs for the full timeout with no reply at all."""
    labels = {"flash": "3.8 Flash", "flash-lite": "3.5 Flash-Lite", "pro": "3.1 Pro"}
    want = labels.get(mode)
    if not want:
        return
    picker = page.locator("button[aria-label*='mode picker']").first
    if picker.count() == 0:
        note(events, "mode picker not found")
        return
    current = picker.get_attribute("aria-label") or ""
    if want in current:
        note(events, "mode already " + want)
        return
    picker.click()
    page.wait_for_timeout(800)
    items = page.locator("[role=menuitem]")
    hit = None
    for i in range(items.count()):
        text = items.nth(i).inner_text().replace("\n", " ")
        if want in text:
            hit = items.nth(i)
            break
    if hit is None:
        note(events, f"mode {want!r} not in picker")
        return
    hit.click()
    page.wait_for_timeout(600)
    after = picker.get_attribute("aria-label") or ""
    note(events, "mode -> " + (after or want))


def cmd_ask(args: argparse.Namespace) -> int:
    images = [Path(i).resolve() for i in args.image]
    missing = [str(i) for i in images if not i.is_file()]
    if missing:
        raise SystemExit("image(s) not found: " + ", ".join(missing))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    from playwright.sync_api import sync_playwright

    events: list = []
    p = sync_playwright().start()
    ctx = None
    reply, selector, page = "", "none", None
    try:
        log("  starting Chrome...")
        ctx = launch(p, headless=args.headless)
        wire_dialogs(ctx, events)
        page = open_gemini(ctx)
        note(events, "page: " + page.url)
        if not signed_in(ctx):
            note(events, "NOT signed in - run: gemini_vision.bat login")
        start_new_chat(page)
        select_mode(page, args.mode, events)
        upload_images(page, images, events)
        send_prompt(page, args.prompt, events)
        wait_for_reply(page, args.timeout, events)
        page.wait_for_timeout(1500)
        reply, selector = extract_reply(page, args.prompt)
        note(events, f"reply extracted via `{selector}` ({len(reply)} chars)")
        # always keep the raw DOM for selector debugging
        hist = page.locator("#chat-history")
        if hist.count():
            (OUT_DIR / "last_chathistory.html").write_text(
                hist.first.evaluate("e => e.innerHTML"), encoding="utf-8"
            )
        if args.screenshot:
            page.screenshot(path=str(OUT_DIR / "last_run.png"))
    except Exception as e:
        note(events, "ERROR: " + repr(e))
        raise
    finally:
        if ctx:
            try:
                if args.keep_open:
                    log("browser left open (--keep-open); close it yourself")
                    ctx = None
                else:
                    ctx.close()
            except Exception:
                pass
        try:
            p.stop()
        except Exception:
            pass

    stamp = time.strftime("%Y%m%d_%H%M%S")
    md = OUT_DIR / f"feedback_{stamp}.md"
    body = (
        f"# Gemini feedback {stamp}\n\n"
        f"- images: " + ", ".join(f"`{i}`" for i in images) + "\n"
        f"- selector: `{selector}`\n\n"
        f"## Prompt\n\n{args.prompt}\n\n"
        f"## Reply\n\n{reply or '(empty)'}\n"
    )
    md.write_text(body, encoding="utf-8")

    log(f"selector used: {selector}")
    log(f"reply length: {len(reply)}")
    log(f"saved: {md}")
    if reply:
        log("-" * 60)
        print(reply)
    return 0 if reply else 2


def cmd_login(args: argparse.Namespace) -> int:
    """Open Gemini in the automation profile and wait for you to sign in.

    Polls the auth cookie instead of waiting for Enter, so it closes itself
    the moment the session exists.
    """
    from playwright.sync_api import sync_playwright

    events: list = []
    p = sync_playwright().start()
    ctx = None
    ok = False
    try:
        ctx = launch(p, headless=False)
        wire_dialogs(ctx, events)
        page = open_gemini(ctx)
        log("  Sign in inside the Chrome window (top right -> Sign in).")
        log(f"  Waiting up to {args.timeout}s for the session cookie...")
        deadline = time.time() + args.timeout
        while time.time() < deadline:
            if signed_in(ctx):
                ok = True
                break
            page.wait_for_timeout(2000)
        log("signed_in=" + str(ok))
        if ok:
            # give Chrome a moment to flush the cookie store to disk
            page.wait_for_timeout(3000)
        for e in events:
            log("  " + e)
    finally:
        if ctx:
            try:
                ctx.close()
            except Exception:
                pass
        try:
            p.stop()
        except Exception:
            pass
    if not ok:
        log("no session cookie appeared - try again, or fall back to the API key")
        return 2
    return 0


def cmd_probe(_args: argparse.Namespace) -> int:
    from playwright.sync_api import sync_playwright

    events: list = []
    p = sync_playwright().start()
    ctx = None
    try:
        ctx = launch(p, headless=False)
        wire_dialogs(ctx, events)
        page = open_gemini(ctx)
        sels = [PROMPT_BOX, UPLOAD_BTN, SEND_BTN, "input[type=file]", "button[aria-label*='Stop' i]",
                "model-response", "message-content", "[data-test-id='message-content']",
                "#chat-history", "[role='menuitem']"]
        for s in sels:
            try:
                log(f"{s}: {page.locator(s).count()}")
            except Exception as e:
                log(f"{s}: ERR {str(e)[:60]}")
        log("signed_in=" + str(signed_in(ctx)))
        log("BODY: " + page.locator("body").inner_text()[:400].replace("\n", " | "))
        page.screenshot(path=str(OUT_DIR / "probe.png"))
        for e in events:
            log("  " + e)
    finally:
        if ctx:
            try:
                ctx.close()
            except Exception:
                pass
        try:
            p.stop()
        except Exception:
            pass
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Gemini web automation for UltraDrive")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("sync-profile", help="copy real Chrome profile (Chrome must be closed)")

    l = sub.add_parser("login", help="open Gemini for a manual sign-in")
    l.add_argument("--timeout", type=int, default=300, help="seconds to wait for the sign-in")

    a = sub.add_parser("ask", help="upload images and read Gemini's reply")
    a.add_argument("--image", action="append", required=True, help="image path (repeatable)")
    a.add_argument("--prompt", required=True, help="the prompt to send")
    a.add_argument("--timeout", type=int, default=180, help="seconds to wait for the reply")
    a.add_argument("--headless", action="store_true")
    a.add_argument("--mode", choices=["flash", "flash-lite", "pro"], default="flash",
                   help="Gemini model (flash = default; pro rate-limits and hangs)")
    a.add_argument("--keep-open", action="store_true", help="leave the browser open after the run")
    a.add_argument("--screenshot", action="store_true", help="save a screenshot of the final state")

    sub.add_parser("probe", help="dump DOM selectors")

    args = ap.parse_args()
    return {"sync-profile": cmd_sync_profile, "login": cmd_login,
            "ask": cmd_ask, "probe": cmd_probe}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
