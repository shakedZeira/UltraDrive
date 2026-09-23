# UltraDrive — First-Person / Cockpit View Research

Sources: 3 web-research passes (Godot implementation, AAA racing design, camera-feel
& headless testing), 2026-09-23. Every claim carries its source URL. Used as the
evidence base for `docs/plans/first_person_view_plan.md`.

## 1. Industry reality: cockpit is optional in arcade, mandatory in sim & VR

- Sims (iRacing, Assetto Corsa/Competizione, rFactor 2) are cockpit-first by design —
  spawn in the car. iRacing's seating/FOV tooling is built around the driver view:
  https://support.iracing.com/support/solutions/articles/31000169161-how-to-configure-your-seating-position
- Arcade/sim-cade (GT7, Forza Horizon, Codemasters F1, Wreckfest) **default to chase**
  and present cockpit as a player choice. GT7 cycles Cockpit → Normal (chase) → Hood
  → Chase with R1 mid-race: https://www.gran-turismo.com/hk/gt7/manual/race/03
  Forza ships a family (chase/hood/driver/cockpit/bumper): https://forza.fandom.com/wiki/Camera_View
  Players report first-person as a race handicap (limited FOV, spatial awareness):
  https://steamcommunity.com/app/1551360/discussions/0/3193612534996800658
- Why chase wins: spatial awareness ("RC car" feel) + track-ahead readability;
  chase costs sense-of-speed. VR flips it — GT7 PSVR2 **locks you to cockpit/bonnet**:
  https://www.gran-turismo.com/gb/gt7/manual/psvr/01
- **Design rule:** cockpit is a *feature/reward view*, never the onboarding default.

## 2. FOV conventions (mind the axis — vertical vs horizontal confusion is endemic)

| Title | FOV | Axis / notes | Source |
|---|---|---|---|
| GT7 | ~55° cockpit & hood, fixed | hFOV, measured; seat sliders only | https://www.reddit.com/r/GranTurismo7/comments/1lvztdx/fov_in_gt7 |
| Assetto Corsa | 56° default cockpit | vertical | https://www.assettocorsa.net/forum/index.php?threads%2Ffov-field-of-view-heres-what-i-think.19426%2F |
| ACC | ~70° default, 50–60 recommended on single monitor | hFOV (some cite vFOV — conflicted) | https://west-games.com/acc-fov-calculator |
| iRacing | ~80° default single 16:9, clamp 179° | hFOV | https://coachdaveacademy.com/tutorials/the-ultimate-guide-to-fov-in-iracing |
| Forza Motorsport (2023) | sliders ~25–65 | community | https://www.reddit.com/r/forzamotorsport/comments/1ditnb7/forza_motorsport_fov_cusomize |
| Codemasters F1 | FOV as **offset from a ~77° baseline**, ±20 | known quirk | https://fovcalc.xusf.xyz/guide/game-fov-settings |
| Wreckfest | base ±30° | community sweet spot ~70% | https://www.pcgamingwiki.com/wiki/Wreckfest |

- Sim-correct cockpit on one monitor: **40–60° vFOV (~45–70 hFOV)**; arcade runs
  wider (70–110+) for sense-of-speed. GT7 **does not** widen FOV with speed; FH5
  cockpit doesn't either and players demand it (greatest "speed sense" complaint):
  https://forums.forza.net/t/speed-sense/807111
- Dynamic FOV widening at speed is the **arcade** kit (DriveClub/Burnout/Split-Second),
  best placed on the **chase** cam. Peer-reviewed: FOV + motion blur + camera height
  jointly drive perceived velocity: https://link.springer.com/chapter/10.1007/978-3-319-55834-9_14
- **Design rule:** keep cockpit FOV ~fixed and tight-ish (55–70°), clamp any speed
  widen; put arcade speed-FOV on chase (already partially done: hood 70→75).

## 3. Camera feel engineering: the rig, not the car

- **Spring-damper rig, layered additive effects, each with its own strength.**
  iRacing documents chase/drone cams as physically dragged via spring/damper:
  https://www.iracing.com/camera-editing-primer  FH5 tuner-mods expose shake/
  vibration/spring/damping (evidence of the underlying rig): https://www.nexusmods.com/forzahorizon5/mods/547
- **G-force head sway/lean** (NFS Shift masterclass — camera recreates Gs, braking
  lurches the head, corners lean into the turn): https://www.thegamer.com/why-need-for-speed-shift-has-a-perfect-cockpit-view
- **Optional shake tiers**: GT7 "Wobbling Type 1/2" (strength selector, dial it off):
  https://www.techradar.com/news/five-gran-turismo-7-settings-you-need-to-change-before-getting-behind-the-wheel
- **Dead-stable baseline preferred at the top**: iRacing cockpit is rock-steady, only
  physics-informed DriverHeadHorizon (active roll axis — head rolls around a
  horizon-level axis, ~80% blend recommended) + DriverRotateHead (yaw look-into-corner,
  ~20%): https://support.iracing.com/support/solutions/articles/31000133498-active-roll-axis-cockpit-view-driverheadhorizon-
- **Look-to-apex** (Codemasters F1 "Look to Apex Limit", default 4/15) + separate
  camera shake/movement sliders: https://www.ea.com/able/resources/f1-22/pc/camera
- **Speed micro-shake** sells speed (FH1 cockpit shake praised) but is top accessibility
  complaint — and at low FPS reads as a stutter bug; must be FPS-independent + toggleable:
  https://forums.forza.net/t/screen-shake-setting/535308

## 4. Steering wheel & hands

- Sim tier renders full wheel + hands; wheel-hiding is famously missing in AC/ACC
  (physical-rig owners hate "two wheels"): https://steamcommunity.com/app/805550/discussions/0/1741094390469098881
  iRacing's `SteeringWheel=0|1|2|3` (off/show/fixed): https://github.com/2m/iracing-config/blob/master/rendererDX11Monitor.ini
- **Hands-free "driver" cam is a real first-party tier**: Forza ships `DriverFOV` +
  `DriverNoWheelFOV`; BeamNG hides interior for driver cams: https://documentation.beamng.com/getting_started/beginner-guide
- Rotation: sims use ~900–1080°; arcade controllers must NOT animate 900° — smooth
  the animation (ACC "Steer Assist" / steer filter exists precisely for this):
  https://steamcommunity.com/app/805550/discussions/0/1738887616129501350
- Godot reference for virtual touch-wheel: `VirtualSteering` (rotation_limit 180°,
  output_limit 60°, wheel_sensitivity 12, wheel_return_speed 0.2, ignore_zone 0.5):
  https://github.com/llama-nl/VirtualSteering
- **Design rule:** wheel animation = filtered/lerped player input, never raw; and
  only "own-ship" rotation (pad players get driver-no-wheel or a fixed wheel).

## 5. Accessibility & camera-feel safety (normative now)

- **Xbox Accessibility Guideline 117**: games must let players disable/reduce FOV
  distortion, camera shake, head-bob, motion blur, auto-camera changes:
  https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117
- FH5 (best-in-class arcade): FOV sliders, cockpit drift cam, motion blur off/short/
  long — but no global shake-off, and players demanded it:
  https://support.forza.net/hc/en-us/articles/4409280058259-Forza-Horizon-5-Accessibility-Support
- Forza Motorsport (2023) added "camera motion effects" off-toggle:
  https://www.gtplanet.net/forum/threads/please-tell-me-i-can-turn-off-the-shaky-cam.423277
- Fish-eye vs nausea: one fixed "safe" number does not exist — a range + player
  freedom is the answer (Blizzard's capped-FOV counterexample):
  https://us.forums.blizzard.com/en/wow/t/motion-sickness-and-fov/1267975
- VR racing comfort techniques worth stealing for flatscreen: FOV filter while
  turning, recenter, "minimize motion sickness" guidance:
  https://support.iracing.com/support/solutions/articles/31000173566-what-you-need-to-play-iracing-in-vr

## 6. HUD, mirrors, dash-as-HUD

- Virtual (screen-space) mirrors are budgeted render passes, not free — iRacing
  `VirtualMirrors=1`, `MaxCockpitMirrors=0..4`: https://github.com/2m/iracing-config/blob/master/rendererDX11Monitor.ini
  Godot rear mirror = SubViewport + ViewportTexture; solvable (URL):
  https://www.reddit.com/r/godot/comments/1pbo2s4/how_to_create_a_rear_view_mirror/
- **Dash-as-HUD is the making-it-worth-it feature**: GT7 Multi-Function Display (TCS,
  fuel, track map in-car); NFS Shift: "turn off the HUD entirely, use the car".
  But ACC players with physical dashes want the in-game dash removable:
  https://www.overtake.gg/threads/how-to-remove-car-dashboard-in-cockpit-view.263000
  → dash HUD must be optional.
- HUD auto-hide in in-car views is mod culture that went mainstream: https://www.beamng.com/resources/immersive-ui-auto-hide-ui.33636
- **No fake windshield tint/reflections** — FH5's forced window-tint that shows
  brake-line reflections is a recurring "I can't see" complaint:
  https://steamcommunity.com/app/1551360/discussions/0/3193612534996800658

## 7. Godot implementation facts & gotchas

- Canonical cam-to-pivot pattern (official demo): a dedicated pivot node at driver-eye;
  camera copies its global_transform each frame; call `reset_physics_interpolation()`
  on camera switch to avoid a 1-frame jump:
  https://raw.githubusercontent.com/godotengine/godot-demo-projects/417732e6/3d/truck_town/vehicles/follow_camera.gd
  https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html
- Community Godot racing cams that validate UltraDrive's "copy body basis + anchor":
  https://github.com/Skaruts/racing_cameras
- **Near plane**: default 0.05 causes cockpit z-fighting/clipping; AMS2 community
  raises ClipPlanes 0.12→0.2: https://forum.reizastudios.com/threads/camera-settings-in-ams2-and-clipplanes-setting.6204/
  Godot: https://docs.godotengine.org/en/latest/tutorials/3d/3d_rendering_limitations.html
- **Camera inside a closed mesh**: StandardMaterial3D cull_mode=Back hides the shell
  interior — exterior-only GLBs are hollow from inside, so a light interior proxy
  (dash/pillars/wheel) is required for cockpit (or hide the body while cockpit cam is
  current). Culling-mask technique reference:
  https://gamedev.stackexchange.com/questions/167520/
- **Shake-before-render only**: game-logic transform stays unshaken; apply shake to a
  copy so it never feeds back into camera state (official Bevy shake example, decay
  0.5/s, exp 2, noise 20, trauma/event 0.4):
  https://github.com/bevyengine/bevy/blob/main/examples/camera/2d_screen_shake.rs
- **Reverse-Z (Godot 4.3+)** already reduces depth fighting for free:
  https://godotengine.org/article/introducing-reverse-z/
- **Headless testing**: GDUnit4 has no headless image capture (#655) → assert
  transforms/FOV/mode state, not screenshots: https://github.com/godot-gdunit-labs/gdUnit4/issues/655
  SceneRunner: `simulate_frames(frames, delta_ms)` — adding a node does NOT advance
  frames, process callbacks never fire without it:
  https://godot-gdunit-labs.github.io/gdUnit4/latest/advanced_testing/sceneRunner/
  Input in `_process` AND `_physics_process` loses frames; press → `await_input_processed()`
  → `await physics_frame`: https://github.com/godot-gdunit-labs/gdUnit4/discussions/581
- Physics interpolation smooths user-facing children; toggle camera current +
  `reset_physics_interpolation()`:
  https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html
- VR future-proofing: keep the cam pivot-node based so `XRCamera3D` can replace the
  Camera3D later without rewiring gameplay: https://docs.godotengine.org/en/4.4/tutorials/xr/openxr_settings.html

## 8. Validation of UltraDrive's existing hood cam (build on, don't rebuild)

| Hood-cam choice | Verdict | Evidence |
|---|---|---|
| Rigid bolt (copy body basis) | Validated — official truck_town + Skaruts | §7 |
| FOV bump with speed (70→75) | Validated for arcade speed-feel; keep the *widen* on chase/hood, keep cockpit tight | §2 |
| Speed head-bob | Validated as neck-spring equivalent; must be small & toggleable | §3, §5 |

## 9. Key gaps the cockpit plan must fill (not supplant)

1. **Interior geometry — the single biggest blocker**: `player_car.tscn`/`CarBody`
   swap exterior-only GLBs (sports_coupe/muscle_car/rally_hatch + Kenney CC0 kit); no
   dash/pillars/interior node exists. Cockpit view currently sees a hollow shell.
2. **Driver-eye pivot node per car** (truck_town pattern) instead of hood hard-math
   offsets; flexible seat height/depth/offset sliders (GT7-style).
3. **`reset_physics_interpolation()` on camera switch** in `orbit_camera.gd._apply_mode()`.
4. **Near plane ~0.2** for the cockpit camera.
5. **Settings-gated comfort vs immersion knobs** (XAG 117): FOV per camera, shake,
   head-motion, motion blur, lean-cam — wired into `settings_menu.gd`'s quality-ladder
   pattern; FPS-independence is an acceptance criterion.