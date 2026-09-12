# scripts/ui/main_menu.gd
extends Control

@onready var continue_button: Button = %ContinueButton

func _ready() -> void:
    continue_button.disabled = not SaveManager.has_save(0)

func _on_play_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/track_select.tscn")

func _on_garage_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/garage.tscn")

func _on_continue_pressed() -> void:
    if SaveManager.has_save(0):
        SceneTransition.flash_to_scene("res://scenes/test/test_track.tscn")

func _on_settings_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/settings_menu.tscn")

func _on_quit_pressed() -> void:
    get_tree().quit()
