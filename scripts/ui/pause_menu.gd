# scripts/ui/pause_menu.gd
class_name PauseMenu
extends Control

@onready var panel: Panel = $Panel
@onready var map_overlay: Control = $MapOverlay
@onready var world_map: WorldMap = %WorldMap
@onready var distance_label: Label = %DistanceLabel
@onready var top_speed_label: Label = %TopSpeedLabel
@onready var drift_time_label: Label = %DriftTimeLabel
@onready var best_lap_label: Label = %BestLapLabel

func _ready() -> void:
	GameState.game_paused.connect(_on_game_paused)
	GameState.game_resumed.connect(hide)

func _on_game_paused() -> void:
	_refresh_stats()
	show()
	panel.show()
	map_overlay.hide()

func _on_resume_pressed() -> void:
	GameState.resume_game()
	hide()

func _on_quit_to_menu_pressed() -> void:
	GameState.resume_game()
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")

func _on_map_pressed() -> void:
	world_map.refresh()
	map_overlay.show()
	panel.hide()

func _on_back_to_pause_pressed() -> void:
	map_overlay.hide()
	panel.show()

func _refresh_stats() -> void:
	var stats := GameState.session_stats
	if stats == null:
		return
	distance_label.text = "DISTANCE  %.2f km" % stats.get_distance_km()
	top_speed_label.text = "TOP SPEED  %d km/h" % roundi(stats.get_top_speed_kmh())
	drift_time_label.text = "DRIFT TIME  %s" % _format_time(stats.get_drift_time())
	best_lap_label.text = "BEST LAP  %s" % _format_time(stats.get_best_lap())

func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "-:--"
	return "%d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]