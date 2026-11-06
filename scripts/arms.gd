extends Node2D
## Short pixel arms. Held palms stay fixed to world-space bomb contact points;
## only elbows and the small thumb gesture keep a little living motion.

const INK: Color = Color("080709")
const PIXEL_SIZE: float = 2.0
const MAX_REACH: float = 78.0
const LEFT_SHOULDER: Vector2 = Vector2(-10, -4)
const RIGHT_SHOULDER: Vector2 = Vector2(14, -4)
const LEFT_REST: Vector2 = Vector2(-22, 9)
const RIGHT_REST: Vector2 = Vector2(22, 9)
const LEFT_CONTACT: Vector2 = Vector2(-7, 2)
const RIGHT_CONTACT: Vector2 = Vector2(7, 2)

var held: bool = false
var left_hand: Vector2 = LEFT_REST
var right_hand: Vector2 = RIGHT_REST
var left_elbow: Vector2 = Vector2(-24, -2)
var right_elbow: Vector2 = Vector2(25, -2)
var arm_clock: float = 0.0

var _active: bool = true
var _body: CharacterBody2D
var _target_world: Vector2 = Vector2.ZERO
var _left_velocity: Vector2 = Vector2.ZERO
var _right_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reset_pose()


func set_hold_target(target_world: Vector2, active: bool) -> void:
	_target_world = target_world
	held = active
	if held:
		_left_velocity = Vector2.ZERO
		_right_velocity = Vector2.ZERO
		# The event that moves the ghost also moves both palms, in this call.
		sync_pose()


func set_active(value: bool) -> void:
	_active = value


func reset_pose() -> void:
	held = false
	arm_clock = 0.0
	_left_velocity = Vector2.ZERO
	_right_velocity = Vector2.ZERO
	left_hand = LEFT_REST
	right_hand = RIGHT_REST
	_update_elbows()
	queue_redraw()


func sync_pose() -> void:
	## Call after moving the player or changing the rig's mirror/squash scale.
	## This refreshes contacts immediately and does not advance animation time.
	if not _active:
		return
	if held:
		# Apply the grip offsets in WORLD space before the full inverse. Neither
		# mirroring nor nonuniform body squash can pull a palm away from the bomb.
		left_hand = to_local(_target_world + LEFT_CONTACT)
		right_hand = to_local(_target_world + RIGHT_CONTACT)
		_left_velocity = Vector2.ZERO
		_right_velocity = Vector2.ZERO
	_update_elbows()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	var elapsed: float = minf(delta, 0.075)
	var steps: int = maxi(1, int(ceil(elapsed * 120.0)))
	var step: float = elapsed / float(steps)
	for index: int in range(steps):
		_step_pose(step)
	queue_redraw()


func _step_pose(delta: float) -> void:
	arm_clock += delta
	if held:
		left_hand = to_local(_target_world + LEFT_CONTACT)
		right_hand = to_local(_target_world + RIGHT_CONTACT)
	else:
		var drift: Vector2 = Vector2.ZERO
		if _body != null and not _body.is_on_floor():
			var world_drift: Vector2 = (-_body.velocity * 0.004).limit_length(2.0)
			drift = to_local(global_position + world_drift)
		var left_goal: Vector2 = LEFT_REST + drift
		var right_goal: Vector2 = RIGHT_REST + drift
		# A compact critically damped return: almost home in about 0.15 seconds.
		_left_velocity += ((left_goal - left_hand) * 1500.0 - _left_velocity * 76.0) * delta
		_right_velocity += ((right_goal - right_hand) * 1500.0 - _right_velocity * 76.0) * delta
		left_hand += _left_velocity * delta
		right_hand += _right_velocity * delta
	_update_elbows()


func _update_elbows() -> void:
	left_elbow = _elbow_goal(LEFT_SHOULDER, left_hand, -1.0, 0.7)
	right_elbow = _elbow_goal(RIGHT_SHOULDER, right_hand, 1.0, 3.1)


func _elbow_goal(shoulder: Vector2, hand: Vector2, side: float, phase: float) -> Vector2:
	var displacement: Vector2 = hand - shoulder
	var distance: float = maxf(displacement.length(), 0.001)
	var direction: Vector2 = displacement / distance
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var stretch: float = clampf((distance - 18.0) / (MAX_REACH - 18.0), 0.0, 1.0)
	# These are much shorter than the old elastic rig. A little inverse-scale
	# compensation is necessary only while the torso is visibly squashed.
	var compensation: float = maxf(1.0, distance / (MAX_REACH - 2.0))
	var upper_length: float = lerpf(14.0, 24.0, stretch) * compensation
	var fore_length: float = lerpf(16.0, 58.0, stretch) * compensation
	var along: float = (distance * distance + upper_length * upper_length - fore_length * fore_length) / (2.0 * distance)
	along = clampf(along, -upper_length, upper_length)
	var height: float = sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var bend: float = -side
	if absf(perpendicular.x) > 0.001:
		bend = lerpf(bend, signf(side * perpendicular.x), clampf(absf(perpendicular.x) * 3.0, 0.0, 1.0))
	var elbow: Vector2 = shoulder + direction * along + perpendicular * height * bend
	var tremor: Vector2 = Vector2(sin(arm_clock * 7.7 + phase), sin(arm_clock * 9.1 + phase * 1.6)) * (0.65 if held else 0.25)
	return elbow + tremor


func _draw() -> void:
	# Draw on the WORLD pixel grid. The rig's reflection and squash still move
	# the joints, while every painted square keeps its crisp two-pixel size.
	draw_set_transform_matrix(global_transform.affine_inverse())
	_draw_arm(to_global(LEFT_SHOULDER), to_global(left_elbow), to_global(left_hand), -1.0, 0.7)
	_draw_arm(to_global(RIGHT_SHOULDER), to_global(right_elbow), to_global(right_hand), 1.0, 3.1)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _pixel_point(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE * PIXEL_SIZE)


func _pixel_line(from: Vector2, to: Vector2, thickness: int) -> void:
	# Bresenham's integer staircase, stamped with square blocks. No AA lines,
	# rounded caps, circles, or subpixel strokes are used anywhere in this rig.
	var x: int = roundi(from.x / PIXEL_SIZE)
	var y: int = roundi(from.y / PIXEL_SIZE)
	var end_x: int = roundi(to.x / PIXEL_SIZE)
	var end_y: int = roundi(to.y / PIXEL_SIZE)
	var dx: int = absi(end_x - x)
	var dy: int = -absi(end_y - y)
	var step_x: int = 1 if x < end_x else -1
	var step_y: int = 1 if y < end_y else -1
	var error: int = dx + dy
	while true:
		draw_rect(Rect2(Vector2(x * PIXEL_SIZE - 1, y * PIXEL_SIZE - 1), Vector2.ONE * thickness), INK)
		if x == end_x and y == end_y:
			break
		var twice_error: int = error * 2
		if twice_error >= dy:
			error += dy
			x += step_x
		if twice_error <= dx:
			error += dx
			y += step_y


func _draw_arm(shoulder: Vector2, elbow: Vector2, hand: Vector2, side: float, phase: float) -> void:
	_pixel_line(shoulder, elbow, 3)
	_pixel_line(elbow, hand, 2)
	var joint: Vector2 = _pixel_point(elbow)
	draw_rect(Rect2(joint - Vector2.ONE, Vector2(3, 3)), INK)
	var palm: Vector2 = _pixel_point(hand)
	# A five-pixel fist with a small squared thumb, matching the supplied sketch.
	draw_rect(Rect2(palm - Vector2(2, 2), Vector2(5, 5)), INK)
	var thumb_side: float = signf(hand.x - shoulder.x) if absf(hand.x - shoulder.x) > 0.1 else side
	if held:
		thumb_side = -1.0 if _target_world.x < hand.x else 1.0
	var thumb_lift: float = -1.0 if sin(arm_clock * 8.5 + phase) > 0.65 else 0.0
	var thumb: Vector2 = palm + Vector2(2.0 if thumb_side > 0.0 else -3.0, -1.0 + thumb_lift)
	draw_rect(Rect2(thumb, Vector2(2, 3)), INK)
