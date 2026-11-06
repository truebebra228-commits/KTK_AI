extends CharacterBody2D
## Only released charges are physical. The held preview belongs to main.gd.

const GRAVITY: float = 1050.0
const RESTITUTION: float = 0.30
static var _shared_texture: Texture2D

var age: float = 0.0
var serial: int = 1
var sprite_texture: Texture2D
var spin: float = 0.0

func _ready() -> void:
	if _shared_texture == null:
		var source: Texture2D = load("res://assets/bomb-cutout.png") as Texture2D
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(source.get_image().get_used_rect())
		_shared_texture = atlas
	sprite_texture = _shared_texture
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 4
	collision_mask = 1
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 9.0
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	floor_snap_length = 1.0

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

func _draw() -> void:
	var glow: float = 0.06 + 0.04 * sin(age * 5.0)
	draw_circle(Vector2.ZERO, 25.0, Color(1.0, 0.60, 0.15, glow))
	if sprite_texture != null:
		var height: float = 43.0
		var width: float = height * sprite_texture.get_width() / float(sprite_texture.get_height())
		draw_set_transform(Vector2.ZERO, clampf(spin, -0.3, 0.3))
		draw_texture_rect(sprite_texture, Rect2(-width / 2.0, 10.0 - height, width, height), false)
		draw_set_transform(Vector2.ZERO)
	draw_circle(Vector2(9, -27), 8.0, Color(1.0, 0.66, 0.18, glow * 1.1))
