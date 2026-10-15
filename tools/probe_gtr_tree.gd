extends SceneTree

## Headless probe: dump the imported GT-R GLB node tree (name, class, transform)
## so we can see how Godot laid out the Wheel_* hubs after import.

func _init() -> void:
	var path := "res://assets/cars/nissan_gt-r_r35_2017.glb"
	var scene := load(path) as PackedScene
	if scene == null:
		print("FAILED to load ", path)
		quit(1)
		return
	var inst := scene.instantiate()
	_dump(inst, 0)
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is Node3D:
		var t := (n as Node3D).transform
		extra = " t=%s r=%s" % [t.origin, (n as Node3D).rotation]
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c: Node in n.get_children():
		_dump(c, depth + 1)
