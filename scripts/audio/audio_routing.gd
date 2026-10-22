# scripts/audio/audio_routing.gd
class_name AudioRouting
extends RefCounted

## Idempotent audio-bus bootstrap. Layout (every bus sends to Master, so the
## settings-menu Master slider still scales everything):
##
##   Master
##    +- Music     user music volume (MusicService); Limiter + a 20.5 kHz
##    |            low-pass that MusicService closes while the pause menu is up
##    +- Vehicle   the player car's engine / skid / wind players; the speed and
##    |            load-shaping low-pass of EngineAudio lives HERE, not on
##    |            Master, so music (and UI) are never muffled by engine shaping
##    +- SFX
##    +- Ambience
##
## ensure_buses() can be called from anywhere, any number of times (the
## AudioServer is process-global state): it only creates what is missing.

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_VEHICLE := &"Vehicle"
const BUS_SFX := &"SFX"
const BUS_AMBIENCE := &"Ambience"

## Cutoff that means "filter open" on the Music bus low-pass.
const MUSIC_LPF_OPEN_HZ := 20500.0

static func ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_VEHICLE, BUS_SFX, BUS_AMBIENCE]:
		_ensure_bus(bus_name)
	_ensure_music_effects()

static func has_bus(bus_name: StringName) -> bool:
	return AudioServer.get_bus_index(bus_name) >= 0

## Index of a bus, or -1.
static func bus_index(bus_name: StringName) -> int:
	return AudioServer.get_bus_index(bus_name)

static func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)

## Music bus effects: [0] hard limiter (if the engine has one), [1] low-pass.
static func _ensure_music_effects() -> void:
	var idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if idx < 0:
		return
	if music_lpf() != null:
		return
	var limiter: AudioEffect = null
	for cls in ["AudioEffectHardLimiter", "AudioEffectLimiter"]:
		if ClassDB.class_exists(cls):
			limiter = ClassDB.instantiate(cls) as AudioEffect
			break
	if limiter != null:
		AudioServer.add_bus_effect(idx, limiter)
	var lpf := AudioEffectLowPassFilter.new()
	lpf.cutoff_hz = MUSIC_LPF_OPEN_HZ
	lpf.resonance = 0.5
	AudioServer.add_bus_effect(idx, lpf)

## The Music bus low-pass, or null.
static func music_lpf() -> AudioEffectLowPassFilter:
	var idx: int = AudioServer.get_bus_index(BUS_MUSIC)
	if idx < 0:
		return null
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var effect: AudioEffect = AudioServer.get_bus_effect(idx, i)
		if effect is AudioEffectLowPassFilter:
			return effect as AudioEffectLowPassFilter
	return null
