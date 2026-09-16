# scripts/ui/pause_menu.gd
extends Control

@onready var panel: Panel = $Panel
@onready var map_overlay: Control = $MapOverlay
@onready var world_map: WorldMap = %WorldMap

func _ready() -> void:
	GameState.game_paused.connect(_on_game_paused)
	GameState.game_resumed.connect(hide)

func _on_game_paused() -> void:
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