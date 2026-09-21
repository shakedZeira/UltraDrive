# tests/suites/test_hud_contrast.gd
extends GdUnitTestSuite

## Item 7 (HUD contrast hierarchy) gate: the FH6/GT7-style re-skin of the
## driving cluster. Asserts (a) a translucent dark backdrop Panel sits behind
## %Cluster with mouse_filter IGNORE, alpha in the 0.4-0.7 band, and its rect
## encloses the cluster (so it never wanders over the corner HUD / countdown);
## (b) the primary speed readout is near-white while the cyan accent holds a
## >=4.5:1 WCAG contrast ratio against the panel background; (c) %NavWidget
## and its labels still resolve after the re-skin.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _managed: Array = []

func before_test() -> void:
	_managed.clear()

func after_test() -> void:
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	VehicleManager.player_car = null
	VehicleManager.all_cars.clear()

func test_cluster_backdrop_exists_behind_the_cluster() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var root := runner.scene().get_node("Root") as Control
	assert_that(root).is_not_null()
	if root == null:
		return
	var backdrop := root.get_node_or_null("ClusterBackdrop")
	assert_that(backdrop).is_not_null()
	if backdrop == null:
		return
	assert_that(backdrop).is_instanceof(Panel)
	assert_that(backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var sb := backdrop.get("theme_override_styles/panel") as StyleBoxFlat
	assert_that(sb).is_not_null()
	if sb == null:
		return
	assert_that(sb.bg_color.a).is_between(0.4, 0.7)
	assert_that(sb.bg_color.r).is_less(0.15)
	var cluster := root.get_node("Cluster") as Control
	if cluster != null:
		assert_that(backdrop.get_rect().encloses(cluster.get_rect())).is_true()

func test_primary_readout_white_and_accent_contrasts_on_panel() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var root := runner.scene().get_node("Root") as Control
	if root == null:
		return
	var speed := root.get_node("Cluster/SpeedValue") as Label
	var accent := root.get_node("Cluster/SpeedUnit") as Label
	var backdrop := root.get_node("ClusterBackdrop")
	var white := speed.get_theme_color("font_color")
	assert_that(_luminance(white)).is_greater(0.75)
	var accent_col := accent.get_theme_color("font_color")
	assert_that(accent_col.b).is_greater(0.8)
	var sb := backdrop.get("theme_override_styles/panel") as StyleBoxFlat
	if sb == null:
		return
	assert_that(_contrast(accent_col, sb.bg_color)).is_greater_equal(4.5)

func test_nav_widget_still_resolves_after_reskin() -> void:
	var runner := scene_runner(HUD_SCENE)
	await runner.simulate_frames(1)
	var scene := runner.scene()
	assert_that(scene.get_node_or_null("%NavWidget")).is_not_null()
	assert_that(scene.get_node_or_null("%NavArrow")).is_not_null()
	assert_that(scene.get_node_or_null("%NavDistance")).is_not_null()
	assert_that(scene.get_node_or_null("%NavHint")).is_not_null()

static func _linear_channel(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)

static func _luminance(col: Color) -> float:
	return 0.2126 * _linear_channel(col.r) + 0.7152 * _linear_channel(col.g) + 0.0722 * _linear_channel(col.b)

static func _contrast(a: Color, b: Color) -> float:
	var hi := maxf(_luminance(a), _luminance(b))
	var lo := minf(_luminance(a), _luminance(b))
	return (hi + 0.05) / (lo + 0.05)