# tests/suites/test_garage_brands.gd
extends GdUnitTestSuite

## Acceptance gate for the garage brand grouping: the CarBrands registry
## (table completeness, emblem files on disk, derivation fallbacks, ordered
## partitioning), the grouped garage rail (one section per non-empty brand,
## emblems loaded, no new focusable nodes) and the owned-index card remap that
## grouping makes necessary. Every test that touches user:// slot 0 snapshots
## it in before_test and restores it in after_test (mirrors test_garage_tuning)
## so the real save stays untouched.

const BRAND_DIR := "res://assets/ui/brands/"
const HOUSE_EMBLEM := "res://assets/ui/brands/house_ultradrive.svg"

var _slot_snapshot: Dictionary = {}

func before_test() -> void:
	_slot_snapshot = SaveManager.load_game(0)

func after_test() -> void:
	var slot := 0
	var path = SaveManager.SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
	if _slot_snapshot.is_empty() and not SaveManager.has_save(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	else:
		SaveManager.save_game(slot, _slot_snapshot)

## The live owned roster, loaded exactly as GarageUI does.
func _owned_configs() -> Array[CarConfig]:
	var configs: Array[CarConfig] = []
	for car_id: String in Garage.new_from_save().get_owned_cars():
		var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
		if config != null:
			configs.append(config)
	return configs

func test_brand_table_is_complete() -> void:
	var order: Array = CarBrands.CATEGORY_ORDER
	assert_that(order.size()).is_equal(CarBrands.BRANDS.size())
	assert_that(String(order[0])).is_equal(CarBrands.HOUSE_ID)
	var seen: Dictionary = {}
	for brand_id: String in order:
		assert_that(CarBrands.BRANDS.has(brand_id)).is_true()
		assert_that(seen.has(brand_id)).is_false()
		seen[brand_id] = true
		var emblem := CarBrands.emblem_path(brand_id)
		assert_that(emblem.begins_with(BRAND_DIR)).is_true()
		assert_that(FileAccess.file_exists(emblem)).is_true()
	assert_that(CarBrands.brand_ids().size()).is_equal(order.size())
	# House first, every other brand strictly alphabetical by display name.
	var previous := ""
	for i in range(1, order.size()):
		var brand_name := CarBrands.display_name(order[i])
		assert_that(brand_name > previous).is_true()
		previous = brand_name

func test_resolve_brand_id_falls_back_to_house() -> void:
	var car := CarConfig.new()
	car.car_name = "Comet"
	car.brand = ""
	car.brand_display_name = ""
	car.visual_path = ""
	# An unsaved resource has an empty resource_path, so only car_name is seen.
	assert_that(CarBrands.resolve_brand_id(car)).is_equal(CarBrands.HOUSE_ID)
	assert_that(CarBrands.brand_display_name(car)).is_equal(CarBrands.HOUSE_NAME)
	car.brand = "nissan"
	assert_that(CarBrands.resolve_brand_id(car)).is_equal("nissan")
	car.brand = "NISSAN"
	assert_that(CarBrands.resolve_brand_id(car)).is_equal("nissan")
	car.brand = "vw"
	assert_that(CarBrands.resolve_brand_id(car)).is_equal("volkswagen")
	# An unrecognized non-empty brand falls through instead of hard-failing.
	car.brand = "not_a_real_brand"
	assert_that(CarBrands.resolve_brand_id(car)).is_equal(CarBrands.HOUSE_ID)
	car.brand_display_name = "Custom Works"
	assert_that(CarBrands.brand_display_name(car)).is_equal("Custom Works")
	assert_that(CarBrands.resolve_brand_id(null)).is_equal(CarBrands.HOUSE_ID)
	assert_that(CarBrands.display_name("no_such_brand")).is_equal(CarBrands.HOUSE_NAME)
	assert_that(CarBrands.emblem_path("no_such_brand")).is_equal(HOUSE_EMBLEM)

func test_resolve_brand_id_derives_from_resource_path() -> void:
	var starter := load("res://resources/cars/starter_car.tres") as CarConfig
	assert_that(starter).is_not_null()
	if starter == null:
		return
	# The live configs carry no brand field, so the path token rule must apply.
	assert_that(starter.brand).is_equal("")
	assert_that(CarBrands.resolve_brand_id(starter)).is_equal(CarBrands.HOUSE_ID)
	var house_ids: Array = [
		"starter_car", "muscle_car", "rally_hatch",
		"cc0_sedan_sports", "cc0_hatchback_sports", "cc0_race",
	]
	for car_id: String in house_ids:
		var config := load("res://resources/cars/%s.tres" % car_id) as CarConfig
		assert_that(config).is_not_null()
		if config != null:
			assert_that(CarBrands.resolve_brand_id(config)).is_equal(CarBrands.HOUSE_ID)
	var gtr := load("res://resources/cars/nissan_gt_r35_2017.tres") as CarConfig
	assert_that(gtr).is_not_null()
	if gtr != null:
		assert_that(CarBrands.resolve_brand_id(gtr)).is_equal("nissan")

func test_group_owned_is_ordered_and_partitioned() -> void:
	assert_that(CarBrands.group_owned([])).is_equal([])
	var configs := _owned_configs()
	assert_that(configs.size()).is_greater(0)
	var groups := CarBrands.group_owned(configs)
	assert_that(groups.size()).is_greater(0)
	var order: Array = CarBrands.CATEGORY_ORDER
	var last_position := -1
	var total := 0
	for group: Dictionary in groups:
		var brand_id := String(group["brand_id"])
		var position := order.find(brand_id)
		assert_that(position > last_position).is_true()
		last_position = position
		assert_that(String(group["display_name"])).is_equal(CarBrands.display_name(brand_id))
		assert_that(String(group["emblem_path"])).is_equal(CarBrands.emblem_path(brand_id))
		var group_cars: Array = group["cars"]
		assert_that(group_cars.size()).is_greater(0)
		total += group_cars.size()
	assert_that(total).is_equal(configs.size())
	# Every owned car lands in exactly one group.
	var seen_ids: Dictionary = {}
	for group: Dictionary in groups:
		var group_cars: Array = group["cars"]
		for car: CarConfig in group_cars:
			assert_that(seen_ids.has(car.get_instance_id())).is_false()
			seen_ids[car.get_instance_id()] = true
	assert_that(seen_ids.size()).is_equal(configs.size())

func test_garage_ui_builds_one_section_per_brand() -> void:
	var expected := CarBrands.group_owned(_owned_configs())
	assert_that(expected.size()).is_greater(0)
	var runner := scene_runner("res://scenes/ui/garage.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as Control
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var rail := scene.get_node("%CarRail") as VBoxContainer
	assert_that(rail).is_not_null()
	if rail == null:
		return
	assert_that(rail.get_child_count()).is_equal(expected.size())
	for i in expected.size():
		var group: Dictionary = expected[i]
		var section := rail.get_child(i) as VBoxContainer
		assert_that(section).is_not_null()
		if section == null:
			continue
		var header := section.get_child(0) as HBoxContainer
		assert_that(header).is_not_null()
		if header != null:
			var emblem := header.get_child(0) as TextureRect
			assert_that(emblem).is_not_null()
			if emblem != null:
				assert_that(emblem.texture).is_not_null()
			var label := header.get_child(1) as Label
			assert_that(label).is_not_null()
			if label != null:
				assert_that(label.text).is_equal(String(group["display_name"]))
		var row := section.get_child(1) as HBoxContainer
		assert_that(row).is_not_null()
		if row != null:
			var group_cars: Array = group["cars"]
			assert_that(row.get_child_count()).is_equal(group_cars.size())
	# Tab-order guard: headers and cards must never be focusable.
	var focusable := 0
	for node: Node in rail.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			focusable += 1
	assert_that(focusable).is_equal(0)

func test_garage_card_mapping_survives_grouping() -> void:
	var owned: Array[String] = Garage.new_from_save().get_owned_cars()
	var runner := scene_runner("res://scenes/ui/garage.tscn")
	await runner.simulate_frames(2)
	var scene := runner.scene() as Control
	assert_that(scene).is_not_null()
	if scene == null:
		return
	var rail := scene.get_node("%CarRail") as VBoxContainer
	assert_that(rail).is_not_null()
	if rail == null:
		return
	var cards := rail.find_children("*", "Button", true, false)
	assert_that(cards.size()).is_equal(owned.size())
	# The owned_index meta must be a permutation of 0..owned.size()-1, i.e. the
	# grouped DOM order still covers every owned car exactly once.
	var metas: Array = []
	for node: Node in cards:
		var meta_card := node as Button
		if meta_card == null:
			continue
		metas.append(int(meta_card.get_meta("owned_index", -1)))
	metas.sort()
	var expected: Array = []
	for i in owned.size():
		expected.append(i)
	assert_that(metas).is_equal(expected)
	# Pressing a card selects the car its owned_index points at, not the card's
	# DOM position, and the highlight follows the same mapping.
	var pressed_card: Button = null
	var target := -1
	for node: Node in cards:
		var card := node as Button
		if card == null:
			continue
		var owned_index := int(card.get_meta("owned_index", -1))
		if owned_index > 0:
			pressed_card = card
			target = owned_index
			card.pressed.emit()
			break
	assert_that(pressed_card).is_not_null()
	assert_that(target).is_greater(0)
	if pressed_card == null or target < 0:
		return
	# _show_car side effects: the car name label shows the selected car and the
	# pressed card is the one highlighted.
	var config := load("res://resources/cars/%s.tres" % owned[target]) as CarConfig
	var name_label := scene.get_node("%CarNameLabel") as Label
	assert_that(name_label).is_not_null()
	if name_label != null and config != null:
		assert_that(name_label.text).is_equal(config.car_name.to_upper())
	assert_that(pressed_card.button_pressed).is_true()

## Additive real-logo gate: every registry emblem - the 12 manufacturer PNGs
## plus the house SVG - must resolve to a file that loads as a texture with
## sane dimensions through garage_ui's plate/aspect pipeline. The scene tests
## above only exercise the brands the test save happens to own (house + the
## seeded GT-R), so this walks the complete final set explicitly.
func test_every_registry_emblem_loads_as_a_texture() -> void:
	var runner := scene_runner("res://scenes/ui/garage.tscn")
	await runner.simulate_frames(2)
	var garage: Variant = runner.scene()
	assert_that(garage).is_not_null()
	if garage == null:
		return
	var checked := 0
	for brand_id in CarBrands.BRANDS:
		var path := CarBrands.emblem_path(String(brand_id))
		assert_that(FileAccess.file_exists(path)).is_true()
		var texture: Variant = garage._emblem_texture(path)
		assert_that(texture).is_not_null()
		if texture == null:
			continue
		assert_that(texture.get_width()).is_greater(0)
		assert_that(texture.get_height()).is_greater(0)
		checked += 1
	assert_that(checked).is_equal(CarBrands.BRANDS.size())
	# Behaviour pin: the all-black 2020 Nissan emblem is below the luminance
	# threshold, so it must come back PLATED - strictly wider than the raw
	# file (trimmed ink box + neutral pad) rather than a passthrough.
	var nissan_path := CarBrands.emblem_path("nissan")
	var plated: Variant = garage._emblem_texture(nissan_path)
	var raw := load(nissan_path) as Texture2D
	assert_that(raw).is_not_null()
	if raw != null and plated != null:
		assert_that(plated.get_width()).is_greater(raw.get_width())
