import { spawn, execFile } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { tool } from "@opencode-ai/plugin";
const execFileAsync = promisify(execFile);
const OLLAMA_BIN = "D:\\Ollama\\ollama.exe";
const OLLAMA_PORT = 11434;
const OLLAMA_URL = `http://localhost:${OLLAMA_PORT}`;
const VISION_MODEL = "qwen2.5vl:7b";
const IDLE_MILLIS = 60_000;
const MAX_DIM = 1280;
const START_TIMEOUT_MS = 120_000;
const INFER_TIMEOUT_MS = 300_000;
let child = null;
let idleTimer = null;
let serverPromise = null;
function visionDir(projectRoot) {
    return path.join(projectRoot, ".vision");
}
function inboxDir(projectRoot) {
    return path.join(visionDir(projectRoot), "inbox");
}
function capturesDir(projectRoot) {
    return path.join(visionDir(projectRoot), "captures");
}
function ensureDirs(projectRoot) {
    mkdirSync(inboxDir(projectRoot), { recursive: true });
    mkdirSync(capturesDir(projectRoot), { recursive: true });
}
async function isUp() {
    try {
        const r = await fetch(`${OLLAMA_URL}/api/version`, { signal: AbortSignal.timeout(2000) });
        return r.ok;
    }
    catch {
        return false;
    }
}
async function startServer() {
    if (await isUp())
        return;
    if (serverPromise)
        return serverPromise;
    serverPromise = (async () => {
        child = spawn(OLLAMA_BIN, ["serve"], {
            windowsHide: true,
            detached: false,
            stdio: "ignore",
            env: {
                ...process.env,
                OLLAMA_LLM_LIBRARY: process.env.OLLAMA_LLM_LIBRARY ?? "vulkan",
                OLLAMA_MODELS: process.env.OLLAMA_MODELS ?? "D:\\Ollama\\models",
            },
        });
        const started = Date.now();
        while (Date.now() - started < START_TIMEOUT_MS) {
            if (child.exitCode !== null)
                break;
            if (await isUp()) {
                scheduleStop();
                return;
            }
            await new Promise((r) => setTimeout(r, 500));
        }
        throw new Error(`Ollama server did not become ready at ${OLLAMA_URL} within ${START_TIMEOUT_MS}ms (model may still be loading in the background)`);
    })();
    const p = serverPromise;
    try {
        await p;
    }
    finally {
        serverPromise = null;
        child = null;
    }
}
function scheduleStop() {
    if (idleTimer)
        clearTimeout(idleTimer);
    idleTimer = setTimeout(async () => {
        idleTimer = null;
        await stopServer();
    }, IDLE_MILLIS);
    if (idleTimer.unref)
        idleTimer.unref();
}
async function stopServer() {
    const c = child;
    child = null;
    serverPromise = null;
    if (!c || c.pid === undefined)
        return;
    const pid = c.pid;
    await new Promise((resolve) => {
        execFile("taskkill", ["/PID", String(pid), "/T", "/F"], () => resolve());
    });
}
function mimeToExt(mime) {
    if (!mime)
        return "bin";
    if (mime.includes("png"))
        return "png";
    if (mime.includes("webp"))
        return "webp";
    if (mime.includes("gif"))
        return "gif";
    if (mime.includes("svg"))
        return "svg";
    if (mime.includes("bmp"))
        return "bmp";
    return "jpg";
}
function isImagePart(p) {
    return p.type === "file" && (p.mime ?? "").startsWith("image/");
}
async function writeImagePart(part, dir) {
    try {
        let data = null;
        if (part.url.startsWith("data:")) {
            const m = part.url.match(/^data:([^;]+);base64,(.*)$/s);
            if (m)
                data = Buffer.from(m[2], "base64");
        }
        else if (part.url.startsWith("file:")) {
            data = readFileSync(new URL(part.url));
        }
        else if (/^https?:\/\//.test(part.url)) {
            const r = await fetch(part.url, { signal: AbortSignal.timeout(15_000) });
            if (r.ok)
                data = Buffer.from(await r.arrayBuffer());
        }
        else if (existsSync(part.url)) {
            data = readFileSync(part.url);
        }
        if (!data)
            return null;
        const name = part.filename && path.extname(part.filename).toLowerCase().length > 1
            ? `${Date.now()}-${path.basename(part.filename)}`
            : `${Date.now()}.${mimeToExt(part.mime)}`;
        const file = path.join(dir, name);
        await new Promise((resolve, reject) => {
            const ws = createWriteStream(file);
            ws.on("finish", resolve);
            ws.on("error", reject);
            ws.end(data);
        });
        return file;
    }
    catch {
        return null;
    }
}
async function askOllama(pathArg, question, mode = "detailed") {
    await startServer();
    try {
        const system = `You are a game developer's visual reviewer. Examine the screenshot carefully and describe what you see. Be specific and concrete.`;
        let text = "";
        if (mode === "brief") {
            text = "Give a brief but specific description of this screenshot: overall scene, notable UI, and any visual issues. Keep it under 120 words.";
        }
        else {
            text = "Describe this screenshot in detail: scene composition, colors, lighting, UI elements/state, and any visual problems you can spot.";
        }
        if (question)
            text += `\n\nThe developer specifically asks: ${question}. Answer that directly and thoroughly.`;
        const b64 = await downscaleToBase64(pathArg);
        const body = {
            model: VISION_MODEL,
            messages: [
                {
                    role: "user",
                    content: [
                        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } },
                        { type: "text", text },
                    ],
                },
            ],
            stream: false,
            max_tokens: 900,
        };
        const res = await fetch(`${OLLAMA_URL}/v1/chat/completions`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(INFER_TIMEOUT_MS),
        });
        if (!res.ok) {
            const t = await res.text();
            throw new Error(`Ollama error ${res.status}: ${t.slice(0, 500)}`);
        }
        const json = (await res.json());
        scheduleStop();
        return json.choices?.[0]?.message?.content ?? "(no content returned)";
    }
    catch (err) {
        scheduleStop();
        throw err;
    }
}
async function downscaleToBase64(file) {
    const ps = `
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$src = [System.Drawing.Image]::FromFile('${file.replace(/'/g, "''")}')
try {
  $w = $src.Width; $h = $src.Height
  $scale = 1.0
  if ($w -gt ${MAX_DIM} -or $h -gt ${MAX_DIM}) {
    $scale = [Math]::Min(${MAX_DIM} / $w, ${MAX_DIM} / $h)
  }
  $nw = [int][Math]::Round($w * $scale); $nh = [int][Math]::Round($h * $scale)
  $bmp = New-Object System.Drawing.Bitmap $nw, $nh
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.CompositingQuality = 'HighQuality'
      $g.InterpolationMode = 'HighQualityBicubic'
      $g.SmoothingMode = 'HighQuality'
      $g.DrawImage($src, 0, 0, $nw, $nh)
    } finally { $g.Dispose() }
    $ms = New-Object System.IO.MemoryStream
    try {
      $fmt = [System.Drawing.Imaging.ImageFormat]::Jpeg
      $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
      $enc = New-Object System.Drawing.Imaging.EncoderParameters 1
      $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
      $bmp.Save($ms, $codec, $enc)
      [Console]::Out.Write([Convert]::ToBase64String($ms.ToArray()))
    } finally { $ms.Dispose() }
  } finally { $bmp.Dispose() }
} finally { $src.Dispose() }
`;
    const { stdout } = await execFileAsync("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], {
        timeout: 90_000,
        windowsHide: true,
        maxBuffer: 32 * 1024 * 1024,
    });
    return stdout.trim();
}
async function captureWindow(projectRoot, windowTitle, fullScreen = false) {
    ensureDirs(projectRoot);
    const file = path.join(capturesDir(projectRoot), `${Date.now()}.png`);
    const ps = fullScreen ? `
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = 'Stop'
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
try {
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try { $g.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size) }
  finally { $g.Dispose() }
  $bmp.Save('${file.replace(/'/g, "''")}', [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $bmp.Dispose() }
` : `
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WinCap {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
'@
$ErrorActionPreference = 'Stop'
$want = '${(windowTitle ?? "UltraDrive").replace(/'/g, "''")}'
$h = [IntPtr]::Zero
$cb = [WinCap+EnumWindowsProc]{ param($w, $l)
  if ([WinCap]::IsWindowVisible($w)) {
    $sb = New-Object System.Text.StringBuilder 256
    $cn = New-Object System.Text.StringBuilder 256
    [WinCap]::GetWindowText($w, $sb, 256) | Out-Null
    [WinCap]::GetClassName($w, $cn, 256) | Out-Null
    $cls = $cn.ToString()
    if ($cls -eq 'CabinetWClass' -or $cls -eq 'Progman' -or $cls -eq 'WorkerW' -or $cls -eq 'ApplicationFrameWindow' -or $cls -eq 'Shell_TrayWnd') { return $true }
    if ($sb.Length -gt 0 -and $sb.ToString().IndexOf($want, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $script:found = $w
      return $false
    }
  }
  return $true
}
[WinCap]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$h = $script:found
if ($h -eq [IntPtr]::Zero) { throw "Window not found: $want" }
$r = New-Object 'WinCap+RECT'
[WinCap]::GetWindowRect($h, [ref]$r) | Out-Null
[WinCap]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 250
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
if ($w -le 0 -or $ht -le 0) { throw "Window has zero size: $title" }
$bmp = New-Object System.Drawing.Bitmap $w, $ht
try {
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try { $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size) }
  finally { $g.Dispose() }
  $bmp.Save('${file.replace(/'/g, "''")}', [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $bmp.Dispose() }
`;
    const { stderr } = await execFileAsync("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps], {
        timeout: 30_000,
        windowsHide: true,
    });
    if (!existsSync(file)) {
        throw new Error(stderr ? stderr.trim().slice(0, 500) : "Capture produced no image file");
    }
    return file;
}
export const VisionBridge = async ({ worktree, directory }) => {
    const projectRoot = worktree ?? directory ?? process.cwd();
    ensureDirs(projectRoot);
    return {
        dispose: async () => {
            await stopServer();
        },
        "experimental.chat.messages.transform": async (_input, output) => {
            for (const m of output.messages) {
                for (let i = 0; i < m.parts.length; i++) {
                    const p = m.parts[i];
                    if (!isImagePart(p))
                        continue;
                    const file = await writeImagePart(p, inboxDir(projectRoot));
                    const marker = file
                        ? `[Image attached and staged on disk at ${file}. You cannot see it directly — call the analyze_image tool with path "${file}" to inspect it before answering if visual detail matters.]`
                        : `[Unreadable image attachment]`;
                    m.parts[i] = {
                        id: p.id,
                        sessionID: p.sessionID,
                        messageID: p.messageID,
                        type: "text",
                        text: marker,
                    };
                }
            }
        },
        tool: {
            analyze_image: tool({
                description: "Analyze a local image file (e.g. a pasted screenshot staged in .vision/inbox, or a screen capture in .vision/captures) using a local vision model. Use this whenever you need to know what an image contains.",
                args: {
                    path: tool.schema.string().describe("Absolute or project-relative path to the image file"),
                    question: tool.schema.string().optional().describe("Specific question to answer about the image"),
                    mode: tool.schema.enum(["brief", "detailed"]).optional().describe("Level of detail (default detailed)"),
                },
                async execute(args, ctx) {
                    const base = ctx?.worktree ?? ctx?.directory ?? projectRoot;
                    const abs = path.isAbsolute(args.path) ? args.path : path.resolve(base, args.path);
                    if (!existsSync(abs)) {
                        return { output: `Image not found: ${abs}` };
                    }
                    try {
                        const response = await askOllama(abs, args.question, args.mode ?? "detailed");
                        return { output: response, title: "Image analysis" };
                    }
                    catch (err) {
                        return { output: `Analysis failed: ${err.message}` };
                    }
                },
            }),
            capture_game_window: tool({
                description: "Capture a screenshot of the running game window (default title UltraDrive) or the entire screen, and save it to .vision/captures. Use before analyzing what the game currently looks like.",
                args: {
                    windowTitle: tool.schema.string().optional().describe("Exact window title to capture (default: UltraDrive)"),
                    fullScreen: tool.schema.boolean().optional().describe("Capture the whole screen instead of a specific window"),
                },
                async execute(args) {
                    try {
                        const file = await captureWindow(projectRoot, args.windowTitle, args.fullScreen);
                        return {
                            output: `Captured image saved to ${file}. Use the analyze_image tool with this exact path to see what it shows.`,
                            title: "Screen capture",
                        };
                    }
                    catch (err) {
                        return { output: `Capture failed: ${err.message}` };
                    }
                },
            }),
        },
    };
};
