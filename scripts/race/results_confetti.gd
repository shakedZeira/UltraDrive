# scripts/race/results_confetti.gd
class_name ResultsConfetti
extends Control

## Plain 2D confetti burst drawn via CanvasItem._draw: a conic fan of squares
## seeded at the overlay centre that falls and fades over DURATION. No GPU
## particles and no textures, so the headless display server renders it as a
## harmless no-op. advance() drives the state so tests can step it to
## completion without a scene; _process() keeps it live at runtime.

const DURATION := 3.0
const PARTICLE_COUNT := 64
const GRAVITY := 900.0

const PALETTE: Array[Color] = [
	Color(0.949, 0.741, 0.167),
	Color(0.898, 0.290, 0.200),
	Color(0.294, 0.639, 0.925),
	Color(0.420, 0.851, 0.416),
	Color(0.898, 0.606, 0.200),
	Color(0.624, 0.388, 0.796),
]

var finished := false
var _elapsed := 0.0
var _particles: Array[Dictionary] = []

func burst() -> void:
	_particles.clear()
	_elapsed = 0.0
	finished = false
	for i in PARTICLE_COUNT:
		var angle := TAU * (float(i) / float(PARTICLE_COUNT)) + (randf() - 0.5) * 0.5
		var speed := 260.0 + randf() * 420.0
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"size": 5.0 + randf() * 9.0,
			"spin": (randf() - 0.5) * 16.0,
			"angle": randf() * TAU,
			"age": 0.0,
			"color": PALETTE[i % PALETTE.size()],
		})
	_redraw()

func advance(delta: float) -> void:
	if finished:
		return
	_elapsed += delta
	if _elapsed >= DURATION:
		finished = true
		_particles.clear()
		_redraw()
		return
	for particle in _particles:
		var pos: Vector2 = particle["pos"]
		var vel: Vector2 = particle["vel"]
		var spin: float = particle["spin"]
		var angle: float = particle["angle"]
		var age: float = particle["age"]
		vel.y += GRAVITY * delta
		pos += vel * delta
		particle["pos"] = pos
		particle["vel"] = vel
		particle["angle"] = angle + spin * delta
		particle["age"] = age + delta
	_redraw()

func reset() -> void:
	finished = true
	_particles.clear()
	_redraw()

func _process(delta: float) -> void:
	advance(delta)

func _draw() -> void:
	var origin := size * 0.5
	for particle in _particles:
		var pos: Vector2 = particle["pos"]
		var age: float = particle["age"]
		var color: Color = particle["color"]
		var angle: float = particle["angle"]
		var size_value: float = particle["size"]
		var dim: float = size_value * (1.0 - 0.4 * (age / DURATION))
		var alpha := clampf(1.0 - age / DURATION, 0.0, 1.0)
		draw_set_transform(origin + pos, angle, Vector2.ONE)
		draw_rect(Rect2(-dim * 0.5, -dim * 0.5, dim, dim), Color(color.r, color.g, color.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _redraw() -> void:
	if is_inside_tree():
		queue_redraw()