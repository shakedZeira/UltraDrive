# UltraDrive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hybrid open-world + circuit racing game (Forza Horizon 6 meets Gran Turismo 7) in Godot 4.7+ with custom Pacejika-inspired vehicle physics, chunk-based open world streaming, career mode, and PS5 controller support — all running at 1080p/60 FPS on mid-range PC, stored entirely on D: drive.

**Architecture:** Modular autoload-based architecture with 6 singletons (GameState, InputManager, RaceManager, VehicleManager, WeatherManager, SaveManager). Vehicle physics built from scratch using RigidBody3D + per-wheel raycast suspension + Pacejika tire curves + configurable drivetrain. Open world uses Terrain3D + OWDB chunk streaming. Subagent-driven development: each task is dispatched to a fresh agent with isolated context.

**Tech Stack:** Godot 4.7+ (GDScript primary, C# for performance-critical), Jolt Physics GDExtension, Vulkan Forward+, Terrain3D, OWDB, ProtonScatter, GDUnit4 for testing.

**Spec:** `docs/superpowers/specs/2026-09-10-ultradrive-design-spec.md`

**Global Constraints:**
- Engine: Godot 4.7+ stable — installed at `D:\Godot\`
- Project directory: `D:\AI Projects\UltraDrive\`
- Language: GDScript primary, C# only if profiled as performance-critical
- Physics: Custom vehicle physics on RigidBody3D (NOT default VehicleBody3D)
- Rendering: Vulkan Forward+ with Jolt Physics GDExtension
- Input: PS5 DualSense via DS4Windows (XInput emulation) + keyboard fallback
- Performance: 1080p, High preset, 60 FPS on RTX 3050/3060 class GPU
- Assets: All free/open-source or self-created (no licensed car brands)
- Solo developer: every task must be self-contained and independently testable
- Subagent rule: dispatch ONE agent per task to keep context windows small
- All source files use: `UltraDrive/` prefix in autoload names to avoid conflicts
- Git: every task ends with a commit

---

## Phase 1: Project Foundation

**Goal:** Working Godot 4.7 project with Jolt Physics, input system, autoloads configured, and a testable 3D scene. Deploys to D:\AI Projects\UltraDrive\.

---

### Task 1.1: Create Godot 4.7 Project with Jolt Physics

**Files:**
- Create: `D:\AI Projects\UltraDrive\project.godot`

**Interfaces:**
- Consumes: None (first task)
- Produces: Working `project.godot` that loads without error

- [ ] **Step 1: Create the project.godot file**

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; but it can also be edited by hand.

config_version=5

[application]

config/name="UltraDrive"
config/description="Hybrid open-world + circuit racing game"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input]

throttle={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":7,"pressure":0.0,"pressed":true,"script":null)
]
}
brake={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":6,"pressure":0.0,"pressed":true,"script":null)
]
}
steer_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":0,"axis_value":-1.0,"script":null)
]
}
steer_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":0,"axis_value":1.0,"script":null)
]
}
handbrake={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":2,"pressure":0.0,"pressed":true,"script":null)
]
}
reset_car={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":114,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":8,"pressure":0.0,"pressed":true,"script":null)
]
}
pause={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194305,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":11,"pressure":0.0,"pressed":true,"script":null)
]
}
camera_mode={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":99,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":9,"pressure":0.0,"pressed":true,"script":null)
]
}

[layer_names]

3d_physics/layer_1="Vehicles"
3d_physics/layer_2="Track"
3d_physics/layer_3="OpenWorld"
3d_physics/layer_4="Traffic"
3d_physics/layer_5="Checkpoints"

[physics]

common/physics_ticks_per_second=120
3d/default_gravity=9.8

[rendering]

renderer/rendering_method="forward_plus"
textures/default_filters/anisotropic_filtering_level=4
anti_aliasing/quality/msaa_3d=2
environment/defaults/default_clear_color=Color(0.3, 0.3, 0.35, 1)
```

- [ ] **Step 2: Verify project.godot is valid**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --editor --path "D:\AI Projects\UltraDrive" --quit`
Expected: Exits without errors (no parse errors in output)

- [ ] **Step 3: Initialize git repository**

Run:
```
cd "D:\AI Projects\UltraDrive"
git init
echo ".godot/" >> .gitignore
echo "save/" >> .gitignore
git add project.godot .gitignore
git commit -m "feat: initialize Godot 4.7 project with Jolt Physics config and input map"
```

---

### Task 1.2: Install Jolt Physics GDExtension

**Files:**
- Create: `D:\AI Projects\UltraDrive\addons\jolt_physics\` (downloaded addon)

**Interfaces:**
- Consumes: `project.godot` from Task 1.1
- Produces: Jolt Physics available as physics engine replacement

- [ ] **Step 1: Download Jolt Physics GDExtension for Godot 4.7**

Download the latest release from: https://github.com/godot-jolt/godot-jolt/releases
Choose: `godot-jolt_godot-v4.7-stable_win64.zip` (or latest stable)

Extract the contents of the zip into `D:\AI Projects\UltraDrive\addons\jolt_physics\`

The folder structure after extraction should be:
```
addons/
└── jolt_physics/
    ├── jolt_physics.gdextension
    └── bin/
        ├── libjolt-godot.windows.x86_64.dll
        └── ... (other platform binaries)
```

- [ ] **Step 2: Enable the plugin in project settings**

Open `project.godot` and add this section at the end:
```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/jolt_physics/jolt_physics.gdextension")
```

- [ ] **Step 3: Verify Jolt loads without error**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --editor --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors mentioning Jolt or missing DLLs

- [ ] **Step 4: Commit**

```
git add addons/jolt_physics/
git commit -m "feat: install Jolt Physics GDExtension"
```

---

### Task 1.3: Create Main 3D Scene with Lighting

**Files:**
- Create: `D:\AI Projects\UltraDrive\scenes\main.tscn`

**Interfaces:**
- Consumes: `project.godot` from Task 1.1
- Produces: A working 3D scene with DirectionalLight3D, Camera3D, and WorldEnvironment

- [ ] **Step 1: Create the scene file**

```gdscript
# scenes/main.tscn (Godot scene format)
[gd_scene load_steps=4 format=3 uid="uid://main_scene"]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]
sky_top_color = Color(0.35, 0.55, 0.85, 1)
sky_horizon_color = Color(0.65, 0.75, 0.85, 1)
ground_bottom_color = Color(0.2, 0.17, 0.13, 1)
ground_horizon_color = Color(0.65, 0.75, 0.85, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 2
ambient_light_color = Color(0.5, 0.5, 0.55, 1)
ambient_light_energy = 0.5
tonemap_mode = 2
ssao_enabled = true
glow_enabled = true
fog_enabled = true
fog_light_color = Color(0.7, 0.75, 0.85, 1)
fog_density = 0.001

[node name="Main" type="Node3D"]
script = ExtResource("1_main")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.707, 0.707, 0, -0.707, 0.707, 0, 50, 0)
light_energy = 1.2
shadow_enabled = true
directional_shadow_max_distance = 200.0

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.966, 0.259, 0, -0.259, 0.966, 0, 5, 10)
fov = 70.0
```

- [ ] **Step 2: Create the main script**

```gdscript
# scripts/main.gd
extends Node3D

func _ready() -> void:
    print("[UltraDrive] Main scene loaded")
```

- [ ] **Step 3: Verify scene loads**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --quit-after 2`
Expected: Window opens showing sky, light, no errors in console

- [ ] **Step 4: Commit**

```
git add scenes/main.tscn scripts/main.gd
git commit -m "feat: add main 3D scene with sky, lighting, and camera"
```

---

### Task 1.4: Create InputManager Autoload

**Files:**
- Create: `D:\AI Projects\UltraDrive\autoload\input_manager.gd`

**Interfaces:**
- Consumes: Input actions defined in `project.godot` (throttle, brake, steer_left, steer_right, handbrake, reset_car, pause, camera_mode)
- Produces: `InputManager.get_throttle() -> float` [0.0 to 1.0], `InputManager.get_steer() -> float` [-1.0 to 1.0], `InputManager.get_brake() -> float` [0.0 to 1.0], `InputManager.is_handbrake() -> bool`, `InputManager.is_reset() -> bool`, `InputManager.is_pause_just_pressed() -> bool`, `InputManager.is_camera_mode_just_pressed() -> bool`

```gdscript
# autoload/input_manager.gd
extends Node

## Provides normalized input values for vehicle control.
## Works with both PS5 controller (via DS4Windows/XInput) and keyboard.

# --- Public API ---

func get_throttle() -> float:
    ## Returns throttle input [0.0 to 1.0].
    ## Controller: right trigger (axis 7). Keyboard: W key.
    var joy_throttle := Input.get_action_strength("throttle")
    var key_throttle := Input.get_action_strength("throttle")
    return maxf(joy_throttle, key_throttle)

func get_brake() -> float:
    ## Returns brake input [0.0 to 1.0].
    ## Controller: left trigger (axis 6). Keyboard: S key.
    var joy_brake := Input.get_action_strength("brake")
    var key_brake := Input.get_action_strength("brake")
    return maxf(joy_brake, key_brake)

func get_steer() -> float:
    ## Returns steering input [-1.0 left, 0.0 center, 1.0 right].
    ## Controller: left stick X axis. Keyboard: A/D keys.
    var joy_steer := Input.get_axis("steer_left", "steer_right")
    var key_steer := Input.get_axis("steer_left", "steer_right")
    # Prioritize joystick if it has significant input
    if absf(joy_steer) > 0.1:
        return joy_steer
    return key_steer

func is_handbrake() -> bool:
    return Input.is_action_pressed("handbrake")

func is_reset() -> bool:
    return Input.is_action_just_pressed("reset_car")

func is_pause_just_pressed() -> bool:
    return Input.is_action_just_pressed("pause")

func is_camera_mode_just_pressed() -> bool:
    return Input.is_action_just_pressed("camera_mode")

func is_any_input_active() -> bool:
    ## Returns true if any vehicle input is active (useful for AI takeover).
    return get_throttle() > 0.01 or get_brake() > 0.01 or absf(get_steer()) > 0.01

func get_raw_joy_info() -> Dictionary:
    ## Debug: returns raw joystick device info.
    var joy_name := Input.get_joy_name(0)
    var joy_guid := Input.get_joy_guid(0)
    return {"name": joy_name, "guid": joy_guid, "connected": joy_name != ""}
```

- [ ] **Step 5: Add to autoloads in project.godot**

Append to `project.godot`:
```ini
[autoload]
InputManager="*res://autoload/input_manager.gd"
```

- [ ] **Step 6: Test with print statements**

Create `scripts/test_input.gd`:
```gdscript
extends Node

func _process(_delta: float) -> void:
    var t := InputManager.get_throttle()
    var b := InputManager.get_brake()
    var s := InputManager.get_steer()
    if t > 0.01 or b > 0.01 or absf(s) > 0.01:
        print("Throttle: %.2f | Brake: %.2f | Steer: %.2f" % [t, b, s])
```

Attach to a Node in main.tscn temporarily, run game, press controller triggers and WASD — verify values print and are normalized.

- [ ] **Step 7: Commit**

```
git add autoload/input_manager.gd
git commit -m "feat: add InputManager autoload with controller + keyboard support"
```

---

### Task 1.5: Configure All Autoloads and Verify Startup

**Files:**
- Modify: `D:\AI Projects\UltraDrive\project.godot` (add remaining autoloads as stubs)
- Create: `D:\AI Projects\UltraDrive\autoload\game_state.gd` (stub)
- Create: `D:\AI Projects\UltraDrive\autoload\race_manager.gd` (stub)
- Create: `D:\AI Projects\UltraDrive\autoload\vehicle_manager.gd` (stub)
- Create: `D:\AI Projects\UltraDrive\autoload\weather_manager.gd` (stub)
- Create: `D:\AI Projects\UltraDrive\autoload\save_manager.gd` (stub)

**Interfaces:**
- Consumes: `project.godot` from Task 1.1, `input_manager.gd` from Task 1.4
- Produces: All 6 autoloads registered and loadable without errors

Each stub should be a minimal Node script:
```gdscript
# Example: autoload/game_state.gd
extends Node
## Manages global game state. Full implementation in Phase 4.
func _ready() -> void:
    print("[UltraDrive] GameState loaded")
```

Create identical stubs for: `race_manager.gd`, `vehicle_manager.gd`, `weather_manager.gd`, `save_manager.gd`.

Update `project.godot` autoload section:
```ini
[autoload]
InputManager="*res://autoload/input_manager.gd"
GameState="*res://autoload/game_state.gd"
RaceManager="*res://autoload/race_manager.gd"
VehicleManager="*res://autoload/vehicle_manager.gd"
WeatherManager="*res://autoload/weather_manager.gd"
SaveManager="*res://autoload/save_manager.gd"
```

- [ ] **Step 1: Verify all autoloads load**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: Console shows "InputManager loaded", "GameState loaded", etc. — no errors.

- [ ] **Step 2: Commit**

```
git add autoload/ project.godot
git commit -m "feat: register all 6 autoload singletons (stubs for Phase 2-5)"
```

---

### Task 1.6: Create GDUnit4 Test Harness Setup

**Files:**
- Create: `D:\AI Projects\UltraDrive\addons\gdUnit4\` (downloaded GDUnit4 addon)
- Create: `D:\AI Projects\UltraDrive\tests\test_input_mapping.gd`

**Interfaces:**
- Consumes: `input_manager.gd` from Task 1.4
- Produces: Working GDUnit4 test framework + first passing test

- [ ] **Step 1: Install GDUnit4**

Download GDUnit4 from Godot Asset Library or GitHub: https://github.com/MikeSchulze/gdUnit4/releases

Extract into `D:\AI Projects\UltraDrive\addons\gdUnit4\`

Enable in `project.godot` — MERGE into the existing `[editor_plugins]` section (do NOT create a duplicate section):
```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/jolt_physics/jolt_physics.gdextension", "res://addons/gdUnit4/plugin.cfg")
```

- [ ] **Step 2: Write first test**

```gdscript
# tests/test_input_mapping.gd
extends GdUnitTestSuite

func test_throttle_returns_zero_when_no_input() -> void:
    assert_eq(InputManager.get_throttle(), 0.0)

func test_brake_returns_zero_when_no_input() -> void:
    assert_eq(InputManager.get_brake(), 0.0)

func test_steer_returns_zero_when_no_input() -> void:
    assert_eq(InputManager.get_steer(), 0.0)

func test_handbrake_returns_false_when_no_input() -> void:
    assert_eq(InputManager.is_handbrake(), false)
```

- [ ] **Step 3: Run tests**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd`
Expected: All 4 tests pass

- [ ] **Step 4: Commit**

```
git add addons/gdUnit4/ tests/
git commit -m "feat: install GDUnit4 test framework with initial input mapping tests"
```

---

### Task 1.7: Create Test Vehicle Physics Scene

**Files:**
- Create: `D:\AI Projects\UltraDrive\scenes\test\test_vehicle_physics.tscn`
- Create: `D:\AI Projects\UltraDrive\scripts\test_ground.gd`

**Interfaces:**
- Consumes: `input_manager.gd` from Task 1.4, `main.tscn` environment
- Produces: A scene with a flat ground plane + placeholder box (representing a car) that can be driven around

This scene is for testing vehicle physics in Phase 2. It should have:
- A large flat StaticBody3D ground plane (500m × 500m)
- Grid lines on the ground for visual reference
- A simple box MeshInstance3D on a RigidBody3D (placeholder car)
- The chase camera from Task 2.7 (or a temporary Camera3D)

```gdscript
# scripts/test_ground.gd
extends Node3D
## Generates a simple ground plane for vehicle physics testing.

func _ready() -> void:
    # Ground plane
    var ground := StaticBody3D.new()
    ground.name = "Ground"
    add_child(ground)

    var mesh_instance := MeshInstance3D.new()
    var plane_mesh := PlaneMesh.new()
    plane_mesh.size = Vector2(500, 500)
    plane_mesh.subdivide_width = 50
    plane_mesh.subdivide_depth = 50
    mesh_instance.mesh = plane_mesh

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.25, 0.25, 0.28)
    material.roughness = 0.8
    mesh_instance.material_override = material
    ground.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(500, 0.1, 500)
    collision.shape = shape
    collision.position.y = -0.05
    ground.add_child(collision)
```

- [ ] **Step 1: Create the scene and ground script**

Create `scenes/test/test_vehicle_physics.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/test_ground.gd" id="1_ground"]

[node name="TestVehiclePhysics" type="Node3D"]
script = ExtResource("1_ground")

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0.966, 0.259, 0, -0.259, 0.966, 0, 8, 15)
fov = 70.0
```

- [ ] **Step 2: Verify scene loads**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" scenes/test/test_vehicle_physics.tscn --quit-after 3`
Expected: Ground plane visible, no errors

- [ ] **Step 3: Commit**

```
git add scenes/test/ scripts/test_ground.gd
git commit -m "feat: add test scene with ground plane for vehicle physics development"
```

---

## Phase 2: Vehicle Physics (THE CORE)

**Goal:** A drivable car with realistic suspension, Pacejika tire grip, configurable drivetrain, and drift capability. This is the hardest and most important phase — every other system depends on this working well.

**Subagent strategy:** Each task (2.1-2.8) is dispatched to a SEPARATE agent. Tasks 2.1-2.5 are sequential (each builds on the previous). Tasks 2.6-2.7 can run in parallel after 2.5 completes.

---

### Task 2.1: CarConfig Resource Definition

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\vehicle\car_config.gd`

**Interfaces:**
- Consumes: None
- Produces: `CarConfig` Resource class with all car tuning parameters. Used by Tasks 2.2-2.5.

```gdscript
# scripts/vehicle/car_config.gd
class_name CarConfig
extends Resource

## Defines all configurable parameters for a vehicle.
## Create .tres files per car to define different vehicles.

@export var car_name: String = "starter_car"
@export var car_class: String = "D"  # D, C, B, A, S

# --- Mass & Dimensions ---
@export var mass_kg: float = 1200.0
@export var wheelbase: float = 2.5     # distance between front and rear axles (m)
@export var track_width: float = 1.6   # distance between left and right wheels (m)
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.3, 0.0)

# --- Engine ---
@export var max_torque: float = 300.0    # Nm at peak RPM
@export var peak_rpm: float = 6500.0
@export var redline_rpm: float = 7500.0
@export var idle_rpm: float = 800.0
@export var engine_brake_torque: float = 50.0  # Nm of engine braking

# --- Transmission ---
@export var gear_ratios: Array[float] = [3.5, 2.1, 1.4, 1.0, 0.75, 0.6]
@export var final_drive_ratio: float = 3.7
@export var reverse_ratio: float = 3.2
@export var shift_time: float = 0.15  # seconds to shift gears

# --- Differential ---
@export_enum("Open", "LSD", "Locked") var diff_type: int = 1
@export var lsd_preload: float = 50.0    # Nm (for LSD only)
@export var lsd_ramp_angle: float = 45.0  # degrees (for LSD only)

# --- Suspension ---
@export var spring_rate: float = 35000.0      # N/m
@export var damper_compression: float = 4000.0  # Ns/m
@export var damper_rebound: float = 5000.0    # Ns/m
@export var suspension_travel: float = 0.1    # meters (100mm)
@export var ride_height: float = 0.15         # meters
@export var anti_roll_bar: float = 10000.0    # N/m

# --- Tire (Pacejika Parameters) ---
@export var tire_B: float = 10.0   # Stiffness factor
@export var tire_C: float = 1.9    # Shape factor
@export var tire_D: float = 1.0    # Peak factor (mu)
@export var tire_E: float = 0.97   # Curvature factor
@export var tire_width: float = 0.225  # meters (for visual + grip calc)

# --- Brakes ---
@export var max_brake_torque: float = 2500.0  # Nm per wheel
@export var brake_bias: float = 0.65          # 0.0 = all rear, 1.0 = all front

# --- Steering ---
@export var max_steer_angle: float = 35.0  # degrees at low speed
@export var steer_speed: float = 3.0       # how fast steering responds (1-5)

# --- Aerodynamics ---
@export var drag_coefficient: float = 0.35
@export var frontal_area: float = 2.2  # m^2
@export var downforce_coefficient: float = 0.0  # 0 = none, higher = more downforce

# --- Drift ---
@export var handbrake_grip_reduction: float = 0.3  # 0.0 = no grip, 1.0 = full grip
@export var countersteer_assist: float = 800.0     # Nm of yaw correction

# --- Handling Mode Modifiers ---
@export var arcade_mode: Dictionary = {
    "grip_multiplier": 1.3,
    "weight_transfer_scale": 0.6,
    "anti_flip": true,
    "max_speed_modifier": 1.1,
}
@export var simulation_mode: Dictionary = {
    "grip_multiplier": 1.0,
    "weight_transfer_scale": 1.0,
    "anti_flip": false,
    "max_speed_modifier": 1.0,
}

# --- Helper Functions ---

func get_engine_torque(rpm: float) -> float:
    ## Returns engine torque at given RPM using a simplified torque curve.
    if rpm < idle_rpm:
        return max_torque * 0.5
    if rpm > redline_rpm:
        return 0.0
    # Parabolic torque curve peaking at peak_rpm
    var t := (rpm - idle_rpm) / (peak_rpm - idle_rpm)
    if t <= 1.0:
        return max_torque * (1.0 - pow(t - 1.0, 2.0))
    else:
        # Past peak, taper off
        var t2 := (rpm - peak_rpm) / (redline_rpm - peak_rpm)
        return max_torque * (1.0 - t2 * 0.8)

func get_gear_ratio(gear: int) -> float:
    ## Returns gear ratio for given gear index (0-based). Negative = reverse.
    if gear < 0:
        return reverse_ratio * final_drive_ratio
    if gear >= gear_ratios.size():
        return gear_ratios[gear_ratios.size() - 1] * final_drive_ratio
    return gear_ratios[gear] * final_drive_ratio

func get_max_speed() -> float:
    ## Approximate top speed in m/s based on highest gear ratio.
    var top_gear_ratio := gear_ratios[gear_ratios.size() - 1] * final_drive_ratio
    var wheel_radius := 0.33  # approximate
    return (peak_rpm / top_gear_ratio) * wheel_radius * TAU / 60.0
```

- [ ] **Step 1: Create car_config.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify it compiles**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No parse errors. `CarConfig` class_name is registered.

- [ ] **Step 3: Create a starter car .tres resource**

Create `resources/cars/starter_car.tres`:
```ini
[gd_resource type="Resource" script_class="CarConfig" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/vehicle/car_config.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
car_name = "Striker"
car_class = "D"
mass_kg = 1100.0
max_torque = 180.0
peak_rpm = 6000.0
redline_rpm = 7000.0
gear_ratios = Array[float]([3.2, 1.9, 1.3, 0.95, 0.72])
final_drive_ratio = 3.8
tire_B = 9.0
tire_C = 1.9
tire_D = 0.95
tire_E = 0.95
spring_rate = 30000.0
max_brake_torque = 2000.0
```

- [ ] **Step 4: Commit**

```
git add scripts/vehicle/car_config.gd resources/cars/
git commit -m "feat: add CarConfig resource with Pacejika tire params, drivetrain, suspension"
```

---

### Task 2.2: WheelPhysics — Per-Wheel Raycast Suspension

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\vehicle\wheel_physics.gd`

**Interfaces:**
- Consumes: `CarConfig` from Task 2.1
- Produces: `WheelPhysics` Node3D class. Methods: `process_wheel(delta, config, handbrake)`, `get_normal_force() -> float`, `get_suspension_length() -> float`, `get_contact_point() -> Vector3`, `is_grounded() -> bool`

```gdscript
# scripts/vehicle/wheel_physics.gd
class_name WheelPhysics
extends Node3D

## Simulates a single wheel with raycast suspension.
## Add as child of VehiclePhysics RigidBody3D.

# --- Configuration ---
@export var wheel_position: Vector3 = Vector3(0.0, -0.3, 0.5)  # local offset from car body

# --- State ---
var suspension_length: float = 0.1
var normal_force: float = 0.0
var contact_point: Vector3 = Vector3.ZERO
var is_in_contact: bool = false
var wheel_angular_velocity: float = 0.0  # rad/s
var lateral_force: float = 0.0
var longitudinal_force: float = 0.0

# --- Internal ---
var _raycast: RayCast3D
var _prev_suspension_length: float = 0.1

func _ready() -> void:
    _raycast = RayCast3D.new()
    _raycast.target_position = Vector3(0, -suspension_travel_max, 0)
    _raycast.enabled = true
    add_child(_raycast)

const suspension_travel_max := 0.5  # total raycast length for ground detection

func process_wheel(delta: float, config: CarConfig, handbrake: bool) -> Dictionary:
    ## Main wheel update. Call every physics frame.
    ## Returns: { normal_force, lateral_force, longitudinal_force, is_grounded }

    _prev_suspension_length = suspension_length

    # --- Raycast to detect ground ---
    _raycast.force_raycast_update()
    is_in_contact = _raycast.is_colliding()

    if is_in_contact:
        contact_point = _raycast.get_collision_point()
        suspension_length = (global_position - contact_point).length()

        # Clamp to max travel
        suspension_length = clampf(suspension_length, 0.0, config.suspension_travel)

        # --- Spring-Damper Suspension ---
        var spring_compression := config.suspension_travel - suspension_length
        var spring_force := config.spring_rate * spring_compression

        # Damper (velocity-dependent)
        var suspension_velocity := (_prev_suspension_length - suspension_length) / delta
        var damper_force := config.damper_compression * maxf(suspension_velocity, 0.0) \
                          + config.damper_rebound * minf(suspension_velocity, 0.0)

        normal_force = maxf(spring_force + damper_force, 0.0)
    else:
        normal_force = 0.0
        suspension_length = config.suspension_travel

    return {
        "normal_force": normal_force,
        "lateral_force": lateral_force,
        "longitudinal_force": longitudinal_force,
        "is_grounded": is_in_contact,
    }

func apply_lateral_force(force: float) -> void:
    lateral_force = force

func apply_longitudinal_force(force: float) -> void:
    longitudinal_force = force

func get_speed_along_heading(car_velocity: Vector3) -> float:
    ## Returns the component of car velocity along the wheel's forward direction.
    return global_basis.z.dot(car_velocity)
```

- [ ] **Step 1: Create wheel_physics.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `WheelPhysics` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/vehicle/wheel_physics.gd
git commit -m "feat: add WheelPhysics with raycast suspension and spring-damper model"
```

---

### Task 2.3: TireModel — Pacejika Magic Formula

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\vehicle\tire_model.gd`

**Interfaces:**
- Consumes: `CarConfig` tire parameters (B, C, D, E), `WheelPhysics.normal_force`
- Produces: `TireModel` class. Methods: `calculate_lateral_force(slip_angle, normal_force, config) -> float`, `calculate_longitudinal_force(slip_ratio, normal_force, config) -> float`

```gdscript
# scripts/vehicle/tire_model.gd
class_name TireModel
extends RefCounted

## Implements a simplified Pacejka "Magic Formula" tire model.
## F = D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
## where x = slip angle (lateral) or slip ratio (longitudinal).

static func calculate_lateral_force(
    slip_angle_rad: float,
    normal_force: float,
    config: CarConfig,
    grip_multiplier: float = 1.0
) -> float:
    ## Returns lateral tire force in Newtons.
    ## slip_angle_rad: angle between wheel heading and velocity vector (radians)
    ## normal_force: vertical load on tire (N)
    ## grip_multiplier: handling mode modifier (arcade = 1.3, sim = 1.0)

    var B := config.tire_B
    var C := config.tire_C
    var D := normal_force * config.tire_D * grip_multiplier
    var E := config.tire_E

    var x := slip_angle_rad
    var force := D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
    return force

static func calculate_longitudinal_force(
    slip_ratio: float,
    normal_force: float,
    config: CarConfig,
    grip_multiplier: float = 1.0
) -> float:
    ## Returns longitudinal tire force in Newtons.
    ## slip_ratio: (wheel_speed - road_speed) / max(wheel_speed, road_speed, 0.1)
    ## Range: -1.0 (full lock) to 1.0 (full spin)

    var B := config.tire_B * 0.8  # longitudinal is usually less stiff
    var C := config.tire_C
    var D := normal_force * config.tire_D * grip_multiplier * 0.95
    var E := config.tire_E

    var x := slip_ratio
    var force := D * sin(C * atan(B * x - E * (B * x - atan(B * x))))
    return force

static func calculate_slip_angle(
    wheel_forward: Vector3,
    wheel_velocity: Vector3
) -> float:
    ## Returns slip angle in radians.
    ## wheel_forward: the direction the wheel is pointing (world space)
    ## wheel_velocity: actual velocity of the wheel contact point

    var vel_along_wheel := wheel_forward.dot(wheel_velocity)
    var vel_perpendicular := wheel_forward.cross(wheel_velocity).length()

    # Determine sign of perpendicular velocity
    var cross := wheel_forward.cross(wheel_velocity)
    var sign := 1.0 if cross.y >= 0.0 else -1.0

    return atan2(vel_perpendicular * sign, maxf(absf(vel_along_wheel), 1.0))

static func calculate_slip_ratio(
    wheel_angular_velocity: float,
    forward_speed: float,
    wheel_radius: float = 0.33
) -> float:
    ## Returns slip ratio [-1.0, 1.0].
    ## 0 = no slip, positive = wheelspin, negative = lockup.

    var wheel_speed := wheel_angular_velocity * wheel_radius
    var denominator := maxf(maxf(absf(wheel_speed), absf(forward_speed)), 1.0)
    return clampf((wheel_speed - forward_speed) / denominator, -1.0, 1.0)

static func get_peak_slip_angle(config: CarConfig) -> float:
    ## Returns the slip angle (in degrees) at which peak grip occurs.
    ## Useful for AI and drift detection.
    return rad_to_deg(1.0 / config.tire_B) * 2.0
```

- [ ] **Step 1: Create tire_model.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `TireModel` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/vehicle/tire_model.gd
git commit -m "feat: add Pacejika-inspired TireModel with lateral/longitudinal force calculation"
```

---

### Task 2.4: Drivetrain — Engine, Transmission, Differential

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\vehicle\drivetrain.gd`

**Interfaces:**
- Consumes: `CarConfig` engine/transmission/diff params
- Produces: `Drivetrain` class. Methods: `update(delta, throttle, config) -> Dictionary`, `shift_up()`, `shift_down()`

```gdscript
# scripts/vehicle/drivetrain.gd
class_name Drivetrain
extends RefCounted

## Simulates engine, transmission, and differential.
## Call update() every physics frame.

# --- State ---
var engine_rpm: float = 800.0
var current_gear: int = 0  # 0 = 1st, -1 = reverse
var drive_torque: float = 0.0
var is_shifting: bool = false
var shift_timer: float = 0.0

# --- Internal ---
var _wheel_speed: float = 0.0  # m/s (set by VehiclePhysics)

func update(delta: float, throttle: float, config: CarConfig) -> Dictionary:
    ## Main drivetrain update.
    ## throttle: [0.0, 1.0] from InputManager
    ## Returns: { engine_rpm, current_gear, drive_torque }

    # --- Shift timer ---
    if is_shifting:
        shift_timer -= delta
        if shift_timer <= 0.0:
            is_shifting = false

    # --- Calculate engine RPM from wheel speed ---
    var gear_ratio := config.get_gear_ratio(current_gear)
    var wheel_radius := 0.33
    var rpm_from_wheels := absf(_wheel_speed) / maxf(wheel_radius, 0.01) \
                         * gear_ratio * 60.0 / TAU

    # Blend RPM with throttle response (engine spins up faster with throttle)
    var target_rpm := lerpf(config.idle_rpm, rpm_from_wheels, throttle)
    engine_rpm = move_toward(engine_rpm, target_rpm, config.peak_rpm * delta * 2.0)

    # --- Auto-clamp RPM ---
    engine_rpm = clampf(engine_rpm, config.idle_rpm * 0.8, config.redline_rpm)

    # --- Engine torque ---
    var engine_torque := config.get_engine_torque(engine_rpm) * throttle

    # --- Engine braking (when off throttle) ---
    if throttle < 0.05:
        engine_torque = -config.engine_brake_torque * (engine_rpm / config.peak_rpm)

    # --- Apply gear ratio and final drive ---
    if not is_shifting:
        drive_torque = engine_torque * absf(gear_ratio) * config.final_drive_ratio
    else:
        drive_torque = 0.0  # no torque during shift

    # --- Auto-shift (simple RPM-based) ---
    if not is_shifting and current_gear >= 0:
        if engine_rpm >= config.redline_rpm * 0.95 and current_gear < config.gear_ratios.size() - 1:
            shift_up(config)
        elif engine_rpm < config.idle_rpm * 1.2 and current_gear > 0:
            shift_down(config)

    return {
        "engine_rpm": engine_rpm,
        "current_gear": current_gear,
        "drive_torque": drive_torque,
    }

func shift_up(config: CarConfig) -> void:
    if current_gear < config.gear_ratios.size() - 1:
        current_gear += 1
        _start_shift(config)

func shift_down(config: CarConfig) -> void:
    if current_gear > -1:  # -1 = reverse
        current_gear -= 1
        _start_shift(config)

func _start_shift(config: CarConfig) -> void:
    is_shifting = true
    shift_timer = config.shift_time

func set_wheel_speed(speed: float) -> void:
    ## Called by VehiclePhysics to update wheel speed for RPM calculation.
    _wheel_speed = speed

func reset() -> void:
    engine_rpm = 800.0
    current_gear = 0
    drive_torque = 0.0
    is_shifting = false
```

- [ ] **Step 1: Create drivetrain.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `Drivetrain` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/vehicle/drivetrain.gd
git commit -m "feat: add Drivetrain with engine torque curve, transmission, and auto-shift"
```

---

### Task 2.5: VehiclePhysics — Main RigidBody3D Controller

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\vehicle\vehicle_physics.gd`

**Interfaces:**
- Consumes: `CarConfig` (Task 2.1), `WheelPhysics` (Task 2.2), `TireModel` (Task 2.3), `Drivetrain` (Task 2.4), `InputManager` (Task 1.4)
- Produces: `VehiclePhysics` RigidBody3D script. Provides `get_speed_kmh() -> float`, `get_rpm() -> float`, `get_gear() -> int`, `get_steer_angle() -> float`, `reset_car()`, `set_handling_mode(mode: String)`

```gdscript
# scripts/vehicle/vehicle_physics.gd
class_name VehiclePhysics
extends RigidBody3D

## Main vehicle physics controller.
## Attach to a RigidBody3D with 4 WheelPhysics children.

# --- Configuration ---
@export var config: CarConfig

# --- Child References (assign in scene or auto-discover) ---
@onready var wheel_fl: WheelPhysics = $WheelFL
@onready var wheel_fr: WheelPhysics = $WheelFR
@onready var wheel_rl: WheelPhysics = $WheelRL
@onready var wheel_rr: WheelPhysics = $WheelRR

# --- State ---
var current_speed_kmh: float = 0.0
var steer_angle: float = 0.0
var handling_mode: String = "arcade"  # "arcade" or "simulation"

# --- Internal ---
var _drivetrain: Drivetrain
var _wheels: Array[WheelPhysics]
var _prev_position: Vector3

func _ready() -> void:
    if config == null:
        config = load("res://resources/cars/starter_car.tres") as CarConfig

    _drivetrain = Drivetrain.new()
    _wheels = [wheel_fl, wheel_fr, wheel_rl, wheel_rr]

    # Configure RigidBody3D
    mass = config.mass_kg
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    center_of_mass = config.center_of_mass_offset
    linear_damp = 0.0  # we handle air resistance ourselves
    angular_damp = 0.5

    _prev_position = global_position

func _physics_process(delta: float) -> void:
    if config == null:
        return

    var throttle := InputManager.get_throttle()
    var brake_input := InputManager.get_brake()
    var steer_input := InputManager.get_steer()
    var handbrake := InputManager.is_handbrake()

    # --- Reset car ---
    if InputManager.is_reset():
        reset_car()
        return

    # --- Steering ---
    var speed_factor := 1.0 - clampf(current_speed_kmh / 200.0, 0.0, 0.7)
    var target_steer := deg_to_rad(config.max_steer_angle) * steer_input * speed_factor
    steer_angle = move_toward(steer_angle, target_steer, config.steer_speed * delta)

    # --- Drivetrain ---
    var forward_speed := -global_basis.z.dot(linear_velocity)
    _drivetrain.set_wheel_speed(forward_speed)
    var drive_info := _drivetrain.update(delta, throttle, config)

    # --- Tire Forces ---
    var grip_mult := config.arcade_mode["grip_multiplier"] if handling_mode == "arcade" else config.simulation_mode["grip_multiplier"]

    # Process each wheel
    for i in range(4):
        var wheel := _wheels[i]
        var wheel_info := wheel.process_wheel(delta, config, handbrake)

        if wheel_info["is_grounded"]:
            # --- Slip Angle ---
            var wheel_forward := -wheel.global_basis.z
            var wheel_vel := linear_velocity + angular_velocity.cross(wheel.global_position - global_position)
            var slip_angle := TireModel.calculate_slip_angle(wheel_forward, wheel_vel)

            # --- Lateral Force (grip) ---
            var lat_force := TireModel.calculate_lateral_force(
                slip_angle, wheel_info["normal_force"], config, grip_mult
            )

            # Handbrake reduces rear grip
            if handbrake and i >= 2:  # rear wheels
                lat_force *= config.handbrake_grip_reduction

            # --- Longitudinal Force (drive/brake) ---
            var drive_force := 0.0
            if i >= 2:  # rear wheels get drive (RWD for now)
                drive_force = drive_info["drive_torque"] / (0.33 * 2.0)

            # Braking
            var brake_force := brake_input * config.max_brake_torque / (0.33 * 2.0)
            if i < 2:  # front wheels get AC drive no drive, only brake
                drive_force = 0.0
            drive_force -= brake_force

            # --- Apply forces to RigidBody3D ---
            apply_central_force(-global_basis.z * drive_force * 0.5)
            apply_central_force(wheel.global_basis.x * lat_force * 0.5)

    # --- Air Resistance ---
    var drag_magnitude := 0.5 * 1.225 * config.drag_coefficient * config.frontal_area * linear_velocity.length_squared()
    if linear_velocity.length() > 0.1:
        apply_central_force(-linear_velocity.normalized() * drag_magnitude)

    # --- Anti-flip (arcade mode only) ---
    if handling_mode == "arcade" and config.arcade_mode.get("anti_flip", false):
        var current_up := global_basis.y
        if current_up.y < 0.8:
            var correction := Vector3.UP.cross(current_up) * 50.0
            apply_torque(correction)

    # --- Update speed ---
    current_speed_kmh = linear_velocity.length() * 3.6
    _prev_position = global_position

# --- Public API ---

func get_speed_kmh() -> float:
    return current_speed_kmh

func get_rpm() -> float:
    return _drivetrain.engine_rpm

func get_gear() -> int:
    return _drivetrain.current_gear

func get_steer_angle() -> float:
    return rad_to_deg(steer_angle)

func get_drive_info() -> Dictionary:
    return {
        "rpm": _drivetrain.engine_rpm,
        "gear": _drivetrain.current_gear,
        "speed_kmh": current_speed_kmh,
        "handling_mode": handling_mode,
    }

func set_handling_mode(mode: String) -> void:
    if mode in ["arcade", "simulation"]:
        handling_mode = mode

func reset_car() -> void:
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _drivetrain.reset()
    global_position.y += 1.0  # lift slightly above ground
```

- [ ] **Step 1: Create vehicle_physics.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `VehiclePhysics` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/vehicle/vehicle_physics.gd
git commit -m "feat: add VehiclePhysics RigidBody3D controller with suspension, tires, drivetrain"
```

---

### Task 2.6: PlayerCarController + VehicleManager Autoload

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\player\player_car_controller.gd`
- Modify: `D:\AI Projects\UltraDrive\autoload\vehicle_manager.gd` (replace stub)

**Interfaces:**
- Consumes: `VehiclePhysics` (Task 2.5), `InputManager` (Task 1.4)
- Produces: `PlayerCarController` script (attaches to player car), `VehicleManager` autoload (tracks active car)

```gdscript
# scripts/player/player_car_controller.gd
extends Node

## Controls the player's car. Attach as child of VehiclePhysics.

@onready var car: VehiclePhysics = get_parent()

func _ready() -> void:
    VehicleManager.register_player_car(car)
```

```gdscript
# autoload/vehicle_manager.gd (replaces stub)
extends Node

## Tracks the active player car and provides spawning utilities.

signal car_registered(car: VehiclePhysics)
signal car_removed(car: VehiclePhysics)

var player_car: VehiclePhysics = null
var all_cars: Array[VehiclePhysics] = []

func register_player_car(car: VehiclePhysics) -> void:
    player_car = car
    if car not in all_cars:
        all_cars.append(car)
    car_registered.emit(car)

func register_ai_car(car: VehiclePhysics) -> void:
    if car not in all_cars:
        all_cars.append(car)

func remove_car(car: VehiclePhysics) -> void:
    all_cars.erase(car)
    if car == player_car:
        player_car = null
    car_removed.emit(car)

func get_player_car() -> VehiclePhysics:
    return player_car

func get_all_cars() -> Array[VehiclePhysics]:
    return all_cars
```

- [ ] **Step 1: Create player_car_controller.gd**

Write the full file as shown above.

- [ ] **Step 2: Replace vehicle_manager.gd stub**

Replace the stub with the full implementation shown above.

- [ ] **Step 3: Create player_car.tscn scene**

```ini
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/vehicle/vehicle_physics.gd" id="1_vp"]
[ext_resource type="Script" path="res://scripts/vehicle/wheel_physics.gd" id="2_wp"]
[ext_resource type="Script" path="res://scripts/player/player_car_controller.gd" id="3_pc"]
[ext_resource type="Resource" path="res://resources/cars/starter_car.tres" id="4_config"]

[sub_resource type="BoxMesh" id="box_mesh"]
size = Vector3(1.8, 0.5, 4.0)

[sub_resource type="BoxShape3D" id="box_shape"]
size = Vector3(1.8, 0.5, 4.0)

[node name="PlayerCar" type="RigidBody3D"]
script = ExtResource("1_vp")
config = ExtResource("4_config")
mass = 1100.0

[node name="CarBody" type="MeshInstance3D" parent="."]
mesh = SubResource("box_mesh")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.3, 0)

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("box_shape")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.3, 0)

[node name="WheelFL" type="Node3D" parent="."]
script = ExtResource("2_wp")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.8, -0.3, 1.25)

[node name="WheelFR" type="Node3D" parent="."]
script = ExtResource("2_wp")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.8, -0.3, 1.25)

[node name="WheelRL" type="Node3D" parent="."]
script = ExtResource("2_wp")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.8, -0.3, -1.25)

[node name="WheelRR" type="Node3D" parent="."]
script = ExtResource("2_wp")
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.8, -0.3, -1.25)

[node name="PlayerCarController" type="Node" parent="."]
script = ExtResource("3_pc")
```

- [ ] **Step 4: Verify scene loads**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" scenes/test/test_vehicle_physics.tscn --quit-after 3`
Expected: Car spawns on ground, no errors

- [ ] **Step 5: Commit**

```
git add scripts/player/ autoload/vehicle_manager.gd scenes/vehicle/player_car.tscn
git commit -m "feat: add PlayerCarController, VehicleManager autoload, and player_car scene"
```

---

### Task 2.7: ChaseCamera

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\camera\chase_camera.gd`

**Interfaces:**
- Consumes: `VehiclePhysics` (target node)
- Produces: `ChaseCamera` script. Follows car with smooth lag, FOV changes with speed.

```gdscript
# scripts/camera/chase_camera.gd
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

    if target == null:
        target = get_parent() as Node3D

func _physics_process(delta: float) -> void:
    if target == null:
        return

    var car := target as VehiclePhysics
    var speed_kmh := 0.0
    if car:
        speed_kmh = car.get_speed_kmh()

    # --- Target position (behind and above car) ---
    var target_pos := target.global_position \
                    - target.global_basis.z * camera_distance \
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
```

- [ ] **Step 1: Create chase_camera.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `ChaseCamera` script loads.

- [ ] **Step 3: Add Camera to player_car.tscn (optional child)**

Add a `ChaseCamera` node as child of `player_car.tscn` with target set to the car body. Add a `Camera3D` to `test_vehicle_physics.tscn` if running standalone.

- [ ] **Step 4: Playtest camera**

Run the test scene, drive around — camera should smoothly follow behind the car, FOV widens at speed.

- [ ] **Step 5: Commit**

```
git add scripts/camera/chase_camera.gd
git commit -m "feat: add ChaseCamera with smooth follow and speed-based FOV"
```

---

### Task 2.8: Full Vehicle Physics Test Scene + Tests

**Files:**
- Modify: `D:\AI Projects\UltraDrive\scenes\test\test_vehicle_physics.tscn`
- Create: `D:\AI Projects\UltraDrive\tests\test_vehicle_physics.gd`

**Interfaces:**
- Consumes: All of Phase 2 (Tasks 2.1-2.7)
- Produces: A playable test scene with drivable car + passing GDUnit4 tests

- [ ] **Step 1: Update test scene to include player car**

Add `res://scenes/vehicle/player_car.tscn` instance to `test_vehicle_physics.tscn`. Position the car at (0, 2, 0) so it falls onto the ground with a slight drop.

- [ ] **Step 2: Write GDUnit4 tests**

```gdscript
# tests/test_vehicle_physics.gd
extends GdUnitTestSuite

var car_config: CarConfig

func before_test() -> void:
    car_config = CarConfig.new()

func test_car_config_default_values() -> void:
    assert_eq(car_config.car_name, "starter_car")
    assert_gt(car_config.mass_kg, 0.0)
    assert_gt(car_config.max_torque, 0.0)

func test_engine_torque_at_peak_rpm() -> void:
    var torque := car_config.get_engine_torque(car_config.peak_rpm)
    assert_eq(torque, car_config.max_torque)

func test_engine_torque_at_idle() -> void:
    var torque := car_config.get_engine_torque(car_config.idle_rpm)
    assert_gt(torque, 0.0)

func test_engine_torque_at_redline() -> void:
    var torque := car_config.get_engine_torque(car_config.redline_rpm)
    assert_eq(torque, 0.0)

func test_gear_ratio_first_gear() -> void:
    var ratio := car_config.get_gear_ratio(0)
    assert_eq(ratio, car_config.gear_ratios[0] * car_config.final_drive_ratio)

func test_gear_ratio_reverse() -> void:
    var ratio := car_config.get_gear_ratio(-1)
    assert_eq(ratio, car_config.reverse_ratio * car_config.final_drive_ratio)

func test_pacejika_returns_zero_at_zero_slip() -> void:
    var force := TireModel.calculate_lateral_force(0.0, 5000.0, car_config)
    assert_eq(force, 0.0)

func test_pacejika_force_positive_for_positive_slip() -> void:
    var force := TireModel.calculate_lateral_force(0.1, 5000.0, car_config)
    assert_gt(force, 0.0)

func test_pacejika_peak_near_configured_slip_angle() -> void:
    var peak_slip := deg_to_rad(TireModel.get_peak_slip_angle(car_config))
    var force := TireModel.calculate_lateral_force(peak_slip, 5000.0, car_config)
    assert_gt(force, 4000.0)  # should be near peak

func test_drivetrain_starts_at_idle() -> void:
    var dt := Drivetrain.new()
    assert_eq(dt.engine_rpm, 800.0)
    assert_eq(dt.current_gear, 0)
```

- [ ] **Step 3: Run tests**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd`
Expected: All 11 tests pass

- [ ] **Step 4: Playtest the test scene**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" scenes/test/test_vehicle_physics.tscn`
Expected: Drive car with WASD or controller. Steering, acceleration, braking, gear shifting, camera follow all work. Car doesn't flip or clip through ground.

- [ ] **Step 5: Commit**

```
git add scenes/test/ tests/test_vehicle_physics.gd
git commit -m "feat: complete vehicle physics test scene with 11 passing GDUnit4 tests"
```

---

## Phase 3: Track System

**Goal:** Modular road segments, checkpoints, lap counting, and a test circuit.

**Subagent strategy:** All 4 tasks (3.1-3.4) can be dispatched sequentially. Each is independent from Phase 2 except Task 3.2 (uses VehiclePhysics for collision).

---

### Task 3.1: TrackBuilder — Spline-Based Road Construction

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\track\track_builder.gd`

**Interfaces:**
- Consumes: None
- Produces: `TrackBuilder` Node3D script. Method: `build_track(points: Array[Vector3], width: float) -> void` that creates road mesh + collision.

```gdscript
# scripts/track/track_builder.gd
class_name TrackBuilder
extends Node3D

## Builds a road from a spline of points.
## Creates visual mesh + collision body for the road surface.

@export var road_width: float = 12.0
@export var road_height: float = 0.1

## Build track from array of Vector3 points (closed loop).
func build_track(points: Array[Vector3]) -> void:
    if points.size() < 3:
        return

    # Close the loop
    var closed_points := points.duplicate()
    closed_points.append(points[0])

    # Create visual mesh
    var road_mesh := _build_mesh(closed_points)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = road_mesh

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.25, 0.25, 0.27)
    material.roughness = 0.9
    mesh_instance.material_override = material
    add_child(mesh_instance)

    # Create collision body
    var body := StaticBody3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(road_width, road_height, _path_length(closed_points))
    var collision := CollisionShape3D.new()
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _build_mesh(points: Array[Vector3]) -> ArrayMesh:
    ## Builds a triangle strip mesh following the points.
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var normals := PackedVector3Array()

    # Triangle strip along the path
    for i in range(points.size()):
        var p := points[i]
        var forward := (points[min(i + 1, points.size() - 1)] - points[max(i - 1, 0)]).normalized()
        var right := forward.cross(Vector3.UP).normalized()

        vertices.append(p - right * road_width * 0.5)
        vertices.append(p + right * road_width * 0.5)

        if i < points.size() - 1:
            var base := i * 2
            indices.append(base)
            indices.append(base + 1)
            indices.append(base + 2)
            indices.append(base + 1)
            indices.append(base + 3)
            indices.append(base + 2)

        normals.append(Vector3.UP)
        normals.append(Vector3.UP)

    var mesh := ArrayMesh.new()
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = normals
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _path_length(points: Array[Vector3]) -> float:
    var total := 0.0
    for i in range(1, points.size()):
        total += points[i - 1].distance_to(points[i])
    return total
```

- [ ] **Step 1: Create track_builder.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `TrackBuilder` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/track/track_builder.gd
git commit -m "feat: add TrackBuilder with spline-based road construction (mesh + collision)"
```

---

### Task 3.2: Checkpoint System

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\track\checkpoint.gd`

**Interfaces:**
- Consumes: `VehiclePhysics` (for detection)
- Produces: `Checkpoint` class. Methods: `is_passed(vehicle) -> bool`, `reset()`. Properties: `index: int`.

```gdscript
# scripts/track/checkpoint.gd
class_name Checkpoint
extends Area3D

## A checkpoint zone that vehicles must pass through.
## Set index to order checkpoints around the track.
## Set next_checkpoints array to allow multiple valid next checkpoints (for branching tracks).

@export var index: int = 0
@export var is_start_line: bool = false

var active: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    add_to_group("checkpoints")
    collision_layer = 0
    collision_mask = 16  # layer 5 (Checkpoints)

func _on_body_entered(body: Node3D) -> void:
    if active and body is VehiclePhysics:
        active = false

func is_passed(vehicle: VehiclePhysics) -> bool:
    ## Returns true if this checkpoint detects the given vehicle passing.
    ## Called by RaceManager. Returns true once per passing (then resets active).
    if active and !(vehicle in get_overlapping_bodies()):
        return false
    return not active and (vehicle in get_overlapping_bodies())

func reset() -> void:
    active = true
```

- [ ] **Step 1: Create checkpoint.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `Checkpoint` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/track/checkpoint.gd
git commit -m "feat: add Checkpoint Area3D trigger system with index ordering and reset"
```

---

### Task 3.3: LapCounter

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\track\lap_counter.gd`

**Interfaces:**
- Consumes: `Checkpoint` signals, `VehiclePhysics`
- Produces: `LapCounter` class. Methods: `start_race(total_laps)`, `update(vehicle) -> Dictionary`, `get_current_lap() -> int`, `get_lap_time() -> float`.

```gdscript
# scripts/track/lap_counter.gd
class_name LapCounter
extends Node

## Tracks lap progress for vehicles by monitoring checkpoints.

signal lap_completed(vehicle: VehiclePhysics, lap: int, time: float)
signal race_finished(vehicle: VehiclePhysics, total_time: float)

var total_laps: int = 3
var _lap_start_time: float = 0.0
var _current_lap: int = 1
var _last_checkpoint: int = -1
var _finished: bool = false

func start_race(laps: int) -> void:
    total_laps = laps
    _current_lap = 1
    _last_checkpoint = -1
    _finished = false
    _lap_start_time = Time.get_ticks_msec() / 1000.0

func update(vehicle: VehiclePhysics, passed_checkpoint: Checkpoint) -> Dictionary:
    ## Called by RaceManager when a vehicle passes a checkpoint.
    ## Returns { lap_completed: bool, race_finished: bool }

    # Check for valid progression (allows wrap-around)
    var expected := (_last_checkpoint + 1) % _get_total_checkpoints()
    if passed_checkpoint.index == expected:
        _last_checkpoint = passed_checkpoint.index

        # If we've passed the last checkpoint, a lap is complete
        if _last_checkpoint == _get_total_checkpoints() - 1:
            _current_lap += 1
            lap_completed.emit(vehicle, _current_lap - 1, get_lap_time())
            _lap_start_time = Time.get_ticks_msec() / 1000.0

            if _current_lap > total_laps:
                _finished = true
                race_finished.emit(vehicle, get_total_time())
                return {"lap_completed": true, "race_finished": true}

    return {"lap_completed": false, "race_finished": false}

func get_current_lap() -> int:
    return _current_lap

func get_lap_time() -> float:
    return (Time.get_ticks_msec() / 1000.0) - _lap_start_time

func get_total_time() -> float:
    return (Time.get_ticks_msec() / 1000.0) - _race_start_time

var _race_start_time: float = 0.0

func _get_total_checkpoints() -> int:
    return get_tree().get_nodes_in_group("checkpoints").size()
```

- [ ] **Step 1: Create lap_counter.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `LapCounter` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/track/lap_counter.gd
git commit -m "feat: add LapCounter with checkpoint progression, lap timing, race completion"
```

---

### Task 3.4: Test Circuit + Race Flow Scene

**Files:**
- Create: `D:\AI Projects\UltraDrive\scenes\track\test_circuit.tscn`
- Modify: `D:\AI Projects\UltraDrive\scenes\test\test_track.tscn`

**Interfaces:**
- Consumes: `TrackBuilder` (3.1), `Checkpoint` (3.2), `LapCounter` (3.3), `player_car.tscn` (2.6)
- Produces: A working closed circuit with 6 checkpoints, lap timing, and the player car.

- [ ] **Step 1: Create test_circuit.tscn (oval track)**

Use TrackBuilder in a script attached to the scene root:

```gdscript
# scripts/test_circuit.gd
extends Node3D

func _ready() -> void:
    # Build an oval track
    var builder := TrackBuilder.new()
    builder.road_width = 12.0
    add_child(builder)

    var points: Array[Vector3] = []
    var radius := 60.0
    var segments := 32
    for i in range(segments):
        var angle := TAU * i / segments
        points.append(Vector3(cos(angle) * radius, 0.1, sin(angle) * radius * 0.6))
    builder.build_track(points)

    # Add checkpoints around the track
    for i in range(8):
        var angle := TAU * i / 8
        var cp := Checkpoint.new()
        cp.index = i
        cp.position = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius * 0.6)
        add_child(cp)
```

- [ ] **Step 2: Create test scene**

Create `scenes/test/test_track.tscn` that instances `test_circuit.tscn` + `player_car.tscn` + a `Camera3D`.

- [ ] **Step 3: Playtest**

Run test_track.tscn. Verify:
- Road is visible and drivable
- Car doesn't fall through road
- Checkpoints register (debug print on pass)

- [ ] **Step 4: Commit**

```
git add scenes/track/ scenes/test/test_track.tscn scripts/test_circuit.gd
git commit -m "feat: add test circuit with checkpoints and player car"
```

---

## Phase 4: Game State Management

**Goal:** Scene transitions, save/load, main menu, pause menu.

**Subagent strategy:** Tasks 4.1-4.2 sequential, then 4.3-4.4 in parallel.

---

### Task 4.1: GameState Autoload

**Files:**
- Modify: `D:\AI Projects\UltraDrive\autoload\game_state.gd` (replace stub)

**Interfaces:**
- Consumes: None
- Produces: `GameState` autoload. Methods: `change_scene(path: String)`, `pause_game()`, `resume_game()`, `is_paused -> bool`.

```gdscript
# autoload/game_state.gd
extends Node

## Manages global game state, scene transitions, and pause.

signal scene_changed(scene_path: String)
signal game_paused
signal game_resumed

enum GameMode { MAIN_MENU, FREE_ROAM, RACE, LICENSE_TEST, GARAGE }

var current_mode: GameMode = GameMode.MAIN_MENU
var is_paused: bool = false

func change_scene(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
    if current_mode != GameMode.MAIN_MENU:
        is_paused = false
    scene_changed.emit(scene_path)

func pause_game() -> void:
    if is_paused:
        return
    is_paused = true
    get_tree().paused = true
    game_paused.emit()

func resume_game() -> void:
    if not is_paused:
        return
    is_paused = false
    get_tree().paused = false
    game_resumed.emit()

func toggle_pause() -> void:
    if is_paused:
        resume_game()
    else:
        pause_game()

func set_mode(mode: GameMode) -> void:
    current_mode = mode
```

- [ ] **Step 1: Replace game_state.gd stub**

Write the full implementation shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 3: Commit**

```
git add autoload/game_state.gd
git commit -m "feat: implement GameState autoload with scene transitions and pause"
```

---

### Task 4.2: SceneTransition (Fade In/Out)

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\ui\scene_transition.gd`
- Create: `D:\AI Projects\UltraDrive\scenes\ui\scene_transition.tscn`

**Interfaces:**
- Consumes: `GameState`
- Produces: `SceneTransition` autoload-able script. Method: `fade_to_scene(scene_path: String)` which fades screen to black, changes scene, fades in.

```gdscript
# scripts/ui/scene_transition.gd
extends CanvasLayer

## Full-screen fade overlay for smooth scene transitions.

var transition_color := Color(0.0, 0.0, 0.0, 0.0)
var _transitioning := false
var _target_scene := ""

func _ready() -> void:
    layer = 100
    var rect := ColorRect.new()
    rect.name = "FadeRect"
    rect.color = transition_color
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(rect)

func flash_to_scene(scene_path: String, fade_time: float = 0.5) -> void:
    if _transitioning:
        return
    _target_scene = scene_path
    _transitioning = true
    _fade_rect().color.a = 0.0
    var tween := create_tween()
    tween.tween_property(_fade_rect(), "color:a", 1.0, fade_time)
    tween.tween_callback(_do_scene_change)
    tween.tween_property(_fade_rect(), "color:a", 0.0, fade_time)
    tween.tween_callback(func(): _transitioning = false)

func _fade_rect() -> ColorRect:
    return $FadeRect as ColorRect

func _do_scene_change() -> void:
    GameState.change_scene(_target_scene)
```

- [ ] **Step 1: Create scene_transition.gd + .tscn**

Write the script. Create the scene with the script attached.

- [ ] **Step 2: Add as autoload**

Add to `project.godot`:
```ini
[autoload]
SceneTransition="*res://scenes/ui/scene_transition.tscn"
```

Replace all `GameState.change_scene()` calls with `SceneTransition.flash_to_scene()` going forward.

- [ ] **Step 3: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 4: Commit**

```
git add scripts/ui/scene_transition.gd scenes/ui/scene_transition.tscn project.godot
git commit -m "feat: add SceneTransition fade effect for smooth scene changes"
```

---

### Task 4.3: SaveManager

**Files:**
- Modify: `D:\AI Projects\UltraDrive\autoload\save_manager.gd` (replace stub)

**Interfaces:**
- Consumes: None
- Produces: `SaveManager`. Methods: `save_game(slot: int, data: Dictionary) -> bool`, `load_game(slot: int) -> Dictionary`, `has_save(slot: int) -> bool`.

```gdscript
# autoload/save_manager.gd
extends Node

## Persists game data to user:// (mapped to AppData on Windows).

const SAVE_DIR := "user://saves"
const MAX_SLOTS := 3

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_game(slot: int, data: Dictionary) -> bool:
    if slot < 0 or slot >= MAX_SLOTS:
        return false
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    var json := JSON.stringify(data, "\t")
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(json)
    file.close()
    return true

func load_game(slot: int) -> Dictionary:
    if slot < 0 or slot >= MAX_SLOTS:
        return {}
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var json := JSON.parse_string(file.get_as_text())
    file.close()
    return json if json is Dictionary else {}

func has_save(slot: int) -> bool:
    var path := SAVE_DIR.path_join("slot_%d.json" % (slot + 1))
    return FileAccess.file_exists(path)
```

- [ ] **Step 1: Replace save_manager.gd stub**

Write the full implementation shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 3: Write GDUnit4 test**

```gdscript
# tests/test_save_manager.gd
extends GdUnitTestSuite

func test_save_and_load_roundtrip() -> void:
    var test_data := {"money": 1000, "cars": ["striker"], "license": "B"}
    var result := SaveManager.save_game(0, test_data)
    assert_true(result)
    var loaded := SaveManager.load_game(0)
    assert_eq(loaded.get("money"), 1000)
    assert_eq(loaded.get("license"), "B")

func test_load_missing_slot_returns_empty() -> void:
    var loaded := SaveManager.load_game(2)
    assert_eq(loaded, {})

func test_has_save() -> void:
    assert_true(SaveManager.has_save(0))
```

- [ ] **Step 4: Run tests**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add autoload/save_manager.gd tests/test_save_manager.gd
git commit -m "feat: implement SaveManager with JSON save/load to user://"
```

---

### Task 4.4: Main Menu + Pause Menu

**Files:**
- Create: `D:\AI Projects\UltraDrive\scenes\ui\main_menu.tscn`
- Create: `D:\AI Projects\UltraDrive\scenes\ui\pause_menu.tscn`
- Create: `D:\AI Projects\UltraDrive\scripts\ui\main_menu.gd`
- Create: `D:\AI Projects\UltraDrive\scripts\ui\pause_menu.gd`

**Interfaces:**
- Consumes: `GameState`, `SceneTransition`, `SaveManager`
- Produces: Working main menu (Play, Continue, Settings, Quit) and pause menu (Resume, Restart, Quit to Menu).

```gdscript
# scripts/ui/main_menu.gd
extends Control

func _on_play_pressed() -> void:
    SceneTransition.flash_to_scene("res://scenes/world/open_world_root.tscn")

func _on_continue_pressed() -> void:
    if SaveManager.has_save(0):
        SceneTransition.flash_to_scene("res://scenes/world/open_world_root.tscn")

func _on_settings_pressed() -> void:
    # TODO: Phase 8 settings menu
    pass

func _on_quit_pressed() -> void:
    get_tree().quit()
```

```gdscript
# scripts/ui/pause_menu.gd
extends Control

func _on_resume_pressed() -> void:
    GameState.resume_game()
    hide()

func _on_quit_to_menu_pressed() -> void:
    GameState.resume_game()
    SceneTransition.flash_to_scene("res://scenes/ui/main_menu.tscn")
```

- [ ] **Step 1: Create menu scripts**

Write both scripts shown above.

- [ ] **Step 2: Create menu scenes**

Build two simple scenes:
- `main_menu.tscn`: Control > VBoxContainer with Play, Continue, Settings, Quit buttons (connect signals to main_menu.gd)
- `pause_menu.tscn`: Control > Panel with Resume, Restart, Quit to Menu buttons (connect signals to pause_menu.gd). Add to `open_world_root.tscn` and `test_track.tscn` for pause overlay.

- [ ] **Step 3: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 4: Commit**

```
git add scenes/ui/ scripts/ui/
git commit -m "feat: add main menu and pause menu with scene transitions"
```

---

## Phase 5: Open World

**Goal:** Chunk-based streaming terrain, road network, foliage, weather system.

**Subagent strategy:** Tasks 5.1 and 5.2 are sequential (5.2 builds on 5.1's chunks). Tasks 5.3-5.4 can run after 5.2. Task 5.5 (weather) is fully independent — can run in parallel.

---

### Task 5.1: ChunkStreamer

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\world\chunk_streamer.gd`

**Interfaces:**
- Consumes: `GameState`, `VehicleManager`
- Produces: `ChunkStreamer` script. Methods: `set_player_position(pos: Vector3)`, `set_chunk_size(size: float)`, `set_load_radius(radius: int)`.

```gdscript
# scripts/world/chunk_streamer.gd
class_name ChunkStreamer
extends Node

## Streams terrain chunks in/out based on player position.
## Uses OWDB for object streaming; this manages terrain mesh chunks.

@export var chunk_size: float = 256.0
@export var load_radius: int = 2  # chunks around player to load
@export var chunk_scene: PackedScene  # scene to instance per chunk

var _loaded_chunks: Dictionary = {}  # key: "x,z", value: Node

func clear() -> void:
    for chunk in _loaded_chunks.values():
        chunk.queue_free()
    _loaded_chunks.clear()

func set_player_position(player_pos: Vector3) -> void:
    var player_chunk_x := int(floor(player_pos.x / chunk_size))
    var player_chunk_z := int(floor(player_pos.z / chunk_size))

    # Load chunks within radius
    for dx in range(-load_radius, load_radius + 1):
        for dz in range(-load_radius, load_radius + 1):
            var cx := player_chunk_x + dx
            var cz := player_chunk_z + dz
            var key := "%d,%d" % [cx, cz]
            if not _loaded_chunks.has(key):
                _load_chunk(cx, cz)

    # Unload distant chunks
    var to_remove: Array[String] = []
    for key in _loaded_chunks:
        var parts := key.split(",")
        var cx := int(parts[0])
        var cz := int(parts[1])
        if abs(cx - player_chunk_x) > load_radius + 1 or abs(cz - player_chunk_z) > load_radius + 1:
            to_remove.append(key)

    for key in to_remove:
        _loaded_chunks[key].queue_free()
        _loaded_chunks.erase(key)

func _load_chunk(cx: int, cz: int) -> void:
    var chunk: Node3D
    if chunk_scene:
        chunk = chunk_scene.instantiate()
    else:
        chunk = _create_flat_chunk()
    chunk.name = "Chunk_%d_%d" % [cx, cz]
    chunk.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
    add_child(chunk)
    _loaded_chunks["%d,%d" % [cx, cz]] = chunk

func _create_flat_chunk() -> Node3D:
    var chunk := Node3D.new()

    var mesh_instance := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(chunk_size, chunk_size)
    plane.subdivide_width = 16
    plane.subdivide_depth = 16
    mesh_instance.mesh = plane
    chunk.add_child(mesh_instance)

    var body := StaticBody3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(chunk_size, 0.1, chunk_size)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    collision.position.y = -0.05
    body.add_child(collision)
    chunk.add_child(body)

    return chunk
```

- [ ] **Step 1: Create chunk_streamer.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `ChunkStreamer` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/world/chunk_streamer.gd
git commit -m "feat: add ChunkStreamer with radius-based chunk loading/unloading"
```

---

### Task 5.2: Terrain3D Integration

**Files:**
- Install: `addons/terrain_3d/` (from GitHub)
- Create: `D:\AI Projects\UltraDrive\scenes\world\open_world_root.tscn`

**Interfaces:**
- Consumes: `ChunkStreamer` (5.1)
- Produces: Open world root scene with Terrain3D node replacing flat chunks.

- [ ] **Step 1: Download Terrain3D**

Download from: https://github.com/TokisanGames/Terrain3D (or Godot Asset Library)
Extract to `D:\AI Projects\UltraDrive\addons\terrain_3d\`
Enable plugin in project.godot.

- [ ] **Step 2: Create open_world_root.tscn**

Scene structure:
```
open_world_root.tscn
├── ChunkStreamer (with chunk_scene set to a Terrain3D chunk scene)
├── Terrain3D (main terrain node, configure LOD)
├── PlayerSpawn (Marker3D)
└── CameraRig (ChaseCamera placeholder)
```

- [ ] **Step 3: Verify scene loads with Terrain3D**

Run game, verify terrain renders and player can drive on it without falling through.

- [ ] **Step 4: Commit**

```
git add addons/terrain_3d/ scenes/world/
git commit -m "feat: integrate Terrain3D for high-performance terrain rendering"
```

---

### Task 5.3: RoadNetwork

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\world\road_network.gd`

**Interfaces:**
- Consumes: `TrackBuilder` (3.1) reuse
- Produces: `RoadNetwork` script. Methods: `add_road(points: Array[Vector3])`, `get_nearest_road_pos(pos: Vector3) -> Vector3`, `is_on_road(pos: Vector3) -> bool`.

```gdscript
# scripts/world/road_network.gd
class_name RoadNetwork
extends Node

## Manages all roads in the open world.
## Roads are simply TrackBuilders placed in the world.

var _roads: Array[Array] = []  # each: Array[Vector3] of spline points

func add_road(points: Array[Vector3], width: float = 8.0) -> void:
    var builder := TrackBuilder.new()
    builder.road_width = width
    builder.build_track(points)
    add_child(builder)
    _roads.append(points)

func get_nearest_road_pos(pos: Vector3) -> Vector3:
    var best := pos
    var best_dist := INF
    for road in _roads:
        for point in road:
            var d := point.distance_to(pos)
            if d < best_dist:
                best_dist = d
                best = point
    return best

func is_on_road(pos: Vector3, threshold: float = 6.0) -> bool:
    return pos.distance_to(get_nearest_road_pos(pos)) < threshold
```

- [ ] **Step 1: Create road_network.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `RoadNetwork` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/world/road_network.gd
git commit -m "feat: add RoadNetwork with spline roads and proximity queries"
```

---

### Task 5.4: TrafficSpawner

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\world\traffic_spawner.gd`

**Interfaces:**
- Consumes: `RoadNetwork` (5.3), `VehiclePhysics` (2.5)
- Produces: `TrafficSpawner` script. Methods: `set_vehicle_scene(scene: PackedScene)`, `update(player_pos: Vector3)`.

```gdscript
# scripts/world/traffic_spawner.gd
class_name TrafficSpawner
extends Node

## Spawns and manages traffic vehicles that follow roads.

@export var vehicle_scene: PackedScene
@export var max_traffic: int = 15
@export var spawn_radius: float = 300.0

var _traffic: Array[VehiclePhysics] = []

func update(player_pos: Vector3) -> void:
    # Remove far traffic
    for vehicle in _traffic.duplicate():
        if vehicle.global_position.distance_to(player_pos) > spawn_radius + 100:
            vehicle.queue_free()
            _traffic.erase(vehicle)

    # Spawn new traffic if under max
    if _traffic.size() < max_traffic:
        _spawn_vehicle(player_pos)

func _spawn_vehicle(player_pos: Vector3) -> void:
    if vehicle_scene == null:
        return
    var offset := Vector3(randf_range(-spawn_radius, spawn_radius), 0, randf_range(-spawn_radius, spawn_radius))
    var spawn_pos := player_pos + offset
    var vehicle := vehicle_scene.instantiate() as VehiclePhysics
    vehicle.global_position = spawn_pos
    add_child(vehicle)
    _traffic.append(vehicle)
```

- [ ] **Step 1: Create traffic_spawner.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `TrafficSpawner` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/world/traffic_spawner.gd
git commit -m "feat: add TrafficSpawner with proximity-based spawn/despawn"
```

---

### Task 5.5: WeatherManager + Day/Night

**Files:**
- Modify: `D:\AI Projects\UltraDrive\autoload\weather_manager.gd` (replace stub)

**Interfaces:**
- Consumes: None
- Produces: `WeatherManager` autoload. Methods: `set_weather(weather: int)`, `get_road_grip_factor() -> float`, `set_time_of_day(hour: float)`, `get_time_of_day() -> float`.

```gdscript
# autoload/weather_manager.gd
extends Node

## Manages weather state, day/night cycle, and road conditions.

enum Weather { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }

signal weather_changed(weather: Weather)
signal time_of_day_changed(hour: float)

var current_weather: Weather = Weather.CLEAR
var time_of_day: float = 12.0  # 0-24 hours

# Road grip multiplier per weather type
const ROAD_GRIP: Dictionary = {
    Weather.CLEAR: 1.0,
    Weather.CLOUDY: 0.98,
    Weather.RAIN: 0.8,
    Weather.STORM: 0.6,
    Weather.FOG: 0.95,
    Weather.SNOW: 0.45,
}

func set_weather(weather: Weather) -> void:
    if current_weather != weather:
        current_weather = weather
        weather_changed.emit(weather)

func get_road_grip_factor() -> float:
    return ROAD_GRIP.get(current_weather, 1.0)

func set_time_of_day(hour: float) -> void:
    time_of_day = fposmod(hour, 24.0)
    time_of_day_changed.emit(time_of_day)

func advance_time(delta_hours: float) -> void:
    set_time_of_day(time_of_day + delta_hours)

func get_computed_sun_position() -> Vector3:
    ## Returns sun direction based on time of day.
    var angle := deg_to_rad(time_of_day / 24.0 * 360.0 - 90.0)
    return Vector3(cos(angle), sin(angle), 0.3).normalized()
```

- [ ] **Step 1: Replace weather_manager.gd stub**

Write the full implementation shown above.

- [ ] **Step 2: Connect to VehiclePhysics**

In `vehicle_physics.gd`, multiply `grip_mult` by `WeatherManager.get_road_grip_factor()`.

- [ ] **Step 3: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 4: Commit**

```
git add autoload/weather_manager.gd scripts/vehicle/vehicle_physics.gd
git commit -m "feat: add WeatherManager with weather states, road grip, day/night cycle"
```

---

## Phase 6: AI & Race Systems

**Goal:** AI opponents with rubber-banding, checkpoint-based race system, drift scoring.

**Subagent strategy:** Task 6.1 (AI) and 6.2 (RaceManager) can run in parallel. Task 6.3 (drift) independent.

---

### Task 6.1: AIController with Rubber-Banding

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\ai\ai_controller.gd`
- Create: `D:\AI Projects\UltraDrive\scripts\ai\ai_rubber_banding.gd`

**Interfaces:**
- Consumes: `VehiclePhysics` (2.5), `RoadNetwork` (5.3)
- Produces: `AIController` class. Methods: `set_waypoints(points: Array[Vector3])`, `set_rubber_banding(enabled: bool)`, `get_ai_speed_multiplier() -> float`.

```gdscript
# scripts/ai/ai_controller.gd
class_name AIController
extends Node

## Drives a VehiclePhysics car along waypoints.
## Attach as sibling of VehiclePhysics.

@onready var car: VehiclePhysics = get_parent() as VehiclePhysics

var waypoints: Array[Vector3] = []
var _current_target: int = 0
var _speed_multiplier: float = 1.0

func _physics_process(delta: float) -> void:
    if car == null or waypoints.size() < 2:
        return

    # --- Follow waypoints ---
    var target := waypoints[_current_target]
    var to_target := target - car.global_position
    to_target.y = 0

    # Find direction to target relative to car
    var car_forward := -car.global_basis.z
    var steer_input := -car_forward.cross(to_target).y

    # Throttle: full unless close to target or turning hard
    var throttle := 1.0
    var turning_fraction := clampf(absf(steer_input), 0.0, 1.0)
    throttle *= (1.0 - turning_fraction * 0.7)

    # Brake when cornering hard
    var braking := 0.0
    if turning_fraction > 0.6:
        braking = turning_fraction - 0.6

    # --- Waypoint progression ---
    if to_target.length() < 8.0:
        _current_target = (_current_target + 1) % waypoints.size()

    # --- Rubber-banding via speed multiplier ---
    _apply_control(steer_input, throttle, braking, delta)

func _apply_control(steer: float, throttle: float, braking: float, delta: float) -> void:
    # Throttle/brake are scaled by rubber-banding multiplier
    var adj_throttle := throttle * _speed_multiplier
    _simulate_input(steer, adj_throttle, braking)

func _simulate_input(steer: float, throttle: float, braking: float) -> void:
    ## Drives the car by re-routing input through the physics controller.
    ## This bypasses InputManager (which is player-only).
    ## (Placeholder — Phase 6 will refactor VehiclePhysics to accept external input.)
    car.set_input_override(Vector2(steer, throttle - braking))

func set_waypoints(points: Array[Vector3]) -> void:
    waypoints = points.duplicate()
    _current_target = 0

func set_speed_multiplier(mult: float) -> void:
    _speed_multiplier = clampf(mult, 0.5, 1.5)
```

```gdscript
# scripts/ai/ai_rubber_banding.gd
class_name AIRubberBanding
extends RefCounted

## Calculates AI speed multiplier based on time gap to player.

const BASE_GAP := 2.0   # seconds
const AHEAD_MULT := 0.95  # slightly slower when ahead
const BEHIND_MULT := 1.05  # slightly faster when behind

static func calculate_speed_multiplier(time_gap_seconds: float) -> float:
    ## time_gap_seconds: positive = AI ahead of player, negative = AI behind.
    if time_gap_seconds > BASE_GAP:
        return AHEAD_MULT
    elif time_gap_seconds < -BASE_GAP:
        return BEHIND_MULT
    else:
        return 1.0  # close race, run at base pace
```

- [ ] **Step 1: Create both AI scripts**

Write both files shown above.

- [ ] **Step 2: Add input override to VehiclePhysics**

In `vehicle_physics.gd`, add:
```gdscript
var input_override: Vector2 = Vector2.ZERO  # (steer, throttle-brake)

func set_input_override(value: Vector2) -> void:
    input_override = value
```

In `_physics_process`, replace InputManager calls with:
```gdscript
var throttle := InputManager.get_throttle() if input_override == Vector2.ZERO else clampf(input_override.y, -1.0, 1.0)
var brake_input := InputManager.get_brake() if input_override == Vector2.ZERO else maxf(-input_override.y, 0.0)
var steer_input := InputManager.get_steer() if input_override == Vector2.ZERO else clampf(input_override.x, -1.0, 1.0)
```

- [ ] **Step 3: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 4: Commit**

```
git add scripts/ai/ scripts/vehicle/vehicle_physics.gd
git commit -m "feat: add AIController with waypoint following and rubber-banding"
```

---

### Task 6.2: RaceManager Autoload

**Files:**
- Modify: `D:\AI Projects\UltraDrive\autoload\race_manager.gd` (replace stub)

**Interfaces:**
- Consumes: `LapCounter` (3.3), `Checkpoint` (3.2), `VehiclePhysics` (2.5)
- Produces: `RaceManager` autoload. Methods: `start_race(cars: Array, total_laps: int)`, `update() -> Dictionary`, `get_standings() -> Array`.

```gdscript
# autoload/race_manager.gd
extends Node

## Manages the active race: checkpoints, lap timing, positions.

signal race_started
signal race_finished(standings: Array)

var is_race_active: bool = false
var total_laps: int = 3
var _participants: Array[VehiclePhysics] = []
var _lap_counters: Dictionary = {}
var _race_time: float = 0.0

func start_race(cars: Array, laps: int) -> void:
    _participants = cars
    total_laps = laps
    _lap_counters = {}
    for car in cars:
        _lap_counters[car] = LapCounter.new()
        add_child(_lap_counters[car])
        _lap_counters[car].start_race(laps)
    _race_time = 0.0
    is_race_active = true
    race_started.emit()

func finish_race() -> void:
    is_race_active = false
    var standings := get_standings()
    race_finished.emit(standings)

func get_standings() -> Array:
    ## Returns array of cars sorted by progress (lap, then checkpoint, then distance)
    var sorted := _participants.duplicate()
    sorted.sort_custom(func(a, b):
        var a_lap := _lap_counters[a].get_current_lap() if _lap_counters.has(a) else 1
        var b_lap := _lap_counters[b].get_current_lap() if _lap_counters.has(b) else 1
        return a_lap > b_lap
    )
    return sorted

func get_lap_counter(car: VehiclePhysics) -> LapCounter:
    return _lap_counters.get(car)

func _process(delta: float) -> void:
    if is_race_active:
        _race_time += delta
        # Check all participants for passed checkpoints
        var checkpoints := get_tree().get_nodes_in_group("checkpoints")
        for car in _participants:
            var counter := _lap_counters[car]
            for cp in checkpoints:
                if cp.is_passed(car):
                    var result := counter.update(car, cp)
                    if result["race_finished"]:
                        finish_race()
```

- [ ] **Step 1: Replace race_manager.gd stub**

Write the full implementation shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors.

- [ ] **Step 3: Write GDUnit4 test**

```gdscript
# tests/test_race_logic.gd
extends GdUnitTestSuite

func test_race_manager_starts_clean() -> void:
    var cars: Array[VehiclePhysics] = []
    RaceManager.start_race(cars, 3)
    assert_true(RaceManager.is_race_active)
    assert_eq(RaceManager.total_laps, 3)

func test_rubber_banding_values_valid() -> void:
    assert_eq(AIRubberBanding.calculate_speed_multiplier(5.0), 0.95)
    assert_eq(AIRubberBanding.calculate_speed_multiplier(-5.0), 1.05)
    assert_eq(AIRubberBanding.calculate_speed_multiplier(1.0), 1.0)
```

- [ ] **Step 4: Run tests**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add autoload/race_manager.gd tests/test_race_logic.gd
git commit -m "feat: implement RaceManager with checkpoint tracking and standings"
```

---

### Task 6.3: DriftScorer

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\race\drift_scorer.gd`

**Interfaces:**
- Consumes: `VehiclePhysics` (2.5)
- Produces: `DriftScorer` class. Methods: `update(delta, car, is_drifting) -> float`, `get_total_score() -> int`, `reset()`.

```gdscript
# scripts/race/drift_scorer.gd
class_name DriftScorer
extends RefCounted

## Scores drift segments based on angle, speed, and duration.

var is_drifting := false
var _drift_angle_accum: float = 0.0
var _drift_time: float = 0.0
var _total_score: int = 0
var _drift_depth := 5  # seconds of history

var _drift_history: Array[float] = []  # recent angles

func update(delta: float, slip_angle_deg: float, drifting: bool) -> float:
    ## Call every physics frame. Returns per-frame score contribution.
    if drifting:
        is_drifting = true
        _drift_time += delta
        _drift_angle_accum += slip_angle_deg

        # Track history for combo
        _drift_history.append(slip_angle_deg)
        if _drift_history.size() > _drift_depth:
            _drift_history.pop_front()

        # Score = angle * time bonus
        var angle_bonus := clampf(slip_angle_deg / 45.0, 0.0, 1.0)
        var time_bonus := 1.0 + _drift_time * 0.5
        var frame_score := angle_bonus * time_bonus * 2.0
        _total_score += int(frame_score)
        return frame_score
    else:
        # End of drift
        if is_drifting:
            is_drifting = false
            _drift_angle_accum = 0.0
            _drift_time = 0.0
            _drift_history.clear()
        return 0.0

func get_total_score() -> int:
    return _total_score

func reset() -> void:
    _total_score = 0
    _drift_time = 0.0
    _drift_angle_accum = 0.0
    _drift_history.clear()
    is_drifting = false
```

- [ ] **Step 1: Create drift_scorer.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `DriftScorer` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/race/drift_scorer.gd
git commit -m "feat: add DriftScorer with angle-speed-duration combo scoring"
```

---

## Phase 7: Career Mode

**Goal:** License tests, championships, garage system.

**Subagent strategy:** Tasks 7.1 and 7.2 are independent (can run in parallel). Task 7.3 (garage) builds on 7.1.

---

### Task 7.1: LicenseSystem

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\career\license_system.gd`

**Interfaces:**
- Consumes: `SaveManager` (4.3), `RaceManager` (6.2)
- Produces: `LicenseSystem` script. Methods: `get_license_tier() -> String`, `complete_test(tier: String, rating: String) -> void`, `get_best_rating(tier: String) -> String`.

```gdscript
# scripts/career/license_system.gd
class_name LicenseSystem
extends Node

## Tracks player's license tier and test results.

const TIERS := ["B", "A", "S", "Race", "Elite"]
const RATINGS := ["Bronze", "Silver", "Gold"]

var results: Dictionary = {}  # tier_name -> best_rating

func get_license_tier() -> String:
    ## Returns highest license tier earned. Starts at "B".
    var current := "B"
    for tier in TIERS:
        if results.has(tier):
            current = tier
        else:
            break
    return current

func complete_test(tier: String, rating: String) -> void:
    if tier not in TIERS or rating not in RATINGS:
        return
    # Keep best result
    if not results.has(tier) or _rating_rank(rating) > _rating_rank(results[tier]):
        results[tier] = rating
        save()

func get_best_rating(tier: String) -> String:
    return results.get(tier, "")

func is_car_unlocked(car_class: String) -> bool:
    var tier := get_license_tier()
    var tier_index := TIERS.find(tier)
    var class_index := ["D", "C", "B", "A", "S"].find(car_class)
    return class_index <= tier_index + 1

func _rating_rank(rating: String) -> int:
    return RATINGS.find(rating)

func save() -> void:
    var data := SaveManager.load_game(0)
    data["license_results"] = results
    SaveManager.save_game(0, data)
```

- [ ] **Step 1: Create license_system.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `LicenseSystem` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/career/license_system.gd
git commit -m "feat: add LicenseSystem with tier progression and test ratings"
```

---

### Task 7.2: Championship

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\career\championship.gd`

**Interfaces:**
- Consumes: `LicenseSystem` (7.1), `RaceManager` (6.2)
- Produces: `Championship` script. Methods: `start_championship(name: String, races: Array)`, `complete_race(position: int)`, `get_standings() -> Dictionary`.

```gdscript
# scripts/career/championship.gd
class_name Championship
extends Node

## Manages a multi-race championship with F1-style points.

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]

var name: String = ""
var races: Array = []  # Array[Dictionary] - track names and configs
var _scores: Dictionary = {}  # car_name -> points
var _current_race: int = 0

func start_championship(champ_name: String, race_list: Array) -> void:
    name = champ_name
    races = race_list
    _scores = {}
    _current_race = 0

func complete_race(position: int) -> void:
    ## Award points based on finishing position (1-indexed).
    if position >= 1 and position <= POINTS.size():
        var participant := "player"  # simplify: single-player championship
        _scores[participant] = _scores.get(participant, 0) + POINTS[position - 1]
    _current_race += 1

func get_standings() -> Dictionary:
    return _scores

func is_complete() -> bool:
    return _current_race >= races.size()

func get_next_race() -> Dictionary:
    if _current_race < races.size():
        return races[_current_race]
    return {}
```

- [ ] **Step 1: Create championship.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `Championship` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/career/championship.gd
git commit -m "feat: add Championship with F1-style points system"
```

---

### Task 7.3: Garage System

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\career\garage.gd`

**Interfaces:**
- Consumes: `SaveManager` (4.3)
- Produces: `Garage` script. Methods: `add_car(car_id: String)`, `remove_car(car_id: String)`, `get_owned_cars() -> Array`, `get_active_car() -> String`.

```gdscript
# scripts/career/garage.gd
class_name Garage
extends Node

## Manages player's car collection.

var _owned_cars: Array[String] = []
var _active_car: String = "starter_car"

func add_car(car_id: String) -> void:
    if car_id not in _owned_cars:
        _owned_cars.append(car_id)
        save()

func remove_car(car_id: String) -> void:
    _owned_cars.erase(car_id)
    if _active_car == car_id:
        _active_car = _owned_cars[0] if _owned_cars.size() > 0 else ""
    save()

func get_owned_cars() -> Array[String]:
    return _owned_cars

func set_active_car(car_id: String) -> void:
    if car_id in _owned_cars:
        _active_car = car_id
        save()

func get_active_car() -> String:
    return _active_car

func save() -> void:
    var data := SaveManager.load_game(0)
    data["owned_cars"] = _owned_cars
    data["active_car"] = _active_car
    SaveManager.save_game(0, data)

func load_data(data: Dictionary) -> void:
    if data.has("owned_cars"):
        _owned_cars.assign(data["owned_cars"])
    if data.has("active_car"):
        _active_car = data["active_car"]
```

- [ ] **Step 1: Create garage.gd**

Write the full file as shown above.

- [ ] **Step 2: Verify compilation**

Run: `"D:\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path "D:\AI Projects\UltraDrive" --quit`
Expected: No errors, `Garage` class_name registered.

- [ ] **Step 3: Commit**

```
git add scripts/career/garage.gd
git commit -m "feat: add Garage with car collection management and persistence"
```

---

## Phase 8: UI/UX

**Goal:** HUD, minimap, menus, garage interface.

**Subagent strategy:** Tasks 8.1-8.4 are all independent (can run in parallel after Phase 7).

---

### Task 8.1: HUD

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\race\race_ui.gd`
- Create: `D:\AI Projects\UltraDrive\scenes\ui\hud.tscn`

**Interfaces:**
- Consumes: `VehicleManager` (2.6), `RaceManager` (6.2)
- Produces: HUD with speedometer, tachometer, gear, position, lap timer.

```gdscript
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
    lap_label.text = "LAP %d" % (RaceManager.get_lap_counter(car).get_current_lap() if RaceManager.get_lap_counter(car) else 1)
    time_label.text = "%.3f" % (RaceManager.get_lap_counter(car).get_lap_time() if RaceManager.get_lap_counter(car) else 0.0)

func _gear_to_string(gear: int) -> String:
    if gear == -1:
        return "R"
    elif gear == 0:
        return "N"
    return str(gear + 1)
```

- [ ] **Step 1: Create race_ui.gd**

Write the full file shown above.

- [ ] **Step 2: Create hud.tscn**

Scene: CanvasLayer > Control (full rect) with 4 Labels (SpeedLabel, GearLabel, LapLabel, PositionLabel, TimeLabel) positioned along bottom of screen. Set unique_name_in_owner on each.

- [ ] **Step 3: Add HUD to test scene**

Add hud.tscn instance to `test_track.tscn`.

- [ ] **Step 4: Verify compilation + playtest**

Run game — speed, gear, lap display update in real time as you drive.

- [ ] **Step 5: Commit**

```
git add scripts/race/race_ui.gd scenes/ui/hud.tscn
git commit -m "feat: add in-race HUD with speed, gear, lap, position indicators"
```

---

### Task 8.2: Minimap

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\ui\minimap.gd`

**Interfaces:**
- Consumes: `VehicleManager` (2.6), `RoadNetwork` (5.3)
- Produces: `Minimap` script rendering a circular minimap in a Sprite2D/TextureRect.

```gdscript
# scripts/ui/minimap.gd
extends Control

## Circular minimap showing player position and direction.

@export var minimap_radius: float = 100.0
@export var zoom: float = 0.2  # world units to pixel

var _player_car: VehiclePhysics

func _ready() -> void:
    _player_car = VehicleManager.get_player_car()

func _draw() -> void:
    if _player_car == null:
        return

    var center := size / 2.0

    # Background circle
    draw_circle(center, minimap_radius, Color(0.0, 0.0, 0.0, 0.3))

    # Player arrow (triangle pointing in facing direction)
    var car_pos: Vector3 = _player_car.global_position
    var car_facing: Vector3 = -_player_car.global_basis.z
    var screen_pos := center + Vector2(car_pos.x * zoom - car_pos.x * zoom, car_pos.z * zoom - car_pos.z * zoom).rotated(0)

    # Draw player at center (rotated to world Up = screen Up)
    var up := center + Vector2(0, -minimap_radius * 0.5)
    var angle := atan2(car_facing.x, car_facing.z)
    var tip := center + Vector2(sin(angle), -cos(angle)) * 10.0
    var left := center + Vector2(sin(angle + TAU / 3), -cos(angle + TAU / 3)) * 6.0
    var right := center + Vector2(sin(angle - TAU / 3), -cos(angle - TAU / 3)) * 6.0
    draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1))

func _process(_delta: float) -> void:
    _player_car = VehicleManager.get_player_car()
    queue_redraw()
```

- [ ] **Step 1: Create minimap.gd**

Write the full file shown above.

- [ ] **Step 2: Add to HUD scene**

Add minimap control to hud.tscn positioned in corner.

- [ ] **Step 3: Playtest**

Verify minimap arrow rotates with car direction and stays centered.

- [ ] **Step 4: Commit**

```
git add scripts/ui/minimap.gd scenes/ui/hud.tscn
git commit -m "feat: add circular minimap with player position and heading"
```

---

### Task 8.3: Settings Menu

**Files:**
- Create: `D:\AI Projects\UltraDrive\scenes\ui\settings_menu.tscn`
- Create: `D:\AI Projects\UltraDrive\scripts\ui\settings_menu.gd`

**Interfaces:**
- Consumes: None
- Produces: Settings menu with video quality, audio volume, and control remapping (basic).

```gdscript
# scripts/ui/settings_menu.gd
extends Control

## Settings menu: video quality, audio, controls.

@onready var quality_option: OptionButton = %QualityOption
@onready var volume_slider: HSlider = %VolumeSlider

const QUALITY_PRESETS := {
    0: {"msaa": 0, "ssao": false, "glow": false},  # Low
    1: {"msaa": 2, "ssao": false, "glow": true},  # Medium
    2: {"msaa": 4, "ssao": true, "glow": true},   # High
}

func _ready() -> void:
    quality_option.item_selected.connect(_on_quality_selected)
    volume_slider.value_changed.connect(_on_volume_changed)

func _on_quality_selected(index: int) -> void:
    var preset := QUALITY_PRESETS.get(index, QUALITY_PRESETS[1])
    get_viewport().world_environment.ssao_enabled = preset["ssao"]
    get_viewport().world_environment.glow_enabled = preset["glow"]
    # MSAA set via rendering settings (applied on restart or godot setting change)

func _on_volume_changed(value: float) -> void:
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
```

- [ ] **Step 1: Create settings script + scene**

Write the script. Create the scene with OptionButton (Low/Medium/High) and HSlider for volume.

- [ ] **Step 2: Link from main menu**

Add a Settings button to main_menu.tscn linking to settings scene.

- [ ] **Step 3: Verify + commit**

```
git add scripts/ui/settings_menu.gd scenes/ui/settings_menu.tscn
git commit -m "feat: add settings menu with quality presets and volume control"
```

---

### Task 8.4: Garage UI

**Files:**
- Create: `D:\AI Projects\UltraDrive\scripts\ui\garage_ui.gd`
- Create: `D:\AI Projects\UltraDrive\scenes\ui\garage.tscn`

**Interfaces:**
- Consumes: `Garage` (7.3), `CarConfig` (2.1)
- Produces: Garage UI to view owned cars, select active car, show car stats.

```gdscript
# scripts/ui/garage_ui.gd
extends Control

## Garage UI: view cars, select active car, see stats.

@onready var car_list: ItemList = %CarList
@onready var car_name_label: Label = %CarNameLabel
@onready var stats_label: Label = %StatsLabel
@onready var select_button: Button = %SelectButton

var _garage: Garage
var _selected_car: String = ""

func _ready() -> void:
    _garage = Garage.new()  # or autoload in Phase 7
    _load_car_list()

func _load_car_list() -> void:
    car_list.clear()
    for car_id in _garage.get_owned_cars():
        car_list.add_item(car_id)
    if car_list.item_count > 0:
        car_list.select(0)
        _on_car_selected(0)

func _on_car_selected(index: int) -> void:
    _selected_car = car_list.get_item_text(index)
    var config := load("res://resources/cars/%s.tres" % _selected_car) as CarConfig
    if config:
        car_name_label.text = config.car_name
        stats_label.text = "Mass: %d kg\nTorque: %d Nm\nClass: %s" % [config.mass_kg, config.max_torque, config.car_class]

func _on_select_pressed() -> void:
    if _selected_car != "":
        _garage.set_active_car(_selected_car)
```

- [ ] **Step 1: Create garage_ui.gd + garage.tscn**

Write the script. Create the scene with ItemList, Labels, and Select button.

- [ ] **Step 2: Verify + commit**

```
git add scripts/ui/garage_ui.gd scenes/ui/garage.tscn
git commit -m "feat: add garage UI for car selection and stats viewing"
```

---

## Testing Strategy

### Per-Phase Testing Summary
| Phase | Test Method | Expected Result |
|-------|------------|-----------------|
| 1 | Manual + GDUnit4 | Scenes load, no errors, 4 input tests pass |
| 2 | GDUnit4 + Playtest | 11 vehicle physics tests pass, car drives well |
| 3 | Manual playtest | Track drivable, checkpoints register, laps count |
| 4 | Manual test | Save/load works, menus navigate, pause works |
| 5 | Manual test | Chunks load/unload, terrain visible, roads drivable |
| 6 | GDUnit4 + Playtest | AI follows track, rubber-banding works, drift scores |
| 7 | GDUnit4 + Manual | License progression, championship points, garage save |
| 8 | Manual playtest | HUD updates, minimap rotates, menus open, garage works |

### Running All Tests
```bash
"D:\Godot\Godot_v4.7.2-stable_win64.exe" --path "D:\AI Projects\UltraDrive" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd
```

### Global Test Files
```
tests/
├── test_input_mapping.gd     (Phase 1: 4 tests)
├── test_vehicle_physics.gd   (Phase 2: 11 tests)
├── test_save_manager.gd      (Phase 4: 3 tests)
├── test_race_logic.gd        (Phase 6: 2 tests)
└── (future) test_track_logic.gd, test_ai_controller.gd, test_career.gd
```

---

## Complete Task List (38 tasks)

### Phase 1: Project Foundation (7 tasks)
- [ ] Task 1.1: Create Godot 4.7 project with Jolt config — `project.godot`
- [ ] Task 1.2: Install Jolt Physics GDExtension — `addons/jolt_physics/`
- [ ] Task 1.3: Create main 3D scene with lighting — `scenes/main.tscn`
- [ ] Task 1.4: Create InputManager autoload — `autoload/input_manager.gd`
- [ ] Task 1.5: Configure all autoloads (stubs) — `autoload/*.gd`
- [ ] Task 1.6: Install GDUnit4 test framework — `addons/gdUnit4/`
- [ ] Task 1.7: Create test vehicle physics scene — `scenes/test/test_vehicle_physics.tscn`

### Phase 2: Vehicle Physics (8 tasks)
- [ ] Task 2.1: CarConfig Resource — `scripts/vehicle/car_config.gd`
- [ ] Task 2.2: WheelPhysics (raycast suspension) — `scripts/vehicle/wheel_physics.gd`
- [ ] Task 2.3: TireModel (Pacejika) — `scripts/vehicle/tire_model.gd`
- [ ] Task 2.4: Drivetrain (engine/transmission) — `scripts/vehicle/drivetrain.gd`
- [ ] Task 2.5: VehiclePhysics (main controller) — `scripts/vehicle/vehicle_physics.gd`
- [ ] Task 2.6: PlayerCarController + VehicleManager — `scripts/player/`, `autoload/vehicle_manager.gd`
- [ ] Task 2.7: ChaseCamera — `scripts/camera/chase_camera.gd`
- [ ] Task 2.8: Full test scene + 11 GDUnit4 tests

### Phase 3: Track System (4 tasks)
- [ ] Task 3.1: TrackBuilder (spline roads) — `scripts/track/track_builder.gd`
- [ ] Task 3.2: Checkpoint system — `scripts/track/checkpoint.gd`
- [ ] Task 3.3: Lap counter — `scripts/track/lap_counter.gd`
- [ ] Task 3.4: Test circuit scene — `scenes/track/test_circuit.tscn`

### Phase 4: Game State (4 tasks)
- [ ] Task 4.1: GameState autoload — `autoload/game_state.gd`
- [ ] Task 4.2: Scene transitions — `scripts/ui/scene_transition.gd`
- [ ] Task 4.3: SaveManager — `autoload/save_manager.gd`
- [ ] Task 4.4: Main menu + pause menu — `scenes/ui/`

### Phase 5: Open World (5 tasks)
- [ ] Task 5.1: ChunkStreamer — `scripts/world/chunk_streamer.gd`
- [ ] Task 5.2: Terrain3D setup — `addons/terrain_3d/`
- [ ] Task 5.3: RoadNetwork — `scripts/world/road_network.gd`
- [ ] Task 5.4: TrafficSpawner — `scripts/world/traffic_spawner.gd`
- [ ] Task 5.5: WeatherManager + day/night — `autoload/weather_manager.gd`

### Phase 6: AI & Race (3 tasks)
- [ ] Task 6.1: AIController + rubber-banding — `scripts/ai/`
- [ ] Task 6.2: RaceManager — `autoload/race_manager.gd`
- [ ] Task 6.3: DriftScorer — `scripts/race/drift_scorer.gd`

### Phase 7: Career (3 tasks)
- [ ] Task 7.1: LicenseSystem — `scripts/career/license_system.gd`
- [ ] Task 7.2: Championship — `scripts/career/championship.gd`
- [ ] Task 7.3: Garage — `scripts/career/garage.gd`

### Phase 8: UI/UX (4 tasks)
- [ ] Task 8.1: HUD — `scenes/ui/hud.tscn`
- [ ] Task 8.2: Minimap — `scripts/ui/minimap.gd`
- [ ] Task 8.3: Settings menu — `scenes/ui/settings_menu.tscn`
- [ ] Task 8.4: Garage UI — `scenes/ui/garage.tscn`

---

## Recommended Execution Sequence

```
Phase 1 (Tasks 1.1-1.7)     ──► PLAYTEST CHECKPOINT 1 (drive not required yet)
        ↓
Phase 2 (Tasks 2.1-2.8)     ──► PLAYTEST CHECKPOINT 2 (car must feel good!)
        ↓
Phase 3 (Tasks 3.1-3.4)     ──► PLAYTEST CHECKPOINT 3 (drive on a real track)
        ↓
Phase 4 (Tasks 4.1-4.4)     ──► PLAYTEST CHECKPOINT 4 (menu + save system)
        ↓
Phase 5 (Tasks 5.1-5.5)     ──► PLAYTEST CHECKPOINT 5 (open world!)
        ↓
Phase 6 (Tasks 6.1-6.3)     ──► PLAYTEST CHECKPOINT 6 (race AI opponents)
        ↓
Phase 7 (Tasks 7.1-7.3)     ──► PLAYTEST CHECKPOINT 7 (career progression)
        ↓
Phase 8 (Tasks 8.1-8.4)     ──► FINAL POLISH + PLAYTEST
```

Each playtest checkpoint is a moment where you (the human) should create a build, drive it yourself, and give feedback before the next phase starts. This keeps the game playable at every stage.

---