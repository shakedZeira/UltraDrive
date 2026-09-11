# scripts/ui/settings_menu.gd
extends Control

## Settings menu: video quality, audio, controls.

@onready var quality_option: OptionButton = %QualityOption
@onready var volume_slider: HSlider = %VolumeSlider

const QUALITY_PRESETS := {
	0: {"msaa": 0, "ssao": false, "glow": false},
	1: {"msaa": 2, "ssao": false, "glow": true},
	2: {"msaa": 4, "ssao": true, "glow": true},
}

func _ready() -> void:
	quality_option.add_item("Low", 0)
	quality_option.add_item("Medium", 1)
	quality_option.add_item("High", 2)
	quality_option.select(1)
	quality_option.item_selected.connect(_on_quality_selected)
	volume_slider.value_changed.connect(_on_volume_changed)

func _on_quality_selected(index: int) -> void:
	var preset: Dictionary = QUALITY_PRESETS.get(index, QUALITY_PRESETS[1])
	var env: WorldEnvironment = get_viewport().world_environment
	if env and env.environment:
		env.environment.ssao_enabled = preset["ssao"]
		env.environment.glow_enabled = preset["glow"]

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_back_pressed() -> void:
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
