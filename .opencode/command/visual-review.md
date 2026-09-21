---
description: Visual review — capture the running game window, analyze it with the local vision model, and apply the top issues found.
agent: build
---

You are reviewing the UltraDrive game's current rendered visual state.

1. Call `capture_game_window` with windowTitle "UltraDrive" (pass fullScreen if the game is borderless/fullscreen and the window title lookup fails).
2. Call `analyze_image` on the returned capture path, mode "detailed". Ask it to critique the current frame as a GT7/Forza Horizon-quality racing game: scene composition, lighting, colors, UI layout/alignment, HUD readability, obvious visual bugs (z-fighting, clipping, placeholder art, mismatched fonts/colors, popping shadows, fog, terrain seams).
3. Report the findings to the user concisely as a numbered list.
4. Then implement the top 3 most impactful fixes that are within the current codebase (GDScript and .tscn scene tweaks only — no asset generation unless the user asks). Prefer quality-ladder settings, Environment tweaks, shader/material params, and UI scene edits.
5. Verify each fix with the project's conventions: headless import probe then GDUnit if the change touches scripted behavior (see AGENTS.md). If you cannot verify a change headlessly, say so explicitly.

If the game window is not running, tell the user to start it (or add a fullScreen capture) and pause at the desired frame.