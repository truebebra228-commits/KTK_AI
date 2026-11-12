extends CharacterBody2D
## Only released charges are physical. The held preview belongs to main.gd.

const GRAVITY: float = 1050.0
const RESTITUTION: float = 0.30
const BLINK_PERIOD: float = 1.2
# Exclude the baked spark cluster and almost-transparent border, preserving
# the original bomb/fuse drawing and its previous visible body size.
const ART_REGION: Rect2 = Rect2(265, 320, 636, 770)
const ART_SCALE: float = 43.0 / 1107.0
const ART_CENTER_X: float = 552.0
const CONTACT_Y: float = 9.1
const FUSE_TIP: Vector2 = Vector2(883, 321)
static var _shared_texture: Texture2D

var age: float = 0.0
var serial: int = 1
var sprite_texture: Texture2D
var spin: float = 0.0

func _ready() -> void:
	sprite_texture = visual_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 4
	collision_mask = 1
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 9.0
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	floor_snap_length = 1.0

static func visual_texture() -> Texture2D:
	if _shared_texture == null:
		var source: Texture2D = load("res://assets/bomb-cutout.png") as Texture2D
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = source
		atlas.region = ART_REGION
		_shared_texture = atlas
	return _shared_texture

func _physics_process(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, 800.0)
	velocity.x = move_toward(velocity.x, 0.0, (700.0 if is_on_floor() else 12.0) * delta)
	var before: Vector2 = velocity
	move_and_slide()
	for index: int in range(get_slide_collision_count()):
		var normal: Vector2 = get_slide_collision(index).get_normal()
		if before.dot(normal) < -100.0:
			velocity = before.bounce(normal) * RESTITUTION
			break
	spin += velocity.x * delta * 0.035
	if position.y > 1000.0:
		queue_free()

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

static func pulse_scale(time: float) -> float:
	return 1.0 + sin(time * TAU / BLINK_PERIOD) * 0.055

static func draw_visual(canvas: CanvasItem, art: Texture2D, at: Vector2, time: float, angle: float = 0.0, opacity: float = 1.0) -> void:
	var scale_factor: float = ART_SCALE * pulse_scale(time)
	var size: Vector2 = art.get_size() * scale_factor
	# Grow upward from the collider's contact point, keeping the painted sole
	# against the floor through the entire pulse instead of making it float.
	var top_left: Vector2 = Vector2((ART_REGION.position.x - ART_CENTER_X) * scale_factor, CONTACT_Y - size.y)
	canvas.draw_set_transform(at, angle)
	canvas.draw_texture_rect(art, Rect2(top_left, size), false, Color(1, 1, 1, opacity))
	var tip: Vector2 = top_left + (FUSE_TIP - ART_REGION.position) * scale_factor
	for index: int in range(5):
		var phase: float = fposmod(time * 2.4 + float(index) * 0.2, 1.0)
		var direction: Vector2 = Vector2.from_angle(-2.65 + float(index) * 0.48)
		var travel: Vector2 = direction * (1.0 + phase * 6.0) + Vector2(0, -phase * phase * 2.0)
		var spark_at: Vector2 = (tip + travel).round()
		var ink: Color = Color("fff1a0").lerp(Color("e68132"), phase)
		ink.a = opacity * (1.0 - phase)
		canvas.draw_line(spark_at - direction * 1.5, spark_at, ink, 1.0)
		canvas.draw_rect(Rect2(spark_at, Vector2.ONE), ink)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if sprite_texture != null:
		var angle: float = 0.0 if is_on_floor() else clampf(spin, -0.3, 0.3)
		draw_visual(self, sprite_texture, Vector2.ZERO, age, angle)
