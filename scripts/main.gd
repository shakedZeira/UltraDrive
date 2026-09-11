extends Node3D

func _ready() -> void:
    print("[UltraDrive] Main scene loaded – transitioning to main menu")
    SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")