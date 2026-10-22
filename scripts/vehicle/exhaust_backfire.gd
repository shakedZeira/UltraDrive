class_name ExhaustBackfire
extends Node3D

## Visible exhaust backfire: every "pop / bang" the engine audio fires produces
## a short, bright flame burst from the car's exhaust tips, a few embers and a
## brief OmniLight3D flash.
##
## Presentation-only and fully pooled: all flames / embers / the light are built
## once (flame + ember meshes share ONE additive material each, per-instance
## state travels through instance uniforms) and recycled; a pop never allocates.
## Everything is parented to this node, which is a child of the car, so it is
## freed with the car and holds no reference to any camera (the ember billboard
## is done in the vertex shader), so camera switches cannot leak or clip it.
##
## HOOK (no edit to EngineAudio needed):
##   1. If the sibling EngineAudio exposes `signal exhaust_pop(loudness, count,
##      window)` it is connected and used (preferred, see docs note in the
##      handover: one emit per pop burst).
##   2. Otherwise the rising edge of EngineAudio's child AudioStreamPlayer3D
##      "ExhaustPop" (`playing` false -> true) is polled once per frame; the
##      burst size/window/loudness are derived from the same CarConfig + the
##      player's own volume / stream length, so the flames track the audio.
## Anything else (shift-cut, launch crackle) can call trigger_pop() /
## trigger_burst() directly.
##
## Tip positions (car-local, +Z is rearward), in priority order:
##   a. Node3D / Marker3D descendants whose name starts with "ExhaustTip"
##      (their local +Z axis is the flame direction),
##   b. the vertex clusters of a MeshInstance3D named like "Exhaust_Tips"
##      (the R35 ships all four quad tips in that single mesh),
##   c. a symmetric pair derived from the CarConfig wheelbase.

const MAX_TIPS: int = 6
const FLAMES_PER_TIP: int = 2
const MAX_FLAMES: int = MAX_TIPS * FLAMES_PER_TIP
const MAX_EMBERS: int = 14
const MAX_PENDING: int = 32
const EMBER_LIFE: float = 0.55
const EMBER_GRAVITY: float = 9.0
const FLAME_DURATION_MIN: float = 0.06
const FLAME_DURATION_MAX: float = 0.15
const FLAME_LENGTH_MIN: float = 0.3
const FLAME_LENGTH_MAX: float = 1.0
const LIGHT_BASE_ENERGY: float = 1.6
const LIGHT_RANGE: float = 4.5
const ENGINE_OFF_RPM: float = 60.0
## Loudness reference: EngineAudio's default -6 dB trim plays at 1.0.
const AUDIO_REF_DB: float = 6.0
const TIP_WELD_MM: float = 1000.0

const FLAME_SHADER: Shader = preload("res://shaders/exhaust_flame.gdshader")
const EMBER_SHADER: Shader = preload("res://shaders/exhaust_ember.gdshader")

## -1 = ask the car (drive info rpm), 0 = force off, 1 = force on. Tests use it.
var engine_state_override: int = -1

var _tips: PackedVector3Array = PackedVector3Array()
var _tip_dirs: PackedVector3Array = PackedVector3Array()
var _tip_source_id: int = 0
var _tips_scanned: bool = false

var _pool_built: bool = false
var _flames: Array[MeshInstance3D] = []
var _flame_age: PackedFloat32Array = PackedFloat32Array()
var _flame_dur: PackedFloat32Array = PackedFloat32Array()
var _flame_energy: PackedFloat32Array = PackedFloat32Array()
var _flame_tip: PackedInt32Array = PackedInt32Array()
var _embers: Array[MeshInstance3D] = []
var _ember_age: PackedFloat32Array = PackedFloat32Array()
var _ember_vel: PackedVector3Array = PackedVector3Array()
var _light: OmniLight3D = null
var _flame_material: ShaderMaterial = null
var _ember_material: ShaderMaterial = null

## Scheduled pops of a burst: parallel arrays (fire_at seconds from now, loudness).
var _pending_t: PackedFloat32Array = PackedFloat32Array()
var _pending_l: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_ember: int = 0

var _audio: Node = null
var _signal_connected: bool = false
var _prev_pop_playing: bool = false
var _pops_fired: int = 0


func _ready() -> void:
	_rng.seed = 90210
	if DisplayServer.get_name() != "headless":
		_ensure_pool()
	call_deferred("_bind_audio")


func _exit_tree() -> void:
	if _signal_connected and _audio != null and is_instance_valid(_audio):
		if _audio.is_connected("exhaust_pop", _on_audio_pop):
			_audio.disconnect("exhaust_pop", _on_audio_pop)
	_signal_connected = false
	_audio = null


## --- Public API -------------------------------------------------------------

## True when the engine is running (drive-info rpm above the stall floor).
func engine_running() -> bool:
	if engine_state_override >= 0:
		return engine_state_override == 1
	var car := get_parent()
	if car != null and car.has_method("get_drive_info"):
		var info: Dictionary = car.call("get_drive_info")
		return float(info.get("rpm", 0.0)) > ENGINE_OFF_RPM
	return true


## Fires one pop NOW at the given loudness (0..1+). `tip_index` < 0 picks the
## tips by loudness (loud pops light every tip, soft ones one or two). Returns
## the number of flames spawned (0 when the engine is off or silent).
func trigger_pop(loudness: float, tip_index: int = -1) -> int:
	if loudness <= 0.02 or not engine_running():
		return 0
	_refresh_tips()
	if _tips.is_empty():
		return 0
	_ensure_pool()
	var l := clampf(loudness, 0.0, 1.5)
	var spawned := 0
	for tip in _pick_tips(l, tip_index):
		spawn_flame(tip, l)
		spawned += 1
	_spawn_embers(l)
	_pops_fired += 1
	set_process(true)
	return spawned


## Schedules `count` pops spread over `window` seconds with a decaying loudness
## envelope (matches the audio burst, which decays as (1 - t/window)^0.8). The
## first pop fires immediately.
func trigger_burst(loudness: float, count: int, window: float) -> void:
	if loudness <= 0.02 or count <= 0 or not engine_running():
		return
	var w := maxf(window, 0.05)
	var gap := w / float(count)
	var t := 0.0
	for i in range(count):
		if i > 0:
			t += gap * (0.45 + 1.1 * _rng.randf())
		if t >= w:
			break
		var env := pow(maxf(1.0 - t / w, 0.0), 0.8)
		var amp := 0.7 + 0.3 * _rng.randf()
		_queue_pop(t, loudness * env * amp)
	set_process(true)


## Spawns one flame on `tip` (index into tip_positions()). Pooled: recycles a
## finished slot, else steals the oldest one. Returns the slot index.
func spawn_flame(tip: int, loudness: float) -> int:
	_refresh_tips()
	_ensure_pool()
	if tip < 0 or tip >= _tips.size():
		return -1
	var slot := _free_flame_slot(tip)
	var l := clampf(loudness, 0.0, 1.5)
	var len_m: float = lerpf(FLAME_LENGTH_MIN, FLAME_LENGTH_MAX, clampf(l, 0.0, 1.0)) * _rng.randf_range(0.8, 1.15)
	var wid_m: float = lerpf(0.13, 0.24, clampf(l, 0.0, 1.0)) * _rng.randf_range(0.9, 1.1)
	var dur: float = lerpf(FLAME_DURATION_MIN, FLAME_DURATION_MAX, clampf(l, 0.0, 1.0)) * _rng.randf_range(0.85, 1.1)
	var dir := _tip_dirs[tip]
	# Small random cone around the pipe axis so repeat pops do not stack.
	var jitter := Vector3(_rng.randf_range(-0.07, 0.07), _rng.randf_range(-0.09, 0.03), 0.0)
	var flame_basis := Basis.looking_at(-(dir + jitter).normalized(), Vector3.UP)
	flame_basis = flame_basis * Basis.from_scale(Vector3(wid_m, wid_m, len_m))
	var mi := _flames[slot]
	mi.transform = Transform3D(flame_basis, _tips[tip] + dir * 0.02)
	mi.visible = true
	mi.set_instance_shader_parameter("life", 0.0)
	mi.set_instance_shader_parameter("energy", 1.6 + 1.2 * clampf(l, 0.0, 1.0))
	mi.set_instance_shader_parameter("seed", _rng.randf() * 40.0)
	_flame_age[slot] = 0.0
	_flame_dur[slot] = dur
	_flame_energy[slot] = clampf(l, 0.0, 1.0)
	_flame_tip[slot] = tip
	return slot


func tip_positions() -> PackedVector3Array:
	_refresh_tips()
	return _tips


func tip_count() -> int:
	_refresh_tips()
	return _tips.size()


func active_flame_count() -> int:
	var n := 0
	for i in range(_flames.size()):
		if _flames[i].visible:
			n += 1
	return n


## Car-local positions of the flames' bases (pipe mouth) that are alive.
func active_flame_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(_flames.size()):
		if _flames[i].visible:
			out.append(_flames[i].position)
	return out


func active_ember_count() -> int:
	var n := 0
	for e in _embers:
		if e.visible:
			n += 1
	return n


func pool_flame_count() -> int:
	return _flames.size()


func pool_ember_count() -> int:
	return _embers.size()


func pending_count() -> int:
	return _pending_t.size()


func pops_fired() -> int:
	return _pops_fired


func light_node() -> OmniLight3D:
	return _light


## --- Per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_audio()
	if not engine_running():
		_clear_pending()
	_advance_pending(delta)
	_advance_flames(delta)
	_advance_embers(delta)
	_update_light()
	if _pending_t.is_empty() and active_flame_count() == 0 and active_ember_count() == 0 and _signal_connected:
		set_process(false)


func _advance_pending(delta: float) -> void:
	var i := 0
	while i < _pending_t.size():
		_pending_t[i] -= delta
		if _pending_t[i] <= 0.0:
			var l := _pending_l[i]
			_pending_t.remove_at(i)
			_pending_l.remove_at(i)
			trigger_pop(l)
		else:
			i += 1


func _advance_flames(delta: float) -> void:
	for i in range(_flames.size()):
		var mi := _flames[i]
		if not mi.visible:
			continue
		_flame_age[i] += delta
		var life := _flame_age[i] / maxf(_flame_dur[i], 0.001)
		if life >= 1.0:
			mi.visible = false
			continue
		mi.set_instance_shader_parameter("life", life)


func _advance_embers(delta: float) -> void:
	for i in range(_embers.size()):
		var e := _embers[i]
		if not e.visible:
			continue
		_ember_age[i] += delta
		var t := _ember_age[i] / EMBER_LIFE
		if t >= 1.0:
			e.visible = false
			continue
		_ember_vel[i].y -= EMBER_GRAVITY * delta
		e.global_position += _ember_vel[i] * delta
		e.set_instance_shader_parameter("fade", pow(1.0 - t, 1.5))


func _update_light() -> void:
	if _light == null:
		return
	var best := 0.0
	var centre := Vector3.ZERO
	var n := 0
	for i in range(_flames.size()):
		if not _flames[i].visible:
			continue
		var life := _flame_age[i] / maxf(_flame_dur[i], 0.001)
		var e: float = _flame_energy[i] * pow(maxf(1.0 - life, 0.0), 1.5)
		best = maxf(best, e)
		centre += _flames[i].position
		n += 1
	if n == 0 or best <= 0.01:
		_light.visible = false
		return
	centre /= float(n)
	_light.visible = true
	_light.position = centre + Vector3(0.0, 0.05, 0.45)
	_light.light_energy = LIGHT_BASE_ENERGY * (0.4 + 0.6 * best) * best


## --- Audio hook ------------------------------------------------------------

func _bind_audio() -> void:
	var car := get_parent()
	if car == null:
		return
	for child in car.get_children():
		if child is EngineAudio:
			_audio = child
			break
	if _audio != null and _audio.has_signal("exhaust_pop"):
		_audio.connect("exhaust_pop", _on_audio_pop)
		_signal_connected = true


## Signal handler tolerant of the signal's exact arity (defaults fill the rest).
func _on_audio_pop(loudness: float = 1.0, count: int = 1, window: float = 0.0) -> void:
	if count <= 1 and window <= 0.0:
		trigger_pop(loudness)
	else:
		trigger_burst(loudness, count, window)


func _poll_audio() -> void:
	if _signal_connected:
		return
	if _audio == null or not is_instance_valid(_audio):
		_bind_audio()
		if _audio == null:
			return
	var player := _audio.get_node_or_null("ExhaustPop") as AudioStreamPlayer3D
	if player == null:
		return
	var playing := player.playing
	if playing and not _prev_pop_playing:
		_on_pop_player_started(player)
	_prev_pop_playing = playing


func _on_pop_player_started(player: AudioStreamPlayer3D) -> void:
	var cfg: CarConfig = null
	var car := get_parent()
	if car != null:
		cfg = car.get("config") as CarConfig
	var style := "crackle"
	var intensity := 1.0
	if cfg != null:
		style = cfg.exhaust_pop_style
		intensity = cfg.exhaust_pop_intensity
	var count := EngineAudio.pop_count_for(style, intensity)
	var window := 0.9
	var stream := player.stream as AudioStreamWAV
	if stream != null:
		window = stream.get_length() / maxf(player.pitch_scale, 0.1)
	var loudness := clampf(db_to_linear(player.volume_db + AUDIO_REF_DB), 0.25, 1.0) * style_size(style)
	trigger_burst(loudness, count, window)


## Visual size multiplier per pop style (bangs are the big ones).
static func style_size(style: String) -> float:
	match style:
		"bang":
			return 1.0
		"burble":
			return 0.6
		_:
			return 0.8


## --- Tips ------------------------------------------------------------------

func _refresh_tips() -> void:
	var src := _tip_source_node()
	var sid := src.get_instance_id() if src != null else 0
	if _tips_scanned and sid == _tip_source_id:
		return
	_tip_source_id = sid
	_tips_scanned = true
	_tips = PackedVector3Array()
	_tip_dirs = PackedVector3Array()
	var car := get_parent() as Node3D
	var root: Node = car if car != null else self
	if car != null and _scan_markers(root, car):
		return
	if car != null and _scan_tip_meshes(root, car):
		return
	_fallback_tips(car)


## The node whose identity changes when the car's visual is swapped (garage /
## controller _apply_visual replaces the CarBody children).
func _tip_source_node() -> Node:
	var car := get_parent()
	if car == null:
		return null
	var body := car.get_node_or_null("CarBody")
	if body == null:
		return null
	for child in body.get_children():
		if not (child is BodyRig):
			return child
	return null


func _scan_markers(root: Node, car: Node3D) -> bool:
	var found: Array[Node3D] = []
	for n in root.find_children("ExhaustTip*", "Node3D", true, false):
		found.append(n as Node3D)
	if found.is_empty():
		return false
	var inv := car.global_transform.affine_inverse()
	for n in found:
		if _tips.size() >= MAX_TIPS:
			break
		var rel := inv * n.global_transform
		_tips.append(rel.origin)
		_tip_dirs.append(rel.basis.z.normalized())
	return not _tips.is_empty()


func _scan_tip_meshes(root: Node, car: Node3D) -> bool:
	var inv := car.global_transform.affine_inverse()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var lname := mi.name.to_lower()
		if not (lname.contains("exhaust") and lname.contains("tip")):
			continue
		if mi.mesh == null:
			continue
		var found := cluster_tips(mi.mesh, inv * mi.global_transform)
		for t in found:
			if _tips.size() >= MAX_TIPS:
				break
			_tips.append(t)
			_tip_dirs.append(Vector3(0.0, 0.0, 1.0))
	return not _tips.is_empty()


func _fallback_tips(car: Node3D) -> void:
	var wheelbase := 2.5
	if car != null:
		var cfg := car.get("config") as CarConfig
		if cfg != null:
			wheelbase = cfg.wheelbase
	var z := wheelbase * 0.5 + 0.55
	for sgn in [-1.0, 1.0]:
		_tips.append(Vector3(0.42 * sgn, 0.3, z))
		_tip_dirs.append(Vector3(0.0, 0.0, 1.0))


## Splits a tip mesh into its separate tubes (welded-vertex connected components
## over the triangle list) and returns each tube's rear-end centre in `xform`'s
## space (rear = +Z). Static + pure so it is unit-testable on a hand-built mesh.
static func cluster_tips(mesh: Mesh, xform: Transform3D) -> PackedVector3Array:
	var parent_of: Dictionary = {}
	var pos_of: Dictionary = {}
	var weld: Dictionary = {}
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		else:
			for i in range(verts.size()):
				idx.append(i)
		var ids := PackedInt32Array()
		ids.resize(verts.size())
		for v in range(verts.size()):
			var p := xform * verts[v]
			var key := Vector3i(roundi(p.x * TIP_WELD_MM), roundi(p.y * TIP_WELD_MM), roundi(p.z * TIP_WELD_MM))
			if not weld.has(key):
				weld[key] = weld.size()
				parent_of[weld[key]] = weld[key]
				pos_of[weld[key]] = p
			ids[v] = weld[key]
		var t := 0
		while t + 2 < idx.size():
			_union(parent_of, ids[idx[t]], ids[idx[t + 1]])
			_union(parent_of, ids[idx[t]], ids[idx[t + 2]])
			t += 3
	var groups: Dictionary = {}
	for id in parent_of.keys():
		var r := _find(parent_of, id)
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(pos_of[id])
	var tips: Array[Vector3] = []
	for g in groups.values():
		var pts: Array = g
		if pts.size() < 8:
			continue
		var zmax := -INF
		for p in pts:
			zmax = maxf(zmax, (p as Vector3).z)
		var sum := Vector3.ZERO
		var n := 0
		for p in pts:
			if (p as Vector3).z >= zmax - 0.02:
				sum += p
				n += 1
		var c := sum / float(maxi(n, 1))
		c.z = zmax
		tips.append(c)
	tips.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var out := PackedVector3Array()
	for t in tips:
		out.append(t)
	return out


static func _find(parent_of: Dictionary, a: int) -> int:
	var r := a
	while int(parent_of[r]) != r:
		r = int(parent_of[r])
	var cur := a
	while int(parent_of[cur]) != r:
		var nxt := int(parent_of[cur])
		parent_of[cur] = r
		cur = nxt
	return r


static func _union(parent_of: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent_of, a)
	var rb := _find(parent_of, b)
	if ra != rb:
		parent_of[ra] = rb


## Which tips a pop of this loudness lights. Pure besides the RNG draw.
func _pick_tips(loudness: float, tip_index: int) -> Array[int]:
	var out: Array[int] = []
	var n := _tips.size()
	if tip_index >= 0:
		if tip_index < n:
			out.append(tip_index)
		return out
	if loudness >= 0.85 or n <= 1:
		for i in range(n):
			out.append(i)
		return out
	var want := clampi(int(ceil(float(n) * loudness)), 1, n)
	var order: Array[int] = []
	for i in range(n):
		order.append(i)
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in range(want):
		out.append(order[i])
	return out


## --- Pool ------------------------------------------------------------------

func _queue_pop(t: float, loudness: float) -> void:
	if _pending_t.size() >= MAX_PENDING:
		return
	_pending_t.append(t)
	_pending_l.append(loudness)


func _clear_pending() -> void:
	_pending_t.clear()
	_pending_l.clear()


func _free_flame_slot(tip: int) -> int:
	var oldest := 0
	var oldest_frac := -1.0
	var base := tip * FLAMES_PER_TIP
	# Prefer one of this tip's own slots, then any free slot, then the oldest.
	for k in range(FLAMES_PER_TIP):
		var s := (base + k) % _flames.size()
		if not _flames[s].visible:
			return s
	for s in range(_flames.size()):
		if not _flames[s].visible:
			return s
	for s in range(_flames.size()):
		var frac := _flame_age[s] / maxf(_flame_dur[s], 0.001)
		if frac > oldest_frac:
			oldest_frac = frac
			oldest = s
	return oldest


func _spawn_embers(loudness: float) -> void:
	var n := clampi(int(round(1.0 + 3.0 * loudness)), 1, 4)
	var car := get_parent()
	var car_vel := Vector3.ZERO
	if car is RigidBody3D:
		car_vel = (car as RigidBody3D).linear_velocity
	for k in range(n):
		var slot := _next_ember
		_next_ember = (_next_ember + 1) % _embers.size()
		var tip := _rng.randi_range(0, maxi(_tips.size() - 1, 0))
		var e := _embers[slot]
		var dir := _tip_dirs[tip]
		var local_pos := _tips[tip] + dir * 0.15
		var car3d := car as Node3D
		var world_pos := car3d.global_transform * local_pos if car3d != null else global_transform * local_pos
		var out_dir := (car3d.global_transform.basis * dir) if car3d != null else dir
		e.global_position = world_pos
		var s: float = _rng.randf_range(0.012, 0.03)
		e.scale = Vector3(s, s, s)
		_ember_vel[slot] = car_vel * 0.85 + out_dir * _rng.randf_range(1.5, 4.5) + Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.2, 1.6), _rng.randf_range(-1.0, 1.0))
		_ember_age[slot] = 0.0
		e.visible = true
		e.set_instance_shader_parameter("fade", 1.0)


func _ensure_pool() -> void:
	if _pool_built:
		return
	_pool_built = true
	_flame_material = ShaderMaterial.new()
	_flame_material.shader = FLAME_SHADER
	_ember_material = ShaderMaterial.new()
	_ember_material.shader = EMBER_SHADER
	var flame_mesh := _build_flame_mesh()
	var ember_mesh := QuadMesh.new()
	ember_mesh.size = Vector2.ONE
	for i in range(MAX_FLAMES):
		var mi := MeshInstance3D.new()
		mi.name = "Flame%d" % i
		mi.mesh = flame_mesh
		mi.material_override = _flame_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flames.append(mi)
	_flame_age.resize(MAX_FLAMES)
	_flame_dur.resize(MAX_FLAMES)
	_flame_energy.resize(MAX_FLAMES)
	_flame_tip.resize(MAX_FLAMES)
	for i in range(MAX_EMBERS):
		var e := MeshInstance3D.new()
		e.name = "Ember%d" % i
		e.mesh = ember_mesh
		e.material_override = _ember_material
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.top_level = true
		e.visible = false
		add_child(e)
		_embers.append(e)
	_ember_age.resize(MAX_EMBERS)
	_ember_vel.resize(MAX_EMBERS)
	_light = OmniLight3D.new()
	_light.name = "BackfireFlash"
	_light.light_color = Color(1.0, 0.55, 0.18)
	_light.omni_range = LIGHT_RANGE
	_light.light_energy = 0.0
	_light.light_specular = 0.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


## Three planes through the +Z axis at 0 / 60 / 120 degrees (UV.x across,
## UV.y 0 at the pipe mouth -> 1 at the flame tip, length 1 along +Z).
static func _build_flame_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in range(3):
		var a := PI * float(k) / 3.0
		var u := Vector3(cos(a), sin(a), 0.0) * 0.5
		var base := verts.size()
		verts.append(-u)
		verts.append(u)
		verts.append(u + Vector3(0.0, 0.0, 1.0))
		verts.append(-u + Vector3(0.0, 0.0, 1.0))
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(0.0, 1.0))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-0.6, -0.6, -0.1), Vector3(1.2, 1.2, 1.3))
	return mesh
