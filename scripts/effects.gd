extends Node2D

var sparks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var smoke: Array[Dictionary] = []

func burst(at: Vector2, color: Color, amount: int = 30, power: float = 400.0) -> void:
	for i: int in range(amount):
		var angle: float = randf() * TAU
		var life: float = randf_range(0.25, 0.7)
		sparks.append({"p": at, "v": Vector2.from_angle(angle) * randf_range(power * 0.2, power), "life": life, "max": life, "c": color})
	rings.append({"p": at, "age": 0.0, "c": color, "size": power * 0.42})
	if color.r > color.g * 1.2:
		for i: int in range(10):
			var life: float = randf_range(0.5, 1.1)
			smoke.append({"p": at + Vector2(randf_range(-10, 10), randf_range(-10, 10)), "v": Vector2(randf_range(-80, 80), randf_range(-90, -25)), "life": life, "max": life, "r": randf_range(9, 26)})

func trail(at: Vector2) -> void:
	ghosts.append({"p": at, "life": 0.24})

func _process(delta: float) -> void:
	for i: int in range(smoke.size() - 1, -1, -1):
		smoke[i].life -= delta
		smoke[i].p += smoke[i].v * delta
		if smoke[i].life <= 0.0:
			smoke.remove_at(i)
	for i: int in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s.life -= delta
		s.p += s.v * delta
		s.v.y += delta * 500.0
		if s.life <= 0.0:
			sparks.remove_at(i)
	for i: int in range(rings.size() - 1, -1, -1):
		rings[i].age += delta
		if rings[i].age > 0.55:
			rings.remove_at(i)
	for i: int in range(ghosts.size() - 1, -1, -1):
		ghosts[i].life -= delta
		if ghosts[i].life <= 0:
			ghosts.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for puff: Dictionary in smoke:
		var ratio: float = float(puff.life) / float(puff.max)
		draw_circle(puff.p, float(puff.r) * (1.4 - ratio * 0.5), Color(0.12, 0.09, 0.14, ratio * 0.3))
	for ghost: Dictionary in ghosts:
		draw_circle(ghost.p, 6.0 * float(ghost.life) / 0.24, Color(0.74, 0.58, 0.32, float(ghost.life) * 0.7))
	for ring: Dictionary in rings:
		var t: float = float(ring.age) / 0.55
		var c: Color = ring.c
		c.a = (1.0 - t) * 0.7
		draw_arc(ring.p, 10.0 + (1.0 - pow(1.0 - t, 3.0)) * float(ring.size), 0, TAU, 60, c, 3.0 * (1.0 - t) + 1.0, true)
		c.a *= 0.12
		draw_circle(ring.p, float(ring.size) * t, c)
	for spark: Dictionary in sparks:
		var c: Color = spark.c
		c.a = float(spark.life) / float(spark.max)
		draw_line(spark.p, spark.p - spark.v * 0.025, c, 2.5, true)
