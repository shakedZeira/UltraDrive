# FreeRoam Music Player - plan (local song folder, stations, now-playing toast)

Status: **AS BUILT (2026-10-23), FreeRoam only.** The plan below was implemented and audited section by section; user guide:
`docs/MUSIC_USER_GUIDE.md`. Code: `scripts/music/*`, `scripts/ui/music_toast.gd`, `music_station_strip.gd`,
`music_settings_section.gd`, `scripts/audio/audio_routing.gd`, `tools/music_convert.py`; tests: `tests/suites/test_music_*.gd`,
`test_audio_routing.gd`, `tests/test_input_mapping.gd`.

As-built deviations / additions:
- `music_in_races`, `music_in_menus`, `resume_position` and "Radio Off"/favourites are NOT built (section 12: FreeRoam only).
- The Music bus carries a Limiter + a 20.5 kHz low-pass that the service closes to 1.2 kHz in the pause menu; the engine
  low-pass lives on `Vehicle` (EngineAudio, and the legacy unused `CarAudio`); rival cars stay on Master.
- Added after the audit: `music_station_strip` (Back held / station change; layer 38), `music_info` key Y (re-show toast),
  `sidecar_loader.gd` (`ultradrive_library.json` / `.m3u8` -> playlist stations + fill of empty tags), `chord_changed` and
  `info_requested` signals, high-priority worker tasks for track loads (a skip must not queue behind terrain bakes).
- Tag/ID3/Ogg/FLAC parsing is split differently than the file table in section 2 (`tag_reader`, `id3_parser`,
  `ogg_comment_parser`, `flac_parser`, `mp3_info`, `music_formats`, `music_covers`, `music_streams`).
- Verified in a windowed open-world run with generated Ogg/MP3/WAV tracks (Dummy audio driver): playback, `track_changed`,
  toast (top-left, below the coordinates label, above the minimap), next/prev/pause by key and by synthetic pad events,
  Back-chord volume/station, Y, pause-menu duck (-8 dB), silence after leaving the world, settings section, folder change.

Remaining / unverified:
- Not heard by ear and not tried with a real DualShock 4 / DS4Windows (touchpad -> Back mapping), nor with real
  Spotify Replica files (M4A/Opus). The default folder (D:/Music/UltraDrive) exists and is empty: the user must add songs.
- Native FileDialog ("Choose Folder...") was not clicked; its result handler was driven directly.
- Not built: Replica "Export for PC" (separate repo), in-game ffmpeg import button, ReplayGain, LAME-tag gapless trim.
- Open questions 1, 2, 4, 6, 7, 8, 9 below are still open (defaults chosen: pre-conversion, tags + optional sidecar,
  2.5 s crossfade, top-left toast, no favourites, Windows-first, separate music slider).
Date: 2026-10-22. Engine: Godot 4.7 (project pins 4.7.2). Reference project (read-only): `D:\AI Projects\Spotify Replica`.

## 0. Decisions already made with the user (not re-asked)

- Music source is a plain FOLDER of audio files that the game scans. No Spotify runtime dependency.
- UX: FH-style radio stations/playlists, an HUD now-playing toast (title, artist, cover art on track change), and
  controls (next / previous / pause / volume) on keyboard AND gamepad.
- Scope: FreeRoam ONLY (user confirmed 2026-10-22). Music is silent in races, garage and menus. The design keeps a
  context seam so other modes could opt in later (section 12), but v1 ships none of them.
- Gamepad (PS4 DualShock 4, user request 2026-10-22): **D-pad Left = previous track, D-pad Right = next track,
  Touchpad click = pause/resume.** Direct buttons, no chord for these three (section 9).

## 1. Key findings that shape the plan

### 1.1 Godot side (verified in this repo, plus Godot docs where noted)

1. **There is no Music bus today.** `project.godot` autoloads are InputManager, GameState, RaceManager, VehicleManager,
   WeatherManager, DayNightDriver, SaveManager, SceneTransition, PhotoModeController, LoadingScreenManager. There is no
   `default_bus_layout.tres`. The `AudioRouting` autoload (Music/Ambience/SFX buses) described in
   `docs/superpowers/plans/2026-09-13-audio-polish.md` Task 6 was never implemented (no `scripts/audio/audio_routing.gd`).
   Only `Master` exists, and `settings_menu.gd:633` (`_on_volume_changed`) drives it directly.
2. **Existing code puts a low-pass filter on `Master`.** `scripts/vehicle/car_audio.gd` (`_ensure_lpf`, line ~389) and
   `scripts/audio/engine_audio.gd` (`_ensure_lpf`, line ~1132) insert an `AudioEffectLowPassFilter` at index 0 of the
   Master bus and slew its cutoff between 900 Hz and 8000 Hz for the player car. Any music routed through Master would be
   muffled whenever the engine shaping closes that filter. **Prerequisite P0: move that LPF to a dedicated `Vehicle` bus**
   (engine/skid/wind players get `bus = "Vehicle"`), so Master stays clean. Highest-risk touch point in this plan.
3. Settings persistence is the slot-0 save JSON via `SaveManager` (atomic tmp+rename, 4 MB cap). `GameState._ready` reads
   slot 0; knobs are additive keys (`quality_preset`, `camera_settings` via `set_camera_setting`, which does
   load -> mutate -> save). Music settings follow the same pattern with a `music_settings` sub-dictionary.
4. HUD precedent: `SpeedTrapHUD` (`scripts/ui/speed_trap_hud.gd`, `scenes/ui/speed_trap_hud.tscn`) is its own `CanvasLayer`
   (layer 40) instanced from `scenes/world/open_world_root.tscn`, with PURE static timing functions (`flash_alpha`,
   `banner_alpha`), a driven `advance(delta)`, and `_process` switched off at rest. The music toast copies this exactly.
   Layers in use: HUD 0, PauseMenu 10, SpeedTrapHUD 40, photo filter 50, SceneTransition 100, loading 128.
5. `VehiclePhysics` already emits `signal impact(strength: float)` (and `CarAudio.impact_fired`) - usable as a crash
   ducking trigger. `GameState.pause_game()` sets `get_tree().paused`, so the music node must be
   `PROCESS_MODE_ALWAYS` (as `GameState` is).
6. `GameState.current_mode` is not reliable for "are we in FreeRoam": `change_scene()` sets FREE_ROAM for every non-main-menu
   scene, and menu flows use `SceneTransition.flash_to_scene()`. Use an explicit context host node in each scene (section 8).
7. Input map: keyboard keys in use are W S A D Space E Q R C T P U J I O K Esc. Joypad buttons in use: 0 headlight,
   1 handbrake, 2 shift_down / photo_toggle_ui, 3 shift_up, 6 pause, 7 photo_mode, 8 reset_car, 9 camera_mode, 10 photo_fov_up,
   11 replay_capture, 12/13/14 photo actions. Free: **4 (Back/Select)** and 5 (Guide - avoid). D-pad (11-14) is claimed
   by photo/replay actions. `replay_capture` and the photo actions are handled with `event.is_action_pressed` (consumable);
   `camera_mode` (button 9) is polled by `orbit_camera.gd` and cannot be suppressed.
8. Tests: GdUnit4 suites under `tests/`, run headless (`docs/GDUNIT_GATE.md`, parallel runner `tools/gdunit_parallel.py`
   isolates `user://` per shard). Music tests must be headless-safe (Dummy audio driver works with `AudioServer`/players)
   and must never read the real user music folder.

### 1.2 Godot audio format support (4.x)

| Format | Native | Notes |
|---|---|---|
| MP3 | Yes - `AudioStreamMP3` | Runtime: `s = AudioStreamMP3.new(); s.data = bytes` (whole ENCODED file in memory, decoded on the fly by the mixer). Verify in the 4.7 class reference whether a `load_from_file` / `load_from_buffer` helper exists for MP3; the `data` property path works regardless. |
| Ogg Vorbis | Yes - `AudioStreamOggVorbis` | Static `load_from_file(path)` and `load_from_buffer(bytes)` exist (documented since 4.2). Gapless-friendly. |
| WAV | Yes - `AudioStreamWAV` | Huge files; build from a RIFF parse (16-bit PCM). Low priority. |
| FLAC | **No** | Not decodable at runtime. |
| Opus (`.opus`, WebM/Ogg-Opus) | **No** | Godot's Ogg decoder is Vorbis-only. |
| M4A / AAC (`.m4a`, `.aac`, `.mp4`) | **No** | |

**Critical consequence for the Spotify Replica library** (section 3): its downloads are `M4A` (preferred), `WEBM_OPUS` and
`MP3`. Only MP3 plays natively, so a conversion step is mandatory for most of that library.

FLAC / M4A / Opus options considered:

1. **Pre-convert with ffmpeg (CHOSEN, v1).** `tools/music_convert.py` (project already has Python tooling): walks a source
   tree, transcodes unsupported formats to Ogg Vorbis (`-c:a libvorbis -q:a 6`, tags preserved with `-map_metadata 0`),
   copies MP3/Ogg unchanged, extracts embedded cover art to a sibling `<stem>.jpg` (ffmpeg does not reliably write
   Vorbis `METADATA_BLOCK_PICTURE`, so a sidecar image is the dependable carrier), and is idempotent (skips up-to-date
   outputs by mtime+size). Note: AAC/Opus -> Vorbis is lossy-to-lossy; q6 (~192 kbps) is transparent enough for in-car
   music. FLAC -> Vorbis loses nothing audible in a game.
2. In-game "Import and convert" button that shells out to a user-installed ffmpeg (`OS.create_process` / worker thread,
   output into `user://music_cache/`). Optional Phase 6; not a hard dependency.
3. GDExtension FLAC/Opus decoder: rejected for v1 (native binary per platform, export-template burden, 4.7 compatibility
   unverified). Revisit only if users object to conversion.
4. Pure-GDScript FLAC decoder: rejected (decode speed, big effort, no Opus/AAC anyway).

The scanner still LISTS unsupported files and reports "N files need conversion (run tools/music_convert.py)" in the
settings UI, so a half-converted library is understandable, not mysteriously empty.

## 2. Architecture overview

```
 user folder  ──scan(worker)──►  MusicLibrary (tracks, stations)  ◄── index cache user://music_index.json
                                        │
 MusicService (autoload, ALWAYS) ◄── MusicSettings (slot-0 save `music_settings`)
   ├─ StationQueue (ShuffleBag + history)
   ├─ MusicDeck: 2x AudioStreamPlayer (A/B) on bus "Music"  (equal-power crossfade)
   ├─ MusicDucker (pure): duck_db / lpf_hz targets from events + context policy
   ├─ MusicInput: actions + gamepad Back-chord
   └─ signals: track_changed(meta), station_changed(st), state_changed(), library_ready(stats)
                │
                ├─► MusicToast (CanvasLayer, scenes/ui/music_toast.tscn)   instanced in open_world_root.tscn
                ├─► MusicStationStrip (overlay shown while switching stations)
                └─► Settings menu "Music" section (folder, rescan, volume, toggles)
 Scenes declare context with a `MusicContextHost` node (FREE_ROAM / RACE / GARAGE / MENU).
```

Proposed files (all new unless noted):

| Path | Purpose |
|---|---|
| `scripts/music/music_service.gd` | Autoload `MusicService`: owns state machine, players, signals. |
| `scripts/music/music_settings.gd` | Static defaults/clamp/sanitize + `from_save(data)`; pattern of `camera_settings_from_save`. |
| `scripts/music/music_scanner.gd` | Threaded recursive scan + index cache. |
| `scripts/music/tag_reader.gd` | Dispatch by extension, fallback chain, never throws. |
| `scripts/music/id3_parser.gd`, `ogg_comment_parser.gd`, `flac_parser.gd` | Pure `PackedByteArray -> Dictionary` parsers. |
| `scripts/music/filename_parser.gd` | "Artist - Title", track-number stripping. |
| `scripts/music/sidecar_loader.gd` | `ultradrive_library.json` and `.m3u8` ingestion. |
| `scripts/music/music_station.gd`, `shuffle_bag.gd` | Station model; no-repeat shuffle + history. |
| `scripts/music/music_ducker.gd`, `crossfade_math.gd` | Pure static math (testable). |
| `scripts/music/music_policy.gd` | Pure `policy_for(context, settings)`. |
| `scripts/music/music_context_host.gd` | Tiny node placed in scenes; sets/clears context. |
| `scripts/ui/music_toast.gd`, `scenes/ui/music_toast.tscn` | HUD toast (layer 39). |
| `scripts/ui/music_station_strip.gd` (+scene) | Station switcher overlay. |
| `tools/music_convert.py` | ffmpeg batch converter + cover extraction. |
| `tests/test_music_*.gd` | See section 14. |
| Edit: `project.godot` | Autoload `MusicService`, 8 input actions, audio bus layout. |
| Edit: `scripts/ui/settings_menu.gd` + `scenes/ui/settings_menu.tscn` | Music section. |
| Edit: `scenes/world/open_world_root.tscn` | Instance toast + context host. |
| Edit: `scripts/vehicle/car_audio.gd`, `scripts/audio/engine_audio.gd` | LPF off Master (P0). |
| Edit: `.gitignore` | Music folders (section 13). |

## 3. What to borrow from Spotify Replica (specific files and concepts)

Read-only inspection of `D:\AI Projects\Spotify Replica` (secrets files `spotify.properties` / `local.properties` were NOT opened).

**3.1 On-disk layout of its downloads** (`data/download/StoragePaths.kt`):

```
<getExternalFilesDir(Music)>/<playlistId>/<spotifyId>.<ext>      downloaded track
<getExternalFilesDir(Music)>/standalone/<spotifyId>.<ext>        track downloaded outside a playlist
<...>/<spotifyId>.part.<ext>                                     in-flight download (atomic rename when done)
```

On a phone that is `/sdcard/Android/data/com.example.spotifyreplica/files/Music/` (pull to PC with `adb pull`).
Consequences for the game:
- File names are opaque Spotify IDs and folder names are opaque playlist IDs. **Filename parsing is useless for this
  library and folder-as-station would show 22-character IDs.** Human names live only in (a) embedded tags and (b) the
  phone's Room database (`TrackEntity`: spotifyId, title, artistsCsv, album, durationMs, artworkUrl, localPath, container,
  bitrateKbps; `PlaylistEntity`: spotifyId, name, ownerName, artworkUrl, trackCount).
- The scanner must skip `*.part.*` files and a folder named `standalone` should be labelled "Singles".
- Extensions seen: m4a, mp4, aac, mp3, opus, ogg, oga, webm, wav, flac (`KNOWN_AUDIO_EXTENSIONS`) - see conversion note in 1.2.

**3.2 Embedded metadata it writes** (`data/download/TagWriter.kt`, jaudiotagger): TITLE, ARTIST (multiple artists joined with
", "), ALBUM and front-cover art (downscaled by the app), best-effort and never throwing; MP3 gets **ID3v2.3** (ID3v1 cannot
hold pictures). Therefore the game's ID3 parser MUST handle v2.3 with UTF-16 (BOM) text frames and `APIC`, not just v2.4 UTF-8.
Borrow the "best-effort, never throws, missing tag is fine" contract for `TagReader`.

**3.3 Sidecar:** Spotify Replica stores NO sidecar file. The gap is closed by a small, separate change to Spotify Replica
(out of scope here, described so it can be filed): an "Export for PC" action that writes, next to the audio files:

```json
{
  "schema": 1,
  "generated_at": "2026-10-22T12:00:00Z",
  "playlists": [
    {"id": "37i9dQ...", "name": "Night Drive", "owner": "me", "cover": "covers/37i9dQ.jpg",
     "tracks": ["4uLU6h...", "1301Wl..."]}
  ],
  "tracks": {
    "4uLU6h...": {"title": "Nightcall", "artists": ["Kavinsky"], "album": "OutRun",
                  "duration_ms": 258000, "file": "37i9dQ.../4uLU6h....ogg", "cover": "covers/4uLU6h.jpg"}
  }
}
```

The game consumes it as follows (`sidecar_loader.gd`): look for `ultradrive_library.json` at the library root; if present, a
track's metadata is looked up by file stem (= spotifyId) and each `playlists[]` entry becomes a station named `name` with
the listed order. If absent, look for `*.m3u8` at the root or inside subfolders (`#EXTINF:<sec>,<Artist> - <Title>`, relative
paths) as an equivalent, hand-writable alternative. If neither exists, use embedded tags, then filename. Sidecar values
override embedded tags only for fields that are empty in the tags (tags win otherwise; the sidecar is the fallback that
turns opaque-ID folders into named stations). Unknown JSON keys are ignored; `schema` mismatch -> ignore sidecar, never crash.

**3.4 Playback ideas to port (as GDScript, not code copy):**
- `playback/QueueOps.kt` - pure queue math (`playNextIndex`, `validateMove`, `isRemovable`): port the "pure and unit-testable"
  style to `StationQueue`.
- `playback/QueueJsonCodec.kt` + `PlaybackRestore.startIndexFor` - tolerant JSON round trip (corrupt blob -> empty, never crash)
  and "restore by last track id, else index 0". Use for `music_index.json` and for resuming the last track.
- `playback/CrossfadeAudioProcessor.kt` (object `Crossfade.volumeFor`) - crossfade as a pure function of
  (position, duration, fade window) with documented edge cases (disabled when <= 0, unknown duration, tracks shorter than two
  windows). Reuse the edge-case list; replace its linear ramp with equal-power (cos/sin) because the game overlaps two
  players. Its settings bounds (default 6 s, min 1 s, max 12 s) inform ours (default 2.5 s, 0-8 s; in a car, shorter reads better).
- `playback/SleepTimer.kt` - deadline model; optionally reused later for "music off after N minutes".
- `data/settings/SettingsManager.kt` keys (gapless, crossfade_ms, normalization) - names and clamping behaviour.
- `ui/components/MiniPlayerBar.kt` and `ui/screen/player/PlayerScreen.kt` - information hierarchy for the now-playing UI:
  square art + title (1 line, ellipsis) + artist(s) + thin progress bar.
- `data/download/StoragePaths.kt` `sanitize` + `.part` rule - what to ignore when scanning.

**3.5 Not borrowed:** Room DB, Hilt/DataStore, Spotify auth/API, YouTube resolver, WorkManager, Compose UI.
Spotify Replica's shuffle is just Media3 `shuffleModeEnabled` (no no-repeat history), so the shuffle design below is new.

## 4. Library scan, metadata and cover art

### 4.1 Folder to stations

- Root = user-chosen folder. Virtual station **All Songs** (every playable track, shuffled).
- Each immediate subfolder with at least one playable file = one station named after the folder (nested subfolders flatten
  into that top-level station). Loose files in the root form station **Library** (included in All Songs).
- Optional `station.json` in a folder: `{"name": "...", "cover": "cover.jpg", "color": "#ff7a00", "shuffle": true, "order": 3}`.
- Sidecar playlists (3.3) override folder naming when present; `standalone/` -> "Singles".
- Station cycle order: user order (`order`, then alphabetical), All Songs first, then a `Radio Off` slot (FH-style silence).
- Unsupported-but-recognised files (flac/m4a/opus/webm/aac) are counted per station as `needs_conversion`, not played.

### 4.2 Threaded scanning (no hitches on hundreds of songs)

- Scan runs on `WorkerThreadPool.add_task()`; the main thread only receives batches via a mutex-protected queue drained in
  `_process` (or `call_deferred`), 25-50 tracks per batch, and emits `library_progress(done, total_estimate)`.
- Pass 1 (cheap): iterative `DirAccess` walk, collect path, size, mtime. Pass 2: for each file, consult
  `user://music_index.json` (key = relative path + size + mtime); on a hit, no file read. On a miss, read only the header:
  ID3v2 header (10 bytes, then exactly `tag_size`), last 128 bytes for ID3v1, first <=1 MB for the Ogg comment packet.
  Do NOT keep cover bytes in the index: store `cover = {"src": "embedded", "offset": n, "len": m, "mime": "image/jpeg"}`
  and extract lazily at play time.
- Duration without decoding: Ogg - granule position of the last page (read the last 64 KB) / sample rate; MP3 - Xing/Info
  frame count, else CBR estimate `size*8/bitrate`, else `TLEN`; refined by `stream.get_length()` once loaded.
- Cancellation: a generation counter; a rescan or folder change bumps it and workers drop stale batches.
- Playback may begin as soon as the first batch arrives (the player does not wait for the full scan).
- Index file written with the same tmp+rename approach as `SaveManager`; has `"version"`; any parse error -> rebuild.
  Budget: ~500 tracks x ~300 B = ~150 KB JSON.
- Do not scan from `_ready` of the autoload on boot unless music is enabled and a folder is set; stat the folder first
  (`DirAccess.dir_exists_absolute`) and degrade to a settings hint if it is gone (removable drive).

### 4.3 Metadata parsers (pure GDScript, `PackedByteArray -> Dictionary`, never throw, return what they found)

- **ID3v2.2 / 2.3 / 2.4:** 10-byte header, syncsafe size, unsynchronisation flag (undo `FF 00`), skip extended header;
  frames: v2.2 3-char id + 3-byte size, v2.3 4-char id + 4-byte BE size, v2.4 4-char id + syncsafe size. Text encodings:
  0 Latin-1 (manual byte->codepoint; `get_string_from_ascii` is not enough), 1 UTF-16 with BOM, 2 UTF-16BE, 3 UTF-8
  (`PackedByteArray.get_string_from_utf16/utf8`). Frames: `TIT2/TT2`, `TPE1/TP1`, `TPE2`, `TALB/TAL`, `TRCK`, `TLEN`,
  `APIC/PIC` (encoding, MIME, picture type - prefer type 3 front cover, then first - description, data). Multi-value text
  separated by NUL (v2.4) -> joined with ", ". ID3v1 trailer (`TAG`) as last resort.
- **Ogg Vorbis:** parse pages (`OggS`, 27-byte header, segment table), reassemble the 2nd packet (`0x03 "vorbis"`),
  read vendor + `KEY=VALUE` comments (case-insensitive `TITLE`, `ARTIST`, `ALBUM`, `ALBUMARTIST`, `TRACKNUMBER`).
  Cover: `METADATA_BLOCK_PICTURE` = base64 of a FLAC picture block (`Marshalls.base64_to_raw`, then type/MIME/desc/w/h/depth/
  colors/length/data). Cap at 1 MB read; large embedded art makes this packet big.
- **FLAC** (only to label unplayable files nicely; reuses the same Vorbis-comment and picture code): STREAMINFO (rate,
  total samples -> duration), `VORBIS_COMMENT` (type 4), `PICTURE` (type 6).
- **Fallback chain per field:** sidecar (if tag empty) -> embedded tag -> filename (`filename_parser.gd`: strip leading
  `01 `, `01-`, `1.`, `[01]`; split on first ` - ` into Artist/Title; `_` -> space) -> title = file stem, artist =
  parent-folder name, else "Unknown Artist".
- **Cover chain:** embedded -> `<stem>.jpg|jpeg|png|webp` -> folder `cover|folder|front|album.(jpg|png)` -> sidecar `cover` ->
  procedurally generated tile (station colour from a hash of the station name + first letter). The toast is never empty.
- Cover decode happens in the worker (`Image.load_jpg_from_buffer` / `load_png_from_buffer`), `Image.resize` to <= 256 px,
  then the main thread builds the `ImageTexture` (one per track change). Previous texture freed on change. Reject
  images > 8 MB or > 4096 px per side before decoding.

## 5. Playback engine

### 5.1 Loading and memory

- Streaming is "decode on the fly from an in-memory encoded buffer": an `AudioStreamMP3` / `AudioStreamOggVorbis` holds
  the compressed bytes (a 4-minute track is ~4-10 MB) and the mixer decodes incrementally - NOT a full PCM expansion (that
  would be ~40 MB per 4 minutes, which is why we never use `AudioStreamWAV` for songs).
- Keep at most 3 streams alive: outgoing, current, prefetched next. Worst case ~30 MB. Everything else is just metadata.
- File read + stream construction happen on a worker (`FileAccess.get_file_as_bytes` or `load_from_file`), result handed back
  via `call_deferred`. Next track is prefetched shortly after the current one starts (and immediately re-planned if the user
  skips: skip loads "current" at high priority, discards stale prefetch).
- A failed load (corrupt file, wrong extension) marks the track `bad` for the session, logs once, advances to the next -
  never loops forever (give up after N consecutive failures and show "No playable tracks").
- Seek-on-resume (restoring the last playback position) may cost a decode scan on long MP3s: make it optional and
  measure in Phase 3; default is to restart the saved track from 0:00.

### 5.2 Gapless vs crossfade

- Two `AudioStreamPlayer` nodes (A/B) on bus `Music`. Godot's `AudioStreamPlaylist` is not used: it needs all streams
  assigned up front (defeats lazy loading), and its crossfade does not give us station/shuffle control.
- Transition trigger: poll in `_process`; remaining = `length - (get_playback_position() + AudioServer.get_time_since_last_mix())`
  (compensating `AudioServer.get_output_latency()` for the visual toast, not for the audio). When remaining <= fade window,
  start the prefetched stream on the idle player.
- Fade curves (pure, in `crossfade_math.gd`): equal power `out = cos(t*pi/2)`, `in = sin(t*pi/2)`, applied through
  `volume_db` of each player (`linear_to_db`, floor at -60 dB then stop). Edge cases carried from Spotify Replica's
  `Crossfade.volumeFor`: fade <= 0 disables; unknown/zero length -> no pre-emptive fade, handle `finished`; tracks shorter
  than 2x fade shrink the window to length/2.
- Default `crossfade_s = 2.5` (range 0-8). With `0` it is a hard back-to-back start. True sample-accurate gapless needs
  encoder delay/padding trimming (LAME/Xing tags for MP3; Ogg is naturally clean) - Phase 6 optional; MP3 without it has a
  few ms of padding silence, which crossfading hides. Manual next/prev uses a short 0.4 s fade, not the full window.
- Optional per-track loudness: if the file has ReplayGain tags (`REPLAYGAIN_TRACK_GAIN`, ID3 `TXXX`) apply the offset;
  otherwise a conservative fixed trim. Prevents the loudest track in the library from dominating. (Phase 6.)

### 5.3 Shuffle with no-repeat history (`shuffle_bag.gd`)

- Shuffle bag: a permutation of the station's track ids; play through; refill when empty with a fresh shuffle
  (Fisher-Yates using a seedable `RandomNumberGenerator`). On refill, ensure the first N tracks differ from the last N played
  (N = min(5, size/2)).
- Soft constraint: avoid the same artist twice in a row (up to k=3 local swaps).
- History: capped stack (100) of played ids for "previous"; a forward stack so previous -> next replays the same sequence
  instead of drawing randomly. Previous after the first 3 s of a track restarts it (standard player behaviour).
- Non-shuffle stations (`shuffle:false`, or m3u8 order) play in list order and loop.
- A station with 1 track repeats it; with 0 playable tracks it is skipped by the station cycle.
- Persist (settings): station id, current track id, shuffle flag. History/bag are not persisted (fresh bag each launch).

## 6. Audio bus design

Final layout (created in code by a new `AudioRouting`-style bootstrap, idempotent like the unimplemented Task 6, or by a
checked-in `default_bus_layout.tres`; prefer code so tests can call `ensure_buses()`):

```
Master  (user master volume; settings_menu.gd already drives it)
 ├─ Music     (user music volume; effects: Limiter at -1 dB ceiling; optional LPF for pause muffling, disabled by default)
 ├─ Vehicle   (engine, skid, wind players; the existing speed/shaping LPF moves here - P0)
 ├─ SFX       (UI blips, countdown, impacts)
 └─ Ambience  (weather bed)
```

- P0 change: `_ensure_lpf` in `car_audio.gd` and `engine_audio.gd` targets bus `Vehicle` (fallback Master if missing), and
  the car players set `bus = "Vehicle"`. Existing tests that assert the LPF on `Master` (search `tests/` for `lpf`) need
  updating - keep the change mechanical.
- There is no sidechain compressor driven by another bus in Godot, so ducking is explicit (below), not signal-driven.
- `MusicService` writes `Music` bus volume = `linear_to_db(user_volume) + duck_db + context_db`, smoothed per frame
  (`move_toward` in dB; attack 0.15 s, release 1.2 s). The two decks only do the per-track crossfade; the bus does ducking
  and user volume, so the two never fight.

### 6.1 Ducking and context (`music_ducker.gd`, `music_policy.gd`, pure)

| Event / context | Behaviour |
|---|---|
| Crash (`VehiclePhysics.impact(strength)` above threshold) | duck `-6 dB`..`-12 dB` by strength, hold 0.8 s, release 1.5 s |
| Speed-trap flash/banner (`SpeedTrapHUD.play`) | duck `-5 dB` for ~2.5 s |
| Pause menu (tree paused) | `-8 dB` + Music-bus LPF 1.2 kHz, music keeps playing (decks are `PROCESS_MODE_ALWAYS`) |
| Photo mode | `-4 dB` (or off, per setting) |
| Race context | fade out over 1.2 s and PAUSE (not stop; position kept) unless `music_in_races` is on |
| Garage / main menu | pause with fade by default (setting `music_in_menus`, off) |
| Return to FreeRoam | resume the same track with a 1.0 s fade-in |

Overlapping duck sources combine by taking the deepest (min), not summing, clamped to -18 dB. `policy_for(context, settings)`
returns `{play: bool, duck_db: float, lpf_hz: float, fade_s: float}` so every row above is a unit test.

## 7. HUD now-playing toast

- `scenes/ui/music_toast.tscn` + `scripts/ui/music_toast.gd`: `CanvasLayer` (layer **39**, just under SpeedTrapHUD 40 and above the HUD 0 and
  the pause menu 10; because it sits above the pause menu, the toast hides itself while the tree is paused). Instanced in `scenes/world/open_world_root.tscn` next to `SpeedTrapHUD`.
- Contents: 72x72 cover (rounded `Panel` clip), title (bold, 1 line, ellipsis), "Artist - Album" (dim), station chip
  ("Night Drive"), 2 px progress bar. Colours taken from the cover's average colour for the accent line (computed in the
  worker on the 256 px image).
- Placement: top-left, 20 px inset, below the race `TimeLabel` area (HUD `TimeLabel` sits at x 20-240, y 48-88 in
  `hud.tscn`) - verify against a game capture, opened by Claude directly (no Ollama/Gemini, per CLAUDE.md). Bottom-left is
  occupied by the cluster, bottom-right by the minimap, bottom-centre by the speed-trap banner.
- Timing is PURE and driven like `SpeedTrapHUD`: `toast_alpha(elapsed)`, `toast_slide(elapsed)`, `advance(delta)`; rise 0.25 s,
  hold 4.0 s, fall 0.5 s; `_process` disabled at rest. No Tween.
- Triggers: `MusicService.track_changed` (not on pause/resume of the same track, not while paused, suppressed during race
  countdown/results via the context). `music_info` key/button re-shows it on demand. A station switch shows the station
  card first (name + cover) then the track toast.
- Toast can be disabled in settings; streamer-safe mode (section 13) disables music entirely.

## 8. Scene integration (FreeRoam scope, reusable elsewhere)

- Autoload registered after `SaveManager` in `project.godot`: `MusicService="*res://scripts/music/music_service.gd"`.
  `process_mode = ALWAYS`.
- `MusicContextHost` (exported enum `NONE/FREE_ROAM/RACE/GARAGE/MENU`) calls `MusicService.set_context(ctx)` in `_enter_tree`
  and `clear_context()` in `_exit_tree`. Put it in `open_world_root.tscn` (FREE_ROAM), and later race/garage/menu scenes.
  Default for scenes without a host: `NONE` (= paused with fade), so no scene can accidentally blast music.
- Race flow: race start uses `race_ui.gd` launching scenes (it already references `FREE_ROAM_SCENE`); because the context
  is scene-driven, results -> "Return to FreeRoam" (race_ui.gd line ~389) automatically resumes music.
- A new input handler lives in the autoload (`_input`), so it works in FreeRoam and while paused.

## 9. Input map additions and gamepad bindings

Add to `project.godot` `[input]` (names follow the existing snake_case actions):

| Action | Keyboard | Gamepad |
|---|---|---|
| `music_next` | N | D-pad Right (button 14) |
| `music_prev` | B | D-pad Left (button 13) |
| `music_toggle` (pause/resume) | M | Touchpad click (`JOY_BUTTON_TOUCHPAD`, index 20) |
| `music_volume_up` | `=` | Back held + D-pad Up |
| `music_volume_down` | `-` | Back held + D-pad Down |
| `music_station_next` | Tab | Back held + RB (10) |
| `music_station_prev` | Shift+Tab | (keyboard only; gamepad cycles forward through the wrap) |
| `music_info` | Y | (none; keyboard-only, because face buttons are polled by driving code) |

Notes:
- **D-pad Left/Right conflict (checked 2026-10-22):** buttons 13 and 14 are currently `photo_screenshot` and
  `photo_filter_cycle`, but `scripts/ui/photo_mode_controller.gd` only reacts to them while photo mode is active
  (`event.is_action_pressed`, lines ~106-114). So the music actions take D-pad Left/Right in FreeRoam driving, and
  `MusicInput` ignores them while photo mode is open (photo keeps its bindings there). Add a test that the music actions
  do not fire in photo mode and the photo actions do not fire outside it. D-pad Up (replay_capture) and Down (photo_fov_down)
  are untouched.
- **Touchpad:** Godot 4 maps the DS4 touchpad click to `JOY_BUTTON_TOUCHPAD` (20) via SDL; nothing in `scripts/` or
  `project.godot` uses it today. Verify on the user's actual pad and connection (USB vs Bluetooth, and whether DS4Windows
  or Steam Input is remapping it, which can hide the button). Fallback if button 20 never arrives: Back-tap. Only the click is
  used, not touch position.
- Keys N B M Tab = - Y are unused today (checked against the current map). Y/`music_info` is optional.
- The D-pad is already bound to `replay_capture` (up) and photo actions (down/left/right), and face buttons/LB are used by
  driving and camera. A Back-modifier chord avoids stealing any of them. Chord logic lives in `MusicInput`: read
  `Input.is_joy_button_pressed(device, 4)` in `_input`; when the chord matches, call `get_viewport().set_input_as_handled()`
  so `_unhandled_input` consumers (`race_ui.gd` replay_capture, photo controller) do not also fire. Polled consumers
  (`Input.is_action_just_pressed("camera_mode")` on LB in `orbit_camera.gd`) cannot be suppressed, so the chord avoids LB (9)
  and avoids face buttons (A would trigger headlight), so `music_info` is keyboard-only.
- The Back chord is now used only for volume (Back + D-pad Up/Down) and station switching (Back + RB). Back-hold shows the
  station strip ("Vol -/+  RB Station").
- Add the actions to `tests/test_input_mapping.gd`'s expectations.
- Menu sliders: volume is also on the settings screen so mouse/controller users have a non-chord path.

## 10. Persistence and settings UI

`music_settings` sub-dictionary in slot-0 save (additive key; old saves lack it and get defaults), sanitised by
`MusicSettings.from_save(data)` (clamps, type-coerces, unknown station/track ids tolerated):

```
{ "enabled": true, "folder": "D:/Music/UltraDrive", "volume": 0.7, "station": "all", "track_id": "rel/path.ogg",
  "shuffle": true, "crossfade_s": 2.5, "toast": true, "duck": true, "music_in_races": false,
  "streamer_safe": false, "resume_position": false }
```

- `volume` is linear 0..1 mapped to the `Music` bus (so a 0.7 default has headroom). Separate from the existing Master slider.
- Writes are debounced (0.8 s) for slider drags and happen on track change and on `NOTIFICATION_WM_CLOSE_REQUEST` /
  scene exit; each write is load -> mutate -> save of slot 0 (same as `GameState.set_camera_setting`) so unrelated keys are
  preserved. Keep a test that proves other slot keys survive.
- `folder` is machine-specific; on load, if it no longer exists show a hint, do not clear it.
- **Settings UI** (`settings_menu.gd` / `.tscn`, `%UniqueName` pattern, `_bind_menu_blip` for focus sounds): section "Music":
  Enable toggle; Music volume slider; Folder row (path label + **Choose Folder...** button); Rescan button; status line
  `"1,284 tracks, 12 stations, 37 need conversion"` with scan progress; Crossfade slider; Now-playing toast toggle;
  Duck on crashes toggle; Music in races toggle; Streamer-safe toggle.
- Folder dialog: `FileDialog` with `file_mode = FILE_MODE_OPEN_DIR`, `access = ACCESS_FILESYSTEM`,
  `use_native_dialog = true` (docs: honoured when the DisplayServer supports it - check
  `DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)`; otherwise fall back to Godot's built-in dialog with
  the same settings). Handle `dir_selected`. If the chosen path is under `ProjectSettings.globalize_path("res://")`, warn:
  files inside the project folder get imported by the editor and bundled into exports; recommend an external folder
  (or add an empty `.gdignore` to it).
- Headless tests construct no dialog; the folder setter is a plain method the UI calls.

## 11. Edge cases

- Empty/invalid folder, folder removed mid-session, read-only drives, unreadable files, 0-byte files, files being copied
  (size changes between passes - skip until stable), very long paths, non-ASCII file names (Windows: use `FileAccess`
  with the exact string from `DirAccess.get_next()`).
- Duplicate tracks across stations are fine (same id/path, different station membership).
- A track of 8+ minutes: crossfade still keys off remaining time. A track < 20 s: window shrinks.
- Sample-rate mismatch (48 kHz vs mix rate): Godot resamples; no action.
- Hot rescan while playing: keep the current track alive even if removed from the index.
- Audio device lost / `AudioServer` output change: players keep running; nothing to do. Headless (Dummy driver): everything
  works silently and tests rely on that.
- Pause with `get_tree().paused`: decks are ALWAYS; fade/duck math uses `delta` from `_process` which keeps running.
- Settings screen reached from main menu: context NONE, no playback; optional "Test" button plays the first 10 s of a track.

## 12. Scope: FreeRoam-only vs reuse

v1 ships FreeRoam music only (the `MusicContextHost` default is NONE) and the user wants it to stay that way: the
`music_in_races` and `music_in_menus` settings and their UI are NOT built in v1, and the race/garage/menu rows of the section 6.1
table collapse to "pause with fade". Because policy is data (`policy_for`), later options
are small: `music_in_races` (a lower-volume station, no toast), garage/menu background music, and cinematic
(`post_race_cinematic`) ducking. No change to the deck/queue code is needed for any of them.

## 13. Licensing, legal, privacy

- All music is user-supplied personal files from a folder the user chooses. **Nothing is bundled in the repo or in builds.**
  The game never downloads, streams, re-encodes in place, or redistributes music. Converted copies go to the user's own
  folder / `user://music_cache/`.
- `.gitignore` additions (do NOT add a blanket `*.mp3`: the repo root tracks `gtr.mp3`, `sututututch.mp3`, `wrx_turbo.mp3`):
  ```
  # User-supplied music (personal, never commit)
  /_music/
  /music_library/
  /ultradrive_music/
  /user_music/
  ```
  Plus an empty `.gdignore` inside any in-project dev folder so Godot's importer ignores it. The index and cache live in
  `user://` (outside the repo).
- Provenance warning: Spotify Replica obtains audio from third-party sources for personal use (its README says
  "private, personal-use build, do not publish"). Whether those files are lawful to hold is the user's responsibility; the
  game treats the folder as opaque local files and must not ship, upload, or log track lists. Do not add telemetry.
- **Streamer-safe toggle** (cheap, valuable): when on, music is disabled entirely so recorded/streamed gameplay carries no
  copyrighted audio. Show the toast with a tiny "music off" notice when it is turned on.
- Never write absolute user paths into repo-tracked reports or logs.

## 14. Test plan (GdUnit4, `tests/test_music_*.gd`, all headless-safe)

No binary fixtures committed: test helpers build byte arrays in code (ID3 tags, Ogg pages, FLAC blocks, tiny `AudioStreamWAV`
via a generator like the planned `AudioSynth`). File-system tests write to `user://` temp dirs (isolated per shard by the
parallel runner) and clean up.

| Suite | Cases |
|---|---|
| `test_music_id3_parser` | v2.2/2.3/2.4 header+frames; UTF-16 BOM, UTF-16BE, UTF-8, Latin-1 (accents); unsync; syncsafe sizes; APIC front-cover preference; truncated tag; garbage input returns `{}`; ID3v1 fallback; multi-artist join |
| `test_music_ogg_flac_parser` | Vorbis comments incl. case-insensitive keys; packet spanning pages; `METADATA_BLOCK_PICTURE` base64 decode; oversize guard; FLAC STREAMINFO duration; truncated pages |
| `test_music_filename_parser` | `01 - Artist - Title`, `1. Title`, `[03] Title`, underscores, no separator, only digits, Spotify-ID stems, unicode |
| `test_music_tag_reader` | fallback chain order (sidecar -> tag -> filename -> stem); cover chain; never throws on random bytes |
| `test_music_sidecar` | valid JSON, wrong schema ignored, unknown keys ignored, missing track ids, m3u8 `#EXTINF`, relative paths with `..` rejected (stay inside root) |
| `test_music_scanner` | folder->station mapping, nested flatten, loose-root "Library", `.part` skipped, unsupported counted `needs_conversion`, index cache hit (no re-parse; counted via a parse counter), mtime change re-parses, cancellation by generation, batches arrive without blocking, 500 synthetic entries finish within a frame budget on the main-thread side |
| `test_music_shuffle_bag` | every track once per cycle; no repeat across refill boundary; same-artist avoidance; previous/next with forward stack; seeded determinism; 0/1/2-track stations; history cap |
| `test_music_crossfade_math` | equal-power sum approx constant; fade 0 disabled; unknown length; short track window shrink; clamps |
| `test_music_ducker_policy` | event table rows; overlapping duck = deepest not sum; clamp -18 dB; attack/release slew with fake time; `policy_for` per context; pause LPF value |
| `test_music_settings` | defaults; clamping; corrupt types; old save without key; round trip preserves other slot-0 keys; debounce coalesces |
| `test_music_service` | with generated `AudioStreamWAV` tracks: play/pause/next/prev state machine, track_changed signal count, bad-track skip + give-up, station switch, context change fades, bus volume written, buses exist (extends the planned `test_audio_routing` idea) |
| `test_music_toast_timing` | `toast_alpha`/`toast_slide` statics, `advance` driven, processing off at rest, suppressed while paused |
| `test_input_mapping` (edit) | new actions exist with expected keys; Back-chord does not collide with existing joypad buttons |

Manual/visual checks (Claude opens captures itself; never Ollama/Gemini): toast placement against the HUD at 1080p and
narrow windows, station strip, settings section layout.

## 15. Phased implementation order (file-level approach, effort)

Estimates are focused engineer-days incl. tests (1 d = ~6 productive hours). Total ~12-15 d.

| Phase | Scope | Main files | Effort |
|---|---|---|---|
| **P0** Bus bootstrap + LPF off Master | `AudioRouting`-style `ensure_buses()` (Music, Vehicle, SFX, Ambience); move LPF to `Vehicle`; set vehicle player buses; fix affected audio tests | `scripts/audio/audio_routing.gd`, `car_audio.gd`, `engine_audio.gd`, `project.godot`, tests | 1 d |
| **P1** Pure core | settings, filename parser, ID3/Ogg/FLAC parsers, tag_reader, sidecar, shuffle bag, crossfade/ducker/policy + all their suites | `scripts/music/*`, `tests/test_music_*` | 3 d |
| **P2** Scanner + index cache | threaded walk, header-only parse, stations, cache, progress signals | `music_scanner.gd`, `music_library.gd` | 2 d |
| **P3** Playback service | autoload, deck A/B, prefetch, crossfade, queue/history, errors, context host, persistence, FreeRoam wiring | `music_service.gd`, `music_context_host.gd`, `open_world_root.tscn`, `project.godot` | 3 d |
| **P4** UI | toast scene, station strip, settings section + FileDialog, input actions + chord, ducking hooks (`impact`, speed trap, pause, photo mode) | `music_toast.*`, `music_station_strip.*`, `settings_menu.*`, `project.godot` | 2.5 d |
| **P5** Converter tool + docs | `tools/music_convert.py`, README for users, `.gitignore`, `.gdignore` guidance | `tools/music_convert.py`, `.gitignore` | 1 d |
| **P6** Polish (optional) | ReplayGain, LAME-tag gapless trim, in-game ffmpeg import button, favourites, sleep-timer reuse, resume position, race/garage music | various | 2-3 d |
| (separate repo) Replica export | "Export for PC" writing `ultradrive_library.json` + covers + named folders | Spotify Replica `data/download`, `ui/screen/library` | 1-1.5 d |

Per `CLAUDE.md`: run `graphify update .` after code changes; verify visuals by opening captures with the Read tool.
Gate: targeted GdUnit run per suite, then the full parallel gate (`py tools\gdunit_parallel.py -j 4`).

## 16. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Moving the Master LPF changes existing audio feel/tests | Med | P0 isolated; mechanical change; A/B listening; update LPF tests |
| User library is mostly M4A/Opus (Replica output) | High | Converter tool + clear "needs conversion" UI; Replica export step |
| Large embedded art makes header reads big | Low | 1 MB cap, header-only reads, lazy extraction, 256 px downscale |
| Hitch on track start | Med | Prefetch on worker; texture creation only on change; profile in P3 |
| Chord input collides with polled actions | Med | Back-modifier, avoid LB/face buttons; `set_input_as_handled` for event consumers |
| Touchpad click not delivered as button 20 (Bluetooth, DS4Windows/Steam Input remap) | Med | Verify on the user's pad in P1; Back-tap fallback |
| D-pad Left/Right double-fire with photo actions in photo mode | Low | `MusicInput` ignores them while photo mode is active; test both directions |
| MP3 seek cost / padding gap | Low | Resume position off by default; crossfade hides padding |
| `res://`-internal music folder gets imported/bundled | Med | UI warning + `.gdignore` guidance |
| Legal exposure from ripped content | Med | User-supplied only; nothing bundled; streamer-safe toggle |

## 17. Open questions

1. Is a mandatory ffmpeg pre-conversion step acceptable, or should the in-game "Import and convert" button (Phase 6) be
   promoted to v1? (Needs ffmpeg installed or bundled; bundling an ffmpeg binary has its own licensing.)
2. Should the Spotify Replica "Export for PC" change (sidecar JSON + named folders) be done, or is `adb pull` + tag-based
   metadata + manually renamed folders enough? Without it, stations from Replica show opaque IDs.
3. ~~Gamepad scheme~~ RESOLVED 2026-10-22: D-pad Left/Right = prev/next, Touchpad = pause (section 9). Remaining: volume and
   station via Back-chord OK, or do you want other buttons?
4. Default crossfade: 2.5 s crossfade, or true gapless with 0 s?
5. ~~Music in races~~ RESOLVED 2026-10-22: FreeRoam only (section 12).
6. Toast position (top-left vs top-right) and whether the persistent mini now-playing bar is wanted in addition to the toast.
7. Station model: should "Favourites" (hearted tracks, stored in settings) and "Radio Off" be v1 or later?
8. Is the target platform Windows only (affects native dialog, paths) or also Linux/Steam Deck?
9. Master volume vs Music volume: separate sliders in settings (assumed), and is -6 dB headroom under the engine bed the right default mix?
