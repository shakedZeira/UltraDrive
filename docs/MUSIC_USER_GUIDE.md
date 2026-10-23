# FreeRoam radio - user guide

UltraDrive plays music from a plain folder of audio files while you drive in FreeRoam (the open world).
It is silent in races, the garage and menus. Nothing is bundled, downloaded or uploaded: you supply the files.

## 1. Point the game at a folder

- Default folder: `D:\Music\UltraDrive` (created for you on first FreeRoam start if missing). Drop songs in it.
- Other folder: Settings -> Music -> **Choose Folder...** (a folder inside the game project is refused:
  the editor would import and bundle it). **Rescan** re-reads the folder after you add songs. The status line shows
  e.g. `6 tracks, 3 stations, 1 need conversion`.
- Stations: **All Songs** (everything, shuffled), **Library** (loose files in the root), and one station per
  sub-folder (nested folders flatten into their top-level station). A folder called `standalone` is shown as "Singles".
  An optional `station.json` in a folder renames it: `{"name": "Night Drive", "color": "#ff7a00", "shuffle": true, "order": 1}`.
- Cover art: embedded picture, else `<song>.jpg|png`, else `cover|folder|front|album.jpg|png` in the folder, else a
  generated colour tile.

## 2. Formats

| Plays directly | Needs conversion (listed, not played) |
|---|---|
| MP3, Ogg Vorbis, WAV | FLAC, M4A/AAC/MP4, Opus, WebM |

Convert with `tools/music_convert.py` (needs ffmpeg on PATH or `--ffmpeg PATH`, only for this step):

```
python tools/music_convert.py "D:\Music\Source" "D:\Music\UltraDrive"
python tools/music_convert.py SRC DST --dry-run      # list what would happen
```

It mirrors the folder tree, converts FLAC/M4A/AAC/Opus/WebM to Ogg Vorbis (quality 6, tags kept, cover saved as
`<song>.jpg`), copies MP3/Ogg/WAV unchanged, skips `*.part.*` downloads, and is safe to re-run (up-to-date files are skipped).

## 3. Songs from the Spotify Replica phone app (`adb pull`)

The app stores downloads on the phone at
`/sdcard/Android/data/com.example.spotifyreplica/files/Music/<playlistId>/<spotifyId>.<ext>` (and `standalone/`).

```
adb pull /sdcard/Android/data/com.example.spotifyreplica/files/Music "D:\Music\Source"
python tools/music_convert.py "D:\Music\Source" "D:\Music\UltraDrive"
```

(Newer Android versions may block `adb pull` of `Android/data`; then copy the folder with a file manager/USB.)
Most of those files are M4A or Opus, so the conversion step is needed. Titles and artists come from the tags the app
embeds. File and folder names are opaque IDs, so stations would be called `37i9dQZF1...`. To get real station names add
**one** of these at the library root (both optional, neither is produced by the app today):

- `ultradrive_library.json` (schema 1). Playlist tracks are file stems (Spotify ids) or relative paths:
  ```json
  {"schema": 1,
   "playlists": [{"name": "Night Drive", "tracks": ["4uLU6hMCjMI75M1A2tKUQC", "1301WleyT98MSxVHPZCA6M"]}],
   "tracks": {"4uLU6hMCjMI75M1A2tKUQC": {"title": "Nightcall", "artists": ["Kavinsky"], "album": "OutRun",
                                          "duration_ms": 258000, "cover": "covers/4uLU6h.jpg"}}}
  ```
- or a hand-written `Night Drive.m3u8` (one playlist per file, at the root or in a sub-folder):
  ```
  #EXTM3U
  #EXTINF:258,Kavinsky - Nightcall
  37i9dQ/4uLU6hMCjMI75M1A2tKUQC.ogg
  ```

Playlists become stations in the listed order; songs not in any playlist keep their folder station. Tags win over the
sidecar (it only fills empty fields). A wrong schema or bad file is ignored. Paths that leave the library root are dropped.
Or simply rename the playlist folders by hand.

## 4. Controls

| Action | Keyboard | Gamepad (DualShock 4 via DS4Windows) |
|---|---|---|
| Next / previous track | N / B | D-pad Right / Left |
| Pause / resume | M | Back (Select) tap, or touchpad click |
| Volume | `=` / `-` | hold Back + D-pad Up / Down |
| Station | Tab / Shift+Tab | hold Back + RB |
| Show now-playing again | Y | - |

Holding Back for a moment shows the station strip. The D-pad keeps its photo-mode role while photo mode is open and
is ignored while the pause menu is up.

**DS4Windows:** it presents the pad as an Xbox 360 controller and hides the touchpad as a button. In DS4Windows open the
profile -> Controls -> Touchpad click and map it to **Back** (Select), or just tap the real Back/Share button. A native
DualShock 4 (Steam Input off, no DS4Windows) reports the touchpad click as button 20, which the game also accepts.

## 5. Settings (Settings -> Music)

Enable, music volume (separate from the master slider), folder, rescan, crossfade (0-8 s, default 2.5), now-playing
toast, duck on crashes and speed traps, shuffle, and **streamer-safe** (turns music off completely so recordings carry no
copyrighted audio). Settings and the last track are saved in save slot 0. Music dips while the pause menu is open
(quieter and muffled), in photo mode, and briefly on hard crashes and speed-trap flashes.

## 6. Troubleshooting

- "Folder not found": create it or choose another. A removed drive keeps its path, music resumes when it is back + Rescan.
- "N need conversion": run `music_convert.py` (section 2).
- Nothing plays: check Settings -> Music -> Play music, streamer-safe is off, and music volume is above 0. Music only
  plays in FreeRoam, never in races or menus.
- Legal: only use files you are entitled to hold. The game never logs or sends track lists.
