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
@onready var tune_panel: VBoxContainer = %TuningTabs.get_node("Tune") as VBoxContainer
@onready var paint_panel: VBoxContainer = %TuningTabs.get_node("Paint") as VBoxContainer
@onready var ui_blip: UiBlip = $UiBlip

const MENU_BLIP_DEBOUNCE_MS: int = 80

var _last_menu_blip_ms: int = -1000

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

var _garage: Garage
var _selected_car: String = ""
var _selected_index: int = 0
var _cards: Array[Button] = []
var _profile: TuningProfile = null
var _gear_sliders: Array[HSlider] = []
var _gear_labels: Array[Label] = []
var _final_drive_slider: HSlider = null
var _final_drive_label: Label = null
var _mass_slider: HSlider = null
var _mass_label: Label = null
var _stat_line: Label = null
var _dyno_label: Label = null
var _paint_state_label: Label = null
var _swatch_buttons: Array[Button] = []

func _ready() -> void:
	_garage = Garage.new_from_save()
	select_button.pressed.connect(_on_select_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_bind_menu_blip(select_button)
	_bind_menu_blip(back_button)
	_build_rail()
	_build_tune_panel()
	_build_paint_panel()
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
		_bind_menu_blip(card)
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
	_refresh_tuning_state()
	_update_garage_info(config)
	_swap_preview(config)
	_update_cards()

## The car's tuned config for garage-tab display: applies the loaded overrides,
## falling back to the stock config when nothing is tuned.
func _display_config(base: CarConfig) -> CarConfig:
	if _profile == null or _profile.overrides.is_empty():
		return base
	var applied := _profile.applied()
	return applied if applied != null else base

## Re-renders the Garage-tab specs + stat bars from the current (tuned) config
## so a slider change is reflected as soon as the player switches tabs.
func _update_garage_info(base: CarConfig) -> void:
	if base == null:
		return
	var display := _display_config(base)
	specs_label.text = "%d Nm  •  %d kg  •  CLASS %s" % [int(display.max_torque), int(display.mass_kg), display.car_class]
	_update_stats(_compute_stats(display))

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
	CarVisuals.apply_paint(instance, CarVisuals.paint_profile_for(_selected_car, _garage.get_car_paint(_selected_car)))

func _on_select_pressed() -> void:
	if _selected_car != "":
		_garage.set_active_car(_selected_car)

func _on_back_pressed() -> void:
	SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")

## S13 --- Tune tab -----------------------------------------------------------

func _build_tune_panel() -> void:
	_gear_sliders.clear()
	_gear_labels.clear()
	var probe := _garage.get_owned_cars()
	var gear_count := 5
	if probe.size() > 0:
		var cfg := load("res://resources/cars/%s.tres" % probe[0]) as CarConfig
		if cfg != null and cfg.gear_ratios.size() > 0:
			gear_count = cfg.gear_ratios.size()
	for i in gear_count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var gear_label := Label.new()
		gear_label.text = "GEAR %d" % (i + 1)
		gear_label.custom_minimum_size = Vector2(64, 0)
		gear_label.add_theme_font_size_override("font_size", 12)
		row.add_child(gear_label)
		var slider := _new_slider()
		slider.value_changed.connect(_on_gear_slider_changed.bind(i))
		row.add_child(slider)
		var value_label := Label.new()
		value_label.text = "--"
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.add_theme_font_size_override("font_size", 12)
		row.add_child(value_label)
		tune_panel.add_child(row)
		_gear_sliders.append(slider)
		_gear_labels.append(value_label)
	_final_drive_slider = _append_row("FINAL", tune_panel)
	_final_drive_label = _row_value_label(_final_drive_slider)
	_mass_slider = _append_row("MASS", tune_panel)
	_mass_label = _row_value_label(_mass_slider)
	_final_drive_slider.value_changed.connect(_on_final_drive_slider_changed)
	_mass_slider.value_changed.connect(_on_mass_slider_changed)
	_stat_line = Label.new()
	_stat_line.text = ""
	_stat_line.add_theme_font_size_override("font_size", 13)
	_stat_line.add_theme_color_override("font_color", ACCENT)
	tune_panel.add_child(_stat_line)
	_dyno_label = Label.new()
	_dyno_label.text = "DYNO  --"
	_dyno_label.add_theme_font_size_override("font_size", 13)
	_dyno_label.add_theme_color_override("font_color", TEXT_MUTED)
	tune_panel.add_child(_dyno_label)

func _new_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.editable = false
	return slider

func _append_row(title: String, panel: VBoxContainer) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(64, 0)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var slider := _new_slider()
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "--"
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.add_theme_font_size_override("font_size", 12)
	row.add_child(value_label)
	panel.add_child(row)
	return slider

func _row_value_label(slider: HSlider) -> Label:
	var row := slider.get_parent() as HBoxContainer
	return row.get_child(2) as Label

func _on_gear_slider_changed(t: float, index: int) -> void:
	if _profile == null or index >= _gear_labels.size():
		return
	var base: float = _profile.base_config.gear_ratios[index]
	_profile.set_gear_ratio(index, base * TuningProfile.slider_to_factor(t))
	_gear_labels[index].text = "%.2f" % _profile.get_gear_ratio(index)
	_persist_tuning()

func _on_final_drive_slider_changed(t: float) -> void:
	if _profile == null:
		return
	_profile.set_final_drive(_profile.base_config.final_drive_ratio * TuningProfile.slider_to_factor(t))
	_final_drive_label.text = "%.2f" % _profile.get_final_drive()
	_persist_tuning()

func _on_mass_slider_changed(t: float) -> void:
	if _profile == null:
		return
	_profile.set_mass(_profile.base_config.mass_kg * TuningProfile.slider_to_factor(t))
	_mass_label.text = "%d kg" % int(_profile.get_mass())
	_persist_tuning()

func _persist_tuning() -> void:
	_garage.set_car_tuning(_selected_car, _profile.to_dict())
	_update_dyno()
	_update_garage_info(_profile.base_config)

## S13 --- Paint tab ----------------------------------------------------------

func _build_paint_panel() -> void:
	_swatch_buttons.clear()
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	paint_panel.add_child(grid)
	for i in CarVisuals.PAINT_SWATCHES.size():
		var swatch: Dictionary = CarVisuals.PAINT_SWATCHES[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = String(swatch["name"])
		btn.disabled = true
		var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
		img.fill(swatch["color"])
		btn.icon = ImageTexture.create_from_image(img)
		btn.connect("pressed", _on_swatch_pressed.bind(i))
		_bind_menu_blip(btn)
		grid.add_child(btn)
		_swatch_buttons.append(btn)
	_paint_state_label = Label.new()
	_paint_state_label.text = ""
	_paint_state_label.add_theme_font_size_override("font_size", 13)
	_paint_state_label.add_theme_color_override("font_color", TEXT_MUTED)
	paint_panel.add_child(_paint_state_label)

func _on_swatch_pressed(index: int) -> void:
	if _selected_car == "" or not _garage.is_car_owned(_selected_car):
		return
	var swatch: Dictionary = CarVisuals.PAINT_SWATCHES[index]
	var paint_id := String(swatch["id"])
	_garage.set_car_paint(_selected_car, paint_id)
	for i in _swatch_buttons.size():
		_swatch_buttons[i].button_pressed = (i == index)
	for child in car_visual.get_children():
		CarVisuals.apply_paint(child as Node3D, CarVisuals.paint_profile_for(_selected_car, paint_id))
	_paint_state_label.text = "PAINT  %s" % String(swatch["name"])

## S13 --- shared refresh ------------------------------------------------------

func _refresh_tuning_state() -> void:
	if _selected_car == "":
		return
	var config := load("res://resources/cars/%s.tres" % _selected_car) as CarConfig
	if config == null:
		return
	_profile = TuningProfile.new(config)
	_profile.from_dict(_garage.get_car_overrides(_selected_car))
	var can_edit := _garage.is_car_owned(_selected_car)
	for i in config.gear_ratios.size():
		if i >= _gear_sliders.size():
			break
		var factor := _profile.get_gear_ratio(i) / maxf(config.gear_ratios[i], 0.001)
		_gear_sliders[i].set_value_no_signal(TuningProfile.factor_to_slider(factor))
		_gear_labels[i].text = "%.2f" % _profile.get_gear_ratio(i)
		_gear_sliders[i].editable = can_edit
	_final_drive_slider.set_value_no_signal(TuningProfile.factor_to_slider(
		_profile.get_final_drive() / maxf(config.final_drive_ratio, 0.001)))
	_final_drive_label.text = "%.2f" % _profile.get_final_drive()
	_final_drive_slider.editable = can_edit
	_mass_slider.set_value_no_signal(TuningProfile.factor_to_slider(
		_profile.get_mass() / maxf(config.mass_kg, 0.001)))
	_mass_label.text = "%d kg" % int(_profile.get_mass())
	_mass_slider.editable = can_edit
	var paint_id := _garage.get_car_paint(_selected_car)
	for idx in _swatch_buttons.size():
		var looked_up := String(CarVisuals.PAINT_SWATCHES[idx]["id"]) == paint_id
		_swatch_buttons[idx].button_pressed = looked_up
		_swatch_buttons[idx].disabled = not can_edit
	if paint_id.is_empty():
		_paint_state_label.text = "PAINT  STOCK"
	else:
		_paint_state_label.text = "PAINT  %s" % CarVisuals.paint_color_for(paint_id).to_html(false).to_upper()
	_update_dyno()

func _update_dyno() -> void:
	var applied := _profile.applied() if _profile != null else null
	if applied == null:
		_dyno_label.text = "DYNO  --"
		_stat_line.text = ""
		return
	var hp := int(TuningProfile.peak_power_hp(applied))
	var top := int(applied.get_max_speed() * 3.6)
	var gear_summary := "1st %.2f  top %.2f" % [applied.gear_ratios[0], applied.gear_ratios[applied.gear_ratios.size() - 1]]
	_dyno_label.text = "DYNO  %d HP  •  %d Nm  •  TOP %d km/h  •  %s" % [
		hp, int(applied.max_torque), top, gear_summary]
	_stat_line.text = _tuned_stat_line(_compute_stats(applied))

func _tuned_stat_line(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	var parts := PackedStringArray()
	for stat_name in ["ACCELERATION", "SPEED", "HANDLING", "BRAKING"]:
		if stats.has(stat_name):
			parts.append("%s %d" % [
				stat_name.left(3),
				int(round(clampf(stats[stat_name], 0.0, 1.0) * 100.0)),
			])
	return "TUNED  " + "  •  ".join(parts)