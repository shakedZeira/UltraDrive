# scripts/music/music_policy.gd
class_name MusicPolicy
extends RefCounted

## What the music should do in each scene context. Pure data: every row of the
## plan's context table is a unit test. v1 ships FreeRoam music ONLY - every
## other context (and NONE, the default for scenes without a host) fades out and
## PAUSES (position kept) so nothing can blast music by accident.

enum Context { NONE, FREE_ROAM, RACE, GARAGE, MENU }

const LPF_OPEN_HZ := 20500.0
const PAUSE_LPF_HZ := 1200.0
const PAUSE_DUCK_DB := -8.0
const PHOTO_DUCK_DB := -4.0
const FADE_OUT_S := 1.2
const FADE_IN_S := 1.0
## Fade for user-driven pause / resume.
const USER_FADE_S := 0.4

## flags: { paused: bool (pause menu / tree paused), photo: bool }
## -> { play: bool, duck_db: float, lpf_hz: float, fade_s: float }
static func policy_for(context: int, settings: Dictionary, flags: Dictionary = {}) -> Dictionary:
	var allowed: bool = bool(settings.get("enabled", true)) and not bool(settings.get("streamer_safe", false))
	var out := {"play": false, "duck_db": 0.0, "lpf_hz": LPF_OPEN_HZ, "fade_s": FADE_OUT_S}
	if context != Context.FREE_ROAM or not allowed:
		return out
	out["play"] = true
	out["fade_s"] = FADE_IN_S
	if bool(flags.get("paused", false)):
		out["duck_db"] = PAUSE_DUCK_DB
		out["lpf_hz"] = PAUSE_LPF_HZ
	elif bool(flags.get("photo", false)):
		out["duck_db"] = PHOTO_DUCK_DB
	return out

static func context_name(context: int) -> String:
	match context:
		Context.FREE_ROAM:
			return "FREE_ROAM"
		Context.RACE:
			return "RACE"
		Context.GARAGE:
			return "GARAGE"
		Context.MENU:
			return "MENU"
	return "NONE"
