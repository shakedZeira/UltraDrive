# scripts/race/race_ui.gd
extends CanvasLayer

## In-race HUD: speedometer, tachometer, gear, position, lap time.

@onready var speed_label: Label = %SpeedLabel
@onready var gear_label: Label = %GearLabel
@onready var lap_label: Label = %LapLabel
@onready var position_label: Label = %PositionLabel
@onready var time_label: Label = %TimeLabel

func _process(_delta: float) -> void:
	var car := VehicleManager.get_player_car()
	if car == null:
		return

	var info := car.get_drive_info()
	speed_label.text = "%d" % int(info["speed_kmh"])
	gear_label.text = _gear_to_string(info["gear"])
	var lap_counter := RaceManager.get_lap_counter(car) if RaceManager.get_lap_counter(car) else null
	lap_label.text = "LAP %d" % (lap_counter.get_current_lap() if lap_counter else 1)
	time_label.text = "%.3f" % (lap_counter.get_lap_time() if lap_counter else 0.0)

func _gear_to_string(gear: int) -> String:
	if gear == -1:
		return "R"
	elif gear == 0:
		return "N"
	return str(gear + 1)
