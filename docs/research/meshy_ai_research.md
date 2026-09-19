# UltraDrive — Meshy AI Research Dossier (AI 3D Asset Generation)

*Research into "Meshi AI" — verified as **Meshy AI** (meshy.ai, Meshy LLC) — and whether/how it fits
UltraDrive's Godot 4.7.2 asset pipeline. Compiled 2026-09-19 from live sources: meshy.ai (features,
pricing, integrations), docs.meshy.ai (API + pricing), help.meshy.ai (ToS/licensing/plans), the
official **Meshy vs Hunyuan3D** compare page, and a 3D Printing Industry hands-on review of Meshy 6.
Unverified vendor claims are marked; where possible cold numbers are quoted from vendor docs/CMS.*

> ⚠️ **Name correction:** the user-facing product is **Meshy** ("Meshy AI"), not "Meshi". Brand +
> domain: https://meshy.ai, operator Meshy LLC. All references below use **Meshy**.

---

## 1. What Meshy actually IS

A **cloud, browser-based AI 3D modeling platform** (no local GPU, no install) that turns text,
single/multi-view images, or sketches into textured 3D meshes, then lets you re-texture, remesh,
auto-rig, and animate them in one workspace. Runs on vendor's cloud GPUs; accessible from any
device. Currently on its **7th generation model** — Meshy 7 (2026, image-to-3D focus), Meshy 6
(2025, "high quality and stable structure"), Meshy 5 (older), plus a **Smart Topology** game-mode
model (2026, ~10 s, optimized for game/real-time). Scale claims: 12M+ users, 100M+ models generated,
G2/Trustpilot 4.8/5 across 3,000+ reviews (vendor-reported).

### Core feature set (what it can do)

| Feature | What it does | Rough timing / cost |
|---|---|---|
| **Text to 3D** | Prompt (≤800 chars) → textured mesh | ~45–60 s; **20 credits** generation |
| **Image to 3D** | 1 photo **or 2–8 multi-view images** → mesh (Pro+ for multi-view) | <1 min; **20–35 credits** (texture adds cost) |
| **3D Agent** | Chat that brainstorms/batches concepts before spending credits | n/a |
| **Smart Topology / Remesh** | Game-ready low-poly rebuild: quad OR triangle, target polycount | ~10 s; **5 credits** |
| **AI Texturing / Retexture** | Full PBR (BaseColor/Normal/Metallic/Roughness/AO) on any mesh, incl. uploaded ones | ~1 min; **10–15 credits** by res |
| **Auto-Rig + Animate** | Humanoid/quadruped rig, 600+ preset animations | fast; 5 + 3 credits |
| **AI Image Generator** | 2D concept art routed to Image-to-3D | 3–9 credits |
| **3D printing chain** | Watertight meshes, printability check/repair, auto-split, slicer send | 3–10 credits |

### Game-ready vs marketing-stills — honest read

- **YES for game props/environment/background variety.** Smart Topology mode + standalone Remesh
  give real **retopology to a budget (100 → 300,000 polys, quad or tri)** and PBR maps — this is the
  strongest "game-ready" story of any AI generator on the market right now.
- **MOSTLY NO for high-poly hero vehicles.** Independent testing (3D Printing Industry, Sept 2026,
  on Meshy 6) found: default Standard output is **heavy** — 1.5M faces (OBJ) for a single-image
  structure, ~141k–293k faces for text-to-3D cubes; **non-manifold edges** that needed repair; a
  **racing-car test produced grainy textures that Meshy could not smooth**; and no
  engineering/dimensional accuracy. Raw generation is a concept/first-pass tool, not a finished car.
  Exactly matches UltraDrive's D4 "AI-scripted geometry came out rough" lesson.

---

## 2. Output formats, textures, topology

| Export formats | GLB, FBX, OBJ, USDZ, STL, 3MF, BLEND, DXF (8) |
|---|---|
| **Texture maps** | BaseColor, Normal, Metallic, Roughness, **AO** (true metal-roughness PBR) |
| **Texture resolution** | 2K / 4K / **8K** (API: 2K=2048², 4K=4096², 8K=8192²) |
| **Remesh topology** | `quad` (quad-dominant) OR `triangle` (decimated) — controllable |
| **Poly budget** | `target_polycount` **100–300,000**, default 30,000; or adaptive levels 1–4 |
| **LOD suitability** | No built-in LOD chain, but trivially derived: remesh the same model to 30K/10K/3K and export a chain. RegionDresser LOD practice still applies. |
| **File-size limits** | Web upload 100 MB for texturing/import (.fbx/.obj/.stl/.gltf/.glb); API accepts GLB/GLTF/OBJ/FBX/STL via URL or data-URI |
| **UV quality** | Provably texture-mapped (PBR maps ship). UV-unwrap is a separate 5-credit endpoint (API `uv_unwrap`); seams generally acceptable for props, watch on showroom cars. |
| **Vendor's own Godot claim** | "Smart Topology Mode + direct Unity/Unreal/Blender/**Godot** export keeps your pipeline friction-free" (marketing; not independently verified in Blender/Godot here) |

**Wheel-node reality check (UltraDrive `WHEEL_GROUPS`):** Meshy emits a whole-car single mesh — it
will **not** hand you per-corner wheel nodes. Wheels must be split + re-oriented (nose +Z, X-axle)
in the existing Blender-MCP normalization pass, exactly like the AI cars already shipped. This is
**extra per-model work vs the CC0 Kenney kit** (which shipped pre-split, top-level wheel nodes).

---

## 3. Licensing / Terms of Service — THE GATE QUESTION

Sources: meshy.ai/terms-of-use, help.meshy.ai articles *"What is the ownership of the generated
models?"*, *"Can I use Meshy assets commercially?"*, *"What Is Included on the Free Plan"*.

| Plan | Output rights | Commercial ship? | Attribution? | License type |
|---|---|---|---|---|
| **Free ($0)** | **Meshy grants you a CC BY 4.0 license** — Meshy keeps ownership of AI output | ✅ Yes, commercially | ✅ **Required** — credit Meshy (e.g. "Model created with Meshy — CC BY 4.0 License") | **CC BY 4.0 — NOT CC0/public-domain** |
| **Paid (Pro/Premium/Ultra/Studio)** | **You own the assets outright** (private; may be sold/resold, used in client work, games) | ✅ Yes, unrestricted (subject to: not published to Meshy community, and inputs didn't violate others' copyright) | ❌ Not required | **Full private ownership — NOT CC0/PD by default** |
| Enterprise | Custom contracts | ✅ | | Custom |

**The two traps unique to generative AI:**

1. **CC0 impossibility on Free.** CC BY 4.0 ≠ public domain. UltRadrive's gate
   (`docs/plans/cc0_car_assets_plan.md`: "handcrafted **CC0 (public-domain)** vehicles … carry no
   license debt") is **not met by any Meshy generation**. A Free-tier Meshy asset ships only if the
   team opts into "CC-BY-with-attribution" as a documented, deliberate exception.
2. **Ownership ≠ clean title.** On Paid you are legal author, so you *could* relicense/waive your
   own Paid output to CC0 later — BUT every generative tool carries an un-quantified training-data
   risk (is the mesh substantially a copyrighted car shape from training data? is your input image
   clean?). Meshy ToS puts the "you used materials that do not violate the copyrights of others"
   burden on you, and *you* are the one who must defend a CC0 waiver in court, not Meshy. Treat
   "paid-owned → we relicense to CC0" as a *fallible* path, not a guarantee.

**Working verdict for UltraDrive:** Meshy can ship commercially under **both** tiers (Free=with
attribution, Paid=clean) — there are no "personal use only" or share-alike landmines in the current
ToS (free is CC **BY**, not CC **BY-NC**). What it **cannot** do is produce a **strict CC0/public-
domain asset**. Paid outputs are the cleanest available Meshy position *if* the project explicitly
re-licenses them (and if licensing gatekeepers accept the gen-AI caveat). This is a decision the
"no AI-generated 3D with problematic licensing" rule must be amended to cover — not a silent win.

---

## 4. Compared to what UltraDrive already tried

| Option | UltraDrive status | Meshy vs it |
|---|---|---|
| **Hyper3D Rodin** (`_via_text`/`_via_images`) | D4 silhouette→mesh flow; sports coupe & muscle/rally; **judged rough, abandoned for cars** | Lateral risk on hero geometry — same AI-scripted class. Meshy's *edge*: remesh-to-game-budget is first-class (Rodin output needs external decim/split). |
| **Hunyuan3D** (via Blender MCP) | Used for coupe/muscle/rally; mesh+built-in material | Meshy is strictly more capable for pipelines: full PBR + AO, quad/tri budgeted remesh, 8 export formats vs GLB/OBJ, **non-geo-restricted global commercial license** (Tencent Community License excludes/limits EU/UK/KR and >1M MAU — a real avoidable risk), same ~1 min gen. Hunyuan wins on price of *self-hosted* (needs Linux+10–29GB NVIDIA GPU — UltraDrive has neither). |
| **Sketchfab** | Import option via Blender MCP | Market (not generator). Complement, not competitor. |
| **Poly Pizza** | Import option, CC0 bundles | Market (not generator). Complement. |
| **Hand-built primitives** (`PropScatterer` fused prims, Kenney CC0 kit) | Current production car/prop source | Meshy = *variety/fidelity* upgrade for dressing, at legal-cost + Au-the-*polish* expense. Kenney stays king on zero-license-debt + engine-native wheel nodes. |

**Where Meshy genuinely wins:** (a) budgeted **game-ready remesh/retopology in the box**; (b) full
PBR incl. AO + 8 extra formats; (c) **an official MCP server** that chains with the Blender-MCP
workflow UltraDrive already runs; (d) clean global commercial terms on Paid vs Hunyuan's territorial
license; (e) iteration speed for *non-mission-critical* variety (traffic/civic props, POI dressing).
**Where it's a lateral move:** hero car geometry — same "AI-scripted surfaces are hostile to smooth
cars" ceiling the team already hit; and any asset where pure CC0 is non-negotiable.

---

## 5. API / workflow fit — can it plug into the existing pipeline?

**Yes — unusually well.** Meshy ships three integration surfaces:

1. **REST API** (`api.meshy.ai`, docs.meshy.ai): 20+ endpoints — text/image/multi-image to 3D,
   refine (texture), retexture, remesh, convert, resize, uv_unwrap, rig, animate, balance/usage.
   Polling model: submit task → poll `GET .../:id` (`PENDING/IN_PROGRESS/SUCCEEDED/FAILED`) →
   download `model_urls.glb`. **Retention: 3 days on Pro/Studio, forever on Enterprise — download
   prompt or lose API assets.**
2. **Official MCP server** — `@meshy-ai/meshy-mcp-server` (npx; `MESHY_API_KEY=msy_...`). Exposes
   `meshy_text_to_3d`, `meshy_image_to_3d`, `meshy_remesh`, `meshy_download_model`,
   `meshy_check_balance`, etc. **Meshy's own tutorial documents chaining it with Blender MCP** —
   i.e. the exact opencode.jsonc `mcp` stanza UltraDrive already has for `mcp-for-blender`. Add a
   second stanza; no new architecture.
3. **Godot plugin** (DCC Bridge, `meshy-godot-plugin-v0.1.6.zip`): one-click send from the Meshy
   workspace into Godot's `addons/`. **Requires Pro+**, and is an editor-side convenience — it does
   **not** solve `WHEEL_GROUPS` conventions (still needs the Blender normalization pass).

**Blocker matrix for UltraDrive's `CarVisuals.WHEEL_GROUPS` flow:**

| Step | Works? | Notes |
|---|---|---|
| GLB export | ✅ | `target_formats: ["glb"]`; single-file, self-contained PBR |
| Godot-4 import as PackedScene | ✅ | Standard glTF; same path as `assets/cars/*.glb` today |
| Per-corner wheel nodes + X-axle + nose +Z | ⚠️ Needs Blender MCP pass | Split body/wheels, strip to named top-level wheel nodes, bake transforms, re-export — the documented AI-car normalization. **Per-model overhead ~15–30 min manually, or a reusable MCP script.** |
| PBR material hookup | ✅ | Metal-roughness works with Godot StandardMaterial; `car_paint.tres` override still applies |
| LOD chain for `region_dresser` traffic | ⚠️ Manual | Remesh to 30K/10K/3K = 3 separate 5-credit calls + export each; no auto LOD |
| License record in repo | ⚠️ Chore | Need per-asset provenance note (CC BY 4.0 credit or "paid-owned, relicensed"). House `License.txt` convention has no slot for this yet. |
| Headless-CI determinism | ⚠️ Out-of-band | Any Meshy call needs network + API key + money — **must be a make-resource (one-time), never a runtime/GDUnit dependency**. Godot import test stays local-only. |

**Concrete practical blockers:** API asset retention (3 days) requires a download-now discipline;
Free tier has **no API access** (Pro+ only); Godot plugin needs Pro+; per-asset wait = gen (~1 min)
+ refinement (~1 min) + remesh (~10 s) when used in the textured-and-budgeted path; account +
`msy_` API key is a new external secret for the machine. None of these are fatal for a <10-asset PoC.

---

## 6. Cost — plans, credits, and what an asset actually costs

### Plans (individual; price/credit data via meshy.ai pricing FAQ + help center plan table)

| Plan | $/mo | Credits/mo | Downloads | API access | Ownership |
|---|---|---|---|---|---|
| **Free** | $0 | **100** | **10/mo, Meshy 6 Lite only** (Meshy 6/7 downloads paywalled) | ❌ | CC BY 4.0 |
| **Pro** | $20 (≈$16/mo annual) | 1,000 | Unlimited | ✅ | Full private ownership |
| **Premium** | $40 | 3,000 | Unlimited | ✅ | Full private ownership |
| **Ultra** | $100 | 8,000 | Unlimited | ✅ | Full private ownership |
| Studio | $70/seat | Pool 5,500–28,000 | Unlimited | ✅ (limited) | Full private ownership |

### Credit cost table (API pricing, docs.meshy.ai/api/pricing)

| Operation | Cost (credits) |
|---|---|
| Text to 3D — preview mesh (Meshy 6 / low-poly / Meshy 7; +5 Ultra mode) | 20 |
| Text to 3D — **Smart Topology** game mesh (T2 model) | 5 |
| Text to 3D — refine/texture (2K/4K) · (8K) | 10 · 15 |
| Image to 3D — no texture · with texture (2K/4K) · with 8K | 20 · 30 · 35 |
| Image to 3D — Smart Topology (T2) no-tex · tex · 8K | 5 · 15 · 20 |
| Retexture (2K/4K) · 8K | 10 · 15 |
| **Remesh** (quad/tri, target polycount) | **5** |
| Convert · Resize | 1 each |
| Auto-rig · Animate · UV unwrap | 5 · 3 · 5 |

### What a single asset costs UltraDrive

| Asset type | Recommended path | Credits | $ at Pro ($0.02/cr) |
|---|---|---|---|
| Traffic sedan (game 15–30K poly) | Image-to-3D w/ texture 30 + remesh 5 | **35** | ~$0.70 |
| Building/POI (lodge, gas station, bridge) | Smart-topology T2 5 + texture 15 | 20 | ~$0.40 |
| Roadside prop (barrier, sign, rock) | Smart-topology T2 5 + texture 15 | 20 | ~$0.40 |
| 10-car traffic fleet | 10 × 35 | **350** | ~$7 (≈⅓ of a Pro month) |
| Full district dressing (40 props) | 40 × 20 | 800 | ~$16 |

Solo-scale summary: **one Pro month ($20) ≈ 1,000 credits ≈ a full traffic fleet + one district of
props**, or ~28 game-ready textured vehicles. Free tier = 100 credits/mo but dead-ends on downloads
(Meshy 6/7) → the *downloadable* PoC floor is effectively **Pro**.

---

## 7. Recommendation for UltraDrive

**Scorecard — use for X / don't use for Y / test for Z:**

| Category | Verdict | Reasoning |
|---|---|---|
| **Traffic cars / AI-rival variety** (10+ living-world cars) | ✅ **USE (Paid)** | Biggest fit: volume + variety at ~$0.70/car, Smart-Topology budgeted mesh, PBR ready. Aesthetic bar is "background believable", not hero. Requires wheel-split Blender pass + license-record chore — both documented. |
| **Environmental props / POI dressing** (buildings, ruins, bridges, lodges, guard detail) | ✅ **USE (Paid)** | RegionDresser/PropScatterer currently fuse primitives — Meshy adds bespoke, textured dressing the corridor planner will happily scatter. LOD = 3×5-credit remesh chain. |
| **Hero player cars** (sports_coupe, muscle, rally, S-class) | ❌ **DON'T** | CC0 gate + house lesson (D4: AI-scripted car surfaces rough; grainy texture per independent review) + meshes are single-piece (override `WHEEL_GROUPS` split work). Kenney CC0 kit + handcrafted stay. |
| **Texturing existing CC0 geometry** (AI Texturing on Kenney/fused primitives) | ⚠️ **TEST** | Tempting (10 credits, full PBR on kept CC0 mesh) — but the resulting *textures* are Meshy outputs → CC BY-4.0/paid-ownership applies to them too. Legal nuance per-map; geometry stays CC0, texture does not. |
| **Concepting / style-locking for districts** (3D Agent, text-to-3D, image-gen) | ✅ **USE (Free-credits)** | Zero-risk creative fuel; nothing ships. Burn the monthly 100 credits here before the gate matters. |
| **Anything that must remain strict CC0** | ❌ **NEVER** | Free=CC BY 4.0 forever; Paid=owned (relicensable, but with the gen-AI title caveat). CC0-only and Meshy are mutually exclusive. |

### Recommended integration path (if the team okays a Paid license + a CC0-exception policy)

**First PoC — one traffic sedan, end-to-end:**
1. **Pro plan** ($20) → API key (`msy_…`).
2. **Image to 3D** from a CC0 reference image (or Text to 3D): `enable_pbr`, `should_remesh`,
   `target_polycount: 20000`, `should_texture`, `target_formats: ["glb"]` → ~35 credits.
3. **Download GLB** within the 3-day retention window → `assets/cars/`.
4. **Blender MCP pass** (existing `mcp-for-blender`): split body/wheels, name wheel nodes per corner,
   enforce nose +Z + X-axle axle, bake transforms → re-export GLB.
5. **Consume stock**: `.tres` in `resources/cars/`, `CarVisuals.WHEEL_GROUPS` entry,
   `Garage`/traffic registry.
6. **Gate**: replicate `tests/suites/test_cc0_cars.gd` discipline (config resolve, GLB instantiate,
   +Z facing, 4-corner `resolve_wheel_nodes`) + record license provenance in the repo.
7. If the sedan passes playtest at 60 km/h up the pass → scale to traffic fleet + district dressing.

**Risks to log:** (a) **legal** — CC0-exception policy must be explicit (this file's §3); gen-AI
title caveat stays with the project; (b) **quality at distance** — verify LOD remesh levels in
RegionDresser before a fleet; (c) **API retention** — 3-day clock means batch-and-download, not
idle-and-hope; (d) **external dependency** — cloud account/secret + spend join the project as a
make-resource; CI stays local/deterministic; (e) **wheel split overhead** — script it in Blender or
it eats the savings; (f) **ToS drift** — Meshy has moved terms before (free tier download/API
restrictions are recent); re-verify plan table before any money commits to it.

### Cross-reference

*See `docs/plans/cc0_car_assets_plan.md` ("CC0 Handcrafted Car Asset Plan", STATUS implemented
2026-09-18): the current production car pipeline is handcrafted CC0 (Kenney Car Kit GLBs consumed as
PackedScenes through `CarVisuals.WHEEL_GROUPS` + `resources/cars/*.tres`). This Meshy research is
the "evaluate an AI generator as a **variety/vibe** supplement" question on top of that plan. Any
Meshy adoption must amend that plan's **CC0-only legal gate** with an explicit exception record
before any Meshy mesh crosses into `assets/`.*

### Decision — 2026-09-19 (owner: UltraDrive team)

**DECLINED / not adopted.** The project stays on the free + strict-CC0 pipeline. Meshy
Free is crippled (10 downloads/mo, Meshy 6 Lite only, no API, CC BY 4.0 — never CC0),
and the useful tier ($20/mo Pro) contradicts the `cc0_car_assets_plan.md` CC0-only gate.
Revisit only if asset variety becomes a shipping blocker AND a documented license
exception is acceptable (e.g. paid-owned traffic props, relicensed, with gen-AI title
caveat recorded per asset).

### Sources
- Meshy features/pricing/ToS: https://www.meshy.ai/features · /pricing · /terms-of-use
- Docs/API pricing: https://docs.meshy.ai/en · /en/api/pricing · /en/api/remesh · /en/api/text-to-3d · /en/api/image-to-3d
- MCP server: https://github.com/meshy-dev/meshy-mcp-server · https://www.meshy.ai/mcp · https://docs.meshy.ai/en/api/ai
- Godot integration: https://www.meshy.ai/integrations/godot
- Licensing/ownership/commercial: https://help.meshy.ai/en/articles/10137554-… · /16102098-… · /9992001-…
- Free plan limits: https://help.meshy.ai/en/articles/15696428-…
- Official compare (Hunyuan3D): https://www.meshy.ai/compare/meshy-vs-hunyuan3d
- Independent hands-on review (Meshy 6, Sept 2026): https://3dprintingindustry.com/news/review-meshy-ai-tested-across-six-practical-3d-modelling-tests-254447/