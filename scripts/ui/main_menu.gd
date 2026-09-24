# scripts/ui/main_menu.gd
extends Control

const MENU_BLIP_DEBOUNCE_MS: int = 80

var _last_menu_blip_ms: int = -1000

@onready var continue_button: Button = %ContinueButton
@onready var ui_blip: UiBlip = $UiBlip

func _ready() -> void:
    continue_button.disabled = not SaveManager.has_save(0)
    for child: Node in $MenuLayout.get_children():
        if child is Button:
            _bind_menu_blip(child as Button)

func _menu_blip() -> void:
    if ui_blip == null:
        return
    var now := Time.get_ticks_msec()
    if now - _last_menu_blip_ms < MENU_BLIP_DEBOUNCE_MS:
        return
    _last_menu_blip_ms = now
    ui_blip.play_blip("menu")

func _bind_menu_blip(button: Button) -> void:
    button.pressed.connect(_menu_blip)
    button.focus_entered.connect(_menu_blip)

func _on_play_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/track_select.tscn")

func _on_free_roam_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/world/open_world_root.tscn")

func _on_garage_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/garage.tscn")

func _on_continue_pressed() -> void:
    if SaveManager.has_save(0):
        SceneTransition.flash_to_scene("res://scenes/test/test_track.tscn")

func _on_settings_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/ui/settings_menu.tscn")

func _on_quit_pressed() -> void:
    get_tree().quit()
