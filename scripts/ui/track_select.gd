class_name TrackSelect
extends Control

## Race menu: pick a CIRCUIT on a region-framed world map, then drive its
## fictional layout.
##
## Map tiers (see TrackMap): ISRAEL is the default framed region, drawn as a
## hand-authored vector Levant silhouette; the ALL CIRCUITS overview shows the
## CC0 equirectangular SVG raster with every pin, and each continent region
## frames one small, legible set. Every pin maps (many-to-one) onto one of the
## four shipped layouts in TrackRegistry.tracks.
##
## Selection is ONE state shared by the map pins and the card list: clicking a
## pin and pressing a card both call select_pin(). The card list is the
## deterministic controller/keyboard path (cards are FOCUS_ALL), so a circuit is
## never mouse-only.
##
## The map itself is zoomable/pannable (wheel, the %MapControls cluster, the
## +/-/0 keys, gamepad shoulders) and the view resets on a region switch.
##
## Race semantics are untouched: _on_play_pressed() still does
## RaceManager.queue_race(laps_default) -> launch_callback(scene_path).

const ACCENT := Color(0.902, 0.698, 0.235)
const CARD_DARK := Color(0.075, 0.095, 0.16)
const CARD_ACTIVE := Color(0.105, 0.13, 0.21)
const TEXT_MUTED := Color(0.62, 0.66, 0.74)

@onready var track_grid: GridContainer = %TrackGrid
@onready var track_name_label: Label = %TrackNameLabel
@onready var meta_label: Label = %MetaLabel
@onready var laps_label: Label = %LapsLabel
@onready var best_lap_label: Label = %BestLapLabel
@onready var region_tabs: Container = %RegionTabs
@onready var track_map: TrackMap = %TrackMap
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_reset_button: Button = %ZoomResetButton
@onready var layout_preview: TrackLayoutPreview = %LayoutPreview
@onready var preview_caption: Label = %PreviewCaption
@onready var field_summary_label: Label = %FieldSummaryLabel
@onready var rivals_box: VBoxContainer = %RivalsBox
@onready var play_button: Button = %PlayButton
@onready var back_button: Button = %BackButton
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

## Framing region only — presentation state, per-instance, never persisted.
var region: String = TrackRegistry.DEFAULT_REGION
var _pin_ids: Array[String] = []
var _cards: Array[Button] = []
var _region_tabs: Array[Button] = []
var _region_tab_ids: Array[String] = []
var _selected_pin_id: String = ""
var launch_callback: Callable = _default_launch

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_bind_menu_blip(play_button)
	_bind_menu_blip(back_button)
	_build_region_tabs()
	track_map.region = region
	_update_region_tabs()
	track_map.pin_clicked.connect(_on_pin_clicked)
	zoom_in_button.pressed.connect(_on_zoom_in)
	zoom_out_button.pressed.connect(_on_zoom_out)
	zoom_reset_button.pressed.connect(_on_zoom_reset)
	_bind_menu_blip(zoom_in_button)
	_bind_menu_blip(zoom_out_button)
	_bind_menu_blip(zoom_reset_button)
	_build_cards()
	if _cards.size() > 0:
		select_pin(_pin_ids[0])
		# The card list is the deterministic focus path. The initial
		# programmatic focus can leave a menu-blip timestamp behind, which would
		# debounce the very next real blip inside the 80 ms window — clear it so
		# the first user blip (and any test spy) always fires.
		_cards[0].grab_focus()
		_last_menu_blip_ms = -1000
	else:
		track_name_label.text = "NO CIRCUITS AVAILABLE"
		meta_label.text = ""
		laps_label.text = ""
		best_lap_label.text = ""
		_clear_detail_panel()
		play_button.disabled = true

func _build_cards() -> void:
	for child in track_grid.get_children():
		child.queue_free()
	_cards.clear()
	# One card per pin that BELONGS to the region (6 in Israel, 38 in the
	# ALL CIRCUITS overview) — the same set the map draws and hit-tests, so the
	# cards and the pins can never disagree.
	_pin_ids = track_map.visible_pin_ids()
	for pin_id: String in _pin_ids:
		var pin := TrackRegistry.get_pin(pin_id)
		var layout := TrackRegistry.get_track(TrackRegistry.track_for_pin(pin_id))
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_ALL
		card.custom_minimum_size = Vector2(0, 92)
		card.connect("pressed", _on_card_pressed.bind(pin_id))
		_bind_menu_blip(card)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 3)
		var badge := Label.new()
		badge.text = "CLASS %s" % str(layout.get("difficulty", "?"))
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", ACCENT)
		box.add_child(badge)
		var name_lbl := Label.new()
		name_lbl.text = str(pin.get("label", pin_id))
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
		box.add_child(name_lbl)
		var type_lbl := Label.new()
		type_lbl.text = str(layout.get("circuit_type", "CIRCUIT"))
		type_lbl.add_theme_font_size_override("font_size", 11)
		type_lbl.add_theme_color_override("font_color", TEXT_MUTED)
		box.add_child(type_lbl)
		card.add_child(box)
		card.add_theme_stylebox_override("normal", _card_style(false))
		card.add_theme_stylebox_override("hover", _card_style(false))
		card.add_theme_stylebox_override("pressed", _card_style(true))
		card.add_theme_stylebox_override("focus", _card_style(false))
		track_grid.add_child(card)
		_cards.append(card)

func _card_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_ACTIVE if active else CARD_DARK
	sb.border_color = ACCENT if active else Color(0.16, 0.20, 0.30)
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb

## Compact variant of _card_style() for the region tab row (built in code, so no
## new scene sub-resource is needed).
func _tab_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_ACTIVE if active else CARD_DARK
	sb.border_color = ACCENT if active else Color(0.16, 0.20, 0.30)
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

# --- region tab row ----------------------------------------------------------

## One toggle per region id, in TrackRegistry.get_region_ids() order (the
## ALL CIRCUITS overview first, ISRAEL second). Mirrors _build_cards(): the row
## is rebuilt from the registry, never hand-listed, so a new region only needs a
## registry entry.
func _build_region_tabs() -> void:
	for child in region_tabs.get_children():
		region_tabs.remove_child(child)
		child.queue_free()
	_region_tabs.clear()
	_region_tab_ids.clear()
	for region_id: Variant in TrackRegistry.get_region_ids():
		var id := str(region_id)
		var tab := Button.new()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_ALL
		tab.text = TrackRegistry.region_label(id)
		tab.add_theme_font_size_override("font_size", 12)
		tab.add_theme_color_override("font_color", Color(0.80, 0.83, 0.90))
		tab.add_theme_stylebox_override("normal", _tab_style(false))
		tab.add_theme_stylebox_override("hover", _tab_style(false))
		tab.add_theme_stylebox_override("pressed", _tab_style(true))
		tab.add_theme_stylebox_override("focus", _tab_style(false))
		tab.pressed.connect(_on_region_tab_pressed.bind(id))
		_bind_menu_blip(tab)
		region_tabs.add_child(tab)
		_region_tabs.append(tab)
		_region_tab_ids.append(id)
	_update_region_tabs()

## Highlight exactly the active region's tab (a toggle can be re-pressed, so the
## visual state is always re-derived from `region`, never trusted to the toggle).
func _update_region_tabs() -> void:
	for i in _region_tabs.size():
		var active := _region_tab_ids[i] == region
		_region_tabs[i].button_pressed = active
		_region_tabs[i].add_theme_stylebox_override("normal", _tab_style(active))
		_region_tabs[i].add_theme_stylebox_override("pressed", _tab_style(active))
		_region_tabs[i].add_theme_stylebox_override("focus", _tab_style(active))

func _on_region_tab_pressed(region_id: String) -> void:
	if region_id == region:
		# Pressing the active tab would otherwise toggle it off; re-sync instead.
		_update_region_tabs()
		return
	set_region(region_id)

# --- map zoom ----------------------------------------------------------------

func _on_zoom_in() -> void:
	track_map.zoom_by(TrackMap.ZOOM_STEP, track_map.size * 0.5)

func _on_zoom_out() -> void:
	track_map.zoom_by(1.0 / TrackMap.ZOOM_STEP, track_map.size * 0.5)

func _on_zoom_reset() -> void:
	track_map.reset_view()

## Zoom keyboard/gamepad shortcuts. Deliberately NOT the arrow keys: the cards
## are FOCUS_ALL and %CardScroll follows focus, so arrows belong to card
## navigation. Deliberately not `_unhandled_key_input`, because that never sees
## joypad events and the menu is pad-playable.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
				_on_zoom_in()
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_on_zoom_out()
				get_viewport().set_input_as_handled()
			KEY_0, KEY_KP_0:
				_on_zoom_reset()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return
		match pad.button_index:
			JOY_BUTTON_RIGHT_SHOULDER:
				_on_zoom_in()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_LEFT_SHOULDER:
				_on_zoom_out()
				get_viewport().set_input_as_handled()

func get_card_count() -> int:
	return _cards.size()

func get_selected_pin_id() -> String:
	return _selected_pin_id

## The LAYOUT (TrackRegistry.tracks) id the selection drives, "" when nothing.
func get_selected_track_id() -> String:
	if _selected_pin_id == "":
		return ""
	return TrackRegistry.track_for_pin(_selected_pin_id)

func get_selected_scene_path() -> String:
	var track_id := get_selected_track_id()
	if track_id == "":
		return ""
	return TrackRegistry.get_scene_path(track_id)

## Primary selection entry point: select a circuit pin. Keeps the selection
## visible — if the current region does not frame the pin, the region that does
## (the pin's own `region` label) is adopted first, never "selected but hidden".
func select_pin(pin_id: String) -> void:
	if not TrackRegistry.has_pin(pin_id):
		return
	var pin := TrackRegistry.get_pin(pin_id)
	if not _pin_ids.has(pin_id):
		_apply_region(str(pin.get("region", region)))
	_selected_pin_id = pin_id
	track_map.selected_pin_id = pin_id
	_update_pin_panel(pin)
	_update_cards()

## Compatibility wrapper (existing tests/callers): select the first pin that
## drives this layout.
func select_track(track_id: String) -> void:
	var ids := TrackRegistry.pins_for_track(track_id)
	if ids.is_empty():
		return
	select_pin(str(ids[0]))

## Switch the framed region (and its backdrop tier); keeps the selection visible.
func set_region(region_id: String) -> void:
	if not TrackRegistry.has_region(region_id):
		return
	if region_id == region:
		return
	_apply_region(region_id)
	if _cards.is_empty():
		_selected_pin_id = ""
		track_map.selected_pin_id = ""
		track_name_label.text = "NO CIRCUITS AVAILABLE"
		meta_label.text = ""
		laps_label.text = ""
		best_lap_label.text = ""
		_clear_detail_panel()
		play_button.disabled = true
		return
	# Keep the selection visible: reuse it when the new framing still contains
	# it, otherwise fall back to the first circuit of the region.
	if _pin_ids.has(_selected_pin_id):
		select_pin(_selected_pin_id)
	else:
		select_pin(_pin_ids[0])

## Framing + backdrop + card-list swap, WITHOUT touching the selection. Both
## select_pin() and set_region() own the selection and call this to avoid each
## other recursively (a select->set_region->select loop that flips regions).
func _apply_region(region_id: String) -> void:
	region = region_id
	track_map.region = region_id
	# A region switch rebases the framing box, so the zoom/pan goes back to the
	# plain fit. (track_map.region already resets; this also covers a repeat call
	# with the same id, where the setter early-returns.)
	track_map.reset_view()
	_update_region_tabs()
	_build_cards()
	play_button.disabled = _cards.is_empty()

func _update_pin_panel(pin: Dictionary) -> void:
	track_name_label.text = str(pin.get("label", "")).to_upper()
	var track_id := TrackRegistry.track_for_pin(_selected_pin_id)
	var layout := TrackRegistry.get_track(track_id)
	var parts: Array[String] = []
	parts.append("CLASS %s" % str(layout.get("difficulty", "?")))
	parts.append(str(layout.get("circuit_type", "CIRCUIT")))
	parts.append("LAYOUT: %s" % str(layout.get("display_name", track_id)).to_upper())
	var meta := "  •  ".join(parts)
	var host := str(pin.get("host", ""))
	if host != "":
		meta = "%s  •  HOST: %s" % [meta, host.to_upper()]
	meta_label.text = meta
	laps_label.text = "%d LAPS" % int(layout.get("laps_default", 3))
	best_lap_label.text = "BEST (LAYOUT): %s" % _best_lap_text(track_id)
	play_button.text = "START RACE"
	_refresh_preview(track_id)
	_refresh_field(track_id)

## Layout-shape preview for the selected LAYOUT (baked centerline; degrades to a
## "layout map unavailable" caption when no data exists).
func _refresh_preview(track_id: String) -> void:
	layout_preview.set_layout(track_id)
	preview_caption.text = "LAYOUT PREVIEW" if layout_preview.has_layout() else "LAYOUT MAP UNAVAILABLE"

## GT7-style event field block: AI difficulty + opponent count from GameState,
## and — ONLY when the layout publishes a rival centerline — one row per grid
## slot. Rival PHYSICS uses the player's config (race_manager.gd); only the grid
## VISUALS vary, so the summary labels the block GRID VISUALS rather than
## promising distinct machines. Read-only mirror of RaceManager/GameState.
func _refresh_field(track_id: String) -> void:
	for child in rivals_box.get_children():
		rivals_box.remove_child(child)
		child.queue_free()
	var count := GameState.clamp_opponents(GameState.opponents)
	var anchor := GameState.normalize_difficulty(GameState.ai_difficulty)
	var summary := "DIFFICULTY: %s  •  OPPONENTS: %d" % [anchor.to_upper(), count]
	if count <= 0:
		field_summary_label.text = summary
		rivals_box.add_child(_make_field_row("AI FIELD: SOLO PRACTICE"))
		return
	if not TrackLayoutSource.has_rival_centerline(track_id):
		field_summary_label.text = summary
		rivals_box.add_child(_make_field_row("AI FIELD: NONE ON THIS LAYOUT"))
		return
	field_summary_label.text = "%s  •  GRID VISUALS" % summary
	for i in count:
		# Deliberate read-only mirror of the exact ladder configure_default_rivals()
		# uses — duplicating _TIER_SPREAD in UI code is a guaranteed drift bug.
		var tier: String = RaceManager._tier_for_slot(anchor, i)
		var visual := CarVisuals.rival_visual_for(i)
		var car_id := str(visual.get("car_id", ""))
		rivals_box.add_child(_make_field_row(_rival_row_text(i, car_id, tier)))

## One passive row in %RivalsBox: a Label, never a button/focusable, so the menu
## binds no new blips (test_audio_feel_layers asserts the play blip count).
func _make_field_row(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", TEXT_MUTED)
	return lbl

## "1. Striker  •  Expert" — resolves the rival's grid-visual .tres display name
## (falling back to the raw id when the resource is missing).
func _rival_row_text(slot: int, car_id: String, tier: String) -> String:
	var display := car_id
	if not car_id.is_empty():
		var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
		if config != null and not config.car_name.is_empty():
			display = config.car_name
	return "%d. %s  •  %s" % [slot + 1, display, tier]

## Empty the layout preview + field rows (a region with no circuits at all).
func _clear_detail_panel() -> void:
	layout_preview.set_layout("")
	preview_caption.text = "LAYOUT PREVIEW"
	field_summary_label.text = ""
	for child in rivals_box.get_children():
		rivals_box.remove_child(child)
		child.queue_free()

## Read-only best lap for a LAYOUT (records key per layout, not per circuit —
## race_ui._resolve_track_id() resolves by scene path). Shared across every pin
## that drives the same layout, which is the documented, intentional behaviour.
func _best_lap_text(track_id: String) -> String:
	if track_id == "" or SaveManager == null:
		return "—"
	var records := BestLapRecords.new()
	if not records.load_from_slot(BestLapRecords.DEFAULT_SLOT):
		return "—"
	var best := 0.0
	var prefix := "%s|" % track_id
	for key: Variant in records.keys():
		var key_str := str(key)
		if not key_str.begins_with(prefix):
			continue
		var parts := key_str.split("|")
		if parts.size() != 2:
			continue
		var seconds := records.get_record(parts[0], parts[1])
		if seconds > 0.0 and (best <= 0.0 or seconds < best):
			best = seconds
	if best <= 0.0:
		return "—"
	return _format_lap(best)

func _format_lap(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes) * 60.0
	return "%d:%06.3f" % [minutes, rest]

func _update_cards() -> void:
	for i in _cards.size():
		var active := _pin_ids[i] == _selected_pin_id
		_cards[i].button_pressed = active
		_cards[i].add_theme_stylebox_override("normal", _card_style(active))
		_cards[i].add_theme_stylebox_override("pressed", _card_style(active))
		_cards[i].add_theme_stylebox_override("focus", _card_style(active))

func _on_card_pressed(pin_id: String) -> void:
	if pin_id != _selected_pin_id:
		select_pin(pin_id)

func _on_pin_clicked(pin_id: String) -> void:
	select_pin(pin_id)

func _on_play_pressed() -> void:
	var track_id := get_selected_track_id()
	if track_id == "":
		return
	var scene_path := TrackRegistry.get_scene_path(track_id)
	var laps := int(TrackRegistry.get_track(track_id).get("laps_default", 3))
	RaceManager.queue_race(laps)
	launch_callback.call(scene_path)

func _on_back_pressed() -> void:
	launch_callback.call("res://scenes/ui/main_menu.tscn")

func _default_launch(scene_path: String) -> void:
	SceneTransition.flash_to_scene(scene_path)
