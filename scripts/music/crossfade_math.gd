# scripts/music/crossfade_math.gd
class_name CrossfadeMath
extends RefCounted

## Pure crossfade helpers. Equal-power curves (out = cos, in = sin) keep the
## summed power constant while two decks overlap. Edge cases carried over from
## Spotify Replica's Crossfade.volumeFor: fade <= 0 disables the fade, an
## unknown / zero length never pre-empts (the deck's `finished` is used), and a
## track shorter than two windows shrinks the window to length / 2.

const SILENCE_DB := -80.0
const MIN_AUDIBLE_DB := -60.0

static func out_gain(t: float) -> float:
	return cos(clampf(t, 0.0, 1.0) * PI * 0.5)

static func in_gain(t: float) -> float:
	return sin(clampf(t, 0.0, 1.0) * PI * 0.5)

## Linear gain -> dB, flooring at SILENCE_DB below MIN_AUDIBLE_DB.
static func gain_to_db(gain: float) -> float:
	if gain <= 0.0:
		return SILENCE_DB
	var db := linear_to_db(gain)
	return SILENCE_DB if db < MIN_AUDIBLE_DB else db

## Effective overlap window in seconds for a track of `length_s`.
static func window_for(fade_s: float, length_s: float) -> float:
	if fade_s <= 0.0 or length_s <= 0.0:
		return 0.0
	return minf(fade_s, length_s * 0.5)

## Seconds left given the deck's playback position and the time since the last
## mix (position only moves per mix block).
static func remaining(length_s: float, position_s: float, since_mix_s: float = 0.0) -> float:
	return length_s - (position_s + maxf(since_mix_s, 0.0))

## True when the next track should start now. length_s <= 0 never triggers.
static func should_start_next(length_s: float, position_s: float, since_mix_s: float, fade_s: float) -> bool:
	if length_s <= 0.0:
		return false
	var window := window_for(fade_s, length_s)
	return remaining(length_s, position_s, since_mix_s) <= window

## Advance a fade clock. Returns the new t in 0..1; len_s <= 0 completes at once.
static func advance_t(t: float, delta: float, len_s: float) -> float:
	if len_s <= 0.0:
		return 1.0
	return clampf(t + delta / len_s, 0.0, 1.0)
