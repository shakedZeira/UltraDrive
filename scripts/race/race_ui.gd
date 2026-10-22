# scripts/race/race_ui.gd
class_name RaceUI
extends CanvasLayer

## In-race HUD: drives the Forza-style gauge cluster (tach/speed/gear), the
## start-gate countdown overlay ("3...2...1...GO!"), position/lap/lap-time
## readouts, and the race results overlay (position, total time, best lap,
## stats rows) with its Next Race / Return to Free Roam exits.

const FREE_ROAM_SCENE := "res://scenes/world/open_world_root.tscn"

## Post-race EXIT destination: the race menu / track picker, distinct from
## NEXT RACE (re-arm the ceremony) and RETURN TO FREE ROAM (the open world).
const TRACK_SELECT_SCENE := "res://scenes/ui/track_select.tscn"

## Virtual-checkpoint spacing (m) for the live standings gap. Small enough that a
## gap reads as continuous, large enough that the split table stays cheap.
const GAP_VCP_SPACING := 5.0

## Position -> award points (1st 1000 .. 4th 250): economy stub for item 11,
## exported here so a future reward loop can read it without touching the HUD.
const POSITION_POINTS: Array[int] = [1000, 750, 500, 250]

const GOLD_TITLE := Color(0.949, 0.741, 0.167)
const NEUTRAL_TITLE := Color(0.96, 0.98, 1.0)

## Below this gap (seconds) a run and the record read as identical, so the
## results card says so instead of printing a "+0.00" delta.
const BEST_LAP_DELTA_EPSILON := 0.005

@onready var cluster: Tachometer = %Cluster
@onready var traction_lamp: TractionLamp = %TractionLamp
@onready var power_value: Label = %PowerValue
@onready var torque_value: Label = %TorqueValue
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel
@onready var coords_label: Label = %CoordsLabel
@onready var countdown_overlay: Control = %CountdownOverlay
@onready var banner: Label = %Banner
@onready var flare: Panel = %Flare
@onready var grid_card: VBoxContainer = %GridCard
@onready var standings_panel: Control = %StandingsPanel
@onready var standings_list: VBoxContainer = %StandingsList
@onready var results_overlay: Control = %ResultsOverlay
@onready var results_title: Label = %ResultsTitle
@onready var results_position: Label = %ResultsPosition
@onready var results_total: Label = %ResultsTotal
@onready var results_best_lap: Label = %ResultsBestLap
@onready var results_best_lap_delta: Label = %ResultsBestLapDelta
@onready var results_points: Label = %ResultsPoints
@onready var results_stats_rows: VBoxContainer = %ResultsStatsRows
@onready var next_race_button: Button = %NextRaceButton
@onready var return_free_roam_button: Button = %ReturnFreeRoamButton
@onready var exit_button: Button = %ExitButton
@onready var confetti: ResultsConfetti = %ResultsConfetti
@onready var nav_widget: Control = %NavWidget
@onready var nav_arrow: Label = %NavArrow
@onready var nav_distance: Label = %NavDistance
@onready var nav_hint: Label = %NavHint
@onready var boost_gauge: BoostGauge = %BoostGauge

## Scene-navigation seam (mirrors TrackSelect): tests stub this to capture the
## launched path without actually swapping scenes.
var launch_callback: Callable = _default_launch

var _pending_laps: int = 0
var _race_over: bool = false
var _rewards_banked: bool = false
## AAA-5 replay capture: a live ReplayRecorder runs from race start to finish
## (finish-line event stamped on RaceManager.race_finished) and, in free-roam,
## from the player's capture toggle. _last_recording keeps the finished buffer
## for a future replay UI; both are RefCounted, so they die with this HUD.
var _recorder: ReplayRecorder = null
var _last_recording: ReplayRecorder = null
var _capture_enabled: bool = false
var _best_lap: float = 0.0
## Best lap of THIS run only, never seeded from the save, so the results card
## can show how the run compared against the cross-session record.
var _run_best_lap: float = 0.0
## (track id, car class) the persisted records are filed under. The track is
## fixed for the lifetime of this HUD (it lives inside one track scene); the
## class is re-read per submit so a mid-session car swap cannot misfile a lap.
var _record_track_id: String = ""
var _record_car_class: String = BestLapRecords.UNKNOWN_CAR_CLASS
## The persisted cross-session record for that pair, reloaded after every
## submit. The results card reads it, so a return visit shows the old time.
var _record_best_lap: float = 0.0
var _tracked_counter: LapCounter = null
var _countdown_audio: CountdownAudio = null
var _ui_blip: UiBlip = null
var _last_countdown_phase: String = ""
var _stats: SessionStats = GameState.session_stats
var _last_tick_speed_kmh: float = 0.0
var _hud_rpm := -1.0
var _hud_gear := -999
var _hud_speed := -1.0
var _nav_road_source: Object = null
var _brake_line: BrakeLine = null
var _grid_card_built: bool = false
var _standings_signature: String = ""
## Live standings gap ("virtual checkpoints"): the row Labels and their
## name-only base text, kept in sync with the current standings order so the
## per-frame gap refresh only rewrites `.text` instead of rebuilding the list.
var _standings_cars: Array = []
var _standings_rows: Array[Label] = []
var _standings_base_text: Array[String] = []
var _gap_tracker: RaceGapTracker = null
var _gap_path_key: String = ""
## Post-race cinematic shell (docs/plans/post_race_cinematic_exit_plan.md). Built
## on race finish, owned by this HUD, torn down on Next Race / Free Roam / EXIT.
## Null while a race is live. All its decisions come from CinematicDirector.
var _cinematic: PostRaceCinematic = null
## HUD-side mirror of CinematicDirector.State, so a re-armed ceremony can assert
## the post-race flow was left behind (RACING) before the next grid forms.
var _post_race_state: int = CinematicDirector.State.RACING

func _ready() -> void:
	_pending_laps = RaceManager.consume_pending_race()
	RaceManager.race_finished.connect(_on_race_finished)
	_countdown_audio = CountdownAudio.new()
	_countdown_audio.name = "CountdownAudio"
	add_child(_countdown_audio)
	_ui_blip = UiBlip.new()
	_ui_blip.name = "UiBlip"
	add_child(_ui_blip)
	next_race_button.pressed.connect(_on_next_race)
	return_free_roam_button.pressed.connect(_on_return_free_roam)
	exit_button.pressed.connect(_on_exit)
	_resolve_nav_source()
	_load_persisted_best_lap()

func _process(delta: float) -> void:
	if _pending_laps <= 0:
		_pending_laps = RaceManager.consume_pending_race()
	if _pending_laps > 0:
		var laps := _pending_laps
		_pending_laps = 0
		# S5 production roster: on a track that published a rival centerline the
		# player races the configured field. Only build the DEFAULT field when no
		# roster was configured explicitly (track-select events / tests may have
		# set one already), so an explicit roster is never clobbered.
		if RaceManager.rival_roster.is_empty():
			RaceManager.configure_default_rivals()
		RaceManager.start_race(VehicleManager.get_all_cars(), laps)
		_start_capture()
	_drive_countdown(delta)
	_resolve_nav_source()
	var car := VehicleManager.get_player_car()
	if car == null:
		# No car: nothing to report, and the lamp must not be left lit from
		# the last frame that had one.
		_refresh_traction_lamp(null)
		_refresh_power_readout({}, null)
		_refresh_boost_gauge({}, null)
		return
	_refresh_lap_tracking(car)
	_refresh_standings()

	var info := car.get_drive_info()
	_capture_drive(car, info, delta)
	var speed_kmh := float(info["speed_kmh"])
	_stats.tick(delta, speed_kmh, _g_from_speed_delta(delta, speed_kmh), _is_drifting(info))
	var rpm := float(info["rpm"])
	var gear := int(info["gear"])
	if absf(rpm - _hud_rpm) >= 1.0:
		_hud_rpm = rpm
		cluster.set_rpm(rpm)
	if gear != _hud_gear:
		_hud_gear = gear
		cluster.set_gear(gear)
	if absf(speed_kmh - _hud_speed) >= 0.5:
		_hud_speed = speed_kmh
		cluster.set_speed_kmh(speed_kmh)
	var cfg := car.config
	if cfg != null:
		cluster.set_engine_range(cfg.idle_rpm, cfg.redline_rpm)
		cluster.set_car_class(cfg.car_class)
	_refresh_traction_lamp(car)
	_refresh_power_readout(info, cfg)
	_refresh_boost_gauge(info, cfg)
	_refresh_nav_assist(car)
	if _race_over:
		return
	position_label.text = _position_text(car)
	var lap_counter := RaceManager.get_lap_counter(car)
	var _lap_cur := lap_counter.get_current_lap() if lap_counter else 1
	var _lap_tot := lap_counter.total_laps if lap_counter else RaceManager.total_laps
	lap_label.text = "LAP %d/%d" % [_lap_cur, _lap_tot]
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)
	var pos := car.global_position
	coords_label.text = "X: %.1f  Y: %.1f  Z: %.1f" % [pos.x, pos.y, pos.z]

func _drive_countdown(delta: float) -> void:
	if countdown_overlay == null:
		return
	var countdown := RaceManager.get_countdown()
	var active := RaceManager.is_race_active and not _race_over and countdown.controls_locked()
	if not active:
		_grid_card_built = false
		countdown_overlay.visible = false
		_last_countdown_phase = ""
		return
	if not _grid_card_built:
		_rebuild_grid_card()
		_grid_card_built = true
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

## AAA-5 replay capture. The race path arms a recorder when start_race commits
## (one per race lifecycle) and free-roam arms one the first time the player
## enables capture. Every frame feeds the car's transform + drive info into the
## pure ReplayRecorder; on finish the "race_finished" event is stamped and the
## capture is frozen into _last_recording for a future replay UI.
func _start_capture() -> void:
	_recorder = ReplayRecorder.new()
	_recorder.start()

func _capture_drive(car: VehiclePhysics, info: Dictionary, delta: float) -> void:
	if _recorder == null or not _recorder.is_capturing():
		return
	_recorder.feed(car.global_transform, info, delta)

func _finalize_capture(event_name: String) -> void:
	if _recorder == null:
		return
	if _recorder.is_capturing():
		_recorder.record_event(event_name)
	_recorder.stop()
	_last_recording = _recorder
	_recorder = null

## Free-roam capture toggle (bound to the replay_capture input action below):
## while free-roaming with no race live, toggling on starts a fresh rolling
## capture of the drive and toggling off freezes it (finish timestamps survive
## in _last_recording). Returns the new toggle state.
func toggle_free_roam_capture() -> bool:
	if RaceManager.is_race_active or _race_over:
		return _capture_enabled
	if _capture_enabled:
		_finalize_capture("capture_ended")
		_capture_enabled = false
	else:
		_capture_enabled = true
		_start_capture()
	return _capture_enabled

func is_free_roam_capture_on() -> bool:
	return _capture_enabled

func get_last_recording() -> ReplayRecorder:
	return _last_recording

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("replay_capture"):
		toggle_free_roam_capture()
		get_viewport().set_input_as_handled()

func _on_race_finished(standings: Array) -> void:
	_finalize_capture("race_finished")
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
	rows.append_array(_build_persona_finish_rows(standings))
	# Final idempotent commit: the best lap may have been set on a lap this HUD
	# never saw (a counter swap mid-race), and the card must read the record.
	_submit_best_lap(_stats.get_best_lap())
	show_result(position, total, _best_lap, rows)
	if not _rewards_banked:
		_rewards_banked = true
		_bank_race_rewards(position)
	_start_cinematic()

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
	# `best_lap` is the merged cross-session record (the record wins whenever it
	# exists), so a return visit to a track still shows the old time. The run
	# delta lives on its own label so the record line keeps its trailing
	# M:SS.ss token for the HUD parser.
	results_best_lap.text = "BEST LAP  %s" % _format_time(best_lap)
	_refresh_best_lap_delta(best_lap)
	results_points.text = "POSITION POINTS  +%d" % points_for_position(safe)
	_rebuild_stats_rows(extra_rows)
	results_title.add_theme_color_override("font_color", GOLD_TITLE if safe == 1 else NEUTRAL_TITLE)
	results_overlay.visible = true
	if safe == 1:
		confetti.burst()
	else:
		confetti.reset()

## Applies best_lap_delta_text() to the delta label, hiding the line entirely
## when there is nothing to compare (no record yet, or no lap this run).
func _refresh_best_lap_delta(record_best: float) -> void:
	if results_best_lap_delta == null:
		return
	var text := best_lap_delta_text(record_best, _run_best_lap)
	results_best_lap_delta.text = text
	results_best_lap_delta.visible = text != ""

## How THIS run's best lap compared against the persisted cross-session record:
## positive = slower than the record, negative = a new record, "" when there is
## nothing to compare. Pure so the wording is testable without a scene.
static func best_lap_delta_text(record_best: float, run_best: float) -> String:
	if record_best <= 0.0 or run_best <= 0.0:
		return ""
	var delta := snappedf(run_best - record_best, 0.01)
	if absf(delta) < BEST_LAP_DELTA_EPSILON:
		return "MATCHES RECORD"
	return "THIS RUN %s" % _signed_seconds(delta)

## Explicit sign rendering (no reliance on a %-format sign flag) so the delta
## string is byte-identical across platforms.
static func _signed_seconds(value: float) -> String:
	return ("+%.2f" % value) if value >= 0.0 else ("%.2f" % value)

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
	_set_post_race_state(CinematicDirector.State.RACING)
	results_overlay.visible = false
	confetti.reset()
	RaceManager.request_race(RaceManager.total_laps if RaceManager.total_laps > 0 else 3)

func _on_return_free_roam() -> void:
	_race_over = false
	_rewards_banked = false
	_set_post_race_state(CinematicDirector.State.RACING)
	results_overlay.visible = false
	confetti.reset()
	launch_callback.call(FREE_ROAM_SCENE)

# --- Post-race cinematic + EXIT (docs/plans/post_race_cinematic_exit_plan.md) -

## Arm the post-race cinematic. The shell dwells FINISHED_DWELL_SEC on the
## results card, then hands the player car to an AIController, retires the
## gameplay rigs and takes the viewport; the camera cuts the field while the pack
## loops. Degrades to "the card just stays up" when the track published no line
## to cruise (solo races: mountain_pass, flat test tracks — plan §3.2/§6).
func _start_cinematic() -> void:
	_stop_cinematic()
	_post_race_state = CinematicDirector.State.FINISHED
	_cinematic = PostRaceCinematic.new()
	_cinematic.name = "PostRaceCinematic"
	var root := _resolve_cinematic_root()
	if root != null:
		# Sibling of the rigs so its _process runs with the track, not after it.
		root.add_child(_cinematic)
	else:
		# HUD-only / headless: no Node3D root. The shell still runs the machine
		# and simply performs no camera work (null-safe, plan §3.3/§5 T9).
		add_child(_cinematic)
	_cinematic.cinematic_started.connect(_on_cinematic_started)
	_cinematic.cinematic_ended.connect(_on_cinematic_ended)
	_cinematic.exit_requested.connect(_on_exit)
	_cinematic.begin(RaceManager.get_standings(), _resolve_gap_path())

## First Node3D ancestor of this HUD (the track root the camera rigs live under),
## else a Node3D current scene, else null — the same walk _resolve_track_id uses
## for scene_file_path. Null is fine: the shell runs camera-less (plan §3.4).
func _resolve_cinematic_root() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is Node3D:
			return node as Node3D
		node = node.get_parent()
	if is_inside_tree():
		var scene: Node = get_tree().current_scene
		if scene is Node3D:
			return scene as Node3D
	return null

## The cinematic is live: the results card gives way to the beauty pass.
func _on_cinematic_started() -> void:
	_post_race_state = CinematicDirector.State.CINEMATIC
	if _race_over:
		results_overlay.visible = false

## The cinematic ended (Esc/cancel, or a teardown that reached CINEMATIC). Put
## the results card back only while the race is still over and we are not already
## on the way out (EXIT / NEXT RACE hide it themselves).
func _on_cinematic_ended() -> void:
	# A teardown initiated by an exit (EXIT / RACING) owns the final state: the
	# end signal fires from inside _stop_cinematic(), so without this guard it
	# would overwrite the terminal state we just set back to FINISHED.
	if _post_race_state == CinematicDirector.State.EXIT or _post_race_state == CinematicDirector.State.RACING:
		return
	if _race_over:
		results_overlay.visible = true
	_post_race_state = CinematicDirector.State.FINISHED

## Single writer for the HUD-side post-race state. The two terminal edges (EXIT,
## RACING) tear the shell down; FINISHED / CINEMATIC are set by the shell's own
## signals. Deliberately does NOT call PostRaceCinematic.request_exit() — that
## emits exit_requested, which is wired back into _on_exit, and would recurse.
## request_exit() stays the public seam for an external harness.
func _set_post_race_state(state: int) -> void:
	_post_race_state = state
	if state == CinematicDirector.State.RACING or state == CinematicDirector.State.EXIT:
		_stop_cinematic()

## EXIT button handler, and the target of the shell's exit_requested signal.
## Tears the cinematic down (restoring the player + rigs), then lands on the race
## menu through the same launch_callback seam the other exits use (plan §3.5).
func _on_exit() -> void:
	_race_over = false
	_set_post_race_state(CinematicDirector.State.EXIT)
	_rewards_banked = false
	results_overlay.visible = false
	confetti.reset()
	launch_callback.call(TRACK_SELECT_SCENE)

## Stops + frees the cinematic if one exists. Idempotent; stop() is the
## no-exit-signal teardown, so the caller owns what the machine becomes next.
func _stop_cinematic() -> void:
	if _cinematic == null or not is_instance_valid(_cinematic):
		_cinematic = null
		return
	_cinematic.stop()
	_cinematic.queue_free()
	_cinematic = null

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
	# A fresh race (new LapCounter) must not inherit the previous race's split
	# history, or the first gap reading would be nonsense.
	if _gap_tracker != null:
		_gap_tracker.reset()
	_stats.start_lap()

func _on_lap_completed(_vehicle: VehiclePhysics, _lap: int, lap_time: float) -> void:
	_stats.end_lap(lap_time)
	_stats.start_lap()
	# Persist immediately: the record (and the HUD delta derived from it) is
	# already current while the player is still on the finish straight.
	_submit_best_lap(lap_time)
	if lap_time > 0.0 and (_run_best_lap <= 0.0 or lap_time < _run_best_lap):
		_run_best_lap = lap_time
	CareerProfile.grant_xp(CareerProfile.RACE_LAP_XP)
	if _ui_blip != null:
		_ui_blip.play_blip("hud")

## Cross-session best-lap flow (roadmap #7). The track id is reverse-looked-up
## from the track scene this HUD is instanced under; the car class comes off the
## player's live config. The persisted record is loaded once at session start
## and seeded into the session accumulator, so a return visit to a track shows
## the old time before a single lap is turned.
func _load_persisted_best_lap() -> void:
	_record_track_id = _resolve_track_id()
	_record_car_class = _resolve_car_class()
	_record_best_lap = BestLapRecords.load_record(_record_track_id, _record_car_class)
	if _record_best_lap > 0.0:
		_stats.seed_best_lap(_record_best_lap)
	_best_lap = _stats.get_best_lap()

## Load / compare / write the lap against the record for (track, class) and
## refresh the merged HUD best. Returns true when the lap set a new record; a
## worse lap leaves the stored record untouched.
func _submit_best_lap(lap_time: float) -> bool:
	if lap_time <= 0.0:
		return false
	var car_class := _resolve_car_class()
	_record_car_class = car_class
	var improved := BestLapRecords.submit_lap(_record_track_id, car_class, lap_time)
	_record_best_lap = BestLapRecords.load_record(_record_track_id, car_class)
	_stats.seed_best_lap(_record_best_lap)
	_best_lap = _stats.get_best_lap()
	return improved

## Registry id of the track scene this HUD is instanced under, reverse-looked-up
## from the parent scene's file path so nothing new has to be plumbed through
## track select. "" (the "unknown" bucket) when the HUD is not inside a
## registered track — free roam or a scene missing from TrackRegistry.
func _resolve_track_id() -> String:
	var ids: Array[String] = []
	ids.assign(TrackRegistry.get_track_ids())
	var node: Node = get_parent()
	while node != null:
		var path := node.scene_file_path
		for track_id in ids:
			if path == TrackRegistry.get_scene_path(track_id):
				return track_id
		node = node.get_parent()
	return ""

## The player's live car class, falling back to the class resolved at session
## start (and finally the shared "D" bucket) when no car is on the track.
func _resolve_car_class() -> String:
	var car := VehicleManager.get_player_car()
	if car != null and car.config != null:
		return BestLapRecords.normalize_class(car.config.car_class)
	return _record_car_class

## Traction lamp: driven straight off the integrated wheel state, so it lights
## exactly when the same 1.25x rolling-match test that drives the wheel-spin
## visuals says traction is gone. Presentation only.
func _refresh_traction_lamp(car: VehiclePhysics) -> void:
	if traction_lamp == null:
		return
	traction_lamp.set_severity(WheelspinGauge.severity_for_car(car))

## HP + torque lines under the cluster: current crank power (hp) and live crank
## torque (Nm) at the current rpm — both curve-only, no sign tokens.
func _refresh_power_readout(info: Dictionary, cfg: CarConfig) -> void:
	if power_value == null:
		return
	var rpm := float(info.get("rpm", 0.0))
	var text := PowerGauge.format_text(cfg, rpm)
	if power_value.text != text:
		power_value.text = text
	if torque_value == null:
		return
	var torque_text := PowerGauge.format_torque_text(cfg, rpm)
	if torque_value.text != torque_text:
		torque_value.text = torque_text

## Boost gauge beside the cluster: fed from the drive info's additive turbo
## keys. set_boost_bar() auto-hides on max_bar <= 0, so NA cars keep the gauge
## out of the way without a visibility special-case here.
func _refresh_boost_gauge(info: Dictionary, cfg: CarConfig) -> void:
	if boost_gauge == null:
		return
	var max_bar: float = cfg.turbo_max_boost_bar if cfg != null else 0.0
	boost_gauge.set_boost_bar(float(info.get("boost_bar", 0.0)), max_bar)

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

## A4 grid card: the countdown ceremony names the rival field (handle + trait)
## in grid order, so the anonymous front row becomes "P1  bowie knife99 — ...
## Late-braker". Rebuilt once per ceremony; hidden when the roster is persona-free.
func _rebuild_grid_card() -> void:
	_clear_rows(grid_card)
	var personas := RaceManager.get_personas()
	if personas.is_empty():
		grid_card.visible = false
		return
	grid_card.visible = true
	for i in range(personas.size()):
		var persona := personas[i]
		if persona == null:
			continue
		var row := Label.new()
		row.text = "P%d  %s   ·  %s   (%s)" % [i + 1, persona.handle, persona.signature, persona.tier]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		row.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1, 1.0))
		row.add_theme_constant_override("outline_size", 3)
		grid_card.add_child(row)

## A4 live standings: a compact P1..Pn list of racing names (persona handles,
## "YOU" for the player) that mirrors RaceManager.get_standings() each frame.
## Only shown when the field actually carries personas, so persona-free races
## keep their existing HUD untouched. Rebuilt only when the order/names change.
func _refresh_standings() -> void:
	if standings_panel == null:
		return
	if not RaceManager.is_race_active or _race_over:
		standings_panel.visible = false
		return
	var standings := RaceManager.get_standings()
	if standings.is_empty():
		standings_panel.visible = false
		return
	var parts := PackedStringArray()
	var has_persona := false
	for car in standings:
		var persona := RaceManager.get_persona_for(car)
		if persona != null:
			has_persona = true
		var rank := standings.find(car) + 1
		parts.append(str(rank) + "|" + _racer_display_name(car, persona, rank))
	if not has_persona:
		standings_panel.visible = false
		return
	var signature := "~".join(parts)
	if signature != _standings_signature:
		_standings_signature = signature
		_rebuild_standings(standings)
	# Gap text is refreshed EVERY frame (the list structure only on an order or
	# name change), so the deltas move continuously between checkpoints.
	_refresh_standings_gaps(standings)
	standings_panel.visible = true

func _rebuild_standings(standings: Array) -> void:
	_clear_rows(standings_list)
	_standings_cars.clear()
	_standings_rows.clear()
	_standings_base_text.clear()
	for i in range(standings.size()):
		var car := standings[i] as VehiclePhysics
		var persona := RaceManager.get_persona_for(car)
		var suffix := ""
		if persona != null:
			suffix = "   ·   %s" % persona.tier
		var base := "P%d  %s%s" % [i + 1, _racer_display_name(car, persona, i + 1), suffix]
		var row := Label.new()
		row.text = base
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 20)
		if persona != null:
			row.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
		else:
			row.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		row.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.1, 1.0))
		row.add_theme_constant_override("outline_size", 3)
		standings_list.add_child(row)
		_standings_cars.append(car)
		_standings_rows.append(row)
		_standings_base_text.append(base)
	standings_panel.visible = true

## Live per-rival gap beside each standings name. Every participant is sampled
## along the racing line, then each rival's signed delta to the player is
## appended to its row. Graceful when no loop geometry is published (free roam,
## checkpoint-less scenes): the tracker is dropped and the rows show name only.
func _refresh_standings_gaps(_standings: Array) -> void:
	var player := VehicleManager.get_player_car()
	var tracker := _ensure_gap_tracker()
	if tracker == null:
		for i in range(_standings_rows.size()):
			_standings_rows[i].text = _standings_base_text[i]
		return
	for i in range(_standings_cars.size()):
		var car := _standings_cars[i] as VehiclePhysics
		if car != null:
			tracker.sample(car, car.global_position, _car_elapsed(car))
	for i in range(_standings_cars.size()):
		var car := _standings_cars[i] as VehiclePhysics
		var text := _standings_base_text[i]
		if car != null and car != player:
			var gap_text := format_gap_seconds(tracker.gap_seconds(car, player))
			if gap_text != "":
				text += "    %s" % gap_text
		_standings_rows[i].text = text

## Race-elapsed time of a car on the shared race clock (the LapCounter is
## created for every participant at start_race, so the reference is identical).
func _car_elapsed(car: VehiclePhysics) -> float:
	var counter := RaceManager.get_lap_counter(car)
	return counter.get_total_time() if counter != null else 0.0

## Lazily (re)builds the gap tracker from the current loop geometry. Reconfigures
## only when the path identity changes, so the per-frame cost is just the sample
## + gap pass. Returns null when no usable loop exists.
func _ensure_gap_tracker() -> RaceGapTracker:
	var line: Array[Vector3] = _resolve_gap_path()
	if line.size() < RaceGapTracker.MIN_PATH_POINTS:
		_gap_tracker = null
		_gap_path_key = ""
		return null
	var key := "%d:%d:%d" % [line.size(), int(line[0].x * 100.0), int(line[0].z * 100.0)]
	if _gap_tracker == null or key != _gap_path_key:
		if _gap_tracker == null:
			_gap_tracker = RaceGapTracker.new()
		_gap_tracker.configure(line, GAP_VCP_SPACING)
		_gap_path_key = key
	return _gap_tracker

## The loop the gaps are measured along: the track's published rival centerline
## (the same line the rivals drive), or the checkpoint ring when a scene has no
## centerline. Empty when neither exists.
func _resolve_gap_path() -> Array[Vector3]:
	var line: Array[Vector3] = RaceManager.rival_centerline
	if line.size() >= RaceGapTracker.MIN_PATH_POINTS:
		return line
	return _checkpoint_ring()

func _checkpoint_ring() -> Array[Vector3]:
	var cps := RaceManager.get_checkpoints()
	if cps.size() < RaceGapTracker.MIN_PATH_POINTS:
		return []
	var sorted: Array[Checkpoint] = cps.duplicate()
	sorted.sort_custom(func(a: Checkpoint, b: Checkpoint) -> bool: return a.index < b.index)
	var pts: Array[Vector3] = []
	for cp in sorted:
		if cp != null:
			pts.append(cp.global_position)
	if pts.size() < RaceGapTracker.MIN_PATH_POINTS:
		return []
	return RacingLine.resample_arc(pts, GAP_VCP_SPACING)

## Signed-seconds display for a gap: "+0.42" behind, "-0.37" ahead, "" when the
## gap is unknown. Two decimals under 10 s, one decimal above, so a long gap
## stays compact.
static func format_gap_seconds(seconds: float) -> String:
	if is_nan(seconds):
		return ""
	if absf(seconds) < 0.005:
		return "+0.00"
	if absf(seconds) < 10.0:
		return "%+.2f" % seconds
	return "%+.1f" % seconds

func _racer_display_name(car: VehiclePhysics, persona: RivalPersona, rank: int) -> String:
	if persona != null:
		return persona.handle
	if car != null and car == VehicleManager.get_player_car():
		return "YOU"
	return "CAR%d" % rank

func _clear_rows(box: VBoxContainer) -> void:
	if box == null:
		return
	for child in box.get_children():
		child.queue_free()

## A4 results rows: every persona rival that crossed the line gets a name +
## rivalry-record row in final order, fed into the existing results card.
func _build_persona_finish_rows(standings: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(standings.size()):
		var car := standings[i] as VehiclePhysics
		if car == null:
			continue
		var persona := RaceManager.get_persona_for(car)
		if persona == null:
			continue
		out.append({
			"label": "P%d  %s" % [i + 1, persona.handle],
			"value": "%s   %s" % [persona.tier, persona.get_record_string()],
		})
	return out

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