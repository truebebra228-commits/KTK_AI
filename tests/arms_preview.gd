extends SceneTree
## Render the actual character, mouse-placement ghost and procedural arms.
## Run after player/main integration is ready:
## Godot --fixed-fps 60 --path bombbound --script res://tests/arms_preview.gd
## Full viewport frames live under .codex-tmp/helpers; the encoder crops them.

const FPS: int = 60
const CAPTURE_EVERY: int = 2
const FRAME_COUNT: int = 258
const CROP: Rect2i = Rect2i(512, 470, 256, 180)

var game: Node2D
var output_directory: String
var sampled_joints: Array[Dictionary] = []
var saved_frames: int = 0


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	output_directory = OS.get_environment("IMPULSE_ARMS_FRAME_DIR")
	if output_directory.is_empty():
		output_directory = ProjectSettings.globalize_path("res://../.codex-tmp/helpers/arms-frames").simplify_path()
	DirAccess.make_dir_recursive_absolute(output_directory)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	game = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(game)
	await process_frame
	game.sound.set_enabled(false)
	game.start_game()
	game.load_room(4)
	game.toast_time = 0.0
	game.player.facing = 1.0
	game.player.rotation = 0.0
	for _i: int in 24:
		await physics_frame
	if game.player.get("arms") == null:
		push_error("Arm preview requires integrated player.arms; wait for the production update.")
		game.queue_free()
		quit(2)
		return
	for frame: int in FRAME_COUNT:
		var time: float = float(frame) / FPS
		_drive_placement(time)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % CAPTURE_EVERY == 0:
			var screenshot: Image = root.get_texture().get_image()
			screenshot.save_png(output_directory.path_join("frame-%04d.png" % saved_frames))
			_sample_joint_state(time)
			saved_frames += 1
			if frame == 0:
				screenshot.save_png("res://previews/arms-idle.png")
			elif frame == 42:
				screenshot.save_png("res://previews/arms-right.png")
			elif frame == 118:
				screenshot.save_png("res://previews/arms-above.png")
			elif frame == 78:
				screenshot.save_png("res://previews/arms-left.png")
			elif frame == 196:
				screenshot.save_png("res://previews/arms-autocorrect.png")
			elif frame == 252:
				screenshot.save_png("res://previews/arms-released.png")
	game.cancel_placement()
	var metadata: Dictionary = {
		"fps": FPS / CAPTURE_EVERY,
		"frames": saved_frames,
		"crop": [CROP.position.x, CROP.position.y, CROP.size.x, CROP.size.y],
		"scale": 3,
		"stills": {"idle": 0, "right": 21, "above": 59, "left": 39, "autocorrect": 98, "released": 126},
		"joint_samples": sampled_joints,
		"description": "Actual Godot viewport: short pixel arms and gaze follow abrupt 56px targets; buried cursor auto-corrects above floor, then release.",
	}
	var file: FileAccess = FileAccess.open(output_directory.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "\t"))
	file.close()
	print("ARMS PREVIEW: %d frames, %.2f seconds, output=%s" % [saved_frames, float(saved_frames) / (FPS / CAPTURE_EVERY), output_directory])
	game.queue_free()
	await process_frame
	quit(0)


func _drive_placement(time: float) -> void:
	if time < 0.25:
		return
	if time >= 3.50:
		if game.placing_bomb:
			game.commit_placement()
		return
	if not game.placing_bomb:
		game.begin_placement()
	var offset: Vector2
	if time < 0.90:
		offset = Vector2(54, -14)
	elif time < 1.55:
		offset = Vector2(-54, -14)
	elif time < 2.20:
		offset = Vector2(0, -56)
	elif time < 2.95:
		var phase: int = int((time - 2.20) / 0.15) % 3
		offset = [Vector2(54, -14), Vector2(-54, -14), Vector2(0, -56)][phase]
	else:
		# A real cursor inside the floor: main's placement solver must move the
		# ghost to a reachable free spot instead of refusing or burying the bomb.
		offset = Vector2(31, 46)
	game.update_placement(game.player.global_position + offset)


func _sample_joint_state(time: float) -> void:
	var arms: Node2D = game.player.arms as Node2D
	var left_hand: Vector2 = arms.left_hand
	var right_hand: Vector2 = arms.right_hand
	var left_elbow: Vector2 = arms.left_elbow
	var right_elbow: Vector2 = arms.right_elbow
	var gaze_offset: Vector2 = game.player.gaze_offset
	var released_bombs: Array = []
	for bomb: Node2D in game.bombs:
		if is_instance_valid(bomb):
			released_bombs.append([bomb.global_position.x, bomb.global_position.y])
	sampled_joints.append({
		"time": time,
		"held": bool(arms.held),
		"left_hand": [left_hand.x, left_hand.y],
		"right_hand": [right_hand.x, right_hand.y],
		"left_elbow": [left_elbow.x, left_elbow.y],
		"right_elbow": [right_elbow.x, right_elbow.y],
		"target": [game.placement_position.x, game.placement_position.y],
		"cursor": [game.placement_cursor_position.x, game.placement_cursor_position.y],
		"placement_valid": game.placement_valid,
		"gaze_offset": [gaze_offset.x, gaze_offset.y],
		"gaze_weight": game.player.gaze_weight,
		"released_bombs": released_bombs,
	})
