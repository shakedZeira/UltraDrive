# OpenCode Plugin V2 Migration Plan

**Date:** 2026-10-17
**OpenCode version:** v2.0.32 (native CLI at
`C:\Users\LotusSeven\AppData\Roaming\npm\node_modules\@opencode\cli\bin\opencode.exe`)

**Problem:** After OpenCode was upgraded to v2, the plugin loader logged

```
failed to load plugin ... cause="... Plugin must export a default definition
with an id and an effect or setup function.
(cause: SchemaError(Expected object at [\"default\"] ...))"
```

The V1 plugin API was replaced by a different V2 contract, so every plugin written
against V1 silently dropped out. This plan records what was found, what was done,
and what is deliberately left for later.

---

## 1. V1 → V2 API delta (the whole reason for this work)

V2 plugin modules must **default-export an object**:

```js
export default {
  id: "my-plugin",            // required, unique
  async setup(ctx) {          // registers everything
    // ...
    return async () => { /* optional cleanup */ };
  },
};
```

`Plugin.define` is the identity function, so a **plain object literal works** — no
import from `@opencode*` is needed. This matters: a plain `.js` file dropped in
`.opencode/plugins/` **cannot resolve `@opencode-ai/plugin`** (there is no
node_modules on the resolution path from that directory), so any port that keeps
an import of the helper is unloadable by construction.

| V1 (broken under v2) | V2 (v2.0.32) |
|---|---|
| `export const MyPlugin = async ({ worktree, directory, client }) => ({...})` | `export default { id, async setup(ctx) }` |
| `return { tool: { ... } }` | `await ctx.tool.transform((editor) => editor.add({...}))` |
| `experimental.chat.messages.transform` | `await ctx.session.hook("context", (event) => { edit event.messages })` |
| `event` callback | `ctx.event.subscribe(...)` |
| returned `dispose()` | cleanup function returned from `setup` |
| `{ worktree, directory }` | `ctx.location.directory` (also `ctx.location.project.{id,directory,canonical}`) |
| config key `"plugin"` | config key `"plugins"` |
| `{ type: "file", url, mime, filename }` message part | `{ type: "media", media: Media.Asset, filename? }` (there is **no** `type:"file"` content part in V2) |

Confirmed `Context` members on v2.0.32: `app`, `location`, `options`, `session`,
`tool`, `event`. There is **no** top-level `log` or `client`.

`ctx.tool.transform(fn)` takes a **synchronous** callback; the added tool's
`execute` may be async and returns
`{ content?: string | Content[], output?, metadata? }`.

`ctx.session.hook("context", cb)` receives
`{ sessionID, agent, model, system, messages, tools, options }` and is expected to
**mutate `event.messages` in place**. Also available:
`ctx.session.hook("retry", cb)` with
`{ sessionID, agent, model, error, attempt, decision }` — the natural seam for a
future provider-failover port.

---

## 2. Plugin inventory and disposition

| Plugin | Location | Disposition |
|---|---|---|
| `vision-bridge.js` | `.opencode/plugins/` (project) | **PORTED to V2** |
| `graphify.js` | `.opencode/plugins/` (project) | already V2-correct — untouched |
| `token-slim.js` | `.opencode/plugins/` (project) | **REMOVED** (dead) |
| `token-slim.js` | `C:\Users\LotusSeven\.config\opencode\plugins\` | **REMOVED** (dead) |
| `provider-failover.ts` | `C:\Users\LotusSeven\.config\opencode\plugins\` | **DISABLED**, port deferred |
| `opencode-easy-vision` | registered in global `opencode.json` | **DEREGISTERED** (no V2 release) |

“Removed / deregistered” for a plain-file plugin means: renamed in place to
`<file>.v1.bak`. A `.bak` extension is not auto-discovered, so the file stops
loading but stays on disk and is instantly reversible.

### 2.1 `vision-bridge.js` — ported

Kept **all** V1 behaviour, converted to V2:

- the `context` hook that stages pasted images to `.vision/inbox/` and replaces
  each image part with a text pointer (so the model is told to call the tool);
- the `analyze_image` tool (local Ollama `qwen2.5vl:7b`);
- the `capture_game_window` tool (window / full-screen capture → `.vision/captures/`);
- the full Ollama lifecycle (spawn on demand, idle-kill after 60 s), which is now
  returned as the `setup` **cleanup function** instead of a V1 `dispose()`.

Specific conversions:

- `export const VisionBridge = async ({...}) => ({...})` →
  `export default { id: "vision-bridge", async setup(ctx) { ... } }`
- The V1 tool map → two `editor.add({ name, description, input, execute })` calls
  inside one `ctx.tool.transform(...)`.
- `experimental.chat.messages.transform` → `ctx.session.hook("context", ...)`,
  editing `event.messages[i].content` in place.
- `{ worktree, directory }` → `ctx.location.directory`
  (fallback `ctx.location.project.directory`, then `process.cwd()`).

Image-part handling is deliberately **tolerant of both shapes**: it understands
V2 `{ type:"media", media }` (`Media.Asset.inline()` for bytes/base64, then
`.source`, then `.toJSON()`) and still understands a legacy V1
`{ type:"file", url, mime }` part, so the staging hook keeps working regardless of
which path the host hands it.

The only imports are Node builtins (`node:child_process`, `node:fs`, `node:path`,
`node:util`) — nothing from an `@opencode*` package, which is what makes the file
loadable from `.opencode/plugins/`.

Backup: `.opencode/plugins/vision-bridge.js.v1.bak`.

### 2.2 `token-slim.js` — removed (both copies)

Dead under both APIs: it imported
`file:///D:/AI%20Projects/OpenCode%20Token%20minimizer/dist/index.js`, which does
not exist on this machine, and its body was the V1 default-export-function shape.
Both copies were byte-identical. Renamed to `token-slim.js.v1.bak` in both
locations. Nothing was rewritten to keep them, because there is nothing left to
keep.

### 2.3 `opencode-easy-vision` — deregistered

Registered via the **V1** config key at global `opencode.json:55`
(`"plugin": ["opencode-easy-vision"]`). npm latest is `1.6.1`, whose peer range is
`@opencode-ai/plugin >=1.0.0` — i.e. a V1-era package with no v2 release. The
registration was replaced with `"plugins": []`. Its sidecar settings file
(`opencode-easy-vision.json`) is left on disk untouched (inert; see §5).

### 2.4 `provider-failover.ts` — disabled, port deferred

A 603-line V1 plugin (`.ts`) that switches the live session model when the active
provider errors. `C:\Users\LotusSeven\.config\opencode\FAILOVER.md` documents that
this behaviour is actively wanted.

It was **disabled only** (renamed `provider-failover.ts.v1.bak`), not ported, for
two reasons:

1. A faithful port depends on V2 runtime semantics that could not be verified
   statically from this session — specifically the exact `retry` hook contract and
   which `ctx` calls can legitimately mutate a live session's model.
2. It is destructive when it fires (it changes the model of the running session),
   so shipping an unverified port is worse than shipping nothing.

Disabling is instantly reversible. The V2 port sketch is in §4.

---

## 3. Config change

`C:\Users\LotusSeven\.config\opencode\opencode.json` (backup:
`opencode.json.v1.bak`):

```diff
-  "plugin": ["opencode-easy-vision"]
+  "plugins": []
 }
```

Only this one line changed. The file is LF; LF was preserved. No other key in any
config file referenced a plugin.

---

## 4. Deferred port sketch — `provider-failover.ts` → V2

Outline only; **not implemented**.

1. Convert the V1 factory to `export default { id: "provider-failover", async setup(ctx) { ... } }`.
2. Replace the V1 provider/error event subscription with
   `await ctx.session.hook("retry", (event) => { ... })`, reading
   `event.error.{type,message,status}`, `event.attempt`, `event.model`.
3. Decide the fallback model from the plugin's own config (it already carries a
   ladder), using `ctx.options` for any plugin-level settings.
4. Set `event.decision` (and/or the session model) per the contract confirmed at
   port time — **verify against the v2.0.32 types first**; do not port blind.
5. Wrap any state it persisted (see `failover-state.json`,
   `failover.json`) with `SaveManager`-style file writes under the project, not C:.
6. Gate: a smoke run that forces a provider error and asserts the session moves to
   the next model, run with a watchdog.

Until then the plugin stays disabled and the V1 file is preserved as
`provider-failover.ts.v1.bak` for reference.

---

## 5. Verification performed (static — no service restart)

Per the hard constraints, the OpenCode service was **not** restarted and the TUI
was **not** restarted during this work. Validation was static plus the one
observed hot-reload:

| Check | Command | Result |
|---|---|---|
| Parse the ported plugin | `node --check` on a `.mjs` copy of `vision-bridge.js` | **OK** |
| Parse the config | `JSON.parse` of `opencode.json` | **OK** |
| Config key | grep `plugin` in `opencode.json` | `"plugins": []` |
| No opencode imports | grep `^import ` in `vision-bridge.js` | only `node:*` builtins |
| Runtime load (observed earlier) | live opencode tool catalog | `analyze_image` + `capture_game_window` present with the ported file |
| Line endings | byte scan | `vision-bridge.js` LF; `opencode.json` LF (unchanged) |

The earlier live load of the identical ported file (under a temporary filename)
is the strongest available evidence that the port satisfies the V2 schema; after
install the sole file carrying `id: "vision-bridge"` is
`.opencode/plugins/vision-bridge.js`.

**Not verified (cannot be, without a restart / a real image / real gameplay):**

- the message-staging `context` hook against a genuinely pasted image;
- `analyze_image` producing a real Ollama response end-to-end;
- `capture_game_window` against a running game window;
- the semantics of the deferred `retry` hook for provider-failover.

---

## 6. Rollback

Everything is working-tree-only; nothing was committed. To revert:

- restore any `*.v1.bak` over the original filename (`copy /Y x.v1.bak x`);
- restore `opencode.json.v1.bak` over `opencode.json`.

The V1 files are preserved in place for exactly this purpose.

---

## 7. Open / follow-up items

- [ ] Restart the OpenCode service once, at a convenient time, and confirm the
      startup log is free of `failed to load plugin`; then exercise a pasted image
      through `analyze_image` and a `capture_game_window` shot.
- [ ] Decide whether to delete the inert `opencode-easy-vision.json` settings file
      (left untouched on purpose — it is not a plugin registration).
- [ ] Implement and verify the `provider-failover.ts` → V2 port (§4), or retire it
      deliberately if `ctx.session.hook("retry", …)` turns out not to cover the
      case.
- [ ] `.opencode/package.json` still pins the V1 helper
      (`@opencode-ai/plugin: 1.18.31`); left as-is because nothing loads it. If a
      future plugin wants the V2 helper, add a v2 dependency then.
