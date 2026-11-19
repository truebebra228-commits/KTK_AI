extends Node2D

const DUST_LIMIT: int = 80
const DUST_TEXTURE_SIZE: Vector2i = Vector2i(24, 16)
const DUST_SHADOW: Color = Color("4d4554")
const DUST_LIGHT: Color = Color("a29798")

static var _dust_textures: Array[Texture2D] = []

var sparks: Array[Dictionary] = []
var ghosts: Array[Dictionary] = []
var smoke: Array[Dictionary] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _dust_textures.is_empty():
		for variant: int in range(3):
			_dust_textures.append(_make_dust_texture(variant))

func burst(at: Vector2, color: Color, amount: int = 30, power: float = 400.0) -> void:
	for _i: int in range(amount):
		var angle: float = randf() * TAU
		var life: float = randf_range(0.25, 0.7)
		sparks.append({"p": at, "v": Vector2.from_angle(angle) * randf_range(power * 0.2, power), "life": life, "max": life, "c": color})

func dust(at: Vector2, strength: float = 1.0, grounded: bool = true) -> void:
	var scale_factor: float = clampf(strength, 0.3, 3.0)
	var count: int = 4 + roundi(scale_factor * 4.0)
	for i: int in range(count):
		if smoke.size() >= DUST_LIMIT:
			smoke.pop_front()
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var width: float = randf_range(12.0, 19.0) * scale_factor
		var life: float = randf_range(0.38, 0.57) * sqrt(scale_factor)
		var offset: Vector2 = Vector2(side * randf_range(1.0, 7.0), -randf_range(0.0, 3.0)) * scale_factor
		var velocity: Vector2 = Vector2(side * randf_range(24.0, 58.0), -randf_range(8.0, 32.0)) * scale_factor
		if not grounded:
			offset.y = randf_range(-6.0, 6.0) * scale_factor
			velocity.y = randf_range(-42.0, 28.0) * scale_factor
		smoke.append({
			"p": at + offset,
			"v": velocity,
			"life": life,
			"max": life,
			"size": Vector2(width, width * randf_range(0.63, 0.82)),
			"grounded": grounded,
			"variant": i % 3,
		})
	queue_redraw()

func trail(at: Vector2) -> void:
	ghosts.append({"p": at, "life": 0.24})

func _process(delta: float) -> void:
	if smoke.is_empty() and sparks.is_empty() and ghosts.is_empty():
		return
	var drag: Vector2 = Vector2(exp(-4.6 * delta), exp(-2.3 * delta))
	for i: int in range(smoke.size() - 1, -1, -1):
		var puff: Dictionary = smoke[i]
		puff.life -= delta
		if puff.life <= 0.0:
			smoke.remove_at(i)
		else:
			puff.p += puff.v * delta
			puff.v *= drag
	for i: int in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s.life -= delta
		s.p += s.v * delta
		s.v.y += delta * 500.0
		if s.life <= 0.0:
			sparks.remove_at(i)
	for i: int in range(ghosts.size() - 1, -1, -1):
		ghosts[i].life -= delta
		if ghosts[i].life <= 0:
			ghosts.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for puff: Dictionary in smoke:
		var progress: float = 1.0 - float(puff.life) / float(puff.max)
		var size: Vector2 = (puff.size as Vector2) * lerpf(0.72, 1.65, ease(progress, 0.65))
		var at: Vector2 = (puff.p as Vector2).round() - size * 0.5
		if puff.grounded:
			# The tracked position is the bottom edge. Growth stays above it.
			at.y -= size.y * 0.5
		var opacity: float = lerpf(0.58, 0.9, smoothstep(0.0, 0.12, progress))
		opacity *= 1.0 - smoothstep(0.14, 1.0, progress)
		draw_texture_rect(_dust_textures[int(puff.variant)], Rect2(at, size), false, Color(1, 1, 1, opacity))
	for ghost: Dictionary in ghosts:
		var size: float = 6.0 * float(ghost.life) / 0.24
		draw_rect(Rect2(ghost.p - Vector2(size, size * 0.25), Vector2(size * 2.0, maxf(1.0, size * 0.5))), Color(0.74, 0.58, 0.32, float(ghost.life) * 0.7))
	for spark: Dictionary in sparks:
		var c: Color = spark.c
		c.a = float(spark.life) / float(spark.max)
		draw_line(spark.p, spark.p - spark.v * 0.025, c, 2.5, true)

static func _make_dust_texture(variant: int) -> Texture2D:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8179 + variant * 53
	var image: Image = Image.create(DUST_TEXTURE_SIZE.x, DUST_TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var centers: PackedVector2Array = PackedVector2Array()
	var radii: PackedVector2Array = PackedVector2Array()
	for i: int in range(5):
		centers.append(Vector2(0.23 + i * 0.135, rng.randf_range(0.4, 0.65)))
		radii.append(Vector2(rng.randf_range(0.15, 0.24), rng.randf_range(0.24, 0.38)))
	for y: int in range(DUST_TEXTURE_SIZE.y):
		for x: int in range(DUST_TEXTURE_SIZE.x):
			var point: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(DUST_TEXTURE_SIZE)
			var density: float = -1.0
			for i: int in range(centers.size()):
				density = maxf(density, 1.0 - ((point - centers[i]) / radii[i]).length_squared())
			# Irregular lobes and shaded undersides read as dust rather than a
			# ring. Quantized opacity keeps the edge soft, but still pixelated.
			density += rng.randf_range(-0.16, 0.12)
			var shade: float = clampf(0.95 - point.y * 0.88 + rng.randf_range(-0.16, 0.16), 0.0, 1.0)
			var ink: Color = DUST_SHADOW.lerp(DUST_LIGHT, roundf(shade * 8.0) / 8.0)
			ink.a = roundf(smoothstep(-0.08, 0.76, density) * 10.0) / 14.0
			image.set_pixel(x, y, ink)
	return ImageTexture.create_from_image(image)
