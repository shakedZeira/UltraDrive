class_name TireMarks
extends Node

## Pooled handbrake tyre marks: short-lived, darks quads pinned under the rear
## axle while the parent car is handbrake-locked and above MIN_SPEED_KMH. Pure
## state machine in update(); the visual mesh pool is headless-culled so CI
## asserts behaviour, not rendering. Marks recycle the oldest pooled slot so
## the scene never grows beyond the cap.

const MARK_LIFETIME := 3.0
const MARK_COUNT_CAP := 48
const MIN_SPEED_KMH := 10.0
const MARK_SPAWN_INTERVAL := 0.12
const MARK_SIZE := Vector2(0.55, 0.8)
const MARK_ALPHA := 0.75
const REAR_WHEEL_OFFSETS: Array[Vector3] = [
	Vector3(-0.85, 0.02, 1.35),
	Vector3(0.85, 0.02, 1.35),
]

var _pool: Array[MeshInstance3D] = []
var _marks: Array[Dictionary] = []
var _spawn_timer := 0.0
var _marking := false
var _next_offset := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in MARK_COUNT_CAP:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "TireMark"
		var quad := QuadMesh.new()
		quad.size = MARK_SIZE
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = false
		material.albedo_color = Color(0.06, 0.06, 0.08, MARK_ALPHA)
		quad.material = material
		mesh_instance.mesh = quad
		mesh_instance.visible = false
		add_child(mesh_instance)
		_pool.append(mesh_instance)

func _process(delta: float) -> void:
	var car := get_parent() as VehiclePhysics
	if car == null:
		return
	update(delta, car.get_handbrake(), car.get_speed_kmh())

## Pure update seam: tests drive this directly with a fixed delta.
func update(delta: float, handbrake: bool, speed_kmh: float) -> void:
	_marking = handbrake and speed_kmh >= MIN_SPEED_KMH and _marks.size() < MARK_COUNT_CAP
	if _marking:
		_spawn_timer += delta
		while _marks.size() < MARK_COUNT_CAP and _spawn_timer >= MARK_SPAWN_INTERVAL:
			_spawn_timer -= MARK_SPAWN_INTERVAL
			_spawn_mark()
	else:
		_spawn_timer = maxf(_spawn_timer - delta, 0.0)
	_age_marks(delta)
	_pin_marks()

func _spawn_mark() -> void:
	var slot := _next_pool_slot()
	var offset := REAR_WHEEL_OFFSETS[_next_offset % REAR_WHEEL_OFFSETS.size()]
	_next_offset += 1
	var car := get_parent() as VehiclePhysics
	var pose := Transform3D()
	if car != null:
		pose = car.global_transform * Transform3D(Basis(), offset)
	var mesh: MeshInstance3D = _pool[slot] if slot >= 0 and _pool.size() > 0 else null
	var mark := {
		"age": 0.0,
		"pose": pose,
		"mesh": mesh,
		"slot": slot,
	}
	_marks.append(mark)

func _next_pool_slot() -> int:
	if _marks.size() >= MARK_COUNT_CAP:
		return -1
	if _pool.size() == 0:
		return _marks.size()
	var slot := _marks.size() % _pool.size()
	if slot < _marks.size():
		_despawn_mark(slot)
	return slot

func _age_marks(delta: float) -> void:
	var i := _marks.size() - 1
	while i >= 0:
		var age: float = float(_marks[i]["age"]) + delta
		if age >= MARK_LIFETIME:
			_despawn_mark(i)
		else:
			_marks[i]["age"] = age
		i -= 1

func _despawn_mark(index: int) -> void:
	var mark: Dictionary = _marks[index]
	var mesh := mark.get("mesh") as MeshInstance3D
	if mesh != null:
		mesh.visible = false
	_marks.remove_at(index)

func _pin_marks() -> void:
	for mark in _marks:
		var mesh := mark.get("mesh") as MeshInstance3D
		if mesh != null:
			mesh.global_transform = mark["pose"]
			mesh.visible = true

func is_marking() -> bool:
	return _marking

func active_mark_count() -> int:
	return _marks.size()

func mark_cap() -> int:
	return MARK_COUNT_CAP