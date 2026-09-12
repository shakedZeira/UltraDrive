extends Control

const CAR_ORIENT := Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)), Vector3.ZERO)
const ACCENT := Color(0.902, 0.698, 0.235)
const TEXT_MUTED := Color(0.62, 0.66, 0.74)
const BAR_BG := Color(0.075, 0.095, 0.16)
const BAR_FILL := Color(0.902, 0.698, 0.235)
const CARD_DARK := Color(0.075, 0.095, 0.16)
const CARD_ACTIVE := Color(0.105, 0.13, 0.21)

@onready var car_name_label: Label = %CarNameLabel
@onready var class_badge_label: Label = %ClassBadgeLabel
@onready var class_circle_label: Label = %ClassCircleLabel
@onready var stats_box: VBoxContainer = %StatsBox
@onready var specs_label: Label = %SpecsLabel
@onready var select_button: Button = %SelectButton
@onready var back_button: Button = %BackButton
@onready var car_rail: HBoxContainer = %CarRail
@onready var turntable: Node3D = %Turntable
@onready var car_visual: Node3D = %CarVisual

var _garage: Garage
var _selected_car: String = ""
var _selected_index: int = 0
var _cards: Array[Button] = []

func _ready() -> void:
	_garage = Garage.new_from_save()
	select_button.pressed.connect(_on_select_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_build_rail()
	if _garage.get_owned_cars().size() > 0:
		_show_car(0)
	else:
		car_name_label.text = "NO CARS OWNED"
		select_button.disabled = true

func _process(delta: float) -> void:
	turntable.rotation.y += 0.4 * delta

func _build_rail() -> void:
	for child in car_rail.get_children():
		child.queue_free()
	_cards.clear()
	var owned := _garage.get_owned_cars()
	for i in owned.size():
		var config := load("res://resources/cars/%s.tres" % owned[i]) as CarConfig
		if config == null:
			continue
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(150, 62)
		card.connect("pressed", _on_card_pressed.bind(i))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var letter := Label.new()
		letter.text = config.car_class
		letter.add_theme_font_size_override("font_size", 20)
		letter.add_theme_color_override("font_color", ACCENT)
		box.add_child(letter)
		var name_lbl := Label.new()
		name_lbl.text = config.car_name
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
		box.add_child(name_lbl)
		card.add_child(box)
		card.add_theme_stylebox_override("normal", _card_style(false))
		card.add_theme_stylebox_override("hover", _card_style(false))
		card.add_theme_stylebox_override("pressed", _card_style(true))
		card.add_theme_stylebox_override("focus", _card_style(false))
		car_rail.add_child(card)
		_cards.append(card)

func _card_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_ACTIVE if active else CARD_DARK
	sb.border_color = ACCENT if active else Color(0.16, 0.20, 0.30)
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	return sb

func _update_cards() -> void:
	for i in _cards.size():
		var active := (i == _selected_index)
		_cards[i].button_pressed = active
		_cards[i].add_theme_stylebox_override("normal", _card_style(active))
		_cards[i].add_theme_stylebox_override("pressed", _card_style(active))
		_cards[i].add_theme_stylebox_override("focus", _card_style(active))

func _on_card_pressed(index: int) -> void:
	if index != _selected_index:
		_show_car(index)

func _show_car(index: int) -> void:
	var owned := _garage.get_owned_cars()
	if index < 0 or index >= owned.size():
		return
	_selected_index = index
	_selected_car = owned[index]
	var config := load("res://resources/cars/%s.tres" % _selected_car) as CarConfig
	if config == null:
		return
	car_name_label.text = config.car_name.to_upper()
	class_badge_label.text = "CLASS %s" % config.car_class
	class_circle_label.text = config.car_class
	specs_label.text = "%d Nm  •  %d kg  •  CLASS %s" % [int(config.max_torque), int(config.mass_kg), config.car_class]
	_update_stats(_compute_stats(config))
	_swap_preview(config)
	_update_cards()

func _compute_stats(config: CarConfig) -> Dictionary:
	if config == null:
		return {}
	var power_ratio: float = config.max_torque * config.peak_rpm / maxf(config.mass_kg, 0.01)
	var grip: float = config.tire_D * (1.0 + 0.08 * (config.tire_B - 9.0))
	var speed: float = config.get_max_speed()
	var handling: float = clampf(
		0.5 * grip
		+ 0.3 * (config.max_steer_angle / 38.0)
		+ 0.2 * clampf((config.spring_rate / maxf(config.mass_kg, 0.01)) / 40.0, 0.0, 1.0),
		0.0, 1.0)
	var acceleration: float = clampf(power_ratio / 2000.0, 0.0, 1.0)
	var launch: float = clampf(
		0.5 * (config.max_torque * config.gear_ratios[0] * config.final_drive_ratio / maxf(config.mass_kg, 0.01)) / 6.0
		+ 0.5 * grip, 0.0, 1.0)
	var braking: float = clampf(config.max_brake_torque / maxf(config.mass_kg, 0.01) / 2.3, 0.0, 1.0)
	var offroad: float = clampf(
		0.3 * clampf(config.suspension_travel / 0.14, 0.0, 1.0)
		+ 0.35 * grip
		+ 0.15 * (1.0 / (1.0 + config.mass_kg / 1200.0))
		+ 0.2 * clampf(config.redline_rpm / 8200.0, 0.0, 1.0),
		0.0, 1.0)
	return {
		"SPEED": speed / 70.0,
		"HANDLING": handling,
		"ACCELERATION": acceleration,
		"LAUNCH": launch,
		"BRAKING": braking,
		"OFFROAD": offroad,
	}

func _update_stats(stats: Dictionary) -> void:
	for child in stats_box.get_children():
		stats_box.remove_child(child)
		child.queue_free()
	for stat_name: String in stats:
		var score: float = clampf(stats[stat_name], 0.0, 1.0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		lbl.text = stat_name
		lbl.custom_minimum_size = Vector2(150, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", TEXT_MUTED)
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 10.0
		bar.step = 1.0
		bar.value = clampi(int(round(score * 10.0)), 0, 10)
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg := StyleBoxFlat.new()
		bg.bg_color = BAR_BG
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_FILL
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		stats_box.add_child(row)

func _swap_preview(config: CarConfig) -> void:
	for child in car_visual.get_children():
		car_visual.remove_child(child)
		child.queue_free()
	if config == null or config.visual_path.is_empty():
		return
	var visual := load(config.visual_path) as PackedScene
	if visual == null:
		return
	var instance: Node3D = visual.instantiate()
	instance.transform = CAR_ORIENT
	car_visual.add_child(instance)

func _on_select_pressed() -> void:
	if _selected_car != "":
		_garage.set_active_car(_selected_car)

func _on_back_pressed() -> void:
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")