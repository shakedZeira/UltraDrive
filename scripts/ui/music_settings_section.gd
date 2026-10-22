# scripts/ui/music_settings_section.gd
class_name MusicSettingsSection
extends VBoxContainer

## The "Music" block of the settings menu (FreeRoam radio): enable toggle, music
## volume, music folder (native folder dialog), rescan + status line, crossfade,
## now-playing toast, crash ducking, shuffle and streamer-safe. Built in code so
## the existing settings menu script stays untouched; the scene just contains one
## instance of this node. Everything reads / writes through the MusicService
## autoload (slot-0 save, debounced); a missing service leaves the block inert.

var _service: Node = null
var _enabled: CheckBox
var _volume: HSlider
var _folder_label: Label
var _status: Label
var _warning: Label
var _crossfade: HSlider
var _crossfade_value: Label
var _toast: CheckBox
var _duck: CheckBox
var _shuffle: CheckBox
var _streamer: CheckBox
var _dialog: FileDialog
var _building: bool = false

## Warning text for a candidate folder ("" when fine).
static func folder_warning(path: String) -> String:
	if MusicSettings.is_inside_project(path):
		return "That folder is inside the game project (it would be imported and bundled). Pick a folder outside it."
	return ""

func _ready() -> void:
	_service = get_node_or_null("/root/MusicService")
	_build()
	if _service == null:
		return
	_service.connect("state_changed", _refresh)
	_service.connect("library_progress", _on_progress)
	# Show the library counts even before the first FreeRoam session.
	if bool(_service.get("auto_start")) and _service.has_method("ensure_library"):
		_service.call("ensure_library")
	_refresh()

func _build() -> void:
	add_theme_constant_override("separation", 6)
	var header := Label.new()
	header.text = "Music (FreeRoam radio)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(header)
	_enabled = _add_check("Play music in FreeRoam", "enabled")
	_volume = _add_slider("Music volume", 0.0, 1.0, 0.05)
	_volume.value_changed.connect(func(v: float) -> void:
		if not _building and _service != null:
			_service.call("set_volume", v))
	# Folder row.
	var row := HBoxContainer.new()
	add_child(row)
	_folder_label = Label.new()
	_folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_folder_label.clip_text = true
	row.add_child(_folder_label)
	var choose := Button.new()
	choose.text = "Choose Folder..."
	choose.pressed.connect(_on_choose_pressed)
	row.add_child(choose)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.pressed.connect(func() -> void:
		if _service != null:
			_service.call("rescan"))
	row.add_child(rescan)
	_status = Label.new()
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)
	_warning = Label.new()
	_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.visible = false
	add_child(_warning)
	# Crossfade.
	var xf_row := HBoxContainer.new()
	add_child(xf_row)
	var xf_label := Label.new()
	xf_label.text = "Crossfade"
	xf_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xf_row.add_child(xf_label)
	_crossfade = HSlider.new()
	_crossfade.min_value = MusicSettings.CROSSFADE_MIN
	_crossfade.max_value = MusicSettings.CROSSFADE_MAX
	_crossfade.step = 0.5
	_crossfade.custom_minimum_size = Vector2(180, 0)
	_crossfade.value_changed.connect(_on_crossfade_changed)
	xf_row.add_child(_crossfade)
	_crossfade_value = Label.new()
	_crossfade_value.custom_minimum_size = Vector2(44, 0)
	xf_row.add_child(_crossfade_value)
	_toast = _add_check("Now-playing toast", "toast")
	_duck = _add_check("Duck music on crashes / speed traps", "duck")
	_shuffle = _add_check("Shuffle", "shuffle")
	_streamer = _add_check("Streamer-safe (music off)", "streamer_safe")
	# Blip on focus, like the other rows, when the host menu offers it.
	var host := owner if owner != null else get_parent()
	if host != null and host.has_method("_bind_menu_blip"):
		for c in [_enabled, _volume, choose, rescan, _crossfade, _toast, _duck, _shuffle, _streamer]:
			host.call("_bind_menu_blip", c)

func _add_check(text: String, key: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.toggled.connect(func(pressed: bool) -> void:
		if not _building and _service != null:
			_service.call("set_setting", key, pressed))
	add_child(box)
	return box

func _add_slider(text: String, lo: float, hi: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size = Vector2(180, 0)
	row.add_child(slider)
	return slider

func _refresh() -> void:
	if _service == null or _enabled == null:
		return
	_building = true
	var s: Dictionary = _service.get("settings")
	_enabled.button_pressed = bool(s.get("enabled", true))
	_volume.value = float(s.get("volume", 0.7))
	_crossfade.value = float(s.get("crossfade_s", 2.5))
	_crossfade_value.text = "%.1f s" % float(s.get("crossfade_s", 2.5))
	_toast.button_pressed = bool(s.get("toast", true))
	_duck.button_pressed = bool(s.get("duck", true))
	_shuffle.button_pressed = bool(s.get("shuffle", true))
	_streamer.button_pressed = bool(s.get("streamer_safe", false))
	_folder_label.text = MusicSettings.effective_folder(s)
	_status.text = String(_service.call("scan_status_text"))
	var warn := folder_warning(MusicSettings.effective_folder(s))
	_warning.text = warn
	_warning.visible = not warn.is_empty()
	_building = false

func _on_progress(_done: int, _total: int) -> void:
	if _service != null and _status != null:
		_status.text = String(_service.call("scan_status_text"))

func _on_crossfade_changed(value: float) -> void:
	_crossfade_value.text = "%.1f s" % value
	if not _building and _service != null:
		_service.call("set_setting", "crossfade_s", value)

func _on_choose_pressed() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.title = "Choose your music folder"
		_dialog.use_native_dialog = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
		_dialog.dir_selected.connect(_on_dir_selected)
		add_child(_dialog)
	if _service != null:
		var s: Dictionary = _service.get("settings")
		var folder := MusicSettings.effective_folder(s)
		if DirAccess.dir_exists_absolute(folder):
			_dialog.current_dir = folder
	_dialog.popup_centered_ratio(0.6)

func _on_dir_selected(dir: String) -> void:
	var warn := folder_warning(dir)
	if not warn.is_empty():
		_warning.text = warn
		_warning.visible = true
		return
	if _service != null:
		_service.call("set_folder", dir)
	_refresh()
