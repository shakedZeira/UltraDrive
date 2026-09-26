# scripts/ui/loading_screen_manager.gd
extends CanvasLayer

## Persistent loading screen that renders above SceneTransition (layer 100).

var _loading_screen: Control
var _loading_label: Label
var _loading_bar: ProgressBar
var _loading_percent_label: Label

func _ready() -> void:
	layer = 128
	process_mode = CanvasLayer.PROCESS_MODE_ALWAYS
	_create_loading_screen()
	hide()

func _create_loading_screen() -> void:
	_loading_screen = Control.new()
	_loading_screen.name = "LoadingScreen"
	_loading_screen.anchors_preset = Control.PRESET_FULL_RECT
	_loading_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_screen.visible = false
	
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.95)
	bg.anchors_preset = Control.PRESET_FULL_RECT
	_loading_screen.add_child(bg)
	
	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_CENTER
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_screen.add_child(vbox)
	
	_loading_label = Label.new()
	_loading_label.text = "Loading..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_loading_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_loading_label)
	
	_loading_bar = ProgressBar.new()
	_loading_bar.min_value = 0
	_loading_bar.max_value = 100
	_loading_bar.value = 0
	_loading_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_bar.custom_minimum_size = Vector2(400, 24)
	vbox.add_child(_loading_bar)
	
	_loading_percent_label = Label.new()
	_loading_percent_label.text = "0%"
	_loading_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_percent_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_loading_percent_label.add_theme_font_size_override("font_size", 18)
	_loading_percent_label.name = "PercentLabel"
	vbox.add_child(_loading_percent_label)
	
	add_child(_loading_screen)

func show_loading(message: String = "Loading...", percent: float = 0.0) -> void:
	_loading_screen.visible = true
	_loading_label.text = message
	_loading_bar.value = percent
	_loading_percent_label.text = "%d%%" % int(percent)

func update_loading(message: String, percent: float) -> void:
	_loading_label.text = message
	_loading_bar.value = percent
	_loading_percent_label.text = "%d%%" % int(percent)

func hide_loading() -> void:
	_loading_screen.visible = false