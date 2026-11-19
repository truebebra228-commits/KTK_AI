extends Node2D
## Short limbs made from the current skeleton, painted on the world pixel grid.
## Palms reach a fixed contact immediately while joints follow the body's motion.

const INK: Color = Color("100c15")
const LEATHER: Color = Color("3b303a")
const PIXEL_SIZE: float = 2.0
const ARM_WIDTH: float = 4.0
const PALM_WIDTH: float = 5.0
const MAX_REACH: float = 78.0
const LEFT_SHOULDER: Vector2 = Vector2(-10, -4)
const RIGHT_SHOULDER: Vector2 = Vector2(14, -4)
const LEFT_REST: Vector2 = Vector2(-19, 11)
const RIGHT_REST: Vector2 = Vector2(21, 10)
const LEFT_CONTACT: Vector2 = Vector2(-7, 2)
const RIGHT_CONTACT: Vector2 = Vector2(7, 2)

var held: bool = false
var left_hand: Vector2 = LEFT_REST
var right_hand: Vector2 = RIGHT_REST
var left_elbow: Vector2 = Vector2(-24, -2)
var right_elbow: Vector2 = Vector2(25, -2)
var arm_clock: float = 0.0
var landing_compression: float = 0.0

var _active: bool = true
var _body: CharacterBody2D
var _target_world: Vector2 = Vector2.ZERO
var _left_velocity: Vector2 = Vector2.ZERO
var _right_velocity: Vector2 = Vector2.ZERO
var _grip_mirrored: bool = false


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reset_pose()


func set_hold_target(target_world: Vector2, active: bool) -> void:
	_target_world = target_world
	if held and not active and _grip_mirrored:
		# Restore the local anatomical order without pushing the palms through
		# one another when a mirrored grip lets go.
		var previous_left: Vector2 = left_hand
		left_hand = right_hand
		right_hand = previous_left
		_grip_mirrored = false
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
	_grip_mirrored = false
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
		_grip()
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
		_grip()
	else:
		var left_goal: Vector2 = _free_hand_goal(LEFT_REST, -1.0, 0.7)
		var right_goal: Vector2 = _free_hand_goal(RIGHT_REST, 1.0, 3.1)
		# Let unoccupied hands carry momentum, then settle rapidly after release.
		_left_velocity += ((left_goal - left_hand) * 1150.0 - _left_velocity * 56.0) * delta
		_right_velocity += ((right_goal - right_hand) * 1150.0 - _right_velocity * 56.0) * delta
		left_hand += _left_velocity * delta
		right_hand += _right_velocity * delta
	_update_elbows()


func _grip() -> void:
	# Apply grip offsets in world space before inverting the artwork transform.
	# Turning or squashing the torso cannot loosen a palm from its contact.
	_grip_mirrored = global_transform.x.x < 0.0
	left_hand = to_local(_target_world + LEFT_CONTACT)
	right_hand = to_local(_target_world + RIGHT_CONTACT)
	_left_velocity = Vector2.ZERO
	_right_velocity = Vector2.ZERO


func _free_hand_goal(rest: Vector2, side: float, phase: float) -> Vector2:
	var breath: Vector2 = Vector2(sin(arm_clock * 3.4 + phase), sin(arm_clock * 4.1 + phase)) * 1.2
	if _body.is_on_floor():
		# The body lowers into the landing while elbows open and hands brace.
		var brace: float = smoothstep(0.05, 0.28, landing_compression)
		return rest + breath + Vector2(side * 5.0, 5.0) * brace
	var velocity: Vector2 = _body.velocity
	var trail: Vector2 = to_local(global_position + (-velocity * 0.014).limit_length(10.0))
	var fall: float = smoothstep(0.0, 470.0, velocity.y)
	var spread: Vector2 = Vector2(side * (3.0 + 5.0 * fall), -4.0 - 7.0 * fall)
	return rest + breath + trail + spread


func _shoulder(left: bool) -> Vector2:
	return LEFT_SHOULDER if left != _grip_mirrored else RIGHT_SHOULDER


func _update_elbows() -> void:
	var side: float = 1.0 if _grip_mirrored else -1.0
	left_elbow = _elbow_goal(_shoulder(true), left_hand, side, 0.7)
	right_elbow = _elbow_goal(_shoulder(false), right_hand, -side, 3.1)


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
	var tremor: Vector2 = Vector2(sin(arm_clock * 7.7 + phase), sin(arm_clock * 9.1 + phase * 1.6)) * (0.85 if held else 0.45)
	return elbow + tremor


func _draw() -> void:
	# Draw on the WORLD pixel grid. The rig's reflection and squash still move
	# the joints, while every painted square keeps its crisp two-pixel size.
	draw_set_transform_matrix(global_transform.affine_inverse())
	_draw_arm(to_global(_shoulder(true)), to_global(left_elbow), to_global(left_hand), -1.0, 0.7)
	_draw_arm(to_global(_shoulder(false)), to_global(right_elbow), to_global(right_hand), 1.0, 3.1)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _pixel_point(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE * PIXEL_SIZE)


func _stroke(from: Vector2, to: Vector2, width: float = PIXEL_SIZE) -> void:
	# Bresenham rasterizes the curved skeleton's control segments into cells.
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
		_stamp(Vector2(x, y) * PIXEL_SIZE, width)
		if x == end_x and y == end_y:
			break
		var twice_error: int = error * 2
		if twice_error >= dy:
			error += dy
			x += step_x
			if twice_error <= dx and width == PIXEL_SIZE:
				# A thin finger still needs a shared edge at a diagonal.
				_stamp(Vector2(x, y) * PIXEL_SIZE, width)
		if twice_error <= dx:
			error += dx
			y += step_y


func _stamp(point: Vector2, width: float) -> void:
	# Grow around the cell so vertical and horizontal segments carry the same weight.
	var inset: float = floorf((PIXEL_SIZE - width) * 0.5)
	draw_rect(Rect2(point + Vector2.ONE * inset, Vector2.ONE * width), INK)


func _draw_arm(shoulder: Vector2, elbow: Vector2, hand: Vector2, side: float, phase: float) -> void:
	var upper: Vector2 = (elbow - shoulder).normalized()
	var forearm: Vector2 = (hand - elbow).normalized()
	var wrist: Vector2 = hand - forearm * minf(4.0, elbow.distance_to(hand) * 0.32)
	# Ease around the elbow so the result reads as one continuous silhouette.
	var before_elbow: Vector2 = shoulder.lerp(elbow, 0.72)
	var after_elbow: Vector2 = elbow.lerp(wrist, 0.23)
	var curve_middle: Vector2 = elbow * 0.5 + (before_elbow + after_elbow) * 0.25
	_stroke(shoulder, before_elbow, ARM_WIDTH)
	_stroke(before_elbow, curve_middle, ARM_WIDTH)
	_stroke(curve_middle, after_elbow, ARM_WIDTH)
	_stroke(after_elbow, wrist, ARM_WIDTH)
	_stroke(wrist, hand, ARM_WIDTH)
	var seam: Vector2 = _pixel_point(shoulder + upper * 4.0) - Vector2(0, PIXEL_SIZE)
	draw_rect(Rect2(seam, Vector2.ONE * PIXEL_SIZE), LEATHER)
	_draw_palm(elbow, hand, side, phase)


func _draw_palm(elbow: Vector2, hand: Vector2, side: float, phase: float) -> void:
	var palm: Vector2 = _pixel_point(hand)
	var direction: Vector2 = (hand - elbow).normalized()
	if held:
		direction = (_target_world - hand).normalized()
	var across: Vector2 = Vector2(-direction.y, direction.x)
	_stamp(palm, PALM_WIDTH)
	var curl: float = 0.5 + 0.5 * sin(arm_clock * 8.5 + phase)
	# Two fingertips fan out while free and curl toward the bomb while held.
	_stroke(hand, hand + direction * (3.0 + curl) + across * 1.5)
	_stroke(hand, hand + direction * 2.5 - across * (2.0 if held else 3.0 + curl))
	var thumb: Vector2 = hand - direction * 2.0 + across * side * (2.5 + curl)
	_stroke(hand, thumb)
