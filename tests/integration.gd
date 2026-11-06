extends SceneTree
## Run: Godot --headless --fixed-fps 120 --path . --script res://tests/integration.gd
## Real bomb/jump routes start at each room's spawn. Position fixtures are used
## separately for collision validation, reset and transition contract checks.

var game: Node2D
var passed: int = 0
var failures: Array[String] = []
var record_existed: bool = false
var record_contents: PackedByteArray = PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	record_existed = FileAccess.file_exists("user://record.cfg")
	if record_existed:
		record_contents = FileAccess.get_file_as_bytes("user://record.cfg")
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("Main scene failed to load; integration aborted")
		_restore_record()
		quit(1)
		return
	game = scene.instantiate() as Node2D
	root.add_child(game)
	await _frames(8)
	if game.get("player") == null or game.get("camera") == null:
		game.set_physics_process(false)
		push_error("Main scene failed to initialize; integration aborted")
		_restore_record()
		game.queue_free()
		quit(1)
		return
	_expect(game.mode == "playing" and game.player.enabled, "the game starts playing immediately without a start menu")
	_expect(game.room_count == 5 and game.challenge_count == 4 and game.room_index == 0 and not game.is_sandbox, "four challenge rooms lead to a fifth sandbox")
	_expect(not _has_property(game, "collected") and not _has_property(game.level, "collectibles"), "gameplay and level no longer expose collectible progress")
	game.sound.set_enabled(false)
	await _basic_movement()
	_radial_blasts()
	await _drag_placement()
	await _bomb_limits()
	await _air_charges_and_refill()
	await _pause()
	await _room_contracts()
	await _room_transitions()
	await _room_reset()
	await _traverse_all_rooms()
	await _sandbox()
	_release_inputs()
	_restore_record()
	print("\nINTEGRATION RESULT: %d passed, %d failed" % [passed, failures.size()])
	for failure: String in failures:
		print("  FAILED: " + failure)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _has_property(object: Object, property: String) -> bool:
	for entry: Dictionary in object.get_property_list():
		if entry.name == property:
			return true
	return false

func _expect(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + description)
	else:
		failures.append(description)
		print("FAIL: " + description)

func _frames(count: int) -> void:
	for _i: int in count:
		await physics_frame
	await process_frame

func _release_inputs() -> void:
	for action: String in ["left", "right", "jump", "brake", "detonate"]:
		if InputMap.has_action(action):
			Input.action_release(action)

func _stage(room: int) -> void:
	_release_inputs()
	game.mode = "playing"
	game.load_room(room)
	game._set_simulation(true)
	await _frames(8)

func _place(at: Vector2) -> bool:
	if not game.begin_placement():
		return false
	game.update_placement(at)
	return game.commit_placement()

func _basic_movement() -> void:
	await _stage(0)
	var initial: Vector2 = game.player.position
	Input.action_press("right")
	await _frames(80)
	Input.action_release("right")
	_expect(absf(game.player.position.x - initial.x) < 0.5, "holding a direction alone cannot walk")
	game.player.perform_jump(0.0)
	await _frames(18)
	_expect(game.player.position.y < initial.y - 35.0 and absf(game.player.position.x - initial.x) < 0.5, "stationary jump rises without horizontal drift")
	await _frames(90)
	_expect(game.player.is_on_floor(), "stationary jump physically lands")
	for direction: float in [-1.0, 1.0]:
		await _stage(0)
		var before: Vector2 = game.player.position
		game.player.perform_jump(direction)
		await _frames(18)
		_expect((game.player.position.x - before.x) * direction > 25.0 and game.player.position.y < before.y - 35.0, "directional jump %s moves and rises" % ("left" if direction < 0.0 else "right"))

func _radial_blasts() -> void:
	var runner: CharacterBody2D = load("res://scripts/player.gd").new() as CharacterBody2D
	root.add_child(runner)
	runner.position = Vector2(300, -300)
	var origins: Array[Vector2] = [Vector2(300, -270), Vector2(270, -300), Vector2(330, -300), Vector2(300, -330)]
	var desired: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]
	for i: int in origins.size():
		runner.velocity = Vector2.ZERO
		_expect(runner.blast(origins[i]) and runner.velocity.dot(desired[i]) > 900.0, "blast applies correct radial direction %d" % i)
	runner.velocity = Vector2(31, -22)
	_expect(not runner.blast(Vector2(900, -300)) and runner.velocity == Vector2(31, -22), "out-of-radius blast leaves velocity untouched")
	runner.velocity = Vector2.ZERO
	_expect(runner.blast(runner.position) and runner.velocity.y < 0.0, "coincident blast origin has a stable upward fallback")
	runner.queue_free()

func _drag_placement() -> void:
	await _stage(0)
	var initial_charges: int = game.charges
	_expect(game.begin_placement(), "beginning a drag creates a placement preview")
	game.update_placement(game.player.position + Vector2(500, -150))
	_expect(game.placing_bomb and game.bombs.is_empty() and game.charges == initial_charges, "holding the preview creates no active bomb and spends no charge")
	_expect(game.placement_position.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.01 and is_equal_approx(game.PLACEMENT_RADIUS, 60.0), "drag position is clamped within the new 60 pixel radius")
	var old_preview: Vector2 = game.placement_position
	game.player.position.x -= 100.0
	game.update_placement(old_preview)
	_expect(game.placement_position.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.01 and game.placement_position.distance_to(old_preview) > 1.0, "placement range follows a moving player while held")
	_expect(game.detonate_bombs() == 0 and game.placing_bomb and game.bombs.is_empty(), "an uncommitted preview cannot detonate")
	game.cancel_placement()
	_expect(not game.placing_bomb and game.charges == initial_charges, "cancelling a preview spends no charge")
	game.respawn(false)
	var committed: bool = _place(game.player.position + Vector2(50, -30))
	_expect(committed and game.bombs.size() == 1 and game.charges == initial_charges - 1 and not game.placing_bomb, "valid release commits one bomb and consumes one charge")
	if game.bombs.is_empty():
		return
	var bomb: Node2D = game.bombs[0]
	var release_position: Vector2 = bomb.position
	var fell: bool = false
	var bounced: bool = false
	var previous_vertical_speed: float = 0.0
	for frame: int in range(90):
		await _frames(1)
		if not is_instance_valid(bomb):
			break
		fell = fell or bomb.position.y > release_position.y + 5.0
		if bomb is CharacterBody2D:
			var vertical_speed: float = (bomb as CharacterBody2D).velocity.y
			bounced = bounced or (previous_vertical_speed > 100.0 and vertical_speed < -20.0)
			previous_vertical_speed = vertical_speed
	_expect(fell and bounced, "a released bomb falls under gravity and physically rebounds from the floor")
	_expect(is_instance_valid(bomb) and bomb is CharacterBody2D and (bomb as CharacterBody2D).is_on_floor() and absf(bomb.position.y - 601.0) < 1.0 and absf((bomb as CharacterBody2D).velocity.y) < 5.0, "the released bomb settles on the platform instead of falling through it")
	var settled_position: Vector2 = bomb.position
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(-50, -40))
	_expect(bomb.position == settled_position, "dragging another preview cannot teleport an already released bomb")
	_expect(game.detonate_bombs() == 1 and game.bombs.is_empty() and game.placing_bomb, "active bombs can detonate while a different preview remains held")
	game.cancel_placement()
	await _stage(1)
	game.player.reset_at(Vector2(520, 400))
	var before_invalid: int = game.charges
	game.begin_placement()
	game.update_placement(Vector2(575, 400))
	var corrected: Vector2 = game.placement_position
	_expect(game.placement_valid and corrected.x <= 531.0 and corrected.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.1, "a cursor inside a wall resolves to a nearby reachable free point")
	_expect(game.commit_placement() and game.bombs.size() == 1 and game.bombs[0].position.distance_to(corrected) < 0.1 and game.charges == before_invalid - 1, "releasing a corrected preview creates a physical bomb at that free point")
	await _stage(1)
	game.player.reset_at(Vector2(520, 400))
	game.begin_placement()
	game.update_placement(Vector2(590, 330))
	_expect(game.placement_valid and game.placement_position.x <= 531.0 and game.placement_position.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.1 and game.commit_placement(), "an occluded corner target resolves to an accessible free point within reach")
	await _stage(1)
	# An embedded-player fixture makes the entire 60 px neighborhood solid.
	# It tests the no-solution fallback separately from playable traversal.
	game.player.reset_at(Vector2(900, 500))
	before_invalid = game.charges
	game.begin_placement()
	game.update_placement(Vector2(900, 500))
	_expect(not game.placement_valid and not game.commit_placement() and game.bombs.is_empty() and game.charges == before_invalid and not game.placing_bomb, "release cancels at no cost only when no reachable free point exists")
	await _stage(0)
	game.begin_placement()
	game.update_placement(game.player.position + Vector2(30, -20))
	game.load_room(1)
	_expect(not game.placing_bomb and game.bombs.is_empty(), "room replacement cancels unfinished placement")

func _bomb_limits() -> void:
	await _stage(0)
	for i: int in 3:
		game.plant_cooldown = 0.0
		_expect(_place(game.player.position + Vector2(0, 9)), "commit charge %d" % (i + 1))
	_expect(game.charges == 0 and game.bombs.size() == 3, "three commits consume exactly three charges")
	game.plant_cooldown = 0.0
	_expect(not game.begin_placement(), "a fourth preview is refused when charges run out")
	game.charges = 3
	_expect(not game.begin_placement() and game.bombs.size() == 3, "the three-active-bomb cap holds even with spare charges")
	_expect(game.detonate_bombs() == 3 and game.bombs.is_empty(), "remote detonation triggers and clears every committed bomb")
	_expect(game.player.velocity.y < -900.0, "stacked explosions impart real upward velocity")
	_expect(game.detonate_bombs() == 0, "detonation without bombs is safe")

func _air_charges_and_refill() -> void:
	await _stage(0)
	var spawn: Vector2 = game.level.checkpoints[0]
	game.player.reset_at(spawn - Vector2(0, 150))
	await _frames(2)
	for i: int in 3:
		_expect(not game.player.is_on_floor() and _place(game.player.position + Vector2(0, 15)), "airborne placement %d succeeds" % (i + 1))
		_expect(game.detonate_bombs() == 1, "airborne blast %d catches the player" % (i + 1))
		await _frames(20)
	_expect(game.charges == 0 and not game.begin_placement(), "challenge air chains stop after three charges before landing")
	game.player.reset_at(spawn - Vector2(0, 70))
	game.player.velocity = Vector2(0, 300)
	await _frames(70)
	_expect(game.player.is_on_floor() and game.charges == 3, "real landing refills challenge charges")

func _pause_event() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	game._unhandled_input(event)

func _pause() -> void:
	await _stage(0)
	game.player.position.y -= 100.0
	game.player.velocity = Vector2(200, -200)
	_place(game.player.position + Vector2(25, 9))
	game.plant_cooldown = 0.0
	game.begin_placement()
	_pause_event()
	var frozen: Vector2 = game.player.position
	var bomb_frozen: Vector2 = game.bombs[0].position
	var frozen_elapsed: float = game.elapsed
	await _frames(40)
	_expect(game.mode == "paused" and game.player.position == frozen and game.bombs[0].position == bomb_frozen and is_equal_approx(game.elapsed, frozen_elapsed), "pause freezes the player, bombs and run timer")
	_expect(not game.placing_bomb and not game.begin_placement() and game.detonate_bombs() == 0, "pause cancels the preview and rejects bomb actions")
	_pause_event()
	await _frames(4)
	_expect(game.mode == "playing" and game.player.position != frozen, "Escape resumes gameplay directly")

func _room_contracts() -> void:
	var layouts: Array[String] = []
	for room: int in range(5):
		await _stage(room)
		var spawn: Vector2 = game.level.checkpoints[0]
		_expect(game.room_index == room and game.level.room_index == room and game.level.checkpoints.size() == 1, "room %d loads with its own spawn" % (room + 1))
		_expect(game.player.is_on_floor() and game.player.position.distance_to(spawn) < 8.0, "room %d spawn settles safely" % (room + 1))
		var bounds: Rect2 = Rect2(0, 0, 1280, 720)
		var valid: bool = bounds.has_point(spawn)
		for hazard: Rect2 in game.level.hazards:
			valid = valid and bounds.encloses(hazard)
		for platform: Rect2 in game.level.platforms:
			valid = valid and bounds.encloses(platform)
		if room < 4:
			valid = valid and game.level.finish_rect.has_area() and bounds.encloses(game.level.finish_rect)
		_expect(valid, "room %d gameplay geometry fits one screen" % (room + 1))
		var signature: String = str(game.level.platforms) + str(game.level.hazards)
		_expect(not layouts.has(signature), "room %d has its own layout" % (room + 1))
		layouts.append(signature)
		var fixed_center: Vector2 = game.camera.position
		game.player.perform_jump(1.0)
		await _frames(20)
		_expect(game.player.position.distance_to(spawn) > 30.0 and game.camera.position.is_equal_approx(fixed_center) and fixed_center.is_equal_approx(Vector2(640, 360)), "room %d camera stays fixed while the player moves" % (room + 1))

func _static_bodies(parent: Node) -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for child: Node in parent.get_children():
		if child is StaticBody2D:
			bodies.append(child as StaticBody2D)
		bodies.append_array(_static_bodies(child))
	return bodies

func _room_transitions() -> void:
	for room: int in range(4):
		await _stage(room)
		_place(game.player.position + Vector2(0, 9))
		var old_bodies: Array[StaticBody2D] = _static_bodies(game.level)
		var old_layout: String = str(game.level.platforms)
		game.plant_cooldown = 0.0
		game.begin_placement()
		game.player.reset_at(game.level.finish_rect.get_center())
		await _frames(1)
		_expect(game.room_index == room and not game.player.enabled and not game.placing_bomb, "room %d exit freezes physics and cancels preview" % (room + 1))
		var faded_out: bool = false
		var loaded_under_black: bool = false
		for frame: int in range(180):
			await _frames(1)
			if game.room_index == room and game.transition_alpha > 0.05 and game.transition_alpha < 0.95:
				faded_out = true
			if game.room_index == room + 1 and game.transition_alpha >= 0.99:
				loaded_under_black = true
			if game.room_index == room + 1 and game.player.enabled:
				break
		_expect(faded_out and loaded_under_black and is_zero_approx(game.transition_alpha), "transition fades out, replaces the room under black, then fades in")
		_expect(game.room_index == room + 1 and game.level.room_index == room + 1 and game.mode == "playing", "room %d exit advances to the next playable room" % (room + 1))
		_expect(game.bombs.is_empty() and game.charges == 3 and game.player.position.distance_to(game.level.checkpoints[0]) < 8.0, "transition clears bombs and restores charges at the next spawn")
		var released: bool = true
		for body: StaticBody2D in old_bodies:
			released = released and not is_instance_valid(body)
		_expect(released and old_layout != str(game.level.platforms), "transition frees old collision bodies and replaces the layout")
	_expect(game.room_index == 4 and game.is_sandbox and game.mode == "playing" and game.player.enabled, "the fourth exit opens the sandbox without a victory screen")

func _room_reset() -> void:
	await _stage(2)
	var spawn: Vector2 = game.level.checkpoints[0]
	_place(game.player.position + Vector2(0, 9))
	game.plant_cooldown = 0.0
	game.begin_placement()
	game.player.reset_at(Vector2(spawn.x, 780))
	var previous_deaths: int = game.deaths
	await _frames(5)
	_expect(game.room_index == 2 and game.deaths == previous_deaths + 1 and game.player.position.distance_to(spawn) < 8.0, "falling respawns in the current challenge room")
	_expect(game.bombs.is_empty() and game.charges == 3 and not game.placing_bomb, "death clears committed bombs and preview and refills charges")
	_place(game.player.position + Vector2(25, -20))
	game.plant_cooldown = 0.0
	game.begin_placement()
	game.player.position.x += 30.0
	var restart: InputEventAction = InputEventAction.new()
	restart.action = "restart"
	restart.pressed = true
	game._unhandled_input(restart)
	await _frames(4)
	_expect(game.room_index == 2 and game.player.position.distance_to(spawn) < 8.0 and game.bombs.is_empty() and not game.placing_bomb, "R restarts the current room and cancels every bomb state")
	var count_before: int = _static_bodies(game.level).size()
	for repeat: int in range(4):
		await _stage(2)
	_expect(_static_bodies(game.level).size() == count_before, "repeated room loads do not accumulate collision bodies")

func _traverse_all_rooms() -> void:
	await _stage(0)
	var deaths_before: int = game.deaths
	var initial_blasts: int = game.blasts
	Input.action_press("right")
	for frame: int in range(1200):
		if game.player.is_on_floor():
			game.player.perform_jump(1.0)
		await _frames(1)
		if game.mode == "transition" or game.room_index != 0 or game.deaths != deaths_before:
			break
	_release_inputs()
	_expect((game.mode == "transition" or game.room_index == 1) and game.deaths == deaths_before and game.blasts == initial_blasts, "room 1: ordinary physical jumps cross the steps to the exit")
	await _stage(1)
	var approach: bool = await _hop_to(330.0)
	_expect(approach, "room 2: real hops reach the blast approach from spawn")
	var launched: bool = await _ground_launch(12)
	var reached: bool = await _fly_to_exit(1, 850.0)
	_expect(launched and reached, "room 2: a released physical bomb clears the 260 px ledge to the exit")
	await _stage(2)
	approach = await _hop_to(285.0)
	_expect(approach, "room 3: real hops reach the bridge edge from spawn")
	launched = await _ground_launch(15)
	reached = await _fly_to_exit(2, 920.0)
	_expect(launched and reached, "room 3: a released physical bomb crosses the 500 px gap to the exit")
	await _stage(3)
	approach = await _hop_to(215.0)
	_expect(approach, "room 4: a braked physical hop reaches the narrow launch platform")
	launched = await _ground_launch(15)
	var blasts_before_chain: int = game.blasts
	reached = await _fly_to_exit(3, 1080.0, 690.0)
	_expect(game.blasts == blasts_before_chain + 1, "room 4: the physical route uses a second committed bomb in mid-air")
	_expect(launched and reached and game.mode == "transition", "room 4: the air chain crosses the 790 px gap and enters the sandbox transition")
	for frame: int in range(180):
		await _frames(1)
		if game.room_index == 4 and game.mode == "playing":
			break
	_expect(game.room_index == 4 and game.is_sandbox and game.player.enabled, "physical completion of all challenges continues into the playable sandbox")

func _hop_to(target: float) -> bool:
	var deaths_before: int = game.deaths
	for frame: int in range(600):
		var remaining: float = target - game.player.position.x
		if remaining > 28.0:
			Input.action_release("brake")
			Input.action_press("right")
			if game.player.is_on_floor() and absf(game.player.velocity.x) < 10.0:
				game.player.perform_jump(1.0)
		else:
			Input.action_release("right")
			Input.action_press("brake")
		await _frames(1)
		if game.deaths != deaths_before:
			break
		if game.player.is_on_floor() and absf(game.player.velocity.x) < 5.0 and absf(target - game.player.position.x) < 35.0:
			_release_inputs()
			return true
	_release_inputs()
	print("APPROACH FAILED: room=%d position=%s" % [game.room_index + 1, game.player.position])
	return false

func _ground_launch(delay: int) -> bool:
	var planted: bool = _place(game.player.position + Vector2(0, 9))
	await _frames(4)
	Input.action_press("right")
	game.player.perform_jump(1.0)
	await _frames(delay)
	var hits: int = game.detonate_bombs()
	print("LAUNCH: room=%d position=%s velocity=%s" % [game.room_index + 1, game.player.position, game.player.velocity])
	return planted and hits == 1

func _fly_to_exit(room: int, brake_at: float, chain_at: float = -1.0) -> bool:
	var deaths_before: int = game.deaths
	var chained: bool = false
	var landed: bool = false
	for frame: int in range(800):
		if chain_at > 0.0 and not chained and game.player.position.x >= chain_at and not game.player.is_on_floor():
			var before_velocity: float = game.player.velocity.y
			var before_charges: int = game.charges
			var planted: bool = _place(game.player.position + Vector2(0, 15))
			var hits: int = game.detonate_bombs()
			chained = planted and hits == 1 and game.charges == before_charges - 1 and game.player.velocity.y < before_velocity - 500.0
			print("CHAIN: position=%s velocity=%s success=%s" % [game.player.position, game.player.velocity, chained])
		if game.player.is_on_floor():
			landed = true
			Input.action_release("brake")
			Input.action_press("right")
			game.player.perform_jump(1.0)
		elif not landed and game.player.position.x >= brake_at:
			Input.action_release("right")
			Input.action_press("brake")
		await _frames(1)
		if game.deaths != deaths_before:
			_release_inputs()
			print("ROUTE FAILED: room=%d died frame=%d" % [room + 1, frame])
			return false
		if game.mode == "transition" or game.room_index != room:
			_release_inputs()
			print("ROUTE EXIT: room=%d position=%s frame=%d chain=%s" % [room + 1, game.player.position, frame, chained])
			return chain_at < 0.0 or chained
	_release_inputs()
	print("ROUTE TIMED OUT: room=%d position=%s velocity=%s" % [room + 1, game.player.position, game.player.velocity])
	return false

func _sandbox() -> void:
	await _stage(4)
	_expect(game.is_sandbox and game.level.sandbox and game.level.platforms.size() == 1 and game.level.hazards.is_empty() and not game.level.finish_rect.has_area(), "the sandbox is one flat floor with no hazards or exit")
	var floor: Rect2 = game.level.platforms[0]
	_expect(floor.position.x == 0.0 and floor.size.x == 1280.0, "sandbox floor spans the complete room")
	var before_time: float = game.elapsed
	var before_animation: float = game.level.get("_clock")
	await _frames(1200)
	_expect(game.mode == "playing" and game.player.enabled and game.room_index == 4 and game.elapsed > before_time + 5.0, "sandbox stays playable over time without a timer ending or victory screen")
	_expect(float(game.level.get("_clock")) > before_animation + 5.0, "sandbox celebration animation continues while playing")
	var infinite_ok: bool = true
	for cycle: int in range(6):
		infinite_ok = infinite_ok and _place(game.player.position + Vector2(0, 9))
		infinite_ok = infinite_ok and game.detonate_bombs() == 1
		await _frames(20)
	_expect(infinite_ok, "sandbox allows more than three successive airborne charges without needing a landing")
	game.respawn(false)
	await _frames(8)
	for index: int in range(3):
		game.plant_cooldown = 0.0
		_place(game.player.position + Vector2(index * 15, -20))
	game.plant_cooldown = 0.0
	_expect(game.bombs.size() == 3 and not game.begin_placement(), "sandbox keeps the three-active-bomb cap despite its unlimited reserve")
	game.begin_placement()
	_pause_event()
	var frozen_clock: float = game.level.get("_clock")
	var frozen_time: float = game.elapsed
	await _frames(45)
	_expect(game.mode == "paused" and is_equal_approx(float(game.level.get("_clock")), frozen_clock) and is_equal_approx(game.elapsed, frozen_time), "sandbox pause freezes confetti animation and run time")
	_pause_event()
	await _frames(15)
	_expect(game.mode == "playing" and float(game.level.get("_clock")) > frozen_clock, "sandbox celebration resumes with gameplay")
	game.respawn(false)
	_expect(game.room_index == 4 and game.is_sandbox and game.player.position.distance_to(game.level.checkpoints[0]) < 1.0 and game.bombs.is_empty(), "a death-style respawn keeps the player in the sandbox")
	game.elapsed = 123.0
	game.deaths = 7
	game.blasts = 9
	_place(game.player.position + Vector2(30, -20))
	game.plant_cooldown = 0.0
	game.begin_placement()
	var replay: InputEventAction = InputEventAction.new()
	replay.action = "restart"
	replay.pressed = true
	game._unhandled_input(replay)
	_expect(game.room_index == 0 and not game.is_sandbox and not game.level.sandbox and game.mode == "playing" and game.player.enabled and game.level.platforms[0] != floor, "R in the sandbox immediately starts a fresh challenge run in room one")
	_expect(game.bombs.is_empty() and not game.placing_bomb and game.charges == 3 and is_zero_approx(game.elapsed) and game.deaths == 0 and game.blasts == 0 and is_zero_approx(game.transition_alpha) and game.next_room == -1, "sandbox replay clears bombs, preview, run statistics and transition state")

func _restore_record() -> void:
	if record_existed:
		var file: FileAccess = FileAccess.open("user://record.cfg", FileAccess.WRITE)
		if file != null:
			file.store_buffer(record_contents)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://record.cfg"))
