# autoload/game_state.gd
extends Node

## Manages global game state, scene transitions, and pause.

signal scene_changed(scene_path: String)
signal game_paused
signal game_resumed

enum GameMode { MAIN_MENU, FREE_ROAM, RACE, LICENSE_TEST, GARAGE }

var current_mode: GameMode = GameMode.MAIN_MENU
var is_paused: bool = false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func change_scene(scene_path: String) -> void:
    get_tree().change_scene_to_file(scene_path)
    # Set mode from destination so the pause guard in _unhandled_input works
    if "main_menu" in scene_path:
        current_mode = GameMode.MAIN_MENU
    else:
        current_mode = GameMode.FREE_ROAM
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

func _physics_process(_delta: float) -> void:
    if current_mode == GameMode.MAIN_MENU:
        return
    if Input.is_action_just_pressed("pause"):
        toggle_pause()