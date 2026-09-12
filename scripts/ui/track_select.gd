class_name TrackSelect
extends Control

const ACCENT := Color(0.902, 0.698, 0.235)
const CARD_DARK := Color(0.075, 0.095, 0.16)
const CARD_ACTIVE := Color(0.105, 0.13, 0.21)
const TEXT_MUTED := Color(0.62, 0.66, 0.74)

@onready var track_grid: GridContainer = %TrackGrid
@onready var track_name_label: Label = %TrackNameLabel
@onready var play_button: Button = %PlayButton
@onready var back_button: Button = %BackButton

var _track_ids: Array[String] = []
var _cards: Array[Button] = []
var _selected_id: String = ""
var launch_callback: Callable = _default_launch

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_build_cards()
	if _cards.size() > 0:
		select_track(_track_ids[0])
	else:
		track_name_label.text = "NO TRACKS AVAILABLE"
		play_button.disabled = true

func _build_cards() -> void:
	for child in track_grid.get_children():
		child.queue_free()
	_cards.clear()
	_track_ids.assign(TrackRegistry.get_track_ids())
	for track_id: String in _track_ids:
		var data := TrackRegistry.get_track(track_id)
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(250, 120)
		card.connect("pressed", _on_card_pressed.bind(track_id))
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 4)
		var badge := Label.new()
		badge.text = "CLASS %s" % data.get("difficulty", "?")
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", ACCENT)
		box.add_child(badge)
		var name_lbl := Label.new()
		name_lbl.text = data.get("display_name", track_id)
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
		box.add_child(name_lbl)
		var type_lbl := Label.new()
		type_lbl.text = data.get("circuit_type", "CIRCUIT")
		type_lbl.add_theme_font_size_override("font_size", 12)
		type_lbl.add_theme_color_override("font_color", TEXT_MUTED)
		box.add_child(type_lbl)
		card.add_child(box)
		card.add_theme_stylebox_override("normal", _card_style(false))
		card.add_theme_stylebox_override("hover", _card_style(false))
		card.add_theme_stylebox_override("pressed", _card_style(true))
		card.add_theme_stylebox_override("focus", _card_style(false))
		track_grid.add_child(card)
		_cards.append(card)
	track_grid.columns = clampi(_cards.size(), 1, 2)

func _card_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_ACTIVE if active else CARD_DARK
	sb.border_color = ACCENT if active else Color(0.16, 0.20, 0.30)
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb

func get_card_count() -> int:
	return _cards.size()

func get_selected_scene_path() -> String:
	if _selected_id == "":
		return ""
	return TrackRegistry.get_scene_path(_selected_id)

func select_track(track_id: String) -> void:
	if not TrackRegistry.has_track(track_id):
		return
	_selected_id = track_id
	var data := TrackRegistry.get_track(track_id)
	track_name_label.text = "%s  •  %s" % [
		data.get("display_name", track_id).to_upper(),
		data.get("circuit_type", "CIRCUIT")]
	_update_cards()

func _update_cards() -> void:
	for i in _cards.size():
		var active := _track_ids[i] == _selected_id
		_cards[i].button_pressed = active
		_cards[i].add_theme_stylebox_override("normal", _card_style(active))
		_cards[i].add_theme_stylebox_override("pressed", _card_style(active))
		_cards[i].add_theme_stylebox_override("focus", _card_style(active))

func _on_card_pressed(track_id: String) -> void:
	if track_id != _selected_id:
		select_track(track_id)

func _on_play_pressed() -> void:
	if _selected_id == "":
		return
	launch_callback.call(TrackRegistry.get_scene_path(_selected_id))

func _on_back_pressed() -> void:
	launch_callback.call("res://scenes/ui/main_menu.tscn")

func _default_launch(scene_path: String) -> void:
	SceneTransition.flash_to_scene(scene_path)