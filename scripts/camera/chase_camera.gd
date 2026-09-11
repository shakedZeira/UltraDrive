extends Node3D

## Smooth chase camera that follows the vehicle.
## Attach as child of VehiclePhysics or set target in inspector.

@export var target: Node3D
@export var follow_speed: float = 5.0
@export var camera_distance: float = 6.0
@export var camera_height: float = 2.5
@export var fov_min: float = 70.0
@export var fov_max: float = 90.0
@export var fov_speed_factor: float = 0.05

var _camera: Camera3D

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.fov = fov_min
    add_child(_camera)
    _camera.current = true

    if target == null:
        var parent := get_parent() as Node3D
        if parent is VehiclePhysics:
            target = parent
        else:
            var found := get_parent().find_children("*", "VehiclePhysics", false, false)
            target = found[0] as Node3D if found.size() > 0 else parent

func _physics_process(delta: float) -> void:
    if target == null:
        return

    var car := target as VehiclePhysics
    var speed_kmh := 0.0
    if car:
        speed_kmh = car.get_speed_kmh()

    # --- Target position (behind and above car) ---
    var target_pos := target.global_position \
                    + target.global_basis.z * camera_distance \
                    + Vector3.UP * camera_height

    # --- Smooth follow ---
    global_position = global_position.lerp(target_pos, follow_speed * delta)

    # --- Look at car ---
    var look_target := target.global_position + Vector3.UP * 1.0
    var look_dir := (look_target - global_position).normalized()
    if look_dir.length() > 0.01:
        _camera.look_at(look_target)

    # --- FOV scaling with speed ---
    var target_fov := lerpf(fov_min, fov_max, clampf(speed_kmh / 200.0, 0.0, 1.0))
    _camera.fov = lerpf(_camera.fov, target_fov, fov_speed_factor)
