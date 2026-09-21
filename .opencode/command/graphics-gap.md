---
description: Close the graphics gap — analyze pasted reference images (Forza/GT7) vs UltraDrive frames, then produce an actionable plan to close the visual gaps. Usage: /graphics-gap [optional path to a specific UltraDrive frame]
agent: build
---

You are a visual quality lead comparing UltraDrive's current render against AAA racing-game reference imagery (e.g. Forza Horizon 6, Gran Turismo 7), then producing a concrete plan to close the gaps.

## Step 1 — Gather reference images
- References live in `.vision/` subfolders keyed by game. Any image under a DIRECTORY LEAF that is not `captures` or `inbox` is a reference; the leaf name (e.g. "Forza Horizon 6", "Gran Turismo 7") tells you which game it is. Annotate every analyzed reference with its game so the plan can cite it.
- If a leaf is empty or no reference images exist anywhere except `inbox`, ask the user which pasted `inbox` images are references for which game (or tell them to drop files under a named leaf).

## Step 2 — Gather UltraDrive frames
- UltraDrive frames are whatever lives under `.vision/captures/`.
- If `$1` (or a later arg) is a path to an UltraDrive frame, use it.
- Otherwise call `capture_game_window` (windowTitle "UltraDrive"; pass fullScreen if title lookup fails or the game runs borderless). If capture fails because the game isn't running, tell the user to launch `play_game.bat` and pause at a representative frame, then retry.
- A single UltraDrive frame is enough for the rubric below, but more frames (different scenes) improve coverage.

## Step 3 — Analyze every image
For EACH image (reference AND UltraDrive frame), call `analyze_image` with mode "detailed", using a question that extracts a consistent rubric:
"Describe and rank the following aspects, and note specifics: 1) lighting & GI/bounce, 2) post-processing (bloom, tonemapping, exposure, shadows), 3) materials & shaders (trunk/road/tire/paint response, roughness, transmission), 4) environment & sky (fog, clouds, foliage, terrain seams), 5) geometry detail/tessellation & LOD, 6) camera/FOV/framing, 7) UI/HUD design and readability. Be concrete — name colors, values, contrast ratios, and specific artifacts."

Known quirks (learned 2026-09-20):
- Analyze images SEQUENTIALLY, one at a time — the Ollama backend (`qwen2.5vl:7b`, Vulkan) can't serve parallel calls and they all time out.
- Keep the prompt short; the model is slow (~90 s/image), and long prompts tend to time out the tool. Use mode "brief" with a compact question if "detailed" times out.
- The plugin's loader uses System.Drawing, which cannot read `.webp`/`.jfif`. Convert them to `.png` first with PowerShell WIC:
  `powershell -NoProfile -Command "Add-Type -AssemblyName PresentationCore; ... BitmapDecoder.Create(...) -> PngBitmapEncoder ..."` (no PIL/ImageMagick is installed on this machine).

## Step 4 — Persist the analysis log
Append EVERY `analyze_image` result to `.vision/analysis.md` as soon as it returns (don't wait until the end — results are easy to lose).
- Header: `# Graphics-gap analysis log` + timestamped section per run.
- Group by source: each UltraDrive capture under `.vision/captures/`, each reference under its game leaf (label it with the game, e.g. "Forza Horizon 6").
- For each image record: filename, game/source, the ranking + concrete artifacts the model returned (verbatim or lightly cleaned). Make sure every reference is labeled with its game so the plan can cite it.
- `.vision/` is gitignored, so this log is purely local documentation.

## Step 5 — Produce the gap-closing plan
Write a numbered, prioritized plan:
- Group gaps by domain (Lighting/GI, Post-Processing, Materials, Environment, Geometry/LOD, Camera, UI).
- For each gap: what the reference looks like vs what UltraDrive currently shows (cite the references), and a specific, implementable fix using ONLY GDScript and .tscn tweaks (Environment node values, WorldEnvironment settings, material params, shader params, UI scene edits). No asset generation unless the user asks.
- Order by impact-per-effort; mark which fixes are quick wins vs high-effort.
- End with a recommended build/verify path per AGENTS.md (headless import probe, then GDUnit for behavior changes).

## Step 6 — Report
Present the plan concisely to the user as a numbered list, keeping per-item detail tight enough to act on. Do NOT start implementing unless the user says so.