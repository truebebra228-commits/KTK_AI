extends CharacterBody2D
class_name BombRunner

const ArmsScript = preload("res://scripts/arms.gd")
const FaceShader = preload("res://scripts/face.gdshader")

signal jumped
signal landed(impact: float)

const GRAVITY: float = 1500.0
const JUMP_SPEED: float = 450.0
const HOP_SPEED: float = 245.0
const ART_HEIGHT: float = 60.0
const ART_TOP: float = -39.0
const LOWER_STRIP_LEFT: float = 0.337
const LOWER_STRIP_RIGHT: float = 0.729
const LOWER_STRIP_TOP: float = 0.58
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
var _head: Sprite2D
var _face_material: ShaderMaterial
var _head_origin: Vector2 = Vector2.ZERO
var _head_pixel_scale: float = 1.0
var _visible_bottom_fraction: float = 1.0
var _visible_sole_y: float = 21.0
var _capsule_radius: float = 13.0
var _capsule_half_segment: float = 8.0
var _visual_floor_y: float = 0.0
var _visual_floor_valid: bool = false

func _ready() -> void:
	var source: Texture2D = load("res://assets/hero-cutout.png") as Texture2D
	var source_image: Image = source.get_image()
	if source_image.is_compressed():
		source_image.decompress()
	var used: Rect2i = source_image.get_used_rect()
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(used)
	sprite_texture = atlas
	_visible_bottom_fraction = _find_visible_bottom(source_image, used)
	_visible_sole_y = ART_TOP + ART_HEIGHT * _visible_bottom_fraction
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 2
	collision_mask = 1
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: CapsuleShape2D = CapsuleShape2D.new()
	shape.radius = 13.0
	shape.height = 42.0
	_capsule_radius = shape.radius
	_capsule_half_segment = shape.height * 0.5 - shape.radius
	collider.shape = shape
	add_child(collider)
	arms = ArmsScript.new()
	arms.name = "ProceduralArms"
	arms.z_index = 1
	add_child(arms)
	# Keep the source face as a separate native texture layer, so its black
	# features can move without drawing any new pupil dots.
	_head_pixel_scale = ART_HEIGHT / float(used.size.y)
	_head_origin = Vector2(-sprite_texture.get_width() * _head_pixel_scale * 0.5 - used.position.x * _head_pixel_scale, ART_TOP - used.position.y * _head_pixel_scale)
	_face_material = ShaderMaterial.new()
	_face_material.shader = FaceShader
	_head = Sprite2D.new()
	_head.name = "MovingFace"
	_head.texture = source
	_head.centered = false
	_head.region_enabled = true
	_head.region_rect = Rect2(0, 0, source.get_width(), used.position.y + used.size.y * 0.58)
	_head.material = _face_material
	_head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_head)
	_sync_arms_transform()
	_sync_head()
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
	_refresh_visual_floor()
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
	_visual_floor_valid = false
	_gaze_held = false
	gaze_weight = 0.0
	gaze_offset = Vector2.ZERO
	if is_instance_valid(arms):
		arms.reset_pose()
		_sync_arms_transform()
	_sync_head()
	reset_physics_interpolation()

func _sync_arms_transform() -> void:
	# All artwork shares the same sole-anchored pose; the collision body is
	# deliberately unaffected by these visual offsets and counter-rotation.
	arms.transform = _art_transform()
	arms.sync_pose()

func _find_visible_bottom(image: Image, used: Rect2i) -> float:
	# Image.get_used_rect() includes faint alpha noise below the painted feet.
	# Scan only the lower body strip that we actually draw, once at startup.
	var left: int = maxi(0, floori(used.position.x + used.size.x * LOWER_STRIP_LEFT))
	var right: int = mini(image.get_width(), ceili(used.position.x + used.size.x * LOWER_STRIP_RIGHT))
	var top: int = floori(used.position.y + used.size.y * LOWER_STRIP_TOP)
	for y: int in range(used.end.y - 1, top - 1, -1):
		for x: int in range(left, right):
			if image.get_pixel(x, y).a >= 0.5:
				return float(y + 1 - used.position.y) / float(used.size.y)
	return 1.0

func _refresh_visual_floor() -> void:
	_visual_floor_valid = false
	if not is_on_floor():
		return
	# Reuse the contact that move_and_slide already computed. No new physics
	# query, collision size, position, velocity or motion parameter is changed.
	for index: int in range(get_slide_collision_count()):
		var contact: KinematicCollision2D = get_slide_collision(index)
		var normal: Vector2 = contact.get_normal()
		if normal.dot(Vector2.UP) > 0.5:
			var point: Vector2 = contact.get_position()
			_visual_floor_y = point.y - normal.x / normal.y * (global_position.x - point.x)
			_visual_floor_valid = true
			return

func _sole_anchor_local() -> Vector2:
	if not is_on_floor():
		return Vector2(0.0, _capsule_radius + _capsule_half_segment)
	var support: float = _capsule_radius + _capsule_half_segment * absf(cos(global_rotation))
	var anchor: Vector2 = global_position + Vector2(0.0, support + safe_margin)
	if _visual_floor_valid:
		anchor.y = _visual_floor_y
	return to_local(anchor)

func _art_transform() -> Transform2D:
	# Landing squash pivots around the visible sole, rather than lifting the
	# feet toward the character origin. Grounded artwork stands upright even
	# while the pre-existing physics-body tilt is still easing out.
	var angle: float = -global_rotation if is_on_floor() else 0.0
	var pose: Transform2D = Transform2D(angle, Vector2.ZERO)
	pose.x *= (1.0 + squash) * facing
	pose.y *= 1.0 - squash
	pose.origin = _sole_anchor_local() - pose.basis_xform(Vector2(0.0, _visible_sole_y))
	return pose

func get_visual_sole_world_position() -> Vector2:
	return to_global(_art_transform() * Vector2(0.0, _visible_sole_y))

func set_gaze_target(target_world: Vector2, held: bool) -> void:
	_gaze_target = target_world
	_gaze_held = held
	if held:
		gaze_weight = 1.0
		_update_gaze(0.0)
	queue_redraw()

func _update_gaze(delta: float) -> void:
	if _gaze_held:
		var target_local: Vector2 = _art_transform().affine_inverse() * to_local(_gaze_target)
		var direction: Vector2 = (target_local - Vector2(2, -23)).normalized()
		gaze_offset = (direction * Vector2(2.0, 1.5)).round()
	else:
		gaze_weight = move_toward(gaze_weight, 0.0, delta * 8.0)
		gaze_offset = gaze_offset.move_toward(Vector2.ZERO, delta * 24.0)
	_sync_head()

func _sync_head() -> void:
	if not is_instance_valid(_head):
		return
	var pose: Transform2D = _art_transform()
	_head.transform = Transform2D(pose.x * _head_pixel_scale, pose.y * _head_pixel_scale, pose * _head_origin)
	_face_material.set_shader_parameter("feature_offset_pixels", gaze_offset * gaze_weight / _head_pixel_scale)

func _draw() -> void:
	# Artwork is fitted to the existing collision body, with feet at its base.
	# AtlasTexture trims only the draw region; the supplied PNG stays intact.
	if sprite_texture == null:
		return
	if is_on_floor():
		var shadow: Transform2D = Transform2D(-global_rotation, _sole_anchor_local())
		shadow.y *= 0.17
		draw_set_transform_matrix(shadow)
		draw_circle(Vector2.ZERO, 24.0, Color(0.05, 0.03, 0.06, 0.24))
	draw_set_transform_matrix(_art_transform())
	var height: float = ART_HEIGHT
	var width: float = height * sprite_texture.get_width() / float(sprite_texture.get_height())
	var rect: Rect2 = Rect2(-width / 2.0, ART_TOP, width, height)
	_draw_body(rect, Color.WHITE)
	if boost_time > 0.55:
		# Warm soot-lit flash, never an opaque overlay on the user's drawing.
		_draw_body(rect, Color(1.0, 0.73, 0.3, (boost_time - 0.55) * 0.5))
	draw_set_transform(Vector2.ZERO)

func _draw_body(rect: Rect2, tint: Color) -> void:
	# The head is drawn by MovingFace; this lower strip preserves torso/pants
	# while the old painted arms outside it are replaced by the live rig.
	var size: Vector2 = sprite_texture.get_size()
	var lower_position: Vector2 = Vector2(LOWER_STRIP_LEFT, LOWER_STRIP_TOP)
	var lower_size: Vector2 = Vector2(LOWER_STRIP_RIGHT - LOWER_STRIP_LEFT, _visible_bottom_fraction - LOWER_STRIP_TOP)
	draw_texture_rect_region(sprite_texture, Rect2(rect.position + rect.size * lower_position, rect.size * lower_size), Rect2(size * lower_position, size * lower_size), tint)
