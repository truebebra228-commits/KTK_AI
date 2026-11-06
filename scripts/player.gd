extends CharacterBody2D
class_name BombRunner

const ArmsScript = preload("res://scripts/arms.gd")

signal jumped
signal landed(impact: float)

const GRAVITY: float = 1500.0
const JUMP_SPEED: float = 450.0
const HOP_SPEED: float = 245.0
var enabled: bool = false
var facing: float = 1.0
var coyote: float = 0.0
var buffer: float = 0.0
var boost_time: float = 0.0
var clock: float = 0.0
var squash: float = 0.0
var last_jump_direction: float = 0.0
var forced_direction: float = 0.0
var sprite_texture: Texture2D
var arms: Node2D
var gaze_offset: Vector2 = Vector2.ZERO
var gaze_weight: float = 0.0
var _gaze_target: Vector2 = Vector2.ZERO
var _gaze_held: bool = false

func _ready() -> void:
	var source: Texture2D = load("res://assets/hero-cutout.png") as Texture2D
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(source.get_image().get_used_rect())
	sprite_texture = atlas
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 2
	collision_mask = 1
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: CapsuleShape2D = CapsuleShape2D.new()
	shape.radius = 13.0
	shape.height = 42.0
	collider.shape = shape
	add_child(collider)
	arms = ArmsScript.new()
	arms.name = "ProceduralArms"
	arms.z_index = 1
	add_child(arms)
	floor_snap_length = 5.0
	add_to_group("player")

func _physics_process(delta: float) -> void:
	clock += delta
	if not enabled:
		queue_redraw()
		return
	squash = move_toward(squash, 0.0, delta * 5.0)
	boost_time = maxf(0.0, boost_time - delta)
	var grounded: bool = is_on_floor()
	if grounded:
		coyote = 0.11
	else:
		coyote = maxf(0.0, coyote - delta)
	buffer = maxf(0.0, buffer - delta)
	if Input.is_action_just_pressed("jump"):
		buffer = 0.13
	var axis: float = Input.get_axis("left", "right")
	if absf(axis) > 0.1:
		facing = axis
	if buffer > 0.0 and coyote > 0.0:
		perform_jump(axis)
	if grounded:
		velocity.x = move_toward(velocity.x, 0.0, (300.0 if boost_time > 0.0 else 1250.0) * delta)
	else:
		# Small air steering preserves the direction and energy of a blast.
		velocity.x += axis * 160.0 * delta
		if Input.is_action_pressed("brake"):
			velocity.x = move_toward(velocity.x, 0.0, delta * 1250.0)
	velocity.y = minf(velocity.y + GRAVITY * delta, 1100.0)
	velocity.x = clampf(velocity.x, -1250.0, 1250.0)
	var impact: float = velocity.y
	move_and_slide()
	if not grounded and is_on_floor():
		squash = 0.28
		landed.emit(impact)
	rotation = lerp_angle(rotation, clampf(velocity.x / 3000.0, -0.28, 0.28), delta * 9.0)
	_sync_arms_transform()
	_update_gaze(delta)
	queue_redraw()

func perform_jump(axis: float) -> void:
	velocity.y = -JUMP_SPEED
	velocity.x = axis * HOP_SPEED + velocity.x * 0.35
	last_jump_direction = axis
	coyote = 0.0
	buffer = 0.0
	squash = -0.15
	jumped.emit()

func blast(origin: Vector2, radius: float = 185.0, power: float = 1080.0) -> bool:
	var offset: Vector2 = global_position - origin
	var distance: float = offset.length()
	if distance > radius:
		return false
	var direction: Vector2 = offset.normalized() if distance > 2.0 else Vector2.UP
	if is_on_floor() and direction.y > -0.25:
		direction = Vector2(direction.x, -0.45).normalized()
	var force: float = power * (0.64 + 0.36 * (1.0 - distance / radius))
	# A blast adds energy; no health or self-damage system.
	velocity += direction * force
	velocity.y = clampf(velocity.y, -1450.0, 1200.0)
	velocity.x = clampf(velocity.x, -1250.0, 1250.0)
	boost_time = 0.8
	coyote = 0.0
	return true

func reset_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	rotation = 0.0
	buffer = 0.0
	coyote = 0.0
	boost_time = 0.0
	_gaze_held = false
	gaze_weight = 0.0
	gaze_offset = Vector2.ZERO
	if is_instance_valid(arms):
		arms.reset_pose()
		_sync_arms_transform()
	reset_physics_interpolation()

func _sync_arms_transform() -> void:
	# The drawn torso flips and squashes independently from the collision body.
	# Apply that same visual transform to its shoulder anchors.
	arms.scale = Vector2((1.0 + squash) * facing, 1.0 - squash)
	arms.sync_pose()

func set_gaze_target(target_world: Vector2, held: bool) -> void:
	_gaze_target = target_world
	_gaze_held = held
	if held:
		gaze_weight = 1.0
		_update_gaze(0.0)
	queue_redraw()

func _update_gaze(delta: float) -> void:
	if _gaze_held:
		var visual_scale: Vector2 = Vector2((1.0 + squash) * facing, 1.0 - squash)
		var target_local: Vector2 = to_local(_gaze_target) / visual_scale
		var direction: Vector2 = (target_local - Vector2(2, -23)).normalized()
		gaze_offset = (direction * Vector2(2.0, 1.5)).round()
	else:
		gaze_weight = move_toward(gaze_weight, 0.0, delta * 8.0)
		gaze_offset = gaze_offset.move_toward(Vector2.ZERO, delta * 24.0)

func _draw() -> void:
	var stretch: Vector2 = Vector2(1.0 + squash, 1.0 - squash)
	# Artwork is fitted to the existing collision body, with feet at its base.
	# AtlasTexture trims only the draw region; the supplied PNG stays intact.
	if sprite_texture == null:
		return
	if is_on_floor():
		draw_set_transform(Vector2(0, 21), 0.0, Vector2(1.0, 0.17))
		draw_circle(Vector2.ZERO, 24.0, Color(0.05, 0.03, 0.06, 0.24))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(stretch.x * facing, stretch.y))
	var height: float = 60.0
	var width: float = height * sprite_texture.get_width() / float(sprite_texture.get_height())
	var rect: Rect2 = Rect2(-width / 2.0, 21.0 - height, width, height)
	_draw_body(rect, Color.WHITE)
	if boost_time > 0.55:
		# Warm soot-lit flash, never an opaque overlay on the user's drawing.
		_draw_body(rect, Color(1.0, 0.73, 0.3, (boost_time - 0.55) * 0.5))
	_draw_gaze()
	draw_set_transform(Vector2.ZERO)

func _draw_gaze() -> void:
	if gaze_weight <= 0.01:
		return
	# Small pixel pupils stay inside the original dark eye shapes. Their
	# offset is computed in the same mirrored/squashed space as the face.
	var paper: Color = Color(0.93, 0.89, 0.74, gaze_weight)
	for eye: Vector2 in [Vector2(-6, -23), Vector2(10, -23)]:
		var pupil: Vector2 = (eye + gaze_offset).round()
		draw_rect(Rect2(pupil, Vector2(2, 2)), paper)

func _draw_body(rect: Rect2, tint: Color) -> void:
	# Draw native texture regions, keeping the supplied PNG intact. The upper
	# region preserves the face; below the shoulders only torso/pants remain.
	# The old painted arms outside this strip are replaced by the live rig.
	var size: Vector2 = sprite_texture.get_size()
	draw_texture_rect_region(sprite_texture, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.58)), Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.58)), tint)
	var lower_position: Vector2 = Vector2(0.337, 0.58)
	var lower_size: Vector2 = Vector2(0.392, 0.42)
	draw_texture_rect_region(sprite_texture, Rect2(rect.position + rect.size * lower_position, rect.size * lower_size), Rect2(size * lower_position, size * lower_size), tint)
