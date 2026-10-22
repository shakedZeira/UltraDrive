# scripts/ui/menu_video_playlist.gd
class_name MenuVideoPlaylist
extends RefCounted

## Pure playlist logic for the main-menu video background: candidate resolution
## (which clips actually exist on disk) and the wrap-around advance used when a
## clip finishes. Node-free and side-effect-free on purpose so the menu's
## background behaviour is testable headlessly with NO .ogv files present.
##
## The existence predicate is injected (`exists: Callable`) rather than calling
## ResourceLoader.exists() directly, so tests can exercise the "no clips", "one
## clip" and "several clips" branches with a fake.

## The clips the menu background wants, in play order. A clip that is not on
## disk (or not yet imported, i.e. no .ogv.import) is skipped at runtime; the
## gradient Backdrop in main_menu.tscn stays visible in its place.
const CANDIDATE_CLIPS: Array[String] = [
	"res://assets/videos/menu_drive_hub.ogv",
	"res://assets/videos/menu_drive_pass.ogv",
	"res://assets/videos/menu_pan_vista.ogv",
]

## The resolved clips this playlist will play, in order. Empty until resolve()
## is handed real candidates; see CANDIDATE_CLIPS.
var clips: Array[String] = []

func _init(resolved: Array[String] = []) -> void:
	clips = resolved.duplicate()

## Filters `candidates` through `exists` (a Callable(String) -> bool) keeping
## order. Returns an empty array when nothing exists, which is the correct state
## before any clip has been recorded.
static func resolve(candidates: Array[String], exists: Callable) -> Array[String]:
	var found: Array[String] = []
	for path in candidates:
		if path.is_empty():
			continue
		if bool(exists.call(path)):
			found.append(path)
	return found

## The index to play after `current`, wrapping back to 0 at the end. Returns -1
## for an empty playlist so a caller can distinguish "nothing to play" from
## "play index 0".
func next_index(current: int) -> int:
	if clips.is_empty():
		return -1
	return posmod(current + 1, clips.size())

## True when there are no playable clips (the fallback-only state).
func is_empty() -> bool:
	return clips.is_empty()

## True when there is exactly one clip: the background then relies on the
## engine's own loop (VideoStreamPlayer.loop = true) instead of the `finished`
## signal, because `finished` never fires for a looping player.
func is_single() -> bool:
	return clips.size() == 1

## Number of playable clips.
func count() -> int:
	return clips.size()

## The clip path at `index` ("" when the index is out of range).
func get_clip(index: int) -> String:
	if index < 0 or index >= clips.size():
		return ""
	return clips[index]
