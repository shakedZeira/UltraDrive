# tests/suites/music_toast_fake_service.gd
extends Node

## Signal-compatible stand-in for MusicService, used by test_music_toast_timing.

signal track_changed(meta: Dictionary)
signal station_changed(station_name: String, station_id: String)
signal notice(title: String, subtitle: String)
signal cover_ready(track_id: String, texture: Texture2D, accent: Color, generated: bool)

var settings: Dictionary = {"toast": true}

func playback_fraction() -> float:
	return 0.5
