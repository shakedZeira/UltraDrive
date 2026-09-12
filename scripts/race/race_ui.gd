# scripts/race/race_ui.gd
extends CanvasLayer

## In-race HUD: drives the Forza-style gauge cluster (tach/speed/gear) plus
## position, lap and lap-time readouts.

@onready var cluster: Tachometer = %Cluster
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel

func _process(_delta: float) -> void:
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
	position_label.text = _position_text(car)
	var lap_counter := RaceManager.get_lap_counter(car)
	lap_label.text = "LAP %d" % (lap_counter.get_current_lap() if lap_counter else 1)
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)

func _position_text(car: VehiclePhysics) -> String:
	if RaceManager.get_lap_counter(car) == null:
		return "P1"
	var standings := RaceManager.get_standings()
	if standings.is_empty():
		return "P1"
	var index := standings.find(car)
	return "P%d" % (index + 1) if index != -1 else "-"