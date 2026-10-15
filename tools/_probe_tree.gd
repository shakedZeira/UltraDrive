extends SceneTree

func _initialize() -> void:
	var track := load("res://scenes/test/test_track.tscn") as PackedScene
	var scene := track.instantiate()
	root.add_child(scene)
	for n: String in ["HUD", "PauseMenu"]:
		var layer := scene.get_node_or_null(n)
		print("FOUND ", n, " -> ", layer != null, " visible pre=", layer.visible if layer != null else "<nil>")
		if layer != null:
			layer.visible = false
			print("  set visible=false -> post=", layer.visible)
	print("window size=", root.size, " texture_size=", root.get_texture().get_size())
	var hud := scene.get_node_or_null("HUD")
	if hud != null:
		for child in hud.get_children():
			if child is CanvasLayer:
				print("HUD child CanvasLayer ", child.name, " visible=", child.visible)
	var cluster := hud.get_node_or_null("Root/Cluster") if hud != null else null
	print("cluster=", cluster != null, " visible=", cluster.visible if cluster != null else "<nil>")
	quit(0)