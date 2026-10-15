# THROWAWAY PROBE (agent 3) — AI rival stall / pace instrument. DELETE WHEN DONE.
# Run:  _tmp_a3_probe.bat   (headless, --fixed-fps 60, writes reports/parallel/agent3/<label>.csv)
extends Node

const NI_SCENE := "res://scenes/track/northern_isle.tscn"
const RIVAL_SCENE := "res://scenes/vehicle/rival_car.tscn"
const OUT_DIR := "res://reports/parallel/agent3"
const SAMPLE_EVERY_PHYS := 30          # 0.5 s at 60 Hz
const PHYS_PER_SECOND := 60.0

var _label := "before"
var _duration := 60.0
var _phys := 0
var _stage := 0                        # 0 boot, 1 wait-ready, 2 running, 3 done
var _scene: Node = null
var _rivals: Array[VehiclePhysics] = []
var _line: Array[Vector3] = []
var _rows: Array[String] = []
var _prev_target: Dictionary = {}
var _stall_run: Dictionary = {}
var _max_stall: Dictionary = {}
var _stall_report: Dictionary = {}
var _stall_frozen: Dictionary = {}
var _deadlock_frames: Dictionary = {}
var _slow_frames: Dictionary = {}
var _speed_sum: Dictionary = {}
var _speed_n: Dictionary = {}
var _lap_seen: Dictionary = {}
var _lap_times: Dictionary = {}
var _gear_hist: Dictionary = {}
var _redline_frames: Dictionary = {}
var _gear1_frames: Dictionary = {}

func _ready() -> void:
	if OS.has_environment("A3_LABEL"):
		_label = OS.get_environment("A3_LABEL")
	if OS.has_environment("A3_DURATION"):
		_duration = float(OS.get_environment("A3_DURATION"))

func _physics_process(_delta: float) -> void:
	_phys += 1
	match _stage:
		0:
			_boot()
		1:
			_try_configure()
		2:
			_tick()

func _boot() -> void:
	var packed := load(NI_SCENE) as PackedScene
	if packed == null:
		print("[a3] FAILED to load NI scene")
		get_tree().quit(2)
		return
	_scene = packed.instantiate()
	add_child(_scene)
	_stage = 1

func _try_configure() -> void:
	if _phys < 20:
		return
	var player := VehicleManager.get_player_car()
	if player == null:
		if _phys > 600:
			print("[a3] FAILED: no player car after 600 physics frames")
			get_tree().quit(2)
		return
	GameState.opponents = 3
	GameState.ai_difficulty = "Skilled"
	RaceManager.rival_vehicle_scene = load(RIVAL_SCENE) as PackedScene
	RaceManager.rival_spawner = Callable()
	RaceManager.configure_default_rivals(player, 0)
	RaceManager.start_race(VehicleManager.get_all_cars(), 3)
	RaceManager.get_countdown().advance(RaceCountdown.TOTAL_SECONDS + 0.5)
	_rivals = RaceManager.get_spawned_rivals()
	_line = RaceManager.rival_centerline
	if _rivals.is_empty() or _line.size() < 3:
		print("[a3] FAILED: rivals=%d line=%d" % [_rivals.size(), _line.size()])
		get_tree().quit(2)
		return
	for car: VehiclePhysics in _rivals:
		_prev_target[car] = -999
		_stall_run[car] = 0.0
		_max_stall[car] = 0.0
		_stall_report[car] = []
		_stall_frozen[car] = false
		_deadlock_frames[car] = 0
		_slow_frames[car] = 0
		_speed_sum[car] = 0.0
		_speed_n[car] = 0
		_lap_seen[car] = 0
		_lap_times[car] = []
		_gear_hist[car] = {}
		_redline_frames[car] = 0
		_gear1_frames[car] = 0
	_phys = 0
	_stage = 2
	print("[a3] label=%s rivals=%d line=%d duration=%.0fs" % [_label, _rivals.size(), _line.size(), _duration])

func _tick() -> void:
	for car: VehiclePhysics in _rivals:
		var driver := _driver(car)
		if driver == null:
			continue
		var speed := car.linear_velocity.length()
		var gear := car.get_gear()
		var hist: Dictionary = _gear_hist[car]
		hist[gear] = int(hist.get(gear, 0)) + 1
		if gear == 1:
			_gear1_frames[car] = int(_gear1_frames[car]) + 1
		var redline := 7000.0
		if car.config != null and car.config.redline_rpm > 0.0:
			redline = car.config.redline_rpm
		if car.get_rpm() >= redline * 0.99:
			_redline_frames[car] = int(_redline_frames[car]) + 1
		if speed < 2.0 and car.input_override.y <= 0.0:
			_deadlock_frames[car] = int(_deadlock_frames[car]) + 1
		if speed < 8.3:
			_slow_frames[car] = int(_slow_frames[car]) + 1
		_speed_sum[car] = float(_speed_sum[car]) + speed
		_speed_n[car] = int(_speed_n[car]) + 1
		if driver._current_target == int(_prev_target[car]):
			_stall_run[car] = float(_stall_run[car]) + 1.0 / PHYS_PER_SECOND
			if float(_stall_run[car]) > float(_max_stall[car]):
				_max_stall[car] = _stall_run[car]
			if float(_stall_run[car]) > 1.5 and not bool(_stall_frozen[car]):
				_stall_frozen[car] = true
				var idx := _nearest_index(_line, car.global_position)
				var p := _line[idx]
				var dx := p.x - car.global_position.x
				var dz := p.z - car.global_position.z
				(_stall_report[car] as Array).append("t=%.1fs idx=%d speed=%.1f km/h lateral=%.1fm y=%.2f" % [
					float(_phys) / PHYS_PER_SECOND, driver._current_target, speed * 3.6,
					sqrt(dx * dx + dz * dz), car.input_override.y])
		else:
			_prev_target[car] = driver._current_target
			_stall_run[car] = 0.0
			_stall_frozen[car] = false
	if _phys % SAMPLE_EVERY_PHYS == 0:
		_sample(float(_phys) / PHYS_PER_SECOND)
	if float(_phys) >= _duration * PHYS_PER_SECOND:
		_finish()

func _driver(car: VehiclePhysics) -> RivalDriver:
	for child in car.get_children():
		if child is RivalDriver:
			return child as RivalDriver
	return null

func _nearest_index(line: Array[Vector3], pos: Vector3) -> int:
	var best_index := 0
	var best_dist := INF
	for i in range(line.size()):
		var p := line[i]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		var d := dx * dx + dz * dz
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index

func _sample(t: float) -> void:
	for car: VehiclePhysics in _rivals:
		var driver := _driver(car)
		if driver == null:
			continue
		var nearest := _nearest_index(_line, car.global_position)
		var p := _line[nearest]
		var dx := p.x - car.global_position.x
		var dz := p.z - car.global_position.z
		var lateral := sqrt(dx * dx + dz * dz)
		var speed := car.linear_velocity.length()
		var fwd := -car.global_basis.z
		fwd.y = 0.0
		var tangent := _line[(nearest + 1) % _line.size()] - _line[nearest]
		tangent.y = 0.0
		var yaw_err := 0.0
		if fwd.length() > 0.001 and tangent.length() > 0.001:
			yaw_err = rad_to_deg(acos(clampf(fwd.normalized().dot(tangent.normalized()), -1.0, 1.0)))
		var target := _line[driver._current_target]
		var to_target := target - car.global_position
		to_target.y = 0.0
		var bearing := 0.0
		if to_target.length() > 0.001 and fwd.length() > 0.001:
			bearing = fwd.normalized().cross(to_target.normalized()).y
		var counter: LapCounter = RaceManager.get_lap_counter(car)
		var lap := 1
		var total := 0.0
		if counter != null:
			lap = counter.get_current_lap()
			total = counter.get_total_time()
			if lap > int(_lap_seen[car]):
				# Skip the t~0 sample (lap 1, total ~0.2 s) -- only real completions.
				if int(_lap_seen[car]) > 0:
					(_lap_times[car] as Array).append(total)
				_lap_seen[car] = lap
		_rows.append("%.2f,%s,%s,%d,%d,%.2f,%.1f,%.2f,%.2f,%.2f,%.2f,%.1f,%.2f,%d,%d,%.0f,%.2f,%.2f" % [
			t, car.name, driver.get_tier() + "/" + driver.get_car_class(),
			driver._current_target, nearest, lateral, speed * 3.6,
			car._throttle_input, car._brake_input, car._steer_input,
			car.input_override.x, yaw_err, bearing, lap, car.get_gear(), car.get_rpm(),
			car.global_position.x, car.global_position.z])

func _finish() -> void:
	_stage = 3
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var csv := FileAccess.open(OUT_DIR.path_join("%s.csv" % _label), FileAccess.WRITE)
	if csv != null:
		csv.store_line("t,name,tier/class,target_idx,nearest_idx,lateral_m,speed_kmh,thr,brk,steer,steer_in,yaw_err_deg,bearing_sin,lap,gear,rpm,px,pz")
		for row in _rows:
			csv.store_line(row)
		csv.close()
	print("[a3] === SUMMARY %s (dur=%.0fs, rows=%d) ===" % [_label, _duration, _rows.size()])
	print("[a3] csv=%s" % OUT_DIR.path_join("%s.csv" % _label))
	for car: VehiclePhysics in _rivals:
		var driver := _driver(car)
		var tier := "?" if driver == null else driver.get_tier() + "/" + driver.get_car_class()
		var n := maxi(1, int(_speed_n[car]))
		var laps_str := ""
		for lt: float in (_lap_times[car] as Array):
			laps_str += "%.1fs " % lt
		print("[a3] rival %s %s avg=%.1f km/h maxstall=%.1fs deadlock_frames=%d slow_frames=%d laps(at)=%s" % [
			car.name, tier, (float(_speed_sum[car]) / float(n)) * 3.6, float(_max_stall[car]),
			int(_deadlock_frames[car]), int(_slow_frames[car]), laps_str])
		var episodes: Array = _stall_report[car]
		print("[a3]   stall episodes(>1.5s frozen target): %d" % episodes.size())
		var hist: Dictionary = _gear_hist[car]
		var keys: Array = hist.keys()
		keys.sort()
		var hist_str := ""
		for k in keys:
			hist_str += "%d:%d " % [int(k), int(hist[k])]
		print("[a3]   gears(history)=%s redline_frames=%d gear1_frames=%d" % [
			hist_str, int(_redline_frames[car]), int(_gear1_frames[car])])
		var shown := 0
		for ep: String in episodes:
			print("[a3]     %s" % ep)
			shown += 1
			if shown >= 12:
				print("[a3]     ... (%d more)" % (episodes.size() - shown))
				break
	get_tree().quit(0)
