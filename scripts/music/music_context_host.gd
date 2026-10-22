# scripts/music/music_context_host.gd
class_name MusicContextHost
extends Node

## Drop one into a scene to declare what the music should do there. Scenes
## WITHOUT a host default to NONE (music fades out and pauses), so no scene can
## blast music by accident. v1 ships a FREE_ROAM host in open_world_root.tscn.

@export_enum("NONE", "FREE_ROAM", "RACE", "GARAGE", "MENU") var context: int = MusicPolicy.Context.FREE_ROAM

func _enter_tree() -> void:
	var service := get_node_or_null("/root/MusicService")
	if service != null and service.has_method("set_context"):
		service.call("set_context", context, get_instance_id())

func _exit_tree() -> void:
	var service := get_node_or_null("/root/MusicService")
	if service != null and service.has_method("clear_context"):
		service.call("clear_context", get_instance_id())
