# scripts/race/race_ui.gd
extends CanvasLayer

## In-race HUD: speedometer, tachometer, gear, position, lap time.

@onready var speed_label: Label = %SpeedLabel
@onready var gear_label: Label = %GearLabel
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel
@onready var rev_label: Label = %RevLabel

func _process(_delta: float) -> void:
	var car := VehicleManager.get_player_car()
	if car == null:
		return

	var info := car.get_drive_info()
	speed_label.text = "%d" % int(info["speed_kmh"])
	gear_label.text = _gear_to_string(info["gear"])
	rev_label.text = "%d RPM" % int(info["rpm"])
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

func _gear_to_string(gear: int) -> String:
	if gear == -1:
		return "R"
	elif gear == 0:
		return "N"
	return str(gear + 1)
