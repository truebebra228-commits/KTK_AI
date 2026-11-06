extends SceneTree
## Run Godot --headless --path . --script tests/ui_smoke.gd
## Exercises real key and mouse events. The original user settings are restored.

var failures: Array[String] = []
var checks: int = 0
var game: Node2D
var record_existed: bool = false
var record_backup: PackedByteArray = PackedByteArray()
var held_buttons: int = 0
var pointer: Vector2 = Vector2.ZERO

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures.append(description)
		print("FAIL: ", description)

func frames(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame

func key(code: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames(2)

func tap(code: int) -> void:
	await key(code, true)
	await key(code, false)

func mouse_move(world_point: Vector2) -> void:
	var physical: Vector2 = root.get_final_transform() * world_point
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = physical
	event.global_position = physical
	event.relative = physical - pointer
	event.button_mask = held_buttons
	pointer = physical
	Input.parse_input_event(event)
	await frames(2)

func mouse_button(button: int, pressed: bool) -> void:
	var flag: int = 1 << (button - 1)
	if pressed:
		held_buttons |= flag
	else:
		held_buttons &= ~flag
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = pointer
	event.global_position = pointer
	event.button_index = button
	event.button_mask = held_buttons
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames(2)

func begin_drag(offset: Vector2 = Vector2(40, -30)) -> void:
	await mouse_move(game.player.position + offset)
	await mouse_button(MOUSE_BUTTON_LEFT, true)

func release_drag() -> void:
	await mouse_button(MOUSE_BUTTON_LEFT, false)

func place_at_free_point() -> void:
	await begin_drag()
	await mouse_move(game.player.position + Vector2(45, -25))
	await release_drag()
	await frames(20) # Wait through the deliberate placement cooldown.

func reset_room() -> void:
	await tap(KEY_R)
	await frames(20)

func wait_for_room(index: int) -> void:
	for tick: int in range(180):
		if game.mode == "playing" and game.room_index == index:
			return
		await frames(1)

func run_checks() -> void:
	record_existed = FileAccess.file_exists("user://record.cfg")
	if record_existed:
		record_backup = FileAccess.get_file_as_bytes("user://record.cfg")
	game = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(game)
	await frames(20)
	check(game.mode == "playing" and game.player.enabled, "Game starts playing immediately without a title menu")
	check(game.room_index == 0 and not game.is_sandbox, "Run starts in the first challenge room")
	await tap(KEY_E)
	check(game.bombs.is_empty() and not game.placing_bomb and game.charges == 3, "E does not create a bomb or placement ghost")

	await begin_drag()
	check(game.placing_bomb and game.bombs.is_empty(), "Holding LMB creates only a placement ghost")
	check(game.charges == 3, "An uncommitted ghost does not consume a charge")
	var intended: Vector2 = game.player.position + Vector2(45, -30)
	await mouse_move(intended)
	check(game.placement_valid and game.placement_position.distance_to(intended) < 3.0, "Dragging moves the ghost to a valid nearby point")
	await release_drag()
	check(not game.placing_bomb and game.bombs.size() == 1 and game.charges == 2, "Releasing LMB commits exactly one bomb and charge")
	if not game.bombs.is_empty():
		var bomb: Node2D = game.bombs[0]
		var release_point: Vector2 = bomb.position
		check(release_point.distance_to(intended) < 3.0, "Released bomb starts at the chosen placement point")
		await frames(30)
		check(is_instance_valid(bomb) and bomb.position.y > release_point.y + 5.0, "Releasing LMB gives the bomb gravity and it falls from the cursor point")
	await tap(KEY_F)
	check(game.bombs.is_empty(), "F detonates a committed bomb")
	await reset_room()

	await begin_drag()
	await tap(KEY_F)
	check(game.placing_bomb and game.bombs.is_empty() and game.charges == 3, "F cannot detonate or spend the placement ghost")
	await mouse_button(MOUSE_BUTTON_RIGHT, true)
	await mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(game.placing_bomb and game.bombs.is_empty() and game.charges == 3, "RMB cannot detonate or spend the placement ghost")
	await tap(KEY_ESCAPE)
	check(game.mode == "paused" and not game.placing_bomb and not game.player.enabled, "Esc cancels the ghost and pauses immediately")
	await release_drag()
	var paused_point: Vector2 = game.player.position
	var paused_velocity: Vector2 = game.player.velocity
	await frames(25)
	check(game.player.position.is_equal_approx(paused_point) and game.player.velocity.is_equal_approx(paused_velocity), "Pause freezes player position and velocity")
	await tap(KEY_ESCAPE)
	check(game.mode == "playing" and game.player.enabled and game.bombs.is_empty(), "Esc resumes without committing a cancelled ghost")

	await place_at_free_point()
	await begin_drag(Vector2(35, -55))
	check(game.bombs.size() == 1 and game.placing_bomb, "A new ghost can coexist with an already committed bomb")
	await tap(KEY_F)
	check(game.bombs.is_empty() and game.placing_bomb, "Placed bombs can explode while another ghost remains uncommitted")
	await tap(KEY_R)
	await release_drag()
	await frames(20)
	check(not game.placing_bomb and game.bombs.is_empty() and game.charges == 3, "R cancels the ghost, clears bombs, and refills charges")
	check(game.player.position.distance_to(game.level.checkpoints[0]) < 10.0, "R restores the current room spawn")

	await begin_drag()
	await mouse_move(game.player.position + Vector2(500, -20))
	check(game.placement_position.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 1.0 or not game.placement_valid, "A cursor beyond the placement radius cannot create an out-of-range bomb")
	await tap(KEY_R)
	await release_drag()
	await frames(20)
	await begin_drag()
	await mouse_move(game.player.position + Vector2(0, 55))
	var corrected_floor: Vector2 = game.placement_position
	check(game.placement_valid and corrected_floor.y < 601.0 and corrected_floor.distance_to(game.player.position) <= game.PLACEMENT_RADIUS + 0.1, "Dragging below the floor automatically moves the preview to reachable free space")
	await release_drag()
	check(not game.placing_bomb and game.bombs.size() == 1 and game.charges == 2, "Releasing the corrected floor preview creates one bomb and spends one charge")
	await reset_room()

	await key(KEY_D, true)
	await key(KEY_SPACE, true)
	check(game.player.velocity.x > 100.0 and game.player.velocity.y < -100.0, "D + Space produces a right jump")
	await key(KEY_SPACE, false)
	await key(KEY_D, false)
	await reset_room()
	await key(KEY_A, true)
	await key(KEY_SPACE, true)
	check(game.player.velocity.x < -100.0 and game.player.velocity.y < -100.0, "A + Space produces a left jump")
	await key(KEY_SPACE, false)
	await key(KEY_A, false)
	await reset_room()
	await key(KEY_SPACE, true)
	check(absf(game.player.velocity.x) < 5.0 and game.player.velocity.y < -100.0, "Space alone produces a vertical jump")
	await key(KEY_SPACE, false)
	await reset_room()

	await place_at_free_point()
	await begin_drag()
	check(game.placing_bomb, "Exit fixture starts with a live uncommitted ghost")
	game.player.reset_at(game.level.finish_rect.get_center())
	await frames(6)
	check(game.mode == "transition" and not game.placing_bomb, "Entering an exit begins a transition and cancels the ghost")
	await release_drag()
	check(game.transition_alpha > 0.0 and game.transition_alpha <= 1.0, "Exit transition drives the fade overlay")
	game.set_process(false)
	var exit_point: Vector2 = game.player.position
	var exit_bombs: int = game.bombs.size()
	var exit_charges: int = game.charges
	await tap(KEY_ESCAPE)
	await tap(KEY_F1)
	await tap(KEY_R)
	await tap(KEY_E)
	await tap(KEY_F)
	await begin_drag()
	await release_drag()
	await tap(KEY_SPACE)
	check(game.mode == "transition", "Transition ignores pause/help/restart and old menu keys")
	check(not game.player.enabled and game.player.position.is_equal_approx(exit_point), "Transition freezes movement and jumping")
	check(not game.placing_bomb and game.bombs.size() == exit_bombs and game.charges == exit_charges, "Transition input cannot place or detonate bombs")
	game.set_process(true)
	await wait_for_room(1)
	check(game.mode == "playing" and game.room_index == 1 and game.transition_alpha == 0.0, "Fade resumes play in the next room")
	check(game.bombs.is_empty() and game.charges == 3, "Room change removes old bombs and refills charges")
	await frames(20)
	var room_two_level: Node2D = game.level
	await place_at_free_point()
	await begin_drag()
	await tap(KEY_R)
	await release_drag()
	await frames(20)
	check(game.room_index == 1 and game.level == room_two_level, "R preserves the current second room")
	check(game.player.position.distance_to(game.level.checkpoints[0]) < 10.0 and game.bombs.is_empty() and not game.placing_bomb, "R restores room two and cancels all bomb state")

	for destination: int in range(2, 5):
		game.player.reset_at(game.level.finish_rect.get_center())
		await frames(3)
		await wait_for_room(destination)
		check(game.mode == "playing" and game.room_index == destination, "Exit leads to playable room %d without a menu" % (destination + 1))
	check(game.is_sandbox and game.room_index == 4 and game.player.enabled, "Fourth challenge leads to the playable fifth sandbox")
	await frames(20)
	await place_at_free_point()
	check(game.bombs.size() == 1, "Bomb placement still works in the final sandbox")
	await tap(KEY_ESCAPE)
	var final_point: Vector2 = game.player.position
	var confetti_clock: float = game.level._clock
	await frames(20)
	check(game.mode == "paused" and game.player.position.is_equal_approx(final_point), "Sandbox pauses without opening a menu")
	check(is_equal_approx(game.level._clock, confetti_clock), "Pause freezes the sandbox confetti animation")
	await tap(KEY_ESCAPE)
	await frames(5)
	check(game.level._clock > confetti_clock, "Sandbox confetti resumes with gameplay")
	game.elapsed = 123.0
	game.deaths = 7
	game.blasts = 9
	await begin_drag()
	await mouse_move(game.player.position + Vector2(35, -25))
	await reset_room()
	await release_drag()
	check(game.room_index == 0 and not game.is_sandbox and not game.level.sandbox and game.mode == "playing" and game.player.enabled, "R in the sandbox starts a new playable run in room one")
	check(game.bombs.is_empty() and not game.placing_bomb and game.charges == 3 and game.elapsed < 1.0 and game.deaths == 0 and game.blasts == 0 and game.transition_alpha == 0.0 and game.next_room == -1, "Replay through the actual R key clears bombs, held preview, run statistics and transition state")
	var audio_before: bool = game.sound.enabled
	await tap(KEY_M)
	check(game.sound.enabled != audio_before, "M toggles sound")
	# Mouse coordinates stay correct with the stretched 960x540 window.
	root.size = Vector2i(960, 540)
	await frames(3)
	await place_at_free_point()
	check(game.bombs.size() == 1, "Drag placement stays aligned after resizing to 960x540")
	await mouse_button(MOUSE_BUTTON_RIGHT, true)
	await mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(game.bombs.is_empty(), "RMB detonates placed bombs after window resizing")

	# The final blast may still be playing when a fast headless run ends.
	game.sound.set_enabled(false)
	# Fixed-FPS test frames do not wait for the real audio mixing thread.
	OS.delay_msec(100)
	game.queue_free()
	await frames(3)
	if record_existed:
		var record: FileAccess = FileAccess.open("user://record.cfg", FileAccess.WRITE)
		record.store_buffer(record_backup)
		record.close()
	elif FileAccess.file_exists("user://record.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://record.cfg"))
	print("UI_SMOKE: ", checks - failures.size(), "/", checks, " checks passed")
	quit(0 if failures.is_empty() else 1)
