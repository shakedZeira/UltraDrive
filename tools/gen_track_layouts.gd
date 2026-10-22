extends SceneTree

## OFFLINE TRACK-LAYOUT BAKE TOOL (run ONCE, never from a test).
##
##   %GODOT_EXE_CONSOLE% --headless -s res://tools/gen_track_layouts.gd
##
## NOTE (verified 2026-10-17): in `-s` mode the autoloads ARE instantiated as
## /root children, but their bare identifiers do NOT resolve at compile time, so
## this script reaches RaceManager via `root.get_node_or_null("/root/RaceManager")`
## rather than the global name.
##
## For EVERY id in `TrackRegistry.get_track_ids()` (no id literals anywhere) it
## instantiates the track scene INTO THE TREE, waits two frames so the scene's
## `_ready()` has built its centerline, then extracts the driven centerline with
## a documented capability chain:
##   1. `root.get("road_points")` when present and `size() >= 3`
##      (mountain_pass.gd / northern_isle.gd expose this member);
##   2. else the first descendant that `is TrackBuilder` -> `_track_points`
##      (track_builder.gd retains the built spline; this covers the oval, whose
##      points are built inline in test_circuit.gd's `_ready()`);
##   3. else record `"has_layout": false` (never guess).
## It also records `"rival_centerline": RaceManager.rival_centerline.size() >= 2`
## read right after the frames — the ground truth for whether the layout will
## field AI rivals. An EMPTY, TYPED centerline is set before each scene so the
## flag can never leak from a previously instanced track (`set_rival_centerline`
## takes `Array[Vector3]` — a bare `[]` is an untyped Array and is a RUNTIME type
## error, so the call site uses a `var no_centerline: Array[Vector3] = []`).
##
## Writes `res://resources/ui/track_layouts/<track_id>.json`:
##   { "scene_path", "points": [[x,y,z]...], "closed", "has_layout",
##     "rival_centerline", "generated" }
##
## Running this is intentionally NOT part of the GDUnit gate: it is a one-shot
## editor step (instancing every track scene runs terrain bakes and HUD `_ready`).
## The runtime (scripts/ui/track_layout_source.gd) degrades gracefully when a
## JSON is missing, so the menu — and the tests — keep working before a bake.
##
## Full type annotations (GDUnit-style hygiene): the tool is not a suite, but it
## stays warning-clean so `--import` remains quiet.

const OUT_DIR := "res://resources/ui/track_layouts"
const FRAMES_SETTLE := 2

func _initialize() -> void:
	# Fire-and-forget coroutine: `_initialize` must return for the engine to run
	# the main loop, and `process_frame` only fires inside it.
	_run()

func _run() -> void:
	# Start on a running frame so the root is safe to touch.
	await process_frame
	# `-s` (SceneTree script) mode DOES instantiate the autoloads, but Godot only
	# registers their bare identifiers for normal project runs -- a direct
	# `RaceManager` reference is a compile error here ("Identifier not found").
	# Reach the real autoload instance through the tree instead. Typed Variant on
	# purpose: RaceManager is an autoload instance, not a global class.
	var race_manager: Variant = root.get_node_or_null("/root/RaceManager")
	if race_manager == null:
		print("[gen_track_layouts] FATAL: /root/RaceManager missing -- refusing to bake bogus rival flags")
		quit(1)
		return
	# Typed empty array on purpose: set_rival_centerline() takes Array[Vector3] and
	# a bare `[]` literal is an UNTYPED Array, which is a runtime error
	# ("Invalid type in function 'set_rival_centerline'") -- hit for real
	# 2026-10-17 on the first ever run of this tool.
	var no_centerline: Array[Vector3] = []
	var out_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ids: Array = TrackRegistry.get_track_ids()
	print("[gen_track_layouts] baking %d layout(s) -> %s" % [ids.size(), OUT_DIR])
	var written := 0
	for id_value: Variant in ids:
		var track_id := str(id_value)
		var scene_path := TrackRegistry.get_scene_path(track_id)
		var packed := load(scene_path) as PackedScene
		if packed == null:
			print("[gen_track_layouts] %s: NO SCENE at %s -- skipped" % [track_id, scene_path])
			continue
		# Independent per-track read: never inherit a centerline from the last one.
		race_manager.set_rival_centerline(no_centerline)
		var root := packed.instantiate()
		if root == null:
			print("[gen_track_layouts] %s: instantiate() returned null -- skipped" % track_id)
			continue
		get_root().add_child(root)
		for _i in FRAMES_SETTLE:
			await process_frame
		var extracted := _extract_points(root)
		var points: Array = extracted.get("points", [])
		var has_layout := bool(extracted.get("has_layout", false))
		var rival_flag := bool(race_manager.rival_centerline.size() >= 2)
		root.queue_free()
		await process_frame
		var payload := {
			"scene_path": scene_path,
			"points": _points_to_json(points),
			"closed": true,
			"has_layout": has_layout,
			"rival_centerline": rival_flag,
			"generated": Time.get_datetime_string_from_system(true, true),
		}
		var path := "%s/%s.json" % [OUT_DIR, track_id]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			print("[gen_track_layouts] %s: WRITE FAILED (%s, error %d)" % [track_id, path, FileAccess.get_open_error()])
			continue
		file.store_string(JSON.stringify(payload, "  "))
		file.close()
		written += 1
		print("[gen_track_layouts] %s: points=%d has_layout=%s rival_centerline=%s -> %s" % [
			track_id, points.size(), str(has_layout), str(rival_flag), path])
	print("[gen_track_layouts] done: %d/%d written" % [written, ids.size()])
	quit(0)

## The documented capability chain. Returns {"points": Array, "has_layout": bool}.
func _extract_points(root: Node) -> Dictionary:
	var road: Variant = root.get("road_points")
	if road is Array and (road as Array).size() >= 3:
		return {"points": (road as Array).duplicate(), "has_layout": true}
	var builder := _find_track_builder(root)
	if builder != null:
		var built: Variant = builder.get("_track_points")
		if built is Array and (built as Array).size() >= 3:
			return {"points": (built as Array).duplicate(), "has_layout": true}
	return {"points": [], "has_layout": false}

## First descendant that is a TrackBuilder (depth-first, tree order).
func _find_track_builder(node: Node) -> TrackBuilder:
	for child: Node in node.get_children():
		if child is TrackBuilder:
			return child as TrackBuilder
		var found := _find_track_builder(child)
		if found != null:
			return found
	return null

## Vector3 spline -> JSON-safe [[x, y, z], ...] (JSON has no Vector3 type).
func _points_to_json(points: Array) -> Array:
	var out: Array = []
	out.resize(points.size())
	for i in points.size():
		var v: Vector3 = points[i]
		out[i] = [v.x, v.y, v.z]
	return out
