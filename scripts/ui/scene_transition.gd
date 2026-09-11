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
