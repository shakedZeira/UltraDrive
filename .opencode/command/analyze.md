---
description: Analyze an existing image with the local vision model (qwen2.5vl:7b). Usage: /analyze <path-or-image> [question]
agent: build
---

You are reviewing an existing image using the local vision bridge.

1. The user supplied this as the argument: `$1`
   - If it is an image file path, call `analyze_image` with it directly (`path` = the exact string; if it's a project-relative path, resolve against the project root).
   - If it is a question that references an image, ask the user for the path, or list `.vision/inbox/` and `.vision/captures/` for recent images and pick/confirm the newest plausible one.
   - If no argument was given, list `.vision/inbox/` and `.vision/captures/` and summarize the most recent images, asking which to analyze.
2. Call `analyze_image` on the chosen image (mode "brief" unless the user asked for detail).
3. If the user supplied a question alongside the path, pass it as the `question` argument.
4. Report the findings concisely; if the user wanted a critique, include specific, actionable notes (composition, UI, lighting, visual bugs).

If the path does not exist, say so and list what IS available under `.vision/`.