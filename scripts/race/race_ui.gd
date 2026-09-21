# scripts/race/race_ui.gd
class_name RaceUI
extends CanvasLayer

## In-race HUD: drives the Forza-style gauge cluster (tach/speed/gear), the
## start-gate countdown overlay ("3...2...1...GO!"), position/lap/lap-time
## readouts, and the race results overlay (position, total time, best lap,
## stats rows) with its Next Race / Return to Free Roam exits.

const FREE_ROAM_SCENE := "res://scenes/world/open_world_root.tscn"

## Position -> award points (1st 1000 .. 4th 250): economy stub for item 11,
## exported here so a future reward loop can read it without touching the HUD.
const POSITION_POINTS: Array[int] = [1000, 750, 500, 250]

const GOLD_TITLE := Color(0.949, 0.741, 0.167)
const NEUTRAL_TITLE := Color(0.96, 0.98, 1.0)

@onready var cluster: Tachometer = %Cluster
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel
@onready var countdown_overlay: Control = %CountdownOverlay
@onready var banner: Label = %Banner
@onready var flare: Panel = %Flare
@onready var results_overlay: Control = %ResultsOverlay
@onready var results_title: Label = %ResultsTitle
@onready var results_position: Label = %ResultsPosition
@onready var results_total: Label = %ResultsTotal
@onready var results_best_lap: Label = %ResultsBestLap
@onready var results_points: Label = %ResultsPoints
@onready var results_stats_rows: VBoxContainer = %ResultsStatsRows
@onready var next_race_button: Button = %NextRaceButton
@onready var return_free_roam_button: Button = %ReturnFreeRoamButton
@onready var confetti: ResultsConfetti = %ResultsConfetti
@onready var nav_widget: Control = %NavWidget
@onready var nav_arrow: Label = %NavArrow
@onready var nav_distance: Label = %NavDistance
@onready var nav_hint: Label = %NavHint

## Scene-navigation seam (mirrors TrackSelect): tests stub this to capture the
## launched path without actually swapping scenes.
var launch_callback: Callable = _default_launch

var _pending_laps: int = 0
var _race_over: bool = false
var _rewards_banked: bool = false
var _best_lap: float = 0.0
var _tracked_counter: LapCounter = null
var _countdown_audio: CountdownAudio = null
var _last_countdown_phase: String = ""
var _stats: SessionStats = GameState.session_stats
var _last_tick_speed_kmh: float = 0.0
var _nav_road_source: Object = null
var _brake_line: BrakeLine = null

func _ready() -> void:
	_pending_laps = RaceManager.consume_pending_race()
	RaceManager.race_finished.connect(_on_race_finished)
	_countdown_audio = CountdownAudio.new()
	_countdown_audio.name = "CountdownAudio"
	add_child(_countdown_audio)
	next_race_button.pressed.connect(_on_next_race)
	return_free_roam_button.pressed.connect(_on_return_free_roam)
	_resolve_nav_source()

func _process(delta: float) -> void:
	if _pending_laps <= 0:
		_pending_laps = RaceManager.consume_pending_race()
	if _pending_laps > 0:
		var laps := _pending_laps
		_pending_laps = 0
		RaceManager.start_race(VehicleManager.get_all_cars(), laps)
	_drive_countdown(delta)
	_resolve_nav_source()
	var car := VehicleManager.get_player_car()
	if car == null:
		return
	_refresh_lap_tracking(car)

	var info := car.get_drive_info()
	var speed_kmh := float(info["speed_kmh"])
	_stats.tick(delta, speed_kmh, _g_from_speed_delta(delta, speed_kmh), _is_drifting(info))
	cluster.set_rpm(float(info["rpm"]))
	cluster.set_gear(int(info["gear"]))
	cluster.set_speed_kmh(float(info["speed_kmh"]))
	var cfg := car.config
	if cfg != null:
		cluster.set_engine_range(cfg.idle_rpm, cfg.redline_rpm)
		cluster.set_car_class(cfg.car_class)
	_refresh_nav_assist(car)
	if _race_over:
		return
	position_label.text = _position_text(car)
	var lap_counter := RaceManager.get_lap_counter(car)
	lap_label.text = "LAP %d" % (lap_counter.get_current_lap() if lap_counter else 1)
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)

func _drive_countdown(delta: float) -> void:
	if countdown_overlay == null:
		return
	var countdown := RaceManager.get_countdown()
	var active := RaceManager.is_race_active and not _race_over and countdown.controls_locked()
	if not active:
		countdown_overlay.visible = false
		_last_countdown_phase = ""
		return
	var phase := countdown.advance(delta)
	if phase != _last_countdown_phase and _countdown_audio != null:
		_countdown_audio.play_phase(phase)
	_last_countdown_phase = phase
	countdown_overlay.visible = true
	banner.text = _banner_text(phase)
	_pulse_flare(phase)

func _banner_text(phase: String) -> String:
	return "GO!" if phase == "GO" else phase

func _pulse_flare(phase: String) -> void:
	if flare == null:
		return
	if phase == "GO":
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		flare.modulate = Color(1.0, 0.85, 0.2, 0.35 + 0.4 * pulse)
		flare.scale = Vector2.ONE * (1.0 + 0.15 * pulse)
	else:
		flare.modulate = Color(1.0, 0.85, 0.2, 0.22)
		flare.scale = Vector2.ONE

func _on_race_finished(standings: Array) -> void:
	_race_over = true
	if standings.is_empty():
		return
	var winner: VehiclePhysics = standings[0]
	var winner_counter := RaceManager.get_lap_counter(winner)
	var winner_total := winner_counter.get_total_time() if winner_counter else 0.0
	position_label.text = "FINISH  %.2fs" % winner_total
	lap_label.text = "RACE TIME %.2fs" % RaceManager.get_race_time()

	var car := VehicleManager.get_player_car()
	var position := 0
	var total := 0.0
	if car != null:
		var index: int = standings.find(car)
		if index != -1:
			position = index + 1
			var counter := RaceManager.get_lap_counter(car)
			total = counter.get_total_time() if counter else winner_total
	if position <= 0:
		position = 1
		total = winner_total
	var rows: Array[Dictionary] = [
		{"label": "DISTANCE", "value": "%.2f km" % _stats.get_distance_km()},
		{"label": "TOP SPEED", "value": "%d km/h" % roundi(_stats.get_top_speed_kmh())},
		{"label": "DRIFT TIME", "value": _format_time(_stats.get_drift_time())},
	]
	show_result(position, total, _best_lap, rows)
	if not _rewards_banked:
		_rewards_banked = true
		_bank_race_rewards(position)

## Item 11 economy: banks the persistent wallet deposit + career XP for a race
## finish. Runs at most once per race lifecycle.
func _bank_race_rewards(position: int) -> void:
	Money.wallet_add(points_for_position(position))
	CareerProfile.grant_xp(CareerProfile.race_position_xp(position))

## Results-card entry point. Fed by standings + per-lap data today; item 3 can
## append its own rows through extra_rows ([{label, value}, ...]) without a
## signature change.
func show_result(position: int, total_time: float, best_lap: float, extra_rows: Array[Dictionary] = []) -> void:
	var safe := maxi(position, 1)
	results_position.text = "P%d" % safe
	results_title.text = "1ST PLACE!" if safe == 1 else "RACE FINISH"
	results_total.text = "TOTAL TIME  %s" % _format_time(total_time)
	results_best_lap.text = "BEST LAP  %s" % _format_time(best_lap)
	results_points.text = "POSITION POINTS  +%d" % points_for_position(safe)
	_rebuild_stats_rows(extra_rows)
	results_title.add_theme_color_override("font_color", GOLD_TITLE if safe == 1 else NEUTRAL_TITLE)
	results_overlay.visible = true
	if safe == 1:
		confetti.burst()
	else:
		confetti.reset()

func _rebuild_stats_rows(rows: Array[Dictionary]) -> void:
	for child in results_stats_rows.get_children():
		child.queue_free()
	for row in rows:
		var row_label := Label.new()
		row_label.text = str(row.get("label", "")) + "    " + str(row.get("value", ""))
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row_label.add_theme_font_size_override("font_size", 18)
		row_label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
		results_stats_rows.add_child(row_label)

func _on_next_race() -> void:
	_race_over = false
	_rewards_banked = false
	results_overlay.visible = false
	confetti.reset()
	RaceManager.request_race(RaceManager.total_laps if RaceManager.total_laps > 0 else 3)

func _on_return_free_roam() -> void:
	_race_over = false
	_rewards_banked = false
	results_overlay.visible = false
	confetti.reset()
	launch_callback.call(FREE_ROAM_SCENE)

func _default_launch(scene_path: String) -> void:
	SceneTransition.flash_to_scene(scene_path)

func _refresh_lap_tracking(car: VehiclePhysics) -> void:
	var counter := RaceManager.get_lap_counter(car)
	if counter == null or counter == _tracked_counter:
		return
	if is_instance_valid(_tracked_counter) and _tracked_counter.lap_completed.is_connected(_on_lap_completed):
		_tracked_counter.lap_completed.disconnect(_on_lap_completed)
	counter.lap_completed.connect(_on_lap_completed)
	_tracked_counter = counter
	_stats.start_lap()

func _on_lap_completed(_vehicle: VehiclePhysics, _lap: int, lap_time: float) -> void:
	_stats.end_lap(lap_time)
	_stats.start_lap()
	_best_lap = _stats.get_best_lap()
	CareerProfile.grant_xp(CareerProfile.RACE_LAP_XP)

func _g_from_speed_delta(delta: float, speed_kmh: float) -> float:
	if delta <= 0.0:
		return 0.0
	var dv := absf(speed_kmh - _last_tick_speed_kmh)
	_last_tick_speed_kmh = speed_kmh
	return dv / (3.6 * 9.81 * delta)

func _is_drifting(info: Dictionary) -> bool:
	var steer := absf(float(info.get("steer", 0.0)))
	var brake := float(info.get("brake", 0.0))
	return steer > 0.5 and brake > 0.1

func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "-:--"
	return "%d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]

static func points_for_position(position: int) -> int:
	if position < 1 or position > POSITION_POINTS.size():
		return 0
	return POSITION_POINTS[position - 1]

func _position_text(car: VehiclePhysics) -> String:
	if RaceManager.get_lap_counter(car) == null:
		return "P1"
	var standings := RaceManager.get_standings()
	if standings.is_empty():
		return "P1"
	var index := standings.find(car)
	return "P%d" % (index + 1) if index != -1 else "-"

## GPS drive-assist HUD wiring (S4 item 4): the widget mirrors RaceUI's road
## source lazily (picked up when the open world loads or a test injects one),
## then feeds the BrakeLine probe into the nav cluster each frame behind the
## GameState.nav_assist_enabled feature flag.
func _resolve_nav_source() -> void:
	if _nav_road_source != null:
		return
	_nav_road_source = MapRoads.resolve_road_source(self)
	if _nav_road_source != null:
		_brake_line = BrakeLine.new(_nav_road_source)

func _refresh_nav_assist(car: VehiclePhysics) -> void:
	if nav_widget == null:
		return
	if not GameState.nav_assist_enabled or _nav_road_source == null or not MapRoads.has_route:
		nav_widget.visible = false
		return
	var probe := _brake_line.probe(car.global_position)
	var hint: String = str(probe["hint"])
	if hint == "none":
		nav_widget.visible = false
		return
	nav_widget.visible = true
	nav_arrow.text = _nav_arrow_text(str(probe["arrow"]))
	nav_hint.text = "HARD BRAKE" if hint == "hard-brake" else "BRAKE"
	var dist_m := float(probe["distance_m"])
	var meters := maxi(roundi(dist_m), 1)
	nav_distance.text = "%d m" % meters

func _nav_arrow_text(arrow: String) -> String:
	match arrow:
		"left":
			return "<<"
		"right":
			return ">>"
		_:
			return "^"