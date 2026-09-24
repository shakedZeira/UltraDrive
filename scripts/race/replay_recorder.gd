# scripts/race/replay_recorder.gd
class_name ReplayRecorder
extends RefCounted

## AAA-5 pure replay recorder: a fixed-tick rolling buffer of the driven car's
## transform + drive info, plus a bounded timeline of named events (finish-line
## crossing, lap splits, capture start/stop). RefCounted by design (no scene),
## and its own clock is advanced ONLY by caller delta — never wall-clock reads —
## so feeding the same stream twice yields a byte-identical buffer. The cap is
## an N-second window (RECORD_SECONDS): once full the oldest samples are
## evicted FIFO, so memory can never grow out of bounds.

const TICK_RATE := 10.0
const TICK_INTERVAL := 1.0 / TICK_RATE
const RECORD_SECONDS := 90.0
const MAX_SAMPLES := int(RECORD_SECONDS * TICK_RATE)
const MAX_EVENTS := 256

## Drift gate mirrors race_ui._is_drifting (steer > 0.5 and brake > 0.1) so the
## recorded "drifting" flag matches what the HUD already emits per frame.
const DRIFT_STEER_MIN := 0.5
const DRIFT_BRAKE_MIN := 0.1

var _samples: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _clock: float = 0.0
var _accumulator: float = 0.0
var _capturing := false

## True under the headless display server. Playback culls its ghost mesh on the
## same gate so CI never renders (mirrors ui_blip / vehicle_fx / car_audio).
static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## Starts a fresh capture: clears both buffers, resets the clock, and arms the
## sampler. The very first sample is written by the first feed() (t = 0).
func start() -> void:
	_samples.clear()
	_events.clear()
	_clock = 0.0
	_accumulator = 0.0
	_capturing = true

## Freezes the capture. The buffer (and any events already recorded) stays
## readable for playback; feed() is ignored until the next start().
func stop() -> void:
	_capturing = false

func clear() -> void:
	_samples.clear()
	_events.clear()
	_clock = 0.0
	_accumulator = 0.0
	_capturing = false

func is_capturing() -> bool:
	return _capturing

func is_empty() -> bool:
	return _samples.is_empty()

## Feeds one frame's pose + drive info. delta advances the recorder clock; the
## sampler only emits on fixed TICK_INTERVAL boundaries, so the buffer is
## frame-rate independent. Same (transform, info, delta) sequence always
## produces the same buffer — the determinism contract replay relies on.
func feed(transform: Transform3D, drive_info: Dictionary, delta: float) -> void:
	if not _capturing:
		return
	delta = maxf(delta, 0.0)
	_clock += delta
	if _samples.is_empty():
		_append_sample(_build_sample(transform, drive_info, 0.0))
	_accumulator += delta
	while _accumulator >= TICK_INTERVAL:
		_accumulator -= TICK_INTERVAL
		_append_sample(_build_sample(transform, drive_info, _clock - _accumulator))

## Records a named timeline event stamped with the current recorder clock. The
## clock only moves on feed(), so an event recorded on a frame sits exactly at
## that frame's accumulated time — finish-line timestamps are preserved through
## playback. Events stay bounded (oldest evicted) so the whole buffer ships a
## memory cap.
func record_event(event_name: String) -> void:
	_events.append({"t": _clock, "name": event_name})
	if _events.size() > MAX_EVENTS:
		_events.pop_front()

func get_clock() -> float:
	return _clock

## Total recorded span (last - first sample time). With the cap engaged this
## stays at (at most) RECORD_SECONDS even after hours of feeding.
func get_duration() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[_samples.size() - 1]["t"]) - float(_samples[0]["t"])

func get_sample_count() -> int:
	return _samples.size()

func get_event_count() -> int:
	return _events.size()

func get_sample_at(index: int) -> Dictionary:
	return _samples[index]

func get_event_at(index: int) -> Dictionary:
	return _events[index]

## Index of the last sample with t <= time (0 when below the first sample,
## size - 1 when past the end). Binary search over the sorted sample stream.
func find_sample_index(time: float) -> int:
	if _samples.is_empty():
		return 0
	var lo := 0
	var hi := _samples.size() - 1
	var result := 0
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(_samples[mid]["t"]) <= time:
			result = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return result

func get_samples() -> Array[Dictionary]:
	return _samples.duplicate()

func get_events() -> Array[Dictionary]:
	return _events.duplicate()

func _append_sample(sample: Dictionary) -> void:
	_samples.append(sample)
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()

func _build_sample(transform: Transform3D, drive_info: Dictionary, t: float) -> Dictionary:
	var speed_kmh := float(drive_info.get("speed_kmh", 0.0))
	var steer := float(drive_info.get("steer", 0.0))
	var brake := float(drive_info.get("brake", 0.0))
	return {
		"t": t,
		"transform": transform,
		"speed_kmh": speed_kmh,
		"gear": int(drive_info.get("gear", 0)),
		"rpm": float(drive_info.get("rpm", 0.0)),
		"throttle": float(drive_info.get("throttle", 0.0)),
		"brake": brake,
		"steer": steer,
		"drifting": steer > DRIFT_STEER_MIN and brake > DRIFT_BRAKE_MIN,
	}