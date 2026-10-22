# tests/suites/test_speed_trap_hud.gd
extends GdUnitTestSuite

## Free-roam speed-trap HUD gate: the per-trap personal-best rules, the pure
## flash/banner timing envelopes, the radius-only crossing detector and the
## presentation shell that binds to it.
##
## Everything here is headless-deterministic: the timing assertions call the
## PURE statics on SpeedTrapHUD, every crossing is driven by an explicit
## simulate_step() (never a frame loop), and no test waits on wall-clock time.
## The only scene work is the scene_runner group-wiring test, deferred one frame
## to let the HUD's call_deferred("_wire") land.
##
## Ordering note: the pure layers (A/B) run first on purpose -- gdUnit aborts a
## suite at its first failure, so a cheap deterministic failure must not be
## hidden behind a later scene test.

const HUD_SCENE := "res://scenes/ui/speed_trap_hud.tscn"
## The slot this suite writes. Snapshot/restored around every test so a real
## playthrough save is never clobbered.
const SLOT := 0
## The injected stub trap id / the real published trap used by the claim test.
const TRAP_ID := "stub_trap"
const TRAP_ID_REAL := "speedtrap_0"
const TRAP_RADIUS := 18.0
const TRAP_TARGET_KMH := 120.0

var _slot_backup: Dictionary = {}
var _slot_existed := false
var _race_was_active := false
var _managed: Array = []
var _emitted: Array = []

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------

func before_test() -> void:
	_managed.clear()
	_emitted.clear()
	_race_was_active = RaceManager.is_race_active
	RaceManager.is_race_active = false
	_slot_existed = SaveManager.has_save(SLOT)
	_slot_backup = SaveManager.load_game(SLOT)
	# Start from an empty best map: SpeedTrapCrossing loads slot 0 in _ready, so
	# a real playthrough's best must not leak into the assertions. after_test
	# restores the whole slot, so the seed is temporary.
	var seed := SpeedTrapRecords.new()
	seed.save_to_slot(SLOT)

func after_test() -> void:
	RaceManager.is_race_active = _race_was_active
	for node in _managed:
		if is_instance_valid(node):
			node.free()
	_managed.clear()
	if _slot_existed:
		SaveManager.save_game(SLOT, _slot_backup)
		return
	# The slot did not exist before this suite touched it, so remove the file
	# rather than leaving a blank slot behind (mirrors SaveManager._slot_path).
	DirAccess.remove_absolute("user://saves/slot_%d.json" % (SLOT + 1))

func _defs() -> Array[RoadDef]:
	return CorridorPlanner.plan(CorridorPlanner.MASTER_SEED, Callable(), {})

## Minimal stand-in for VehiclePhysics: the crossing only reads global_position
## plus a km/h speed, and must not care which shipped speed source reports it.
class StubCar extends Node3D:
	var current_speed_kmh: float = 0.0

func _stub_trap() -> Dictionary:
	return {
		"id": TRAP_ID,
		"kind": Collectibles.KIND_SPEED_TRAP,
		"position": Vector3.ZERO,
		"extra": {"claim_radius": TRAP_RADIUS, "target_kmh": TRAP_TARGET_KMH},
	}

func _stub_traps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_stub_trap())
	return out

func _new_car(pos: Vector3, speed_kmh: float) -> StubCar:
	var car := StubCar.new()
	car.name = "StubCar"
	add_child(car)
	car.global_position = pos
	car.current_speed_kmh = speed_kmh
	_managed.append(car)
	return car

## A crossing in the tree (so _ready runs and the group/pause wiring is real)
## with the live physics tick OFF, so every assertion here drives
## simulate_step() deliberately instead of racing gdUnit's own frame pumps.
func _make_crossing() -> SpeedTrapCrossing:
	var crossing := SpeedTrapCrossing.new()
	crossing.save_on_pause = false
	add_child(crossing)
	crossing.set_physics_process(false)
	_managed.append(crossing)
	return crossing

func _record_emit(trap_id: String, speed_kmh: float, best_kmh: float, is_new_best: bool) -> void:
	_emitted.append({"id": trap_id, "speed": speed_kmh, "best": best_kmh, "new": is_new_best})

## Walks the car fully outside the re-arm radius and back inside, i.e. one
## clean second pass at the same gate.
func _reenter(crossing: SpeedTrapCrossing, car: StubCar) -> void:
	car.global_position = Vector3(TRAP_RADIUS * SpeedTrapCrossing.HYSTERESIS + 1.0, 0.0, 0.0)
	crossing.simulate_step()
	car.global_position = Vector3.ZERO

# ---------------------------------------------------------------------------
# A. Pure record rules (SpeedTrapRecords).
# ---------------------------------------------------------------------------

func test_is_new_best_is_strict_and_monotonic() -> void:
	assert_that(SpeedTrapRecords.is_new_best(0.0, 0.0)).is_false()
	assert_that(SpeedTrapRecords.is_new_best(0.0, 1.0)).is_true()
	assert_that(SpeedTrapRecords.is_new_best(150.0, 150.0)).is_false()
	assert_that(SpeedTrapRecords.is_new_best(150.0, 149.9)).is_false()
	assert_that(SpeedTrapRecords.is_new_best(150.0, 150.1)).is_true()

func test_merged_best_never_decreases() -> void:
	assert_that(SpeedTrapRecords.merged_best(150.0, 120.0)).is_equal(150.0)
	assert_that(SpeedTrapRecords.merged_best(150.0, 160.0)).is_equal(160.0)
	# A fold over a descending+ascending series is the running max.
	var series: Array[float] = [120.0, 150.0, 90.0, 175.0, 160.0, 40.0]
	var running := 0.0
	var max_seen := 0.0
	for value: float in series:
		running = SpeedTrapRecords.merged_best(running, value)
		max_seen = maxf(max_seen, value)
	assert_that(running).is_equal(max_seen)
	assert_that(running).is_equal(175.0)

func test_record_tracks_monotonic_best_and_reports_improvement() -> void:
	var records := SpeedTrapRecords.new()
	assert_that(records.best_of(TRAP_ID)).is_equal(0.0)
	assert_that(records.record(TRAP_ID, 140.0)).is_true()
	assert_that(records.best_of(TRAP_ID)).is_equal(140.0)
	# A slower pass is not an improvement and never lowers the best.
	assert_that(records.record(TRAP_ID, 130.0)).is_false()
	assert_that(records.best_of(TRAP_ID)).is_equal(140.0)
	assert_that(records.record(TRAP_ID, 151.0)).is_true()
	assert_that(records.best_of(TRAP_ID)).is_equal(151.0)
	# An untouched trap stays at 0.0.
	assert_that(records.best_of("never_crossed")).is_equal(0.0)

func test_banner_text_covers_new_best_best_and_no_best() -> void:
	assert_that(SpeedTrapRecords.banner_text(143.0, 151.0, false)) \
		.is_equal("SPEED TRAP — 143 km/h · BEST 151 km/h")
	assert_that(SpeedTrapRecords.banner_text(151.0, 151.0, true)) \
		.is_equal("SPEED TRAP — 151 km/h · NEW BEST!")
	# With no recorded best there is no dangling "BEST 0 km/h".
	assert_that(SpeedTrapRecords.banner_text(90.0, 0.0, false)) \
		.is_equal("SPEED TRAP — 90 km/h")
	# No string ever carries a hyphen, so a "--" separator or a negative number
	# can never sneak in.
	var samples: Array[String] = [
		SpeedTrapRecords.banner_text(143.0, 151.0, false),
		SpeedTrapRecords.banner_text(151.0, 151.0, true),
		SpeedTrapRecords.banner_text(90.0, 0.0, false),
		SpeedTrapRecords.banner_text(0.0, 0.0, false),
	]
	for text: String in samples:
		assert_that(text.contains("-")).is_false()
		assert_that(text.begins_with("SPEED TRAP")).is_true()

# ---------------------------------------------------------------------------
# B. Pure timing envelopes (SpeedTrapHUD statics, no scene).
# ---------------------------------------------------------------------------

func test_flash_alpha_envelope_is_bounded_and_peaks_at_rise() -> void:
	assert_that(SpeedTrapHUD.flash_alpha(-1.0)).is_equal(0.0)
	assert_that(SpeedTrapHUD.flash_alpha(0.0)).is_equal(0.0)
	assert_float(SpeedTrapHUD.flash_alpha(SpeedTrapHUD.FLASH_RISE)) \
		.is_equal_approx(SpeedTrapHUD.FLASH_PEAK_ALPHA, 0.001)
	assert_that(SpeedTrapHUD.flash_alpha(SpeedTrapHUD.flash_total())).is_equal(0.0)
	assert_that(SpeedTrapHUD.flash_alpha(999.0)).is_equal(0.0)
	# Bounded everywhere across the whole envelope.
	var t := 0.0
	while t <= SpeedTrapHUD.flash_total():
		assert_float(SpeedTrapHUD.flash_alpha(t)) \
			.is_between(0.0, SpeedTrapHUD.FLASH_PEAK_ALPHA)
		t += 0.01

func test_banner_alpha_envelope_rises_holds_falls() -> void:
	assert_that(SpeedTrapHUD.banner_alpha(0.0)).is_equal(0.0)
	assert_float(SpeedTrapHUD.banner_alpha(SpeedTrapHUD.BANNER_RISE)) \
		.is_equal_approx(1.0, 0.001)
	assert_float(SpeedTrapHUD.banner_alpha(SpeedTrapHUD.BANNER_RISE + SpeedTrapHUD.BANNER_HOLD)) \
		.is_equal_approx(1.0, 0.001)
	assert_that(SpeedTrapHUD.banner_alpha(SpeedTrapHUD.banner_total())).is_equal(0.0)
	assert_that(SpeedTrapHUD.banner_alpha(SpeedTrapHUD.banner_total() + 1.0)).is_equal(0.0)
	# Rise is monotone non-decreasing.
	var prev := -1.0
	var t := 0.0
	while t <= SpeedTrapHUD.BANNER_RISE:
		var rising := SpeedTrapHUD.banner_alpha(t)
		assert_float(rising).is_greater_equal(prev)
		prev = rising
		t += 0.01
	# Fall is monotone non-increasing.
	prev = 2.0
	t = SpeedTrapHUD.BANNER_RISE + SpeedTrapHUD.BANNER_HOLD
	while t <= SpeedTrapHUD.banner_total():
		var falling := SpeedTrapHUD.banner_alpha(t)
		assert_float(falling).is_less_equal(prev)
		prev = falling
		t += 0.01

func test_banner_is_longer_than_the_flash() -> void:
	# Guards against a future inversion: a flash that outlasts the banner would
	# blind the very text it announces.
	assert_float(SpeedTrapHUD.banner_total()).is_greater(SpeedTrapHUD.flash_total())

# ---------------------------------------------------------------------------
# C. Crossing detection (SpeedTrapCrossing + StubCar, no HUD).
# ---------------------------------------------------------------------------

func test_crossing_fires_once_per_pass_with_hysteresis() -> void:
	var car := _new_car(Vector3.ZERO, 120.0)
	var crossing := _make_crossing()
	crossing.set_traps(_stub_traps())
	crossing.player_path = NodePath("../" + car.name)
	crossing.speed_trap_crossed.connect(_record_emit)

	# Entering the 18 m radius fires once.
	assert_that(crossing.simulate_step()).is_equal(1)
	# Still inside: latched, so no flicker and no second emit.
	assert_that(crossing.simulate_step()).is_equal(0)
	# Just past the re-arm radius (18 * 1.6 + 1 = 29.8 m): disarm, no emit.
	car.global_position = Vector3(TRAP_RADIUS * SpeedTrapCrossing.HYSTERESIS + 1.0, 0.0, 0.0)
	assert_that(crossing.simulate_step()).is_equal(0)
	# Back inside: re-armed, fires again.
	car.global_position = Vector3.ZERO
	assert_that(crossing.simulate_step()).is_equal(1)
	# Exactly two emits over the whole pass.
	assert_that(_emitted.size()).is_equal(2)

func test_crossing_signal_carries_speed_best_and_new_best_flag() -> void:
	var car := _new_car(Vector3.ZERO, 120.0)
	var crossing := _make_crossing()
	crossing.set_traps(_stub_traps())
	crossing.player_path = NodePath("../" + car.name)
	crossing.speed_trap_crossed.connect(_record_emit)

	assert_that(crossing.simulate_step()).is_equal(1)
	assert_that(_emitted[0]).is_equal({"id": TRAP_ID, "speed": 120.0, "best": 120.0, "new": true})

	# A slower second pass is not a new best, and the best published is the
	# stored one (not the slower crossing).
	_reenter(crossing, car)
	car.current_speed_kmh = 100.0
	assert_that(crossing.simulate_step()).is_equal(1)
	assert_that(_emitted[1]).is_equal({"id": TRAP_ID, "speed": 100.0, "best": 120.0, "new": false})

	# A faster third pass is a new best.
	_reenter(crossing, car)
	car.current_speed_kmh = 130.0
	assert_that(crossing.simulate_step()).is_equal(1)
	assert_that(_emitted[2]).is_equal({"id": TRAP_ID, "speed": 130.0, "best": 130.0, "new": true})
	assert_that(crossing.records().best_of(TRAP_ID)).is_equal(130.0)

func test_crossing_is_suppressed_while_a_race_is_active() -> void:
	var car := _new_car(Vector3.ZERO, 150.0)
	var crossing := _make_crossing()
	crossing.set_traps(_stub_traps())
	crossing.player_path = NodePath("../" + car.name)
	crossing.speed_trap_crossed.connect(_record_emit)

	RaceManager.is_race_active = true
	assert_that(crossing.simulate_step()).is_equal(0)
	assert_that(_emitted).is_empty()
	assert_that(crossing.records().best_of(TRAP_ID)).is_equal(0.0)

	# Free roam again: the suppressed pass never latched, so the same position
	# now fires and records.
	RaceManager.is_race_active = false
	assert_that(crossing.simulate_step()).is_equal(1)
	assert_that(crossing.records().best_of(TRAP_ID)).is_equal(150.0)

func test_crossing_does_not_require_the_money_speed_target() -> void:
	var trap := _stub_trap()
	# The money rule refuses a crawl over the line...
	assert_that(Collectibles.can_claim(trap, Vector3.ZERO, 5.0)).is_false()
	# ...but the crossing rule is radius-only and still fires, and records.
	var car := _new_car(Vector3.ZERO, 5.0)
	var crossing := _make_crossing()
	crossing.set_traps(_stub_traps())
	crossing.player_path = NodePath("../" + car.name)
	crossing.speed_trap_crossed.connect(_record_emit)
	assert_that(crossing.simulate_step()).is_equal(1)
	assert_that(_emitted.size()).is_equal(1)
	assert_that(crossing.records().best_of(TRAP_ID)).is_equal(5.0)

func test_already_claimed_trap_still_records_a_best() -> void:
	# Bank speedtrap_0 through the SHIPPED claim ledger first: the trap now reads
	# as claimed, so the money path can never pay it again.
	var ledger := Collectibles.new()
	assert_that(ledger.claim(Collectibles.place_data(_defs()), TRAP_ID_REAL)).is_greater(0)
	ledger.save_to_slot(SLOT)

	var trap := POIRegistry.get_poi(TRAP_ID_REAL)
	var at := trap["position"] as Vector3
	var car := _new_car(at, 145.0)
	var crossing := _make_crossing()
	crossing.player_path = NodePath("../" + car.name)
	crossing.speed_trap_crossed.connect(_record_emit)

	# The crossing is independent of the claim ledger: it still fires...
	assert_that(crossing.simulate_step()).is_greater_equal(1)
	var found := false
	for entry: Dictionary in _emitted:
		if str(entry.get("id", "")) == TRAP_ID_REAL:
			found = true
	assert_that(found).is_true()
	# ...and it still records a personal best for the already-claimed trap.
	assert_that(crossing.records().best_of(TRAP_ID_REAL)).is_equal(145.0)

# ---------------------------------------------------------------------------
# D. Wiring / no-leak (scene runner).
# ---------------------------------------------------------------------------

func test_hud_binds_by_group_and_plays_on_crossing() -> void:
	var runner := scene_runner(HUD_SCENE)
	var hud := runner.scene() as SpeedTrapHUD
	assert_that(hud).is_not_null()
	if hud == null:
		return
	# The crossing must be in the tree before the HUD's deferred _wire flushes.
	var crossing := SpeedTrapCrossing.new()
	crossing.save_on_pause = false
	crossing.set_physics_process(false)
	runner.scene().add_child(crossing)
	_managed.append(crossing)
	await runner.simulate_frames(2)
	assert_that(hud.is_wired()).is_true()

	crossing.speed_trap_crossed.emit(TRAP_ID, 143.0, 151.0, false)
	assert_that(hud.is_playing()).is_true()
	assert_that(hud.advance(0.01)).is_true()

func test_advance_finishes_and_hides_both_overlays() -> void:
	var runner := scene_runner(HUD_SCENE)
	var hud := runner.scene() as SpeedTrapHUD
	assert_that(hud).is_not_null()
	if hud == null:
		return
	hud.play(143.0, 151.0, false)
	assert_that(hud.is_playing()).is_true()

	var guard := 0
	while hud.advance(0.05):
		guard += 1
		if guard > 1000:
			break
	assert_that(hud.is_playing()).is_false()
	assert_that(hud.elapsed()).is_equal(0.0)
	assert_that((hud.get_node("Flash") as ColorRect).visible).is_false()
	assert_that((hud.get_node("Banner") as Panel).visible).is_false()
	# Idle means no per-frame cost.
	assert_that(hud.is_processing()).is_false()

func test_play_does_not_stack_nodes() -> void:
	var runner := scene_runner(HUD_SCENE)
	var hud := runner.scene() as SpeedTrapHUD
	assert_that(hud).is_not_null()
	if hud == null:
		return
	# The scene is one reused Flash + one reused Banner.
	var children := hud.get_child_count()
	assert_that(children).is_equal(2)
	hud.play(100.0, 100.0, false)
	hud.play(120.0, 120.0, true)
	hud.play(140.0, 140.0, true)
	assert_that(hud.get_child_count()).is_equal(children)
	# The third play restarted the one-shot from t = 0.
	assert_that(hud.elapsed()).is_equal(0.0)
	assert_float(SpeedTrapHUD.flash_alpha(hud.elapsed())).is_equal(0.0)
	assert_that(hud.is_playing()).is_true()

func test_hud_ignores_play_while_a_race_is_active() -> void:
	var runner := scene_runner(HUD_SCENE)
	var hud := runner.scene() as SpeedTrapHUD
	assert_that(hud).is_not_null()
	if hud == null:
		return
	RaceManager.is_race_active = true
	hud.play(143.0, 151.0, false)
	assert_that(hud.is_playing()).is_false()
	assert_that((hud.get_node("Flash") as ColorRect).visible).is_false()
	assert_that((hud.get_node("Banner") as Panel).visible).is_false()
	assert_that(hud.is_processing()).is_false()
