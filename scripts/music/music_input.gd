# scripts/music/music_input.gd
class_name MusicInput
extends RefCounted

## Turns raw InputEvents into music commands. Pure state machine (no nodes, no
## polling) so the chord / tap logic is unit-testable with synthetic events.
##
## Keyboard (acts via the music_* InputMap actions): N next, B prev, M pause,
## = / - volume, Tab / Shift+Tab station, Y re-shows the now-playing toast.
##
## Gamepad (raw button indices, so photo mode / menus can gate them):
##   D-pad Left / Right      previous / next   (ignored in photo mode and while paused)
##   Touchpad click (20)     pause / resume    (native DualShock 4)
##   Back/Select (4) TAP     pause / resume    (press+release < TAP_MAX_S, no chord);
##                           this is how it works under DS4Windows, which presents an
##                           Xbox-360 pad and hides the touchpad as a joypad button
##                           unless it is remapped to Back
##   Back held + D-pad Up/Down   volume up / down
##   Back held + RB (10)         next station
##
## Commands returned: next, prev, toggle, vol_up, vol_down, station_next, station_prev, info.

const JOY_BACK := 4
const JOY_RIGHT_SHOULDER := 10
const JOY_DPAD_UP := 11
const JOY_DPAD_DOWN := 12
const JOY_DPAD_LEFT := 13
const JOY_DPAD_RIGHT := 14
const JOY_TOUCHPAD := 20
const TAP_MAX_S := 0.3

const ACTIONS: Array[String] = [
	"music_next", "music_prev", "music_toggle", "music_volume_up",
	"music_volume_down", "music_station_next", "music_station_prev", "music_info",
]

var _back_down: bool = false
var _back_since: float = 0.0
var _chord_used: bool = false

func back_held() -> bool:
	return _back_down

## flags: { photo: bool, paused: bool }. -> { commands: Array[String], consume: bool }
func interpret(event: InputEvent, now_s: float, flags: Dictionary = {}) -> Dictionary:
	var out := {"commands": [], "consume": false}
	var photo: bool = bool(flags.get("photo", false))
	var paused: bool = bool(flags.get("paused", false))
	var cmds: Array = out["commands"]
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return out
		if _action(event, "music_station_prev", true):
			cmds.append("station_prev")
		elif _action(event, "music_station_next", false) and not key.shift_pressed:
			cmds.append("station_next")
		elif _action(event, "music_next", false):
			cmds.append("next")
		elif _action(event, "music_prev", false):
			cmds.append("prev")
		elif _action(event, "music_toggle", false):
			cmds.append("toggle")
		elif _action(event, "music_volume_up", false):
			cmds.append("vol_up")
		elif _action(event, "music_volume_down", false):
			cmds.append("vol_down")
		elif _action(event, "music_info", false):
			cmds.append("info")
		return out
	if not (event is InputEventJoypadButton):
		return out
	var btn := event as InputEventJoypadButton
	var idx: int = btn.button_index
	if idx == JOY_BACK:
		if btn.pressed:
			_back_down = true
			_back_since = now_s
			_chord_used = false
		else:
			if _back_down and not _chord_used and (now_s - _back_since) < TAP_MAX_S:
				cmds.append("toggle")
			_back_down = false
			_chord_used = false
		return out
	if not btn.pressed:
		return out
	if idx == JOY_TOUCHPAD:
		cmds.append("toggle")
		out["consume"] = true
		return out
	if _back_down:
		# Back-chord: only volume and station; never in photo mode (photo owns the pad).
		if photo:
			return out
		match idx:
			JOY_DPAD_UP:
				cmds.append("vol_up")
			JOY_DPAD_DOWN:
				cmds.append("vol_down")
			JOY_RIGHT_SHOULDER:
				cmds.append("station_next")
		if not cmds.is_empty():
			_chord_used = true
			out["consume"] = true
		return out
	if idx == JOY_DPAD_LEFT or idx == JOY_DPAD_RIGHT:
		if photo or paused:
			return out # photo mode keeps its D-pad; menus use it for focus
		cmds.append("prev" if idx == JOY_DPAD_LEFT else "next")
		out["consume"] = true
	return out

func reset() -> void:
	_back_down = false
	_chord_used = false

static func _action(event: InputEvent, action: String, exact: bool) -> bool:
	if not InputMap.has_action(action):
		return false
	return event.is_action_pressed(action, false, exact)
