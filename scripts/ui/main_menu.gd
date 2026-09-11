# scripts/ui/main_menu.gd
extends Control

func _on_play_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/test/test_track.tscn")

func _on_continue_pressed() -> void:
    if SaveManager.has_save(0):
        SceneTransition.flash_to_scene("res://scenes/test/test_track.tscn")

func _on_settings_pressed() -> void:
    # TODO: Phase 8 settings menu
    pass

func _on_quit_pressed() -> void:
    get_tree().quit()
