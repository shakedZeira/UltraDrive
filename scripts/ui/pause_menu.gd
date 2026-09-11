# scripts/ui/pause_menu.gd
extends Control

func _on_resume_pressed() -> void:
    GameState.resume_game()
    hide()

func _on_quit_to_menu_pressed() -> void:
    GameState.resume_game()
    SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
