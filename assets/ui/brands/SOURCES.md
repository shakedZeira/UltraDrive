# assets/ui/brands — logo sources & provenance

Every `*.png` in this directory is the **real manufacturer's trademarked logo**,
fetched **once at build time** from Wikimedia Commons (2026-10-18) by
`tools/_dl_brands.py` and committed as a static asset — the game never touches
the network at runtime.

**Fidelity promise:** the files are Wikimedia's own PNG renderings of the
source artwork, stored *exactly as fetched*. Nothing here was recoloured,
flattened to monochrome, tinted to match the garage palette, or re-rendered
locally. Where the UI needs help (dark artwork on the dark garage panel), it
adds a neutral backing plate *around* the artwork at runtime and constrains
size/position only — see "How the UI uses these files" below.

`house_ultradrive.svg` is the exception: it is **original artwork made for this
project** (UltraDrive Motors is the fictional in-house brand) and contains no
third-party mark.

## Files

| File | Brand | Commons file page | Image fetched (exact URL) | Licence |
|---|---|---|---|---|
| `bmw.png` | BMW | [File:BMW.svg](https://commons.wikimedia.org/wiki/File:BMW.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/4/44/BMW.svg/960px-BMW.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `chevrolet.png` | Chevrolet | [File:Chevrolet bowtie 2023.svg](https://commons.wikimedia.org/wiki/File:Chevrolet_bowtie_2023.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a8/Chevrolet_bowtie_2023.svg/960px-Chevrolet_bowtie_2023.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo ² |
| `ford.png` | Ford | [File:Ford Motor Company Logo.svg](https://commons.wikimedia.org/wiki/File:Ford_Motor_Company_Logo.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a0/Ford_Motor_Company_Logo.svg/960px-Ford_Motor_Company_Logo.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `honda.png` | Honda | [File:Honda.svg](https://commons.wikimedia.org/wiki/File:Honda.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/3/38/Honda.svg/960px-Honda.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `lamborghini.png` | Lamborghini | [File:Lamborghini - logo wordmark+payoff (Italy, 1963-).svg](https://commons.wikimedia.org/wiki/File:Lamborghini_-_logo_wordmark%2Bpayoff_%28Italy%2C_1963-%29.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3a/Lamborghini_-_logo_wordmark%2Bpayoff_%28Italy%2C_1963-%29.svg/960px-Lamborghini_-_logo_wordmark%2Bpayoff_%28Italy%2C_1963-%29.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `mazda.png` | Mazda | [File:Mazda-Logo.png](https://commons.wikimedia.org/wiki/File:Mazda-Logo.png) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b7/Mazda-Logo.png/960px-Mazda-Logo.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo ² |
| `mitsubishi.png` | Mitsubishi | [File:Mitsubishi logo.svg](https://commons.wikimedia.org/wiki/File:Mitsubishi_logo.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/5/5a/Mitsubishi_logo.svg/960px-Mitsubishi_logo.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `nissan.png` | Nissan | [File:Nissan 2020 logo.svg](https://commons.wikimedia.org/wiki/File:Nissan_2020_logo.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/2/23/Nissan_2020_logo.svg/960px-Nissan_2020_logo.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo ² |
| `porsche.png` | Porsche | [File:Porsche Wordmark Logo Black.svg](https://commons.wikimedia.org/wiki/File:Porsche_Wordmark_Logo_Black.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b7/Porsche_Wordmark_Logo_Black.svg/960px-Porsche_Wordmark_Logo_Black.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | Public domain ¹ |
| `subaru.png` | Subaru | [File:Subaru logo (transparent).svg](https://commons.wikimedia.org/wiki/File:Subaru_logo_%28transparent%29.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ca/Subaru_logo_%28transparent%29.svg/960px-Subaru_logo_%28transparent%29.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo ² |
| `toyota.png` | Toyota | [File:Toyota Symbol.svg](https://commons.wikimedia.org/wiki/File:Toyota_Symbol.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/e/ed/Toyota_Symbol.svg/960px-Toyota_Symbol.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo + Trademarked ² |
| `volkswagen.png` | Volkswagen | [File:Volkswagen logo 2019.svg](https://commons.wikimedia.org/wiki/File:Volkswagen_logo_2019.svg) | [960px PNG](https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6d/Volkswagen_logo_2019.svg/960px-Volkswagen_logo_2019.svg.png?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail) | PD-textlogo + Trademark ² |
| `house_ultradrive.svg` | UltraDrive Motors (fictional) | — (original project artwork) | — | Project artwork; no third-party mark |

¹ Licence string as reported by the Commons `imageinfo` API (`extmetadata`),
retrieved 2026-10-18.
² Licence templates read from the file's wikitext on 2026-10-18.
**The Commons file page is authoritative and may change — re-check it before
any redistribution.**

**All 12 files retrieved 2026-10-18.** Wikimedia only serves bucketed
thumbnail widths, so the downloads use its `960px-` bucket rather than an
arbitrary width (requests for hand-picked widths such as `512px-` are rejected
with HTTP 400).

### Variant / era notes (why *these* files)

- `chevrolet` — 2023 bowtie, black; file-page source field points at an
  official chevrolet.com asset.
- `nissan` — the 2010s+ outline emblem; official Nissan asset per file page.
- `subaru` — current (since 2019) oval + wordmark, transparent background;
  official subaru.it asset per file page.
- `toyota` — the three-ellipse mark (since 1989).
- `mazda` — the 1997–present emblem.
- `volkswagen` — 2019 roundel; file page states it was extracted from the
  volkswagen.de source code.
- `lamborghini` — wordmark + payoff lockup.
- `bmw` / `ford` / `honda` / `mitsubishi` / `porsche` — roundel, blue oval,
  red H badge, red tri-diamond, black wordmark respectively.

Rejected alternates, for the record:

- An earlier `Honda-logo.svg` candidate was **rejected** — it carries the
  "The Power of Dreams" campaign slogan, which is not a clean brand mark.
- The initial generic wordmarks for Chevrolet / Nissan / Mazda / Subaru /
  Toyota (`Chevrolet.svg`, `Nissan logo.svg`, `Mazda logo.svg`,
  `Subaru logo.svg`, `Toyota logo.svg`) were **superseded** by the current
  official marks listed above.
- The twelve fictional monogram SVGs that used to live here were **deleted**
  on 2026-10-18 when the real marks landed; only `house_ultradrive.svg`
  remains fictional.

## Car → brand mapping

Resolution is data-only (`scripts/career/car_brands.gd`): a car's
`CarConfig.brand`, else a whole-token alias match on its
resource/visual path basename, else on its name, else the in-house default.
Adding a brand is a registry entry + an emblem file — no scene edits.

| Brand id | Display name | Emblem | Resolves from |
|---|---|---|---|
| `ultradrive` | UltraDrive Motors | `house_ultradrive.svg` | in-house default — the six bespoke/CC0 vehicles (Striker, Thunderhead, Dirt Devil, Comet, Hooligan, Interceptor; GLBs `sports_coupe`, `muscle_car`, `rally_hatch`, `cc0_sedan_sports`, `cc0_race`, `cc0_hatchback_sports`) and any config without brand fields |
| `bmw` | BMW | `bmw.png` | `bmw_m3_1988.glb` |
| `chevrolet` | Chevrolet | `chevrolet.png` | `chevrolet_corvette_stingray_427_1967.glb` |
| `ford` | Ford | `ford.png` | `ford_mustang_gt_2+2_fastback_1968.glb` |
| `honda` | Honda | `honda.png` | `honda_nsx-r_1992.glb` |
| `lamborghini` | Lamborghini | `lamborghini.png` | `lamborghini_countach_lp5000_qv_1988.glb` |
| `mazda` | Mazda | `mazda.png` | `mazda_rx-7_type_r_1992.glb` |
| `mitsubishi` | Mitsubishi | `mitsubishi.png` | `mitsubishi_lancer_evolution_vi_gsr_tm_edition_2001.glb` |
| `nissan` | Nissan | `nissan.png` | `nissan_gt-r_r35_2017.glb`, `nissan_370z_2010.glb` |
| `porsche` | Porsche | `porsche.png` | `porsche_911_carrera_rs_1973.glb` |
| `subaru` | Subaru | `subaru.png` | `subaru_impreza_22b_sti-version_1998.glb` |
| `toyota` | Toyota | `toyota.png` | `toyota_supra_rz_1998.glb` |
| `volkswagen` | Volkswagen | `volkswagen.png` | `volkswagen_golf_r_2010.glb` |

## How the UI uses these files (`scripts/ui/garage_ui.gd`)

- **No tinting, ever.** There is no `modulate` colour override on any emblem;
  only minimum size and position are constrained.
- **Neutral backing plate (runtime, source files untouched):** artwork is
  trimmed to its ink bounding box and composited onto a neutral near-white
  plate *only* when its mean opaque luminance is below 0.55 (dark marks like
  black/red-on-transparent would otherwise vanish on the dark garage panel).
  Light marks are used as-is. The plate adds transparent/neutral pixels
  *around* the artwork — no artwork pixel is altered.
- **Aspect-fit boxes:** the minimum box is `side` tall and up to
  `4 × side` wide (`KEEP_ASPECT_CENTERED`), so wide wordmarks stay readable
  instead of collapsing into a sliver of a square slot.

## Trademark & copyright caveat

These files depict **registered trademarks of their respective companies**
(BMW, Chevrolet, Ford, Honda, Lamborghini, Mazda, Mitsubishi, Nissan, Porsche,
Subaru, Toyota, Volkswagen). They are used here **solely to identify the
real-world cars** that appear as rival vehicles in this non-commercial fan
racing game. There is no affiliation with, endorsement by, or sponsorship from
any of these manufacturers.

Commons' "Public domain" / `{{PD-textlogo}}` status means the *depiction* is
free of **copyright** restriction (simple geometric/textual logos are below
Commons' copyright threshold, and several file pages additionally carry
`{{Trademarked}}` / `{{Trademark}}` notices). It does **not** place the marks
in the public domain as trademarks, and nothing in this repository claims
CC0, public-domain, or original authorship over them. Trademark rights remain
with their owners, who may object to any use beyond this repository — re-check
each Commons file page before redistributing.
