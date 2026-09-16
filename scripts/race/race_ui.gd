# scripts/race/race_ui.gd
extends CanvasLayer

## In-race HUD: drives the Forza-style gauge cluster (tach/speed/gear) plus
## position, lap and lap-time readouts, and the FINISH banner.

@onready var cluster: Tachometer = %Cluster
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel

var _pending_laps: int = 0
var _race_over: bool = false

func _ready() -> void:
	_pending_laps = RaceManager.consume_pending_race()
	RaceManager.race_finished.connect(_on_race_finished)

func _process(_delta: float) -> void:
	if _pending_laps > 0:
		var laps := _pending_laps
		_pending_laps = 0
		RaceManager.start_race(VehicleManager.get_all_cars(), laps)
	var car := VehicleManager.get_player_car()
	if car == null:
		return

	var info := car.get_drive_info()
	cluster.set_rpm(float(info["rpm"]))
	cluster.set_gear(int(info["gear"]))
	cluster.set_speed_kmh(float(info["speed_kmh"]))
	var cfg := car.config
	if cfg != null:
		cluster.set_engine_range(cfg.idle_rpm, cfg.redline_rpm)
		cluster.set_car_class(cfg.car_class)
	if _race_over:
		return
	position_label.text = _position_text(car)
	var lap_counter := RaceManager.get_lap_counter(car)
	lap_label.text = "LAP %d" % (lap_counter.get_current_lap() if lap_counter else 1)
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)

func _on_race_finished(standings: Array) -> void:
	_race_over = true
	if standings.is_empty():
		return
	var winner: VehiclePhysics = standings[0]
	var counter := RaceManager.get_lap_counter(winner)
	var total := counter.get_total_time() if counter else 0.0
	position_label.text = "FINISH  %.2fs" % total
	lap_label.text = "RACE TIME %.2fs" % RaceManager.get_race_time()

func _position_text(car: VehiclePhysics) -> String:
	if RaceManager.get_lap_counter(car) == null:
		return "P1"
	var standings := RaceManager.get_standings()
	if standings.is_empty():
		return "P1"
	var index := standings.find(car)
	return "P%d" % (index + 1) if index != -1 else "-"