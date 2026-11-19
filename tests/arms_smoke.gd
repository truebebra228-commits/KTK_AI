extends SceneTree
## Run: Godot --headless --fixed-fps 120 --path . --script res://tests/arms_smoke.gd
## Samples rendered-joint world positions through actual placement/reset APIs.

var game: Node2D
var passed: int = 0
var failures: Array[String] = []
var record_existed: bool = false
var record_contents: PackedByteArray = PackedByteArray()

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	record_existed = FileAccess.file_exists("user://record.cfg")
	if record_existed:
		record_contents = FileAccess.get_file_as_bytes("user://record.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene failed to load; arms checks aborted")
		quit(1)
		return
	game = scene.instantiate() as Node2D
	root.add_child(game)
	await frames(12)
	if game.get("player") == null or game.player.get("arms") == null:
		if game != null:
			game.set_physics_process(false)
		push_error("Player arms failed to initialize; checks aborted")
		game.queue_free()
		quit(1)
		return
	game.sound.set_enabled(false)
	game.start_game()
	await frames(12)
	await reach_and_release()
	await directional_targets()
	await pause_pose()
	await resets()
	_restore_record()
	print("\nARMS RESULT: %d passed, %d failed" % [passed, failures.size()])
	for failure: String in failures:
		print("  FAILED: " + failure)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failures.append(description)
		print("FAIL: " + description)

func frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
	await process_frame

func stage(room: int = 0) -> void:
	game.mode = "playing"
	game.load_room(room)
	game._set_simulation(true)
	await frames(20)

func hands() -> Array[Vector2]:
	var arms: Node2D = game.player.arms
	return [arms.to_global(arms.left_hand), arms.to_global(arms.right_hand)]

func joint_pose() -> Array[Vector2]:
	var arms: Node2D = game.player.arms
	return [arms.left_hand, arms.right_hand, arms.left_elbow, arms.right_elbow]

func reach(offset: Vector2 = Vector2(45, -30)) -> void:
	game.plant_cooldown = 0.0
	game.begin_placement()
	game.update_placement(game.player.position + offset)
	await frames(60)

func reach_and_release() -> void:
	await stage()
	var home: Array[Vector2] = hands()
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(45, -30))
	var target: Vector2 = game.placement_position
	check(game.placement_valid and game.placing_bomb and game.player.arms.held, "a valid held bomb preview activates both reaching arms")
	var extended: Array[Vector2] = hands()
	check(extended[0].distance_to(target) < 12.0 and extended[1].distance_to(target) < 12.0 and extended[0].x < target.x - 4.0 and extended[1].x > target.x + 4.0 and ((extended[0] + extended[1]) * 0.5).distance_to(target) < 3.0, "both hands grip opposite sides of the bomb immediately in the same cursor update")
	check(game.player.gaze_weight > 0.5 and game.player.gaze_offset.x * game.player.facing > 0.0, "eyes immediately look toward the held bomb on the right")
	var before_turn: Array[Vector2] = hands()
	game.update_placement(game.player.position + Vector2(-45, -30))
	var second_target: Vector2 = game.placement_position
	var after_turn: Array[Vector2] = hands()
	var full_motion: float = after_turn[0].distance_to(before_turn[0]) + after_turn[1].distance_to(before_turn[1])
	check(full_motion > 100.0 and after_turn[0].distance_to(second_target) < 12.0 and after_turn[1].distance_to(second_target) < 12.0, "switching to the opposite side moves both hands immediately without a lag frame")
	await frames(2)
	var next_frame: Array[Vector2] = hands()
	check(next_frame[0].distance_to(second_target) < 12.0 and next_frame[1].distance_to(second_target) < 12.0, "the hand grip remains aligned on the next physics frame")
	check(game.player.gaze_weight > 0.5 and game.player.gaze_offset.x * game.player.facing < 0.0, "moving the held bomb left reverses the eye direction")
	var sample: Array[Vector2] = hands()
	var elbow_sample: Array[Vector2] = [game.player.arms.left_elbow, game.player.arms.right_elbow]
	var hand_variation: float = 0.0
	var elbow_variation: float = 0.0
	for tick: int in range(90):
		await frames(1)
		var current: Array[Vector2] = hands()
		hand_variation = maxf(hand_variation, maxf(current[0].distance_to(sample[0]), current[1].distance_to(sample[1])))
		elbow_variation = maxf(elbow_variation, maxf(game.player.arms.left_elbow.distance_to(elbow_sample[0]), game.player.arms.right_elbow.distance_to(elbow_sample[1])))
	check(hand_variation < 0.25 and elbow_variation < 6.0, "a stationary bomb keeps both hands stable while elbow motion stays small")
	var committed: bool = game.commit_placement()
	check(committed and not game.player.arms.held, "releasing the preview commits the bomb and ends the held arm pose")
	if game.bombs.is_empty():
		return
	var bomb: Node2D = game.bombs[0]
	var released_at: Vector2 = bomb.position
	await frames(84)
	var released: Array[Vector2] = hands()
	check(released[0].distance_to(home[0]) < 7.0 and released[1].distance_to(home[1]) < 7.0, "both hands settle back to their idle pose after release")
	check(game.player.gaze_weight < 0.02 and game.player.gaze_offset.length() < 0.1, "eyes return to neutral after releasing the bomb")
	check(is_instance_valid(bomb) and bomb.position.y > released_at.y + 8.0 and absf(bomb.position.x - released_at.x) < 1.0, "arms return home while the released bomb falls independently")

func directional_targets() -> void:
	await stage()
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for direction: Vector2 in directions:
		game.begin_placement()
		game.update_placement(game.player.position + direction * 1000.0)
		var finite_bounded: bool = true
		for point: Vector2 in joint_pose():
			finite_bounded = finite_bounded and point.is_finite() and game.player.arms.to_global(point).distance_to(game.player.position) < 90.0
		var gaze_world: Vector2 = Vector2(game.player.gaze_offset.x * game.player.facing, game.player.gaze_offset.y)
		var actual_direction: Vector2 = (game.placement_position - game.player.position).normalized()
		check(finite_bounded and game.placement_position.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.1 and gaze_world.is_finite() and gaze_world.length() < 6.0 and gaze_world.dot(actual_direction) > 0.0, "far target %s keeps a short finite arm reach and eyes directed toward the corrected bomb" % direction)
		game.cancel_placement()

func pause_event() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	game._unhandled_input(event)

func pause_pose() -> void:
	await stage()
	await reach()
	pause_event()
	var frozen: Array[Vector2] = joint_pose()
	var frozen_clock: float = game.player.arms.arm_clock
	var frozen_gaze: Vector2 = game.player.gaze_offset
	var frozen_gaze_weight: float = game.player.gaze_weight
	await frames(45)
	check(not game.player.enabled and game.mode == "paused" and joint_pose() == frozen and is_equal_approx(game.player.arms.arm_clock, frozen_clock) and game.player.gaze_offset == frozen_gaze and is_equal_approx(game.player.gaze_weight, frozen_gaze_weight), "pause freezes every arm joint, its clock and the eyes while the body is disabled")
	pause_event()
	await frames(45)
	check(game.mode == "playing" and game.player.arms.arm_clock > frozen_clock and joint_pose() != frozen and game.player.gaze_weight < 0.02 and game.player.gaze_offset.length() < 0.1, "arms resume and the cancelled gaze returns to neutral with gameplay")

func restart_event() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "restart"
	event.pressed = true
	game._unhandled_input(event)

func resets() -> void:
	await stage()
	var rest: Array[Vector2] = joint_pose()
	await reach()
	game.player.reset_at(game.player.position + Vector2(30, -70))
	var pose: Array[Vector2] = joint_pose()
	check(not game.player.arms.held and pose[0].distance_to(rest[0]) < 7.0 and pose[1].distance_to(rest[1]) < 7.0 and is_zero_approx(game.player.gaze_weight) and game.player.gaze_offset == Vector2.ZERO, "teleport resets arm reach and eye direction instead of stretching from the old location")
	game.respawn(false)
	await reach()
	game.respawn(false)
	check(not game.placing_bomb and not game.player.arms.held and is_zero_approx(game.player.gaze_weight), "respawn clears placement, held arms and eye tracking")
	await reach()
	restart_event()
	check(game.room_index == 0 and not game.placing_bomb and not game.player.arms.held and is_zero_approx(game.player.gaze_weight), "R in a challenge clears arm reach and eye tracking")
	await reach()
	game.load_room(1)
	check(not game.player.arms.held and not game.placing_bomb and is_zero_approx(game.player.gaze_weight), "loading another room resets arms, preview and gaze")
	await stage(4)
	await reach()
	restart_event()
	check(game.room_index == 0 and not game.is_sandbox and not game.placing_bomb and not game.player.arms.held and is_zero_approx(game.player.gaze_weight), "replaying from the sandbox resets arms and eyes for a fresh run")

func _restore_record() -> void:
	if record_existed:
		var file: FileAccess = FileAccess.open("user://record.cfg", FileAccess.WRITE)
		if file != null:
			file.store_buffer(record_contents)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://record.cfg"))
